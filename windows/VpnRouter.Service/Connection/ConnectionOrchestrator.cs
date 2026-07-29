using System.Net;
using VpnRouter.Core.Profiles;
using VpnRouter.Core.Rules;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Vpn.Abstractions;
using VpnRouter.Service.Recovery;
using VpnRouter.Service.Networking;

namespace VpnRouter.Service.Connection;

public sealed class ConnectionOrchestrator(
    IVpnAdapter vpnAdapter,
    INetworkSnapshotStore networkSnapshotStore,
    IDnsProxyController dnsProxyController,
    IDnsSettingsManager dnsSettingsManager,
    IDomainPreResolver domainPreResolver,
    IRouteManager routeManager,
    ConnectionRecoveryStateStore recoveryStateStore,
    LegacyDnsFilterRecovery legacyDnsFilterRecovery,
    ConnectionStateStore connectionStateStore,
    ILogger<ConnectionOrchestrator> logger)
{
    private readonly object _dnsHealthGate = new();
    private CancellationTokenSource? _dnsHealthCancellation;

    public async Task ConnectAsync(
        VpnProfile profile,
        IReadOnlyList<DomainRule> rules,
        IPAddress? upstreamDnsServer,
        CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "Starting connection for profile {ProfileId} with {RuleCount} rule(s).",
            profile.Id,
            rules.Count);

        var effectiveRules = DomainRuleExpander.Expand(rules);
        logger.LogInformation(
            "Expanded {RuleCount} user rule(s) to {EffectiveRuleCount} effective routing rule(s).",
            rules.Count,
            effectiveRules.Count);

        await networkSnapshotStore.SaveCurrentAsync(cancellationToken);
        await recoveryStateStore.MarkActiveAsync(profile.Id, cancellationToken);
        try
        {
            await vpnAdapter.ValidateProfileAsync(profile, cancellationToken);
            var domainIps = await domainPreResolver.ResolveAsync(effectiveRules, cancellationToken);
            await vpnAdapter.ConnectAsync(profile, cancellationToken);

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

            var routedIps = new Dictionary<string, IReadOnlyList<IPAddress>>(domainIps, StringComparer.OrdinalIgnoreCase);
            if (upstreamDnsServer is not null)
            {
                routedIps["__vpn_dns__"] = [upstreamDnsServer];
            }

            await routeManager.RemoveManagedRoutesAsync(profile.Id, cancellationToken);
            await routeManager.AddHostRoutesAsync(routedIps, profile.Id, interfaceIndex, cancellationToken);
            await dnsProxyController.StartAsync(
                effectiveRules,
                upstreamDnsServer,
                profile.Id,
                interfaceIndex,
                cancellationToken);
            await dnsSettingsManager.PointActiveAdaptersToLocalProxyAsync(cancellationToken);
            StartDnsHealthMonitor(profile.Id);
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
        StopDnsHealthMonitor();

        var failures = new List<Exception>();
        await RunDisconnectStepAsync("stop DNS proxy", () => dnsProxyController.StopAsync(cancellationToken), failures);
        await RunDisconnectStepAsync("remove managed routes", () => routeManager.RemoveManagedRoutesAsync(profileId, cancellationToken), failures);
        await RunDisconnectStepAsync("disconnect VPN", () => vpnAdapter.DisconnectAsync(profileId, cancellationToken), failures);
        await RunDisconnectStepAsync("restore network snapshot", () => networkSnapshotStore.RestoreAsync(cancellationToken), failures);
        await RunDisconnectStepAsync("restore legacy DNS filter state", () => legacyDnsFilterRecovery.RestoreAsync(cancellationToken), failures);

        if (failures.Count > 0)
        {
            throw new AggregateException("One or more disconnect cleanup steps failed.", failures);
        }

        await recoveryStateStore.ClearAsync(cancellationToken);
    }

    private async Task RunDisconnectStepAsync(
        string step,
        Func<Task> action,
        ICollection<Exception> failures)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            failures.Add(ex);
            logger.LogWarning(ex, "Failed to {DisconnectStep} during disconnect cleanup.", step);
        }
    }

    public async Task RestoreNetworkAsync(CancellationToken cancellationToken)
    {
        logger.LogWarning("Restoring network settings on request.");
        StopDnsHealthMonitor();

        var failures = new List<Exception>();
        await RunDisconnectStepAsync("stop DNS proxy", () => dnsProxyController.StopAsync(cancellationToken), failures);
        await RunDisconnectStepAsync("remove all managed routes", () => routeManager.RemoveAllManagedRoutesAsync(cancellationToken), failures);
        await RunDisconnectStepAsync("remove stale VPN tunnels", async () =>
        {
            await vpnAdapter.CleanupStaleConnectionsAsync(cancellationToken);
        }, failures);
        await RunDisconnectStepAsync("restore network snapshot", () => networkSnapshotStore.RestoreAsync(cancellationToken), failures);
        await RunDisconnectStepAsync("restore legacy DNS filter state", () => legacyDnsFilterRecovery.RestoreAsync(cancellationToken), failures);

        if (failures.Count > 0)
        {
            throw new AggregateException("One or more network restore steps failed.", failures);
        }

        await recoveryStateStore.ClearAsync(cancellationToken);
    }

    private async Task SafeCleanupAfterConnectFailureAsync(Guid profileId, CancellationToken cancellationToken)
    {
        StopDnsHealthMonitor();
        var cleanupSucceeded = true;
        try
        {
            await dnsProxyController.StopAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            cleanupSucceeded = false;
            logger.LogWarning(ex, "Failed to stop DNS proxy during connection failure cleanup.");
        }

        try
        {
            await routeManager.RemoveManagedRoutesAsync(profileId, cancellationToken);
        }
        catch (Exception ex)
        {
            cleanupSucceeded = false;
            logger.LogWarning(ex, "Failed to remove managed routes during connection failure cleanup.");
        }

        try
        {
            await vpnAdapter.DisconnectAsync(profileId, cancellationToken);
        }
        catch (Exception ex)
        {
            cleanupSucceeded = false;
            logger.LogWarning(ex, "Failed to disconnect VPN during connection failure cleanup.");
        }

        try
        {
            await networkSnapshotStore.RestoreAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            cleanupSucceeded = false;
            logger.LogError(ex, "Failed to restore network snapshot during connection failure cleanup. Manual network restore may be required.");
        }

        try
        {
            await legacyDnsFilterRecovery.RestoreAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            cleanupSucceeded = false;
            logger.LogError(ex, "Failed to restore the DNS filter during connection failure cleanup.");
        }

        if (cleanupSucceeded)
        {
            await recoveryStateStore.ClearAsync(cancellationToken);
        }
    }

    private void StartDnsHealthMonitor(Guid profileId)
    {
        StopDnsHealthMonitor();
        var cancellation = new CancellationTokenSource();
        lock (_dnsHealthGate)
        {
            _dnsHealthCancellation = cancellation;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                var failure = await dnsProxyController.WaitForFatalFailureAsync(cancellation.Token);
                logger.LogError(failure, "A local DNS conflict appeared while the VPN connection was active.");
                connectionStateStore.SetFailed("로컬 DNS 충돌이 감지되어 안전하게 VPN 연결을 해제합니다.");
                try
                {
                    await DisconnectAsync(profileId, CancellationToken.None);
                    connectionStateStore.SetFailed(
                        "DNS 보호, 광고 차단, 보안 또는 다른 VPN 프로그램과의 DNS 충돌로 연결이 해제되었습니다.");
                }
                catch (Exception cleanupError)
                {
                    logger.LogError(cleanupError, "Failed to clean up after a local DNS ownership failure.");
                    connectionStateStore.SetFailed(
                        "DNS 충돌 후 네트워크 복구가 완전히 끝나지 않았습니다. 네트워크 복구를 실행해 주세요.");
                }
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
            }
        }, CancellationToken.None);
    }

    private void StopDnsHealthMonitor()
    {
        CancellationTokenSource? cancellation;
        lock (_dnsHealthGate)
        {
            cancellation = _dnsHealthCancellation;
            _dnsHealthCancellation = null;
        }

        if (cancellation is not null)
        {
            cancellation.Cancel();
            cancellation.Dispose();
        }
    }
}
