using VpnRouter.Vpn.WireGuard;
using VpnRouter.Service.Networking;
using VpnRouter.Service.Storage;

var tests = new (string Name, Action Body)[]
{
    ("Parse valid WireGuard config", ParsesValidConfig),
    ("Prepare import sanitizes private key", PrepareImportSanitizesPrivateKey),
    ("Reject missing peer section", RejectsMissingPeerSection),
    ("Reject invalid CIDR", RejectsInvalidCidr),
    ("Parse DNS AAAA query", ParsesDnsAaaaQuery),
    ("Create empty DNS NoError response", CreatesEmptyDnsNoErrorResponse),
    ("Keep WireGuard endpoint when DNS pre-resolution fails", KeepsEndpointWhenDnsPreResolutionFails)
};

var failures = 0;
foreach (var test in tests)
{
    try
    {
        test.Body();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failures++;
        Console.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

if (failures > 0)
{
    Environment.ExitCode = 1;
}

static void ParsesValidConfig()
{
    var parser = new WireGuardConfigParser();
    var config = parser.Parse(ValidConfig());

    AssertEqual("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", config.Interface.PrivateKey);
    AssertEqual("10.7.0.2/32", config.Interface.Addresses[0]);
    AssertEqual("1.1.1.1", config.Interface.DnsServers[0]);
    AssertEqual(51820, config.Interface.ListenPort);
    AssertEqual(1, config.Peers.Count);
    AssertEqual("vpn.example.com:51820", config.Peers[0].Endpoint);
    AssertEqual("0.0.0.0/0", config.Peers[0].AllowedIps[0]);
    AssertEqual("::/0", config.Peers[0].AllowedIps[1]);
}

static void PrepareImportSanitizesPrivateKey()
{
    var parser = new WireGuardConfigParser();
    var result = parser.PrepareImport(ValidConfig());

    Assert(result.SanitizedConfig.Contains("PrivateKey = <stored securely>"), "sanitized config must mask private key");
    Assert(!result.SanitizedConfig.Contains("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="), "sanitized config leaked private key");
    AssertEqual("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", result.PrivateKeySecret);
    AssertEqual(1, result.Summary.PeerCount);
}

static void RejectsMissingPeerSection()
{
    var parser = new WireGuardConfigParser();
    AssertThrows<WireGuardConfigException>(() => parser.Parse("""
        [Interface]
        PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
        Address = 10.7.0.2/32
        """));
}

static void RejectsInvalidCidr()
{
    var parser = new WireGuardConfigParser();
    AssertThrows<WireGuardConfigException>(() => parser.Parse(ValidConfig().Replace("10.7.0.2/32", "10.7.0.2")));
}

static void ParsesDnsAaaaQuery()
{
    var query = DnsQueryParser.TryParse(DnsQueryPacket("youtube.com", 28));

    Assert(query is not null, "DNS query should be parsed.");
    AssertEqual("youtube.com", query!.Domain);
    AssertEqual("AAAA", query.QueryType);
}

static void CreatesEmptyDnsNoErrorResponse()
{
    var response = DnsQueryParser.CreateEmptyNoErrorResponse(DnsQueryPacket("youtube.com", 28));

    Assert((response[2] & 0x80) == 0x80, "response bit should be set");
    AssertEqual(0, response[6]);
    AssertEqual(0, response[7]);
    AssertEqual(0, response[8]);
    AssertEqual(0, response[9]);
    AssertEqual(0, response[10]);
    AssertEqual(0, response[11]);
}

static void KeepsEndpointWhenDnsPreResolutionFails()
{
    var config = ValidConfig().Replace("vpn.example.com:51820", "missing.invalid:51820 # provider endpoint");
    var resolved = WireGuardRuntimeConfigStore
        .ResolveEndpointHostsAsync(config, CancellationToken.None)
        .GetAwaiter()
        .GetResult();

    Assert(resolved.Contains("Endpoint = missing.invalid:51820 # provider endpoint"), "unresolvable endpoint should remain unchanged");
}

static string ValidConfig() => """
    [Interface]
    PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
    Address = 10.7.0.2/32
    DNS = 1.1.1.1, 8.8.8.8
    ListenPort = 51820

    [Peer]
    PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
    PresharedKey = CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = vpn.example.com:51820
    PersistentKeepalive = 25
    """;

static byte[] DnsQueryPacket(string domain, ushort queryType)
{
    var bytes = new List<byte>
    {
        0x12, 0x34,
        0x01, 0x00,
        0x00, 0x01,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00
    };

    foreach (var label in domain.Split('.'))
    {
        bytes.Add((byte)label.Length);
        bytes.AddRange(System.Text.Encoding.ASCII.GetBytes(label));
    }

    bytes.Add(0);
    bytes.Add((byte)(queryType >> 8));
    bytes.Add((byte)(queryType & 0xFF));
    bytes.Add(0x00);
    bytes.Add(0x01);
    return bytes.ToArray();
}

static void Assert(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}, got {actual}.");
    }
}

static void AssertThrows<TException>(Action action)
    where TException : Exception
{
    try
    {
        action();
    }
    catch (TException)
    {
        return;
    }

    throw new InvalidOperationException($"Expected exception {typeof(TException).Name}.");
}
