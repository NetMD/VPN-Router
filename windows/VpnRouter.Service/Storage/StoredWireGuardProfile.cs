using VpnRouter.Core.Profiles;
using VpnRouter.Vpn.WireGuard;

namespace VpnRouter.Service.Storage;

public sealed record StoredWireGuardProfile(
    VpnProfile Profile,
    string ConfigText,
    WireGuardConfig ParsedConfig);
