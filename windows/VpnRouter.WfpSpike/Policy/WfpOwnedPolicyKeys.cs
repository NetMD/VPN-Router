using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike;

public static class WfpOwnedPolicyKeys
{
    public static readonly Guid DesktopIpv4 = new("32458d2e-74f4-4bc1-9f0d-7809c7c70601");
    public static readonly Guid DesktopIpv6 = new("32458d2e-74f4-4bc1-9f0d-7809c7c70602");
    public static readonly Guid PackageIpv4 = new("32458d2e-74f4-4bc1-9f0d-7809c7c70603");
    public static readonly Guid PackageIpv6 = new("32458d2e-74f4-4bc1-9f0d-7809c7c70604");

    public static Guid For(WfpPolicyPlan plan) => (plan.IdentityKind, plan.IpVersion) switch
    {
        (WfpAppIdentityKind.DesktopAppId, WfpIpVersion.IPv4) => DesktopIpv4,
        (WfpAppIdentityKind.DesktopAppId, WfpIpVersion.IPv6) => DesktopIpv6,
        (WfpAppIdentityKind.PackageId, WfpIpVersion.IPv4) => PackageIpv4,
        (WfpAppIdentityKind.PackageId, WfpIpVersion.IPv6) => PackageIpv6,
        _ => throw new WfpSpikeException(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE)
    };

    public static bool Contains(Guid key) =>
        key == DesktopIpv4 || key == DesktopIpv6 || key == PackageIpv4 || key == PackageIpv6;
}
