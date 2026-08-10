using Microsoft.Win32.SafeHandles;
using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike.Native;

internal sealed class WfpNativeApi : IWfpNativeApi
{
    private const uint RpcCAuthnWinnt = 10;

    public IWfpIdentityLease GetAppId(string normalizedExecutablePath)
    {
        var result = NativeMethods.FwpmGetAppIdFromFileName0(normalizedExecutablePath, out var pointer);
        if (result != 0 || pointer == 0) throw new WfpSpikeException(WfpSpikeResultCode.APP_ID_LOOKUP_FAILED);
        return new WfpMemoryIdentityLease(pointer, WfpAppIdentityKind.DesktopAppId);
    }

    public IWfpIdentityLease ResolvePackageIdentity(PackageIdentityEvidence evidence)
    {
        uint packageCount = 0;
        uint bufferLength = 0;
        var packageQuery = NativeMethods.GetPackagesByPackageFamily(evidence.PackageFamilyName, ref packageCount, 0, ref bufferLength, 0);
        if ((packageQuery != 0 && packageQuery != 122) || packageCount == 0)
            throw new WfpSpikeException(WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE);

        // Package Query API로 설치 PFN은 확인했지만 PFN↔AppContainer 이름↔토큰 SID 관계를
        // 공식 API로 같은 실행에서 증명하기 전에는 package live 정책을 열지 않습니다.
        throw new WfpSpikeException(WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE);
    }

    public WfpInterfaceIdentity ConvertIndexToLuidAndBack(uint interfaceIndex)
    {
        if (interfaceIndex == 0 || NativeMethods.ConvertInterfaceIndexToLuid(interfaceIndex, out var luid) != 0)
            throw new WfpSpikeException(WfpSpikeResultCode.INTERFACE_NOT_FOUND);
        if (NativeMethods.ConvertInterfaceLuidToIndex(in luid, out var roundTrip) != 0 || roundTrip != interfaceIndex)
            throw new WfpSpikeException(WfpSpikeResultCode.INTERFACE_IDENTITY_MISMATCH);
        return new(roundTrip, luid);
    }

    public IWfpEngineLease OpenDynamicEngine()
    {
        // ABI probe가 FWPM_SESSION0 배치를 확인한 factory 경로에서만 사용합니다.
        using var session = new NativeSessionBuffer();
        var result = NativeMethods.FwpmEngineOpen0(0, RpcCAuthnWinnt, 0, session.Pointer, out var handle);
        if (result == 5) throw new WfpSpikeException(WfpSpikeResultCode.BFE_ACCESS_DENIED);
        if (result != 0 || handle == 0) throw new WfpSpikeException(WfpSpikeResultCode.ENGINE_OPEN_FAILED);
        return new WfpEngineLease(handle);
    }

    public void AddConnectionPolicy(IWfpEngineLease engine, WfpPolicyPlan plan, IWfpIdentityLease identity, Guid policyKey)
    {
        if (!WfpOwnedPolicyKeys.Contains(policyKey) || engine is not WfpEngineLease nativeEngine)
            throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE);

        using var buffer = new NativePolicyBuffer(plan, identity, policyKey);
        var result = NativeMethods.FwpmConnectionPolicyAdd0(
            nativeEngine.DangerousGetHandle(), buffer.ConnectionPolicy,
            plan.IpVersion == WfpIpVersion.IPv4 ? 0u : 1u,
            plan.Weight, 1, buffer.FilterCondition, 0);
        if (result != 0)
        {
            Console.Error.WriteLine($"WFP_NATIVE_FAILURE:ADD_{plan.IpVersion}:0x{result:X8}");
            throw new WfpSpikeException(plan.IpVersion == WfpIpVersion.IPv4
                ? WfpSpikeResultCode.IPV4_POLICY_ADD_FAILED : WfpSpikeResultCode.IPV6_POLICY_ADD_FAILED);
        }
    }

    public void DeleteConnectionPolicyByKey(IWfpEngineLease engine, Guid policyKey)
    {
        if (!WfpOwnedPolicyKeys.Contains(policyKey) || engine is not WfpEngineLease nativeEngine)
            throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE);
        if (NativeMethods.FwpmConnectionPolicyDeleteByKey0(nativeEngine.DangerousGetHandle(), in policyKey) != 0)
            throw new WfpSpikeException(WfpSpikeResultCode.SESSION_CLOSE_FAILED);
    }

    public void CloseEngine(IWfpEngineLease engine)
    {
        if (engine is not WfpEngineLease nativeEngine || !nativeEngine.CloseOnce())
            throw new WfpSpikeException(WfpSpikeResultCode.SESSION_CLOSE_FAILED);
    }
}

internal sealed class WfpMemoryIdentityLease(nint value, WfpAppIdentityKind kind) : IWfpIdentityLease
{
    private nint _value = value;
    public WfpAppIdentityKind Kind { get; } = kind;
    public nint Value => _value;
    public void Dispose()
    {
        var pointer = Interlocked.Exchange(ref _value, 0);
        if (pointer != 0) NativeMethods.FwpmFreeMemory0(ref pointer);
    }
}

internal sealed class WfpEngineLease : SafeHandleZeroOrMinusOneIsInvalid, IWfpEngineLease
{
    private int _closed;

    public WfpEngineLease(nint nativeHandle) : base(true) => SetHandle(nativeHandle);

    bool IWfpEngineLease.IsClosed => Volatile.Read(ref _closed) != 0;
    public bool CloseOnce()
    {
        if (Volatile.Read(ref _closed) != 0) return true;
        if (NativeMethods.FwpmEngineClose0(DangerousGetHandle()) != 0) return false;
        Interlocked.Exchange(ref _closed, 1);
        SetHandleAsInvalid();
        return true;
    }
    protected override bool ReleaseHandle() => CloseOnce();
}
