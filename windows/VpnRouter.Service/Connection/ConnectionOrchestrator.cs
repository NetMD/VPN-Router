using System.Net;
using VpnRouter.Core.Profiles;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Vpn.Abstractions;

namespace VpnRouter.Service.Connection;

public sealed class ConnectionOrchestrator(
    IVpnAdapter vpnAdapter,
    INetworkSnapshotStore networkSnapshotStore,
    IDnsProxyController dnsProxyController,
    IDnsSettingsManager dnsSettingsManager,
    IDomainPreResolver domainPreResolver,
    IRouteManager routeManager,
    ILogger<ConnectionOrchestrator> logger)
{
    public async Task ConnectAsync(
        VpnProfile profile,
        IReadOnlyList<DomainRule> rules,
        bool protectionMode,
        CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "Starting connection for profile {ProfileId} with {RuleCount} rule(s). ProtectionMode={ProtectionMode}",
            profile.Id,
            rules.Count,
            protectionMode);

        await networkSnapshotStore.SaveCurrentAsync(cancellationToken);
        try
        {
            await vpnAdapter.ValidateProfileAsync(profile, cancellationToken);
            await vpnAdapter.ConnectAsync(profile, cancellationToken);
            await dnsProxyController.StartAsync(rules, cancellationToken);
            await dnsSettingsManager.PointActiveAdaptersToLocalProxyAsync(cancellationToken);

            var domainIps = await domainPreResolver.ResolveAsync(rules, cancellationToken);
            var interfaceIndex = 0;
            try
            {
                var vpnInterface = await vpnAdapter.GetInterfaceInfoAsync(profile.Id, cancellationToken);
                interfaceIndex = vpnInterface.InterfaceIndex;
                logger.LogInformation(
                    "Detected VPN interface {InterfaceName} with index {InterfaceIndex}.",
                    vpnInterface.InterfaceName,
                    vpnInterface.InterfaceIndex);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "VPN interface detection failed. Route prototype will use interface index 0.");
            }

            await routeManager.AddHostRoutesAsync(domainIps, profile.Id, interfaceIndex, cancellationToken);
        }
        catch
        {
            logger.LogWarning("Connection failed. Attempting automatic DNS/proxy/route/VPN cleanup.");
            await SafeCleanupAfterConnectFailureAsync(profile.Id, cancellationToken);
            throw;
        }
    }

    public async Task DisconnectAsync(Guid profileId, CancellationToken cancellationToken)
    {
        logger.LogInformation("Disconnecting profile {ProfileId}.", profileId);

        await dnsProxyController.StopAsync(cancellationToken);
        await routeManager.RemoveManagedRoutesAsync(profileId, cancellationToken);
        await vpnAdapter.DisconnectAsync(profileId, cancellationToken);
        await networkSnapshotStore.RestoreAsync(cancellationToken);
    }

    public async Task RestoreNetworkAsync(CancellationToken cancellationToken)
    {
        logger.LogWarning("Restoring network settings on request.");

        await dnsProxyController.StopAsync(cancellationToken);
        await networkSnapshotStore.RestoreAsync(cancellationToken);
    }

    private async Task SafeCleanupAfterConnectFailureAsync(Guid profileId, CancellationToken cancellationToken)
    {
        try
        {
            await dnsProxyController.StopAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to stop DNS proxy during connection failure cleanup.");
        }

        try
        {
            await routeManager.RemoveManagedRoutesAsync(profileId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to remove managed routes during connection failure cleanup.");
        }

        try
        {
            await vpnAdapter.DisconnectAsync(profileId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to disconnect VPN during connection failure cleanup.");
        }

        try
        {
            await networkSnapshotStore.RestoreAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to restore network snapshot during connection failure cleanup. Manual network restore may be required.");
        }
    }
}
