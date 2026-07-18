using VpnRouter.Core.Profiles;

namespace VpnRouter.Vpn.Abstractions;

public interface IVpnAdapter
{
    VpnProfileType Type { get; }

    Task ValidateProfileAsync(VpnProfile profile, CancellationToken cancellationToken);

    Task ConnectAsync(VpnProfile profile, CancellationToken cancellationToken);

    Task DisconnectAsync(Guid profileId, CancellationToken cancellationToken);

    Task<VpnInterfaceInfo> GetInterfaceInfoAsync(Guid profileId, CancellationToken cancellationToken);

    Task<VpnConnectionStatus> GetConnectionStatusAsync(Guid profileId, CancellationToken cancellationToken);

    Task<int> CleanupStaleConnectionsAsync(CancellationToken cancellationToken);
}
