using VpnRouter.Networking.Abstractions;
using VpnRouter.Vpn.Abstractions;
using VpnRouter.Service.Networking;

namespace VpnRouter.Service.Recovery;

public sealed class StartupRecoveryCoordinator(
    ConnectionRecoveryStateStore recoveryStateStore,
    IRouteManager routeManager,
    IVpnAdapter vpnAdapter,
    INetworkSnapshotStore networkSnapshotStore,
    DnsFilterHandoff dnsFilterHandoff,
    ILogger<StartupRecoveryCoordinator> logger)
{
    public async Task RecoverAsync(CancellationToken cancellationToken)
    {
        var hasMarker = recoveryStateStore.HasActiveMarker;
        var hasRoutes = await routeManager.HasManagedRoutesAsync(cancellationToken);
        var hasDnsFilterHandoff = dnsFilterHandoff.HasPendingRestore;
        var failures = new List<Exception>();

        if (hasRoutes)
        {
            await RunStepAsync(
                "remove stale managed routes",
                () => routeManager.RemoveAllManagedRoutesAsync(cancellationToken),
                failures);
        }

        var staleTunnelCount = 0;
        await RunStepAsync(
            "remove stale VPN tunnels",
            async () => staleTunnelCount = await vpnAdapter.CleanupStaleConnectionsAsync(cancellationToken),
            failures);

        if (hasMarker || hasRoutes || staleTunnelCount > 0 || hasDnsFilterHandoff)
        {
            logger.LogWarning(
                "Startup recovery detected stale state. Marker={HasMarker}, Routes={HasRoutes}, Tunnels={TunnelCount}, DnsFilterHandoff={HasDnsFilterHandoff}.",
                hasMarker,
                hasRoutes,
                staleTunnelCount,
                hasDnsFilterHandoff);
            await RunStepAsync(
                "restore saved network settings",
                () => networkSnapshotStore.RestoreAsync(cancellationToken),
                failures);
            await RunStepAsync(
                "restore DNS filter",
                () => dnsFilterHandoff.RestoreAsync(cancellationToken),
                failures);
        }

        if (failures.Count > 0)
        {
            throw new AggregateException("Startup recovery did not complete cleanly.", failures);
        }

        await recoveryStateStore.ClearAsync(cancellationToken);
        logger.LogInformation("Startup network recovery check completed.");
    }

    private async Task RunStepAsync(string name, Func<Task> action, ICollection<Exception> failures)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            failures.Add(ex);
            logger.LogError(ex, "Failed to {RecoveryStep} during startup recovery.", name);
        }
    }
}
