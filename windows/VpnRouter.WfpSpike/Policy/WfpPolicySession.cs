using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike;

public sealed class WfpPolicySession : IDisposable, IAsyncDisposable
{
    private readonly IWfpNativeApi _nativeApi;
    private readonly IWfpIdentityLease _identity;
    private readonly IWfpEngineLease _engine;
    private readonly Stack<Guid> _installedKeys = new();
    private readonly object _cleanupLock = new();
    private bool _deletesAttempted;
    private bool _cleanupCompleted;

    private WfpPolicySession(IWfpNativeApi nativeApi, IWfpIdentityLease identity, IWfpEngineLease engine)
    {
        _nativeApi = nativeApi;
        _identity = identity;
        _engine = engine;
    }

    public static WfpPolicySession Apply(
        IWfpNativeApi nativeApi,
        IWfpIdentityLease identity,
        uint interfaceIndex,
        CancellationToken cancellationToken = default)
    {
        if (interfaceIndex == 0)
        {
            identity.Dispose();
            throw new WfpSpikeException(WfpSpikeResultCode.INTERFACE_NOT_FOUND);
        }

        WfpInterfaceIdentity interfaceIdentity;
        try
        {
            interfaceIdentity = nativeApi.ConvertIndexToLuidAndBack(interfaceIndex);
        }
        catch
        {
            identity.Dispose();
            throw;
        }

        if (interfaceIdentity.InterfaceIndex != interfaceIndex)
        {
            identity.Dispose();
            throw new WfpSpikeException(WfpSpikeResultCode.INTERFACE_IDENTITY_MISMATCH);
        }

        IWfpEngineLease engine;
        try
        {
            engine = nativeApi.OpenDynamicEngine();
        }
        catch
        {
            identity.Dispose();
            throw;
        }

        var session = new WfpPolicySession(nativeApi, identity, engine);
        try
        {
            foreach (var plan in WfpPolicyPlanner.Create(identity.Kind, interfaceIdentity.InterfaceLuid))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var current = nativeApi.ConvertIndexToLuidAndBack(interfaceIndex);
                if (current != interfaceIdentity)
                {
                    throw new WfpSpikeException(WfpSpikeResultCode.INTERFACE_CHANGED);
                }

                var key = WfpOwnedPolicyKeys.For(plan);
                nativeApi.AddConnectionPolicy(engine, plan, identity, key);
                session._installedKeys.Push(key);
            }

            return session;
        }
        catch
        {
            session.CleanupOnce();
            throw;
        }
    }

    public WfpSpikeResultCode CleanupOnce()
    {
        lock (_cleanupLock)
        {
            if (_cleanupCompleted) return WfpSpikeResultCode.NONE;

            var result = WfpSpikeResultCode.NONE;
            if (!_deletesAttempted)
            {
                _deletesAttempted = true;
                while (_installedKeys.TryPop(out var key))
                {
                    try { _nativeApi.DeleteConnectionPolicyByKey(_engine, key); }
                    catch { result = WfpSpikeResultCode.SESSION_CLOSE_FAILED; }
                }
            }

            try { _nativeApi.CloseEngine(_engine); }
            catch { return WfpSpikeResultCode.SESSION_CLOSE_FAILED; }

            _cleanupCompleted = true;
            _engine.Dispose();
            _identity.Dispose();
            return result;
        }
    }

    public void Dispose() => CleanupOnce();
    public ValueTask DisposeAsync() { CleanupOnce(); return ValueTask.CompletedTask; }
}
