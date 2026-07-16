using System.Net;

namespace VpnRouter.Vpn.WireGuard;

public sealed class WireGuardConfigParser
{
    private const string InterfaceSection = "Interface";
    private const string PeerSection = "Peer";

    public WireGuardConfig Parse(string configText)
    {
        if (string.IsNullOrWhiteSpace(configText))
        {
            throw new WireGuardConfigException("WireGuard config is empty.");
        }

        var sections = ParseSections(configText);
        var interfaceValues = GetRequiredSection(sections, InterfaceSection);
        var peers = sections
            .Where(section => string.Equals(section.Name, PeerSection, StringComparison.OrdinalIgnoreCase))
            .Select(ParsePeer)
            .ToArray();

        if (peers.Length == 0)
        {
            throw new WireGuardConfigException("WireGuard config must contain at least one [Peer] section.");
        }

        var parsed = new WireGuardConfig(ParseInterface(interfaceValues), peers);
        Validate(parsed);
        return parsed;
    }

    public WireGuardImportResult PrepareImport(string configText)
    {
        var config = Parse(configText);
        var sanitizedConfig = Sanitize(configText);

        return new WireGuardImportResult(
            config,
            sanitizedConfig,
            config.Interface.PrivateKey,
            CreateSummary(config));
    }

    public string Sanitize(string configText)
    {
        if (string.IsNullOrWhiteSpace(configText))
        {
            return string.Empty;
        }

        var sanitizedLines = new List<string>();
        foreach (var rawLine in NormalizeLineEndings(configText).Split('\n'))
        {
            var line = rawLine.TrimEnd('\r');
            var trimmed = line.Trim();
            if (trimmed.StartsWith("PrivateKey", StringComparison.OrdinalIgnoreCase)
                && TrySplitKeyValue(trimmed, out var key, out _))
            {
                sanitizedLines.Add($"{key} = <stored securely>");
            }
            else
            {
                sanitizedLines.Add(line);
            }
        }

        return string.Join(Environment.NewLine, sanitizedLines).Trim();
    }

    public WireGuardConfigSummary CreateSummary(WireGuardConfig config)
    {
        return new WireGuardConfigSummary(
            HasInterfaceSection: true,
            HasPeerSection: config.Peers.Count > 0,
            HasPrivateKey: !string.IsNullOrWhiteSpace(config.Interface.PrivateKey),
            InterfaceAddresses: config.Interface.Addresses,
            DnsServers: config.Interface.DnsServers,
            PeerCount: config.Peers.Count,
            AllowedIps: config.Peers.SelectMany(peer => peer.AllowedIps).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(),
            Endpoints: config.Peers.Select(peer => peer.Endpoint).Where(endpoint => endpoint is not null).Cast<string>().ToArray());
    }

    private static WireGuardInterfaceConfig ParseInterface(ParsedSection section)
    {
        var values = section.Values;

        return new WireGuardInterfaceConfig(
            PrivateKey: GetRequiredValue(values, "PrivateKey", InterfaceSection),
            Addresses: SplitCsv(values.GetValueOrDefault("Address")).ToArray(),
            DnsServers: SplitCsv(values.GetValueOrDefault("DNS")).ToArray(),
            ListenPort: ParseNullableInt(values.GetValueOrDefault("ListenPort"), "ListenPort"));
    }

    private static WireGuardPeerConfig ParsePeer(ParsedSection section)
    {
        var values = section.Values;

        return new WireGuardPeerConfig(
            PublicKey: GetRequiredValue(values, "PublicKey", PeerSection),
            PresharedKey: values.GetValueOrDefault("PresharedKey"),
            Endpoint: values.GetValueOrDefault("Endpoint"),
            AllowedIps: SplitCsv(values.GetValueOrDefault("AllowedIPs")).ToArray(),
            PersistentKeepalive: ParseNullableInt(values.GetValueOrDefault("PersistentKeepalive"), "PersistentKeepalive"));
    }

    private static void Validate(WireGuardConfig config)
    {
        if (config.Interface.Addresses.Count == 0)
        {
            throw new WireGuardConfigException("[Interface] must contain at least one Address.");
        }

        ValidateBase64LikeKey(config.Interface.PrivateKey, "PrivateKey");

        foreach (var address in config.Interface.Addresses)
        {
            ValidateCidr(address, "Address");
        }

        foreach (var dnsServer in config.Interface.DnsServers)
        {
            if (!IPAddress.TryParse(dnsServer, out _))
            {
                throw new WireGuardConfigException($"DNS value is not a valid IP address: {dnsServer}");
            }
        }

        foreach (var peer in config.Peers)
        {
            ValidateBase64LikeKey(peer.PublicKey, "PublicKey");

            if (!string.IsNullOrWhiteSpace(peer.PresharedKey))
            {
                ValidateBase64LikeKey(peer.PresharedKey, "PresharedKey");
            }

            if (peer.AllowedIps.Count == 0)
            {
                throw new WireGuardConfigException("[Peer] must contain at least one AllowedIPs value.");
            }

            foreach (var allowedIp in peer.AllowedIps)
            {
                ValidateCidr(allowedIp, "AllowedIPs");
            }
        }
    }

