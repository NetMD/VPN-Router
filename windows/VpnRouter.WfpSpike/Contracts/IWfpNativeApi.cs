namespace VpnRouter.WfpSpike.Contracts;

public interface IWfpIdentityLease : IDisposable
{
    WfpAppIdentityKind Kind { get; }
    nint Value { get; }
}

public interface IWfpEngineLease : IDisposable
{
    bool IsClosed { get; }
}

public interface IWfpNativeApi
{
    IWfpIdentityLease GetAppId(string normalizedExecutablePath);
    IWfpIdentityLease ResolvePackageIdentity(PackageIdentityEvidence evidence);
    WfpInterfaceIdentity ConvertIndexToLuidAndBack(uint interfaceIndex);
    IWfpEngineLease OpenDynamicEngine();
    void AddConnectionPolicy(IWfpEngineLease engine, WfpPolicyPlan plan, IWfpIdentityLease identity, Guid policyKey);
    void DeleteConnectionPolicyByKey(IWfpEngineLease engine, Guid policyKey);
    void CloseEngine(IWfpEngineLease engine);
}

public sealed record PackageIdentityEvidence(string PackageFamilyName, string AppContainerName, string SidBase64);
