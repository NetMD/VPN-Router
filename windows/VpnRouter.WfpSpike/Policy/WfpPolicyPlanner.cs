using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike;

public static class WfpPolicyPlanner
{
    public const ulong WfpSpikePolicyWeight = 10_000UL;

    public static IReadOnlyList<WfpPolicyPlan> Create(WfpAppIdentityKind kind, ulong luid) =>
    [
        new(WfpIpVersion.IPv4, kind, luid),
        new(WfpIpVersion.IPv6, kind, luid)
    ];
}
