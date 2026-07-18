using System.Diagnostics;
using System.Text.Json;

namespace VpnRouter.Service.Networking;

public sealed class DnsFilterHandoff(ILogger<DnsFilterHandoff> logger)
{
    private const string ServiceName = "Adguard Service";
    private readonly string _statePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "dns-filter-handoff.json");

    public bool HasPendingRestore => File.Exists(_statePath);

    public async Task PrepareAsync(CancellationToken cancellationToken)
    {
        var json = await RunPowerShellAsync(
            "$service=Get-CimInstance Win32_Service -Filter \"Name='Adguard Service'\" -ErrorAction SilentlyContinue; if($service){$service | Select-Object State,StartMode | ConvertTo-Json -Compress}",
            cancellationToken);
        if (string.IsNullOrWhiteSpace(json))
        {
            return;
        }

        var service = JsonSerializer.Deserialize<ServiceState>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });
        if (service is null || !string.Equals(service.State, "Running", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(_statePath)!);
        await File.WriteAllTextAsync(_statePath, JsonSerializer.Serialize(service), cancellationToken);
        await RunPowerShellAsync(
            $"Set-Service -Name '{ServiceName}' -StartupType Disabled; Stop-Service -Name '{ServiceName}' -Force -ErrorAction Stop",
            cancellationToken);
        logger.LogInformation("Paused AdGuard while VpnRouter owns the local DNS listener.");
    }

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
            throw new InvalidOperationException("The saved DNS filter handoff state is invalid.");
        }

        var startupType = service.StartMode switch
        {
            "Auto" => "Automatic",
            "Manual" => "Manual",
            "Disabled" => "Disabled",
            _ => "Automatic"
        };
        var startCommand = string.Equals(service.State, "Running", StringComparison.OrdinalIgnoreCase)
            ? $"; Start-Service -Name '{ServiceName}' -ErrorAction Stop"
            : string.Empty;
        await RunPowerShellAsync(
            $"Set-Service -Name '{ServiceName}' -StartupType {startupType}{startCommand}",
            cancellationToken);
        File.Delete(_statePath);
        logger.LogInformation("Restored AdGuard after releasing the local DNS listener.");
    }

    private static async Task<string> RunPowerShellAsync(string command, CancellationToken cancellationToken)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            ArgumentList = { "-NoProfile", "-NonInteractive", "-Command", command },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("Failed to manage the DNS filter service.");

        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"DNS filter handoff failed: {error}".Trim());
        }

        return output.Trim();
    }

    private sealed record ServiceState(string State, string StartMode);
}
