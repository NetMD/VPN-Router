using System.Diagnostics;
using Microsoft.Extensions.Options;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsDnsSettingsManager(
    IOptions<VpnRouterFeatureOptions> options,
    ILogger<WindowsDnsSettingsManager> logger) : IDnsSettingsManager
{
    public async Task PointActiveAdaptersToLocalProxyAsync(CancellationToken cancellationToken)
    {
        if (!options.Value.EnableWindowsDnsMutation)
        {
            logger.LogInformation("Windows DNS mutation is disabled. DNS server settings were not changed.");
            return;
        }

        const string previewCommand = """
            Get-NetAdapter |
              Where-Object {
                $_.Status -eq 'Up' -and
                $_.InterfaceDescription -notmatch 'WireGuard|Wintun' -and
                $_.Name -notmatch 'WireGuard|Wintun'
              } |
              Select-Object Name,ifIndex,InterfaceDescription |
              ConvertTo-Json -Depth 3
            """;

        var preview = await RunPowerShellAsync(previewCommand, cancellationToken);
        if (string.IsNullOrWhiteSpace(preview))
        {
            throw new InvalidOperationException("No active non-WireGuard network adapter was found for DNS mutation.");
        }

        logger.LogWarning("DNS mutation target adapter(s): {AdaptersJson}", preview);

        const string command = """
            $targets = Get-NetAdapter |
              Where-Object {
                $_.Status -eq 'Up' -and
                $_.InterfaceDescription -notmatch 'WireGuard|Wintun' -and
                $_.Name -notmatch 'WireGuard|Wintun'
              }
            if (-not $targets) { throw 'No active non-WireGuard network adapter was found for DNS mutation.' }
            $targets |
              ForEach-Object {
                Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses @('127.0.0.1')
              }
            """;

        await RunPowerShellAsync(command, cancellationToken);
        logger.LogWarning("Active adapter IPv4 DNS servers were changed to 127.0.0.1.");
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
        }) ?? throw new InvalidOperationException("Failed to start powershell.exe.");

        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"PowerShell DNS command failed: {error} {output}".Trim());
        }

        return output.Trim();
    }
}
