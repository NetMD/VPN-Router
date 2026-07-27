using Microsoft.Extensions.Options;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Service.Configuration;
using VpnRouter.Service.Storage;
using VpnRouter.Vpn.WireGuard;
using System.Text.Json;

namespace VpnRouter.Service.Diagnostics;

public sealed class DiagnosticsService(
    ProfileStore profileStore,
    IOptions<VpnRouterFeatureOptions> options)
{
    public async Task<DiagnosticsDto> GetAsync(CancellationToken cancellationToken)
    {
        var dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VpnRouter");
        var profiles = await profileStore.ListProfilesAsync(cancellationToken);
        var wireGuard = WireGuardInstallationDetector.Detect();
        var features = options.Value;
        var managedRoutesPath = Path.Combine(dataRoot, "managed-routes.json");
        var dnsObservationsPath = Path.Combine(dataRoot, "dns-observations.json");

        return new DiagnosticsDto(
            ServiceReachable: true,
            WireGuardInstalled: wireGuard.IsInstalled,
            WireGuardMessage: wireGuard.Message,
            ProfileCount: profiles.Count,
            ManagedRouteCount: CountJsonArrayEntries(managedRoutesPath),
            DnsObservationCount: CountLines(dnsObservationsPath),
            NetworkSnapshotExists: File.Exists(Path.Combine(dataRoot, "network-snapshot.json")),
            ManagedRoutesExists: File.Exists(managedRoutesPath),
            DnsObservationsExists: File.Exists(dnsObservationsPath),
            EnableWireGuardActivation: features.EnableWireGuardActivation,
            EnableWindowsDnsMutation: features.EnableWindowsDnsMutation,
            EnableWindowsRouteMutation: features.EnableWindowsRouteMutation);
    }

    public async Task<string> CreateTroubleshootingFileAsync(CancellationToken cancellationToken)
    {
        var dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VpnRouter");
        Directory.CreateDirectory(dataRoot);

        var diagnostics = await GetAsync(cancellationToken);
        var filePath = Path.Combine(dataRoot, $"troubleshooting-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.txt");

        var lines = BuildTroubleshootingLines(diagnostics, DateTimeOffset.UtcNow);

        await File.WriteAllLinesAsync(filePath, lines, cancellationToken);
        return filePath;
    }

    public static IReadOnlyList<string> BuildTroubleshootingLines(
        DiagnosticsDto diagnostics,
        DateTimeOffset createdAtUtc) =>
    [
        "VPN Router troubleshooting file",
        "SchemaVersion: 1",
        $"CreatedAtUtc: {createdAtUtc:O}",
        "",
        "Diagnostics:",
        $"ServiceReachable: {diagnostics.ServiceReachable}",
        $"WireGuardInstalled: {diagnostics.WireGuardInstalled}",
        $"WireGuardMessage: {diagnostics.WireGuardMessage}",
        $"ProfileCount: {diagnostics.ProfileCount}",
        $"ManagedRouteCount: {diagnostics.ManagedRouteCount}",
        $"DnsObservationCount: {diagnostics.DnsObservationCount}",
        $"NetworkSnapshotExists: {diagnostics.NetworkSnapshotExists}",
        $"ManagedRoutesExists: {diagnostics.ManagedRoutesExists}",
        $"DnsObservationsExists: {diagnostics.DnsObservationsExists}",
        $"EnableWireGuardActivation: {diagnostics.EnableWireGuardActivation}",
        $"EnableWindowsDnsMutation: {diagnostics.EnableWindowsDnsMutation}",
        $"EnableWindowsRouteMutation: {diagnostics.EnableWindowsRouteMutation}",
        ""
    ];

    private static int CountJsonArrayEntries(string path)
    {
        if (!File.Exists(path))
        {
            return 0;
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return document.RootElement.ValueKind == JsonValueKind.Array
                ? document.RootElement.GetArrayLength()
                : 0;
        }
        catch (JsonException)
        {
            return 0;
        }
    }

    private static int CountLines(string path) =>
        File.Exists(path) ? File.ReadLines(path).Take(100_000).Count() : 0;
}