    private static IReadOnlyList<ParsedSection> ParseSections(string configText)
    {
        var sections = new List<ParsedSection>();
        ParsedSection? currentSection = null;

        var lineNumber = 0;
        foreach (var rawLine in NormalizeLineEndings(configText).Split('\n'))
        {
            lineNumber++;
            var line = StripComment(rawLine).Trim();
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                var sectionName = line[1..^1].Trim();
                if (string.IsNullOrWhiteSpace(sectionName))
                {
                    throw new WireGuardConfigException($"Empty section name at line {lineNumber}.");
                }

                currentSection = new ParsedSection(sectionName, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase));
                sections.Add(currentSection);
                continue;
            }

            if (currentSection is null)
            {
                throw new WireGuardConfigException($"Key/value pair appears before any section at line {lineNumber}.");
            }

            if (!TrySplitKeyValue(line, out var key, out var value))
            {
                throw new WireGuardConfigException($"Invalid key/value line at line {lineNumber}.");
            }

            currentSection.Values[key] = value;
        }

        return sections;
    }

    private static ParsedSection GetRequiredSection(IReadOnlyList<ParsedSection> sections, string name)
    {
        var section = sections.FirstOrDefault(section => string.Equals(section.Name, name, StringComparison.OrdinalIgnoreCase));
        return section ?? throw new WireGuardConfigException($"WireGuard config must contain [{name}] section.");
    }

    private static string GetRequiredValue(IReadOnlyDictionary<string, string> values, string key, string sectionName)
    {
        return values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new WireGuardConfigException($"[{sectionName}] must contain {key}.");
    }

    private static bool TrySplitKeyValue(string line, out string key, out string value)
    {
        var equalsIndex = line.IndexOf('=');
        if (equalsIndex <= 0)
        {
            key = string.Empty;
            value = string.Empty;
            return false;
        }

        key = line[..equalsIndex].Trim();
        value = line[(equalsIndex + 1)..].Trim();
        return !string.IsNullOrWhiteSpace(key);
    }

    private static IEnumerable<string> SplitCsv(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return [];
        }

        return value
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(item => !string.IsNullOrWhiteSpace(item));
    }

    private static int? ParseNullableInt(string? value, string key)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return int.TryParse(value, out var parsed) && parsed is >= 0 and <= 65535
            ? parsed
            : throw new WireGuardConfigException($"{key} must be a valid port/interval integer.");
    }

    private static void ValidateBase64LikeKey(string value, string key)
    {
        if (value.Length < 32)
        {
            throw new WireGuardConfigException($"{key} is too short to be a valid WireGuard key.");
        }
    }

    private static void ValidateCidr(string value, string key)
    {
        var parts = value.Split('/', StringSplitOptions.TrimEntries);
        if (parts.Length != 2 || !IPAddress.TryParse(parts[0], out _) || !int.TryParse(parts[1], out var prefix))
        {
            throw new WireGuardConfigException($"{key} value must be CIDR notation: {value}");
        }

        var maxPrefix = parts[0].Contains(':') ? 128 : 32;
        if (prefix < 0 || prefix > maxPrefix)
        {
            throw new WireGuardConfigException($"{key} prefix is out of range: {value}");
        }
    }

    private static string StripComment(string line)
    {
        var hashIndex = line.IndexOf('#');
        return hashIndex >= 0 ? line[..hashIndex] : line;
    }

    private static string NormalizeLineEndings(string value) => value.Replace("\r\n", "\n").Replace('\r', '\n');

    private sealed record ParsedSection(string Name, Dictionary<string, string> Values);
}

public sealed record WireGuardImportResult(
    WireGuardConfig Config,
    string SanitizedConfig,
    string PrivateKeySecret,
    WireGuardConfigSummary Summary);

public sealed record WireGuardConfig(WireGuardInterfaceConfig Interface, IReadOnlyList<WireGuardPeerConfig> Peers);

public sealed record WireGuardInterfaceConfig(
    string PrivateKey,
    IReadOnlyList<string> Addresses,
    IReadOnlyList<string> DnsServers,
    int? ListenPort);

public sealed record WireGuardPeerConfig(
    string PublicKey,
    string? PresharedKey,
    string? Endpoint,
    IReadOnlyList<string> AllowedIps,
    int? PersistentKeepalive);

public sealed record WireGuardConfigSummary(
    bool HasInterfaceSection,
    bool HasPeerSection,
    bool HasPrivateKey,
    IReadOnlyList<string> InterfaceAddresses,
    IReadOnlyList<string> DnsServers,
    int PeerCount,
    IReadOnlyList<string> AllowedIps,
    IReadOnlyList<string> Endpoints);

public sealed class WireGuardConfigException(string message) : Exception(message);
