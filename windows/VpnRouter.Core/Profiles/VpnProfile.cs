namespace VpnRouter.Core.Profiles;

public sealed record VpnProfile(
    Guid Id,
    string Name,
    VpnProfileType Type,
    bool Enabled,
    string ConfigRef,
    string? ProviderId,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public enum VpnProfileType
{
    WireGuard = 1,
    OpenVpn = 2,
    L2tp = 3
}
