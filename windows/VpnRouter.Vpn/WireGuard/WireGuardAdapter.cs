using VpnRouter.Core.Profiles;
using VpnRouter.Vpn.Abstractions;
using System.Net.NetworkInformation;
using System.Diagnostics;
using Microsoft.Extensions.Options;

namespace VpnRouter.Vpn.WireGuard;

public sealed class WireGuardAdapter(IOptions<WireGuardAdapterOptions> options) : IVpnAdapter
{
    public VpnProfileType Type => VpnProfileType.WireGuard;

    public Task ValidateProfileAsync(VpnProfile profile, CancellationToken cancellationToken)
    {
        if (profile.Type != VpnProfileType.WireGuard)
        {
            throw new ArgumentException("Profile type must be WireGuard.", nameof(profile));
        }

        if (string.IsNullOrWhiteSpace(profile.ConfigRef))
        {
            throw new ArgumentException("WireGuard profile must reference an imported config.", nameof(profile));
        }

        return Task.CompletedTask;
    }

    public async Task ConnectAsync(VpnProfile profile, CancellationToken cancellationToken)
    {
        if (!options.Value.EnableActivation)
        {
            return;
        }

        var installation = WireGuardInstallationDetector.Detect();
        if (!installation.IsInstalled)
        {
            throw new InvalidOperationException(installation.Message);
        }

        if (!File.Exists(profile.ConfigRef))
        {
            throw new FileNotFoundException("WireGuard runtime config file was not found.", profile.ConfigRef);
        }

        await RunWireGuardIfPossibleAsync(
            installation.ExecutablePath!,
            ["/uninstalltunnelservice", WireGuardTunnelName.ForProfile(profile.Id)],
            cancellationToken);

        await RunWireGuardAsync(
            installation.ExecutablePath!,
            ["/installtunnelservice", profile.ConfigRef],
            cancellationToken);
    }

    public Task DisconnectAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var installation = WireGuardInstallationDetector.Detect();
        if (!installation.IsInstalled || !options.Value.EnableActivation)
        {
            return Task.CompletedTask;
        }

        return RunWireGuardAsync(
            installation.ExecutablePath!,
            ["/uninstalltunnelservice", WireGuardTunnelName.ForProfile(profileId)],
            cancellationToken);
    }

    public async Task<VpnInterfaceInfo> GetInterfaceInfoAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var tunnelName = WireGuardTunnelName.ForProfile(profileId);
        for (var attempt = 1; attempt <= 20; attempt++)
        {
            var candidate = FindWireGuardInterface(tunnelName);
            if (candidate is not null)
            {
                return candidate;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken);
        }

        throw new InvalidOperationException("No active WireGuard/Wintun interface was detected.");
    }

    public Task<VpnConnectionStatus> GetConnectionStatusAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var installation = WireGuardInstallationDetector.Detect();
        if (!installation.IsInstalled)
        {
            return Task.FromResult(new VpnConnectionStatus(false, installation.Message));
        }

        var tunnelName = WireGuardTunnelName.ForProfile(profileId);
        var hasInterface = FindWireGuardInterface(tunnelName) is not null;

        return Task.FromResult(new VpnConnectionStatus(
            hasInterface,
            hasInterface
                ? "WireGuard/Wintun interface is active."
                : "WireGuard is installed, but no active WireGuard/Wintun interface was detected."));
    }

    private static VpnInterfaceInfo? FindWireGuardInterface(string tunnelName)
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(networkInterface =>
                networkInterface.OperationalStatus == OperationalStatus.Up
                && IsWireGuardInterface(networkInterface, tunnelName))
            .Select(networkInterface =>
            {
                var properties = networkInterface.GetIPProperties();
                var addresses = properties.UnicastAddresses.Select(address => address.Address).ToArray();
                return new VpnInterfaceInfo(properties.GetIPv4Properties()?.Index ?? 0, networkInterface.Name, addresses);
            })
            .ToArray();

        return candidates.FirstOrDefault(item => item.InterfaceName.Contains(tunnelName, StringComparison.OrdinalIgnoreCase))
            ?? candidates.FirstOrDefault(item => item.InterfaceName.Contains("wireguard", StringComparison.OrdinalIgnoreCase))
            ?? candidates.FirstOrDefault();
    }

    private static bool IsWireGuardInterface(NetworkInterface networkInterface, string tunnelName)
    {
        return networkInterface.Name.Contains("wireguard", StringComparison.OrdinalIgnoreCase)
            || networkInterface.Description.Contains("wireguard", StringComparison.OrdinalIgnoreCase)
            || networkInterface.Name.Contains("wintun", StringComparison.OrdinalIgnoreCase)
            || networkInterface.Description.Contains("wintun", StringComparison.OrdinalIgnoreCase)
            || networkInterface.Name.Contains(tunnelName, StringComparison.OrdinalIgnoreCase)
            || networkInterface.Description.Contains(tunnelName, StringComparison.OrdinalIgnoreCase);
    }

    private static async Task RunWireGuardAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = executablePath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        }.WithArguments(arguments)) ?? throw new InvalidOperationException("Failed to start WireGuard.");

        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var error = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"WireGuard command failed. {error} {output}".Trim());
        }
    }

    private static async Task RunWireGuardIfPossibleAsync(
        string executablePath,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        try
        {
            await RunWireGuardAsync(executablePath, arguments, cancellationToken);
        }
        catch
        {
            // Best-effort cleanup before tunnel install. The following install command will report
            // the actionable error if cleanup was required and failed in a meaningful way.
        }
    }
}

public static class WireGuardTunnelName
{
    public static string ForProfile(Guid profileId) => $"VpnRtr-{profileId:N}"[..31];
}

internal static class ProcessStartInfoExtensions
{
    public static ProcessStartInfo WithArguments(this ProcessStartInfo startInfo, IEnumerable<string> arguments)
    {
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        return startInfo;
    }
}
