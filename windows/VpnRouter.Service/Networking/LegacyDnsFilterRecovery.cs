using System.Diagnostics;
using System.Text.Json;

namespace VpnRouter.Service.Networking;

/// <summary>
/// Restores state written by builds that used to stop AdGuard automatically.
/// New connections must never create this state or modify third-party services.
/// </summary>
public sealed class LegacyDnsFilterRecovery(ILogger<LegacyDnsFilterRecovery> logger)
{
    private const string LegacyServiceName = "Adguard Service";
    private readonly string _statePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "dns-filter-handoff.json");

    public bool HasPendingRestore => File.Exists(_statePath);

    public async Task RestoreAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_statePath))
        {
            return;
        }

        var service = JsonSerializer.Deserialize<ServiceState>(
            await File.ReadAllTextAsync(_statePath, cancellationToken),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (service is null)
        {
            throw new InvalidOperationException("The saved legacy DNS filter state is invalid.");
        }

        var startupType = service.StartMode switch
        {
            "Auto" => "Automatic",
            "Manual" => "Manual",
            "Disabled" => "Disabled",
            _ => "Automatic"
        };
        var startCommand = string.Equals(service.State, "Running", StringComparison.OrdinalIgnoreCase)
            ? $"; Start-Service -Name '{LegacyServiceName}' -ErrorAction Stop"
            : string.Empty;
        await RunPowerShellAsync(
            $"Set-Service -Name '{LegacyServiceName}' -StartupType {startupType}{startCommand}",
            cancellationToken);
        File.Delete(_statePath);
        logger.LogInformation("Restored DNS filter state left by an older VPN Router build.");
    }

    private static async Task RunPowerShellAsync(string command, CancellationToken cancellationToken)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            ArgumentList = { "-NoProfile", "-NonInteractive", "-Command", command },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("Failed to restore legacy DNS filter state.");

        _ = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"Legacy DNS filter restore failed: {error}".Trim());
        }
    }

    private sealed record ServiceState(string State, string StartMode);
}
