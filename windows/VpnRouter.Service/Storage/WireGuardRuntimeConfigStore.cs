using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using VpnRouter.Vpn.WireGuard;

namespace VpnRouter.Service.Storage;

public sealed class WireGuardRuntimeConfigStore
{
    private readonly string _runtimeDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "wireguard-runtime");

    public async Task<string> MaterializeAsync(
        Guid profileId,
        string configText,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_runtimeDirectory);

        var path = Path.Combine(_runtimeDirectory, $"{WireGuardTunnelName.ForProfile(profileId)}.conf");
        var runtimeConfigText = await ResolveEndpointHostsAsync(configText, cancellationToken);
        await File.WriteAllTextAsync(path, runtimeConfigText, cancellationToken);
        return path;
    }

    public Task DeleteAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var path = Path.Combine(_runtimeDirectory, $"{WireGuardTunnelName.ForProfile(profileId)}.conf");
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        return Task.CompletedTask;
    }

    public static async Task<string> ResolveEndpointHostsAsync(string configText, CancellationToken cancellationToken)
    {
        var lines = configText.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var trimmed = line.Trim();
            if (!trimmed.StartsWith("Endpoint", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var equalsIndex = line.IndexOf('=');
            if (equalsIndex <= 0)
            {
                continue;
            }

            var endpoint = StripInlineComment(line[(equalsIndex + 1)..]).Trim();
            if (!TrySplitEndpoint(endpoint, out var host, out var port)
                || IPAddress.TryParse(host, out _))
            {
                continue;
            }

            IPAddress[] addresses;
            try
            {
                addresses = await Dns.GetHostAddressesAsync(host, cancellationToken);
            }
            catch (SocketException)
            {
                continue;
            }

            var ipv4 = addresses.FirstOrDefault(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);
            if (ipv4 is null)
            {
                continue;
            }

            lines[i] = $"{line[..(equalsIndex + 1)]} {ipv4}:{port}";
        }

        return string.Join(Environment.NewLine, lines).Trim();
    }

    private static string StripInlineComment(string value)
    {
        var hashIndex = value.IndexOf('#');
        var semicolonIndex = value.IndexOf(';');
        var indexes = new[] { hashIndex, semicolonIndex }.Where(index => index >= 0).ToArray();
        return indexes.Length == 0 ? value : value[..indexes.Min()];
    }

    private static bool TrySplitEndpoint(string endpoint, out string host, out string port)
    {
        host = string.Empty;
        port = string.Empty;

        if (endpoint.StartsWith('['))
        {
            return false;
        }

        var match = Regex.Match(endpoint, "^(?<host>[^:]+):(?<port>[0-9]{1,5})$");
        if (!match.Success)
        {
            return false;
        }

        host = match.Groups["host"].Value.Trim();
        port = match.Groups["port"].Value.Trim();
        return !string.IsNullOrWhiteSpace(host) && !string.IsNullOrWhiteSpace(port);
    }
}
