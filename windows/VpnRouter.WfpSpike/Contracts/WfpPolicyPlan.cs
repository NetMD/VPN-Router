namespace VpnRouter.WfpSpike.Contracts;

public sealed record WfpPolicyPlan(
    WfpIpVersion IpVersion,
    WfpAppIdentityKind IdentityKind,
    ulong InterfaceLuid,
    ulong Weight = global::VpnRouter.WfpSpike.WfpPolicyPlanner.WfpSpikePolicyWeight);

public sealed record WfpInterfaceIdentity(uint InterfaceIndex, ulong InterfaceLuid);

public sealed class WfpSpikeException(WfpSpikeResultCode code) : Exception
{
    public WfpSpikeResultCode Code { get; } = code;
}
