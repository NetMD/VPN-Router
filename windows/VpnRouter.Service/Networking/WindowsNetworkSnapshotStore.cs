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
            "Get-DnsClientServerAddress | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,ServerAddresses | ConvertTo-Json -Depth 5",
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
        foreach (var entry in ParseDnsEntries(dnsClientServerAddressJson))
        {
            if (!IsIpv4(entry.AddressFamily))
            {
                continue;
            }

            var command = entry.ServerAddresses.Count == 0
                ? $"Set-DnsClientServerAddress -InterfaceIndex {entry.InterfaceIndex} -AddressFamily IPv4 -ResetServerAddresses"
                : $"Set-DnsClientServerAddress -InterfaceIndex {entry.InterfaceIndex} -AddressFamily IPv4 -ServerAddresses @({string.Join(",", entry.ServerAddresses.Select(ToPowerShellString))})";

            await RunPowerShellAsync(command, cancellationToken);
            logger.LogWarning(
                "Restored IPv4 DNS settings for interface index {InterfaceIndex}. Server count={ServerCount}.",
                entry.InterfaceIndex,
                entry.ServerAddresses.Count);
        }
    }

    private static IReadOnlyList<DnsSnapshotEntry> ParseDnsEntries(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        using var document = JsonDocument.Parse(json);
        var elements = document.RootElement.ValueKind == JsonValueKind.Array
            ? document.RootElement.EnumerateArray().ToArray()
            : [document.RootElement];

        return elements
            .Where(element => element.TryGetProperty("InterfaceIndex", out _))
            .Select(element =>
            {
                var interfaceIndex = element.GetProperty("InterfaceIndex").GetInt32();
                var addressFamily = element.TryGetProperty("AddressFamily", out var familyElement)
                    ? familyElement.ToString()
                    : string.Empty;
                var serverAddresses = element.TryGetProperty("ServerAddresses", out var addressesElement)
                    ? ReadServerAddresses(addressesElement)
                    : [];

                return new DnsSnapshotEntry(interfaceIndex, addressFamily, serverAddresses);
            })
            .ToArray();
    }

    private static IReadOnlyList<string> ReadServerAddresses(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Array => element.EnumerateArray()
                .Select(item => item.GetString())
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Select(item => item!)
                .ToArray(),
            JsonValueKind.String => string.IsNullOrWhiteSpace(element.GetString()) ? [] : [element.GetString()!],
            _ => []
        };
    }

    private static bool IsIpv4(string addressFamily)
    {
        return string.Equals(addressFamily, "IPv4", StringComparison.OrdinalIgnoreCase)
            || string.Equals(addressFamily, "2", StringComparison.OrdinalIgnoreCase)
            || string.Equals(addressFamily, "InterNetwork", StringComparison.OrdinalIgnoreCase);
    }

    private static string ToPowerShellString(string value) => $"'{value.Replace("'", "''")}'";

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

    private sealed record DnsSnapshotEntry(int InterfaceIndex, string AddressFamily, IReadOnlyList<string> ServerAddresses);
}
