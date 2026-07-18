using VpnRouter.Service.Recovery;

namespace VpnRouter.Service;

public class Worker(
    StartupRecoveryCoordinator startupRecoveryCoordinator,
    StartupRecoveryGate startupRecoveryGate,
    ILogger<Worker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("VpnRouter service startup recovery started.");
        try
        {
            await startupRecoveryCoordinator.RecoverAsync(stoppingToken);
            startupRecoveryGate.Complete();
        }
        catch (Exception ex)
        {
            logger.LogCritical(ex, "VpnRouter startup recovery failed. New VPN connections are blocked.");
            startupRecoveryGate.Fail(ex.Message);
        }

        logger.LogInformation("VpnRouter service started. RecoverySucceeded={RecoverySucceeded}.", startupRecoveryGate.Succeeded);

        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        }
    }
}
