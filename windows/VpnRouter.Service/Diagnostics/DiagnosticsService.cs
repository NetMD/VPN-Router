using Microsoft.Extensions.Options;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Service.Configuration;
using VpnRouter.Service.Storage;
using VpnRouter.Vpn.WireGuard;

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

        return new DiagnosticsDto(
            ServiceReachable: true,
            WireGuardInstalled: wireGuard.IsInstalled,
            WireGuardMessage: wireGuard.Message,
            ProfileCount: profiles.Count,
            NetworkSnapshotExists: File.Exists(Path.Combine(dataRoot, "network-snapshot.json")),
            ManagedRoutesExists: File.Exists(Path.Combine(dataRoot, "managed-routes.json")),
            DnsObservationsExists: File.Exists(Path.Combine(dataRoot, "dns-observations.json")),
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

        var lines = new List<string>
        {
            "VPN Router troubleshooting file",
            $"CreatedAtUtc: {DateTimeOffset.UtcNow:O}",
            "",
            "Diagnostics:",
            $"ServiceReachable: {diagnostics.ServiceReachable}",
            $"WireGuardInstalled: {diagnostics.WireGuardInstalled}",
            $"WireGuardMessage: {diagnostics.WireGuardMessage}",
            $"ProfileCount: {diagnostics.ProfileCount}",
            $"NetworkSnapshotExists: {diagnostics.NetworkSnapshotExists}",
            $"ManagedRoutesExists: {diagnostics.ManagedRoutesExists}",
            $"DnsObservationsExists: {diagnostics.DnsObservationsExists}",
            $"EnableWireGuardActivation: {diagnostics.EnableWireGuardActivation}",
            $"EnableWindowsDnsMutation: {diagnostics.EnableWindowsDnsMutation}",
            $"EnableWindowsRouteMutation: {diagnostics.EnableWindowsRouteMutation}",
            ""
        };

        AppendFilePreview(lines, Path.Combine(dataRoot, "network-snapshot.json"), "Network snapshot");
        AppendFilePreview(lines, Path.Combine(dataRoot, "managed-routes.json"), "Managed route plan");
        AppendFilePreview(lines, Path.Combine(dataRoot, "dns-observations.json"), "DNS observations");

        await File.WriteAllLinesAsync(filePath, lines, cancellationToken);
        return filePath;
    }

    private static void AppendFilePreview(List<string> lines, string path, string title)
    {
        lines.Add($"{title}:");
        if (!File.Exists(path))
        {
            lines.Add("  <missing>");
            lines.Add("");
            return;
        }

        var text = File.ReadAllText(path);
        lines.Add(text.Length <= 4000 ? text : text[..4000] + Environment.NewLine + "<truncated>");
        lines.Add("");
    }
}
