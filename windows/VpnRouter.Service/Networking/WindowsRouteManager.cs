using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;
using VpnRouter.Core.Routing;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Networking;

public sealed class WindowsRouteManager(
    IOptions<VpnRouterFeatureOptions> options,
    ILogger<WindowsRouteManager> logger) : IRouteManager, IAsyncDisposable
{
    private static readonly TimeSpan RouteLifetime = TimeSpan.FromMinutes(15);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly PersistentPowerShellRunner _powerShellRunner = new(logger);
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
        await _gate.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_routesPath)!);

            var existing = await LoadEntriesAsync(cancellationToken);
            var update = ManagedRouteLifecycle.Update(
                existing,
                domainIps,
                profileId,
                interfaceIndex,
                DateTimeOffset.UtcNow,
                RouteLifetime);

            if (options.Value.EnableWindowsRouteMutation)
            {
                if (interfaceIndex <= 0)
                {
                    throw new InvalidOperationException("Cannot add VPN routes because the WireGuard interface index was not detected.");
                }

                await AddWindowsRoutesAsync(update.Added, cancellationToken);
                logger.LogInformation(
                    "Added {AddedCount} and refreshed {RefreshedCount} IPv4 host route(s) for profile {ProfileId}.",
                    update.Added.Count,
                    update.RefreshedCount,
                    profileId);
            }
            else
            {
                logger.LogInformation(
                    "Recorded {AddedCount} new and {RefreshedCount} refreshed IPv4 route plan(s) for profile {ProfileId}. Route mutation is disabled.",
                    update.Added.Count,
                    update.RefreshedCount,
                    profileId);
            }

            await SaveEntriesAsync(update.Entries, cancellationToken);
            return update.Added;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<int> RemoveExpiredRoutesAsync(Guid profileId, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var existing = await LoadEntriesAsync(cancellationToken);
            var expired = ManagedRouteLifecycle.FindExpired(existing, profileId, DateTimeOffset.UtcNow);
            if (expired.Count == 0)
            {
                return 0;
            }

            if (options.Value.EnableWindowsRouteMutation)
            {
                await RemoveWindowsRoutesAsync(expired, cancellationToken);
            }

            var expiredKeys = expired
                .Select(entry => (entry.ProfileId, Ip: entry.Ip.ToString()))
                .ToHashSet();
            var remaining = existing
                .Where(entry => !expiredKeys.Contains((entry.ProfileId, entry.Ip.ToString())))
                .ToArray();
            await SaveEntriesAsync(remaining, cancellationToken);
            logger.LogInformation(
                "Removed {RouteCount} expired IPv4 host route(s) for profile {ProfileId}.",
                expired.Count,
                profileId);
            return expired.Count;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var existing = await LoadEntriesAsync(cancellationToken);
            var removed = existing.Where(entry => entry.ProfileId == profileId).ToArray();
            if (options.Value.EnableWindowsRouteMutation)
            {
                await RemoveWindowsRoutesAsync(removed, cancellationToken);
            }

            var remaining = existing.Where(entry => entry.ProfileId != profileId).ToArray();
            await SaveEntriesAsync(remaining, cancellationToken);
            logger.LogInformation(
                "Removed {RouteCount} recorded route plan(s) for profile {ProfileId}.",
                removed.Length,
                profileId);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<bool> HasManagedRoutesAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return (await LoadEntriesAsync(cancellationToken)).Count > 0;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task RemoveAllManagedRoutesAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var existing = await LoadEntriesAsync(cancellationToken);
            if (options.Value.EnableWindowsRouteMutation)
            {
                await RemoveWindowsRoutesAsync(existing, cancellationToken);
            }

            await SaveEntriesAsync([], cancellationToken);
            logger.LogInformation("Removed all {RouteCount} recorded route plan(s).", existing.Count);
        }
        finally
        {
            _gate.Release();
        }
    }

    private Task AddWindowsRoutesAsync(IReadOnlyList<RouteEntry> entries, CancellationToken cancellationToken)
    {
        if (entries.Count == 0)
        {
            return Task.CompletedTask;
        }

        var prefixes = string.Join(",", entries.Select(entry => $"'{entry.Ip}/32'"));
        var interfaceIndex = entries[0].InterfaceIndex;
        var command = $"$prefixes=@({prefixes}); foreach($prefix in $prefixes) {{ if (-not (Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex {interfaceIndex} -ErrorAction SilentlyContinue)) {{ New-NetRoute -DestinationPrefix $prefix -InterfaceIndex {interfaceIndex} -NextHop '0.0.0.0' -PolicyStore ActiveStore -ErrorAction Stop | Out-Null }} }}";

        return _powerShellRunner.RunAsync(command, cancellationToken);
    }

    private Task RemoveWindowsRoutesAsync(IReadOnlyList<RouteEntry> entries, CancellationToken cancellationToken)
    {
        if (entries.Count == 0)
        {
            return Task.CompletedTask;
        }

        var routes = string.Join(",", entries.Select(entry =>
            $"@{{Prefix='{entry.Ip}/32';InterfaceIndex={entry.InterfaceIndex}}}"));
        var command =
            $"$routes=@({routes}); foreach($route in $routes) {{ Get-NetRoute -DestinationPrefix $route.Prefix -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue }}";

        return _powerShellRunner.RunAsync(command, cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        await _powerShellRunner.DisposeAsync();
        _gate.Dispose();
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

public static class ManagedRouteLifecycle
{
    public const string PersistentDnsDomain = "__vpn_dns__";

    public static ManagedRouteUpdate Update(
        IReadOnlyList<RouteEntry> existing,
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> domainIps,
        Guid profileId,
        int interfaceIndex,
        DateTimeOffset now,
        TimeSpan lifetime)
    {
        var discovered = domainIps
            .SelectMany(pair => pair.Value
                .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                .Select(address => (Ip: address, Domain: pair.Key)))
            .GroupBy(item => item.Ip.ToString(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var entries = new List<RouteEntry>(existing.Count + discovered.Count);
        var refreshedCount = 0;

        foreach (var entry in existing)
        {
            if (entry.ProfileId == profileId && discovered.Remove(entry.Ip.ToString(), out var match))
            {
                entries.Add(entry with
                {
                    Domain = match.Domain,
                    ExpiresAt = ExpirationFor(match.Domain, now, lifetime),
                    InterfaceIndex = interfaceIndex
                });
                refreshedCount++;
            }
            else
            {
                entries.Add(entry);
            }
        }

        var added = discovered.Values
            .Select(item => new RouteEntry(
                item.Ip,
                item.Domain,
                profileId,
                ExpirationFor(item.Domain, now, lifetime),
                interfaceIndex,
                "VpnRouter.RoutePrototype"))
            .ToArray();
        entries.AddRange(added);
        return new ManagedRouteUpdate(entries, added, refreshedCount);
    }

    public static IReadOnlyList<RouteEntry> FindExpired(
        IReadOnlyList<RouteEntry> entries,
        Guid profileId,
        DateTimeOffset now) =>
        entries
            .Where(entry =>
                entry.ProfileId == profileId
                && entry.Domain != PersistentDnsDomain
                && entry.ExpiresAt <= now)
            .ToArray();

    private static DateTimeOffset ExpirationFor(string domain, DateTimeOffset now, TimeSpan lifetime) =>
        domain == PersistentDnsDomain ? DateTimeOffset.MaxValue : now.Add(lifetime);
}

public sealed record ManagedRouteUpdate(
    IReadOnlyList<RouteEntry> Entries,
    IReadOnlyList<RouteEntry> Added,
    int RefreshedCount);
