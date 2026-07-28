using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Options;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsNetworkSnapshotStore(
    IOptions<VpnRouterFeatureOptions> options,
    ILogger<WindowsNetworkSnapshotStore> logger) : INetworkSnapshotStore
{
    private readonly string _snapshotPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "network-snapshot.json");

    public async Task SaveCurrentAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_snapshotPath)!);

        var dnsJson = await RunPowerShellAsync(
            """
            $targets = Get-NetAdapter |
              Where-Object {
                $_.Status -eq 'Up' -and
                $_.InterfaceDescription -notmatch 'WireGuard|Wintun' -and
                $_.Name -notmatch 'WireGuard|Wintun'
              }
            $entries = foreach ($target in $targets) {
              $ipv4RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($target.InterfaceGuid)"
              $ipv4Registry = Get-ItemProperty -Path $ipv4RegistryPath -ErrorAction SilentlyContinue
              foreach ($dnsEntry in @(Get-DnsClientServerAddress -InterfaceIndex $target.ifIndex)) {
                [pscustomobject]@{
                  InterfaceAlias = $dnsEntry.InterfaceAlias
                  InterfaceIndex = $dnsEntry.InterfaceIndex
                  AddressFamily = $dnsEntry.AddressFamily
                  ServerAddresses = @($dnsEntry.ServerAddresses)
                  IsAutomatic = if ([int]$dnsEntry.AddressFamily -eq 2) {
                    if ($null -eq $ipv4Registry) {
                      $null
                    } else {
                      [string]::IsNullOrWhiteSpace([string]$ipv4Registry.NameServer)
                    }
                  } else {
                    $null
                  }
                }
              }
            }
            $entries | ConvertTo-Json -Depth 5
            """,
            cancellationToken);

        var routeText = await RunPowerShellAsync(
            "Get-NetRoute -AddressFamily IPv4 | Select-Object ifIndex,DestinationPrefix,NextHop,RouteMetric,InterfaceMetric | ConvertTo-Json -Depth 5",
            cancellationToken);

        var snapshot = new NetworkSnapshot(DateTimeOffset.UtcNow, dnsJson, routeText);
        await File.WriteAllTextAsync(_snapshotPath, JsonSerializer.Serialize(snapshot, new JsonSerializerOptions
        {
            WriteIndented = true
        }), cancellationToken);

        logger.LogInformation("Network snapshot saved to {SnapshotPath}.", _snapshotPath);
    }

    public async Task RestoreAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_snapshotPath))
        {
            logger.LogWarning("No network snapshot file exists at {SnapshotPath}.", _snapshotPath);
            return;
        }

        var snapshotJson = await File.ReadAllTextAsync(_snapshotPath, cancellationToken);
        var snapshot = JsonSerializer.Deserialize<NetworkSnapshot>(snapshotJson);
        logger.LogInformation(
            "Network restore loaded snapshot from {CreatedAt}.",
            snapshot?.CreatedAt);

        if (snapshot is not null && options.Value.EnableWindowsDnsMutation)
        {
            await RestoreDnsAsync(snapshot.DnsClientServerAddressJson, logger, cancellationToken);
        }
    }

    private static async Task RestoreDnsAsync(
        string dnsClientServerAddressJson,
        ILogger<WindowsNetworkSnapshotStore> logger,
        CancellationToken cancellationToken)
    {
        foreach (var entry in DnsSnapshotRestorePlanner.ParseEntries(dnsClientServerAddressJson))
        {
            var command = DnsSnapshotRestorePlanner.BuildRestoreCommand(entry);
            if (command is null)
            {
                continue;
            }

            await RunPowerShellAsync(command, cancellationToken);
            logger.LogWarning(
                "Restored IPv4 DNS settings for interface index {InterfaceIndex}. Automatic={IsAutomatic}. Server count={ServerCount}.",
                entry.InterfaceIndex,
                entry.IsAutomatic,
                entry.ServerAddresses.Count);
        }
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
            throw new InvalidOperationException($"PowerShell command failed: {error}");
        }

        return output.Trim();
    }

    private sealed record NetworkSnapshot(DateTimeOffset CreatedAt, string DnsClientServerAddressJson, string Ipv4RouteJson);
}
