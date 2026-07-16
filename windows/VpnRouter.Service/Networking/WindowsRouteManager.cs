using System.Net;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Options;
using VpnRouter.Core.Routing;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsRouteManager(
    IOptions<VpnRouterFeatureOptions> options,
    ILogger<WindowsRouteManager> logger) : IRouteManager
{
    private readonly string _routesPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "managed-routes.json");

    public async Task<IReadOnlyList<RouteEntry>> AddHostRoutesAsync(
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> domainIps,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_routesPath)!);

        var entries = domainIps
            .SelectMany(pair => pair.Value
                .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                .Select(address => new RouteEntry(
                    address,
                    pair.Key,
                    profileId,
                    DateTimeOffset.UtcNow.AddMinutes(15),
                    interfaceIndex,
                    "VpnRouter.RoutePrototype")))
            .ToArray();

        var existing = await LoadEntriesAsync(cancellationToken);
        var merged = existing
            .Where(entry => entry.ProfileId != profileId)
            .Concat(entries)
            .ToArray();

        if (options.Value.EnableWindowsRouteMutation)
        {
            if (interfaceIndex <= 0)
            {
                throw new InvalidOperationException("Cannot add VPN routes because the WireGuard interface index was not detected.");
            }

            foreach (var entry in entries)
            {
                await AddWindowsRouteAsync(entry, cancellationToken);
            }

            logger.LogInformation("Added {RouteCount} IPv4 host route(s) for profile {ProfileId}.", entries.Length, profileId);
        }
        else
        {
            logger.LogInformation("Recorded {RouteCount} IPv4 route plan(s) for profile {ProfileId}. Route mutation is disabled.", entries.Length, profileId);
        }

        await SaveEntriesAsync(merged, cancellationToken);
        return entries;
    }

    public async Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var existing = await LoadEntriesAsync(cancellationToken);
        var removed = existing.Where(entry => entry.ProfileId == profileId).ToArray();
        if (options.Value.EnableWindowsRouteMutation)
        {
            foreach (var entry in removed)
            {
                await RemoveWindowsRouteAsync(entry, cancellationToken);
            }
        }

        var remaining = existing.Where(entry => entry.ProfileId != profileId).ToArray();
        await SaveEntriesAsync(remaining, cancellationToken);
        logger.LogInformation(
            "Removed {RouteCount} recorded route plan(s) for profile {ProfileId}.",
            removed.Length,
            profileId);
    }

    private static Task AddWindowsRouteAsync(RouteEntry entry, CancellationToken cancellationToken)
    {
        var command =
            $"New-NetRoute -DestinationPrefix '{entry.Ip}/32' -InterfaceIndex {entry.InterfaceIndex} -NextHop '0.0.0.0' -PolicyStore ActiveStore -ErrorAction Stop";

        return RunPowerShellAsync(command, cancellationToken);
    }

    private static Task RemoveWindowsRouteAsync(RouteEntry entry, CancellationToken cancellationToken)
    {
        var command =
            $"Get-NetRoute -DestinationPrefix '{entry.Ip}/32' -InterfaceIndex {entry.InterfaceIndex} -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue";

        return RunPowerShellAsync(command, cancellationToken);
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
        }) ?? throw new InvalidOperationException("Failed to start powershell.exe.");

        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"PowerShell route command failed: {error} {output}".Trim());
        }
    }

    private async Task<IReadOnlyList<RouteEntry>> LoadEntriesAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_routesPath))
        {
            return [];
        }

        var json = await File.ReadAllTextAsync(_routesPath, cancellationToken);
        return (JsonSerializer.Deserialize<StoredRouteEntry[]>(json) ?? [])
            .Select(entry => new RouteEntry(
                IPAddress.Parse(entry.Ip),
                entry.Domain,
                entry.ProfileId,
                entry.ExpiresAt,
                entry.InterfaceIndex,
                entry.AddedBy))
            .ToArray();
    }

    private async Task SaveEntriesAsync(IReadOnlyList<RouteEntry> entries, CancellationToken cancellationToken)
    {
        var storedEntries = entries.Select(entry => new StoredRouteEntry(
            entry.Ip.ToString(),
            entry.Domain,
            entry.ProfileId,
            entry.ExpiresAt,
            entry.InterfaceIndex,
            entry.AddedBy));

        await File.WriteAllTextAsync(_routesPath, JsonSerializer.Serialize(storedEntries, new JsonSerializerOptions
        {
            WriteIndented = true
        }), cancellationToken);
    }

    private sealed record StoredRouteEntry(
        string Ip,
        string Domain,
        Guid ProfileId,
        DateTimeOffset ExpiresAt,
        int InterfaceIndex,
        string AddedBy);
}
