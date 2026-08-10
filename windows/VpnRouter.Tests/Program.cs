using VpnRouter.Vpn.WireGuard;
using VpnRouter.Service.Networking;
using VpnRouter.Service.Storage;
using VpnRouter.Service.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using VpnRouter.Core.Rules;
using VpnRouter.Core.Routing;
using System.Net;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Service.Ipc;
using VpnRouter.Service.Portable;
using VpnRouter.Service.Diagnostics;
using VpnRouter.Service.Connection;
using VpnRouter.Service.Recovery;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Vpn.Abstractions;
using VpnRouter.Core.Profiles;
using System.Collections.Concurrent;
using VpnRouter.WfpSpike;
using VpnRouter.WfpSpike.Contracts;
using VpnRouter.WfpSpike.Native;
using VpnRouter.WfpSpike.Harness;
using System.Text.Json;

var tests = new (string Name, Action Body)[]
{
    ("Parse valid WireGuard config", ParsesValidConfig),
    ("Prepare import sanitizes private key", PrepareImportSanitizesPrivateKey),
    ("Reject missing peer section", RejectsMissingPeerSection),
    ("Reject invalid CIDR", RejectsInvalidCidr),
    ("Parse DNS AAAA query", ParsesDnsAaaaQuery),
    ("Create empty DNS NoError response", CreatesEmptyDnsNoErrorResponse),
    ("Create DNS IPv4 ownership response", CreatesDnsIpv4OwnershipResponse),
    ("Parse DNS IPv4 answers", ParsesDnsIpv4Answers),
    ("Detect occupied local DNS port", DetectsOccupiedLocalDnsPort),
    ("Proxy returns empty response for target AAAA query", ProxyReturnsEmptyTargetAaaaResponse),
    ("Record concurrent DNS observations", RecordsConcurrentDnsObservations),
    ("Batch concurrent dynamic route discoveries", BatchesConcurrentDynamicRouteDiscoveries),
    ("Reuse persistent PowerShell worker", ReusesPersistentPowerShellWorker),
    ("Expand media service domains", ExpandsMediaServiceDomains),
    ("Interpret browser secure DNS policy", InterpretsBrowserSecureDnsPolicy),
    ("Restore automatic DNS mode from snapshot", RestoresAutomaticDnsModeFromSnapshot),
    ("Restore manual DNS mode from snapshot", RestoresManualDnsModeFromSnapshot),
    ("Restore legacy DNS snapshot compatibly", RestoresLegacyDnsSnapshotCompatibly),
    ("Refresh repeated managed route expiration", RefreshesRepeatedManagedRouteExpiration),
    ("Retain rotating managed route answers", RetainsRotatingManagedRouteAnswers),
    ("Reject route plan above limit before mutation", RejectsRoutePlanAboveLimitBeforeMutation),
    ("Validate backend protocol and payload identity", ValidatesBackendProtocolAndPayloadIdentity),
    ("Restrict service pipe to launching user", RestrictsServicePipeToLaunchingUser),
    ("Clean up after DNS ownership failure", CleansUpAfterDnsOwnershipFailure),
    ("Retain active and previous portable cache", RetainsActiveAndPreviousPortableCache),
    ("Create bounded troubleshooting summary", CreatesBoundedTroubleshootingSummary),
    ("Expire only eligible managed routes", ExpiresOnlyEligibleManagedRoutes),
    ("Force WireGuard runtime routing table off", ForcesRuntimeRoutingTableOff),
    ("Split WireGuard default allowed IPs", SplitsRuntimeDefaultAllowedIps),
    ("Keep WireGuard endpoint when DNS pre-resolution fails", KeepsEndpointWhenDnsPreResolutionFails),
    ("Plan desktop WFP IPv4 and IPv6 policies", PlansDesktopWfpPolicies),
    ("Plan package WFP identity policies", PlansPackageWfpPolicies),
    ("Reject invalid WFP interface before engine open", RejectsInvalidWfpInterface),
    ("Reject mismatched WFP interface identity", RejectsMismatchedWfpInterface),
    ("Roll back partial WFP policy failure", RollsBackPartialWfpPolicyFailure),
    ("Clean WFP policy session only once", CleansWfpPolicySessionOnlyOnce),
    ("Reapply WFP policy after cleanup", ReappliesWfpPolicyAfterCleanup),
    ("Keep live WFP ABI validation fail closed", KeepsLiveWfpAbiValidationFailClosed),
    ("Redact prohibited WFP result content", RedactsProhibitedWfpResultContent),
    ("Require all live WFP gate conditions", RequiresAllLiveWfpGateConditions),
    ("Reject missing WFP executable", RejectsMissingWfpExecutable),
    ("Reject directory WFP executable", RejectsDirectoryWfpExecutable),
    ("Reject non-executable WFP file", RejectsNonExecutableWfpFile),
    ("Report WFP engine access denial", ReportsWfpEngineAccessDenial),
    ("Stop after IPv4 WFP add failure", StopsAfterIpv4WfpAddFailure),
    ("Clean WFP session after cancellation", CleansWfpSessionAfterCancellation),
    ("Reject changed WFP interface", RejectsChangedWfpInterface),
    ("Retry WFP engine close failure", RetriesWfpEngineCloseFailure),
    ("Accept complete WFP case observations", AcceptsCompleteWfpCaseObservations),
    ("Reject missing WFP case observations", RejectsMissingWfpCaseObservations),
    ("Reject duplicate WFP case observations", RejectsDuplicateWfpCaseObservations),
    ("Reject invalid WFP case outcome code", RejectsInvalidWfpCaseOutcomeCode),
    ("Reject arbitrary WFP result argument", RejectsArbitraryWfpResultArgument),
    ("Reject missing WFP marker", RejectsMissingWfpMarker),
    ("Reject marker path traversal", RejectsWfpMarkerPathTraversal),
    ("Reject unprotected marker spool", RejectsUnprotectedMarkerSpool),
    ("Reject expired WFP marker", RejectsExpiredWfpMarker),
    ("Reject malformed WFP marker hash", RejectsMalformedWfpMarkerHash),
    ("Consume WFP marker only once", ConsumesWfpMarkerOnlyOnce),
    ("Keep package WFP identity evidence explicit", KeepsPackageWfpIdentityEvidenceExplicit),
    ("Report WFP app ID lookup failure", ReportsWfpAppIdLookupFailure),
    ("Reject duplicate owned WFP policy key", RejectsDuplicateOwnedWfpPolicyKey),
    ("Reject WFP case before READY", RejectsWfpCaseBeforeReady),
    ("Reject FAIL with NONE code", RejectsFailWithNoneCode),
    ("Make cleanup failure verdict FAIL", MakesCleanupFailureVerdictFail),
    ("Detect untracked feature content mutation", DetectsUntrackedFeatureContentMutation),
    ("Detect staged feature identity mutation", DetectsStagedFeatureIdentityMutation),
    ("Discover recursive Directory.Build imports", DiscoversRecursiveDirectoryBuildImports),
    ("Detect discovered import content mutation", DetectsDiscoveredImportContentMutation),
    ("Detect discovered import staged identity mutation", DetectsDiscoveredImportStagedIdentityMutation),
    ("Reject dynamic Directory.Build import", RejectsDynamicDirectoryBuildImport),
    ("Reject glob Directory.Build import", RejectsGlobDirectoryBuildImport),
    ("Reject missing Directory.Build import", RejectsMissingDirectoryBuildImport),
    ("Reject outside Directory.Build import", RejectsOutsideDirectoryBuildImport),
    ("Reject non-MSBuild import before reading", RejectsNonMsBuildImportBeforeReading),
    ("Reject reparse Directory.Build import", RejectsReparseDirectoryBuildImport),
    ("Reject cyclic Directory.Build imports", RejectsCyclicDirectoryBuildImports),
    ("Block payload mutation while execution lease held", BlocksPayloadMutationWhileExecutionLeaseHeld)
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

static void CreatesDnsIpv4OwnershipResponse()
{
    const ushort transactionId = 0x5372;
    var query = DnsQueryParser.CreateQuery("token.vpnrouter-self-test.invalid", transactionId, 1);
    var expectedAddress = IPAddress.Parse("127.255.53.53");
    var response = DnsQueryParser.CreateIpv4Response(query, expectedAddress);
    var addresses = DnsQueryParser.ParseIpv4Answers(response);

    AssertEqual(query[0], response[0]);
    AssertEqual(query[1], response[1]);
    AssertEqual(1, addresses.Count);
    AssertEqual(expectedAddress, addresses[0]);
}

static void DetectsOccupiedLocalDnsPort()
{
    int port;
    using (var listener = new System.Net.Sockets.UdpClient(System.Net.Sockets.AddressFamily.InterNetwork))
    {
        listener.ExclusiveAddressUse = true;
        listener.Client.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        port = ((IPEndPoint)listener.Client.LocalEndPoint!).Port;
        Assert(DnsConflictDetector.Detect(port) is not null, "occupied DNS port should be reported");
    }

    Assert(DnsConflictDetector.Detect(port) is null, "released DNS port should be available");
}

static void ParsesDnsIpv4Answers()
{
    var response = DnsAResponsePacket("youtube.com", [203, 0, 113, 7]);
    var addresses = DnsQueryParser.ParseIpv4Answers(response);

    AssertEqual(1, addresses.Count);
    AssertEqual("203.0.113.7", addresses[0].ToString());
}

static void ProxyReturnsEmptyTargetAaaaResponse()
{
    var controller = new WindowsDnsProxyController(
        Options.Create(new VpnRouterFeatureOptions()),
        new VpnRouter.Networking.NoopRouteManager(),
        NullLogger<WindowsDnsProxyController>.Instance);
    var profileId = Guid.NewGuid();
    var rule = new DomainRule(Guid.NewGuid(), profileId, "youtube.com", true, true, DateTimeOffset.UtcNow);

    controller.StartAsync([rule], System.Net.IPAddress.Loopback, profileId, 0, CancellationToken.None)
        .GetAwaiter()
        .GetResult();
    try
    {
        using var client = new System.Net.Sockets.UdpClient();
        client.Client.ReceiveTimeout = 3000;
        var query = DnsQueryPacket("youtube.com", 28);
        client.Send(query, query.Length, "127.0.0.1", 53535);
        var remoteEndPoint = new System.Net.IPEndPoint(System.Net.IPAddress.Any, 0);
        var response = client.Receive(ref remoteEndPoint);

        AssertEqual(0, response[6]);
        AssertEqual(0, response[7]);
    }
    finally
    {
        controller.StopAsync(CancellationToken.None).GetAwaiter().GetResult();
    }
}

static void RecordsConcurrentDnsObservations()
{
    var domain = $"concurrent-{Guid.NewGuid():N}.invalid";
    var profileId = Guid.NewGuid();
    var controller = new WindowsDnsProxyController(
        Options.Create(new VpnRouterFeatureOptions()),
        new VpnRouter.Networking.NoopRouteManager(),
        NullLogger<WindowsDnsProxyController>.Instance);
    var rule = new DomainRule(Guid.NewGuid(), profileId, domain, false, true, DateTimeOffset.UtcNow);

    controller.StartAsync([rule], IPAddress.Loopback, profileId, 0, CancellationToken.None)
        .GetAwaiter()
        .GetResult();
    try
    {
        var requests = Enumerable.Range(0, 12).Select(_ => Task.Run(() =>
        {
            using var client = new System.Net.Sockets.UdpClient();
            client.Client.ReceiveTimeout = 3000;
            var query = DnsQueryPacket(domain, 28);
            client.Send(query, query.Length, "127.0.0.1", 53535);
            var remoteEndPoint = new IPEndPoint(IPAddress.Any, 0);
            client.Receive(ref remoteEndPoint);
        })).ToArray();
        Task.WhenAll(requests).GetAwaiter().GetResult();
    }
    finally
    {
        controller.StopAsync(CancellationToken.None).GetAwaiter().GetResult();
    }

    var observationsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VpnRouter",
        "dns-observations.json");
    var matchingCount = File.ReadAllLines(observationsPath)
        .Count(line => line.Contains($"\"Domain\":\"{domain}\"", StringComparison.Ordinal));
    AssertEqual(12, matchingCount);
}

static void BatchesConcurrentDynamicRouteDiscoveries()
{
    var accumulator = new DynamicRouteAccumulator();
    Parallel.For(0, 50, index =>
    {
        accumulator.Add(
            index % 2 == 0 ? "www.youtube.com" : "WWW.YOUTUBE.COM",
            [IPAddress.Parse("203.0.113.1"), IPAddress.Parse($"203.0.113.{10 + index % 10}")]);
    });

    var batch = accumulator.Drain();

    AssertEqual(1, batch.Count);
    AssertEqual(11, batch["www.youtube.com"].Count);
    AssertEqual(0, accumulator.Drain().Count);
}

static void ReusesPersistentPowerShellWorker()
{
    var runner = new PersistentPowerShellRunner(NullLogger.Instance);
    try
    {
        runner.RunAsync("$null = 1 + 1", CancellationToken.None).GetAwaiter().GetResult();
        var firstProcessId = runner.ProcessId;
        runner.RunAsync("$null = 2 + 2", CancellationToken.None).GetAwaiter().GetResult();

        Assert(firstProcessId is not null, "PowerShell worker should be running after the first command.");
        AssertEqual(firstProcessId, runner.ProcessId);
        AssertThrows<InvalidOperationException>(() =>
            runner.RunAsync("throw 'expected worker failure'", CancellationToken.None).GetAwaiter().GetResult());
    }
    finally
    {
        runner.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }
}

static void ExpandsMediaServiceDomains()
{
    var profileId = Guid.NewGuid();
    var rules = new[]
    {
        new DomainRule(Guid.NewGuid(), profileId, "youtube.com", true, true, DateTimeOffset.UtcNow),
        new DomainRule(Guid.NewGuid(), profileId, "netflix.com", true, true, DateTimeOffset.UtcNow),
        new DomainRule(Guid.NewGuid(), profileId, "ytimg.com", true, true, DateTimeOffset.UtcNow)
    };

    var expanded = DomainRuleExpander.Expand(rules);
    var domains = expanded.Select(rule => rule.Domain).ToArray();

    Assert(domains.Contains("googlevideo.com"), "YouTube video CDN should be included.");
    Assert(domains.Contains("nflxvideo.net"), "Netflix video CDN should be included.");
    Assert(domains.Contains("www.youtube.com"), "YouTube www entry point should be explicit.");
    Assert(domains.Contains("www.netflix.com"), "Netflix www entry point should be explicit.");
    AssertEqual(1, domains.Count(domain => string.Equals(domain, "ytimg.com", StringComparison.OrdinalIgnoreCase)));
    AssertEqual(domains.Length, domains.Distinct(StringComparer.OrdinalIgnoreCase).Count());
}

static void InterpretsBrowserSecureDnsPolicy()
{
    AssertEqual<string?>(null, BrowserSecureDnsDetector.BuildWarning("Chrome", false, null));
    AssertEqual<string?>(null, BrowserSecureDnsDetector.BuildWarning("Chrome", true, "off"));
    Assert(
        BrowserSecureDnsDetector.BuildWarning("Chrome", true, null)?.Contains("보안 DNS") == true,
        "An installed browser without an off policy should produce guidance.");
    Assert(
        BrowserSecureDnsDetector.BuildWarning("Edge", true, "automatic")?.Contains("automatic") == true,
        "A non-off policy value should be included in the warning.");
}

static void RestoresAutomaticDnsModeFromSnapshot()
{
    const string snapshot = """
        {
          "InterfaceIndex": 8,
          "AddressFamily": 2,
          "ServerAddresses": [ "192.0.2.53" ],
          "IsAutomatic": true
        }
        """;

    var entry = DnsSnapshotRestorePlanner.ParseEntries(snapshot).Single();
    var command = DnsSnapshotRestorePlanner.BuildRestoreCommand(entry);

    AssertEqual(
        "Set-DnsClientServerAddress -InterfaceIndex 8 -ResetServerAddresses",
        command);
}

static void RestoresManualDnsModeFromSnapshot()
{
    const string snapshot = """
        {
          "InterfaceIndex": 8,
          "AddressFamily": 2,
          "ServerAddresses": [ "192.0.2.53", "198.51.100.53" ],
          "IsAutomatic": false
        }
        """;

    var entry = DnsSnapshotRestorePlanner.ParseEntries(snapshot).Single();
    var command = DnsSnapshotRestorePlanner.BuildRestoreCommand(entry);

    AssertEqual(
        "Set-DnsClientServerAddress -InterfaceIndex 8 -ServerAddresses @('192.0.2.53','198.51.100.53')",
        command);
}

static void RestoresLegacyDnsSnapshotCompatibly()
{
    const string snapshot = """
        {
          "InterfaceIndex": 8,
          "AddressFamily": 2,
          "ServerAddresses": [ "192.0.2.53" ]
        }
        """;

    var entry = DnsSnapshotRestorePlanner.ParseEntries(snapshot).Single();
    var command = DnsSnapshotRestorePlanner.BuildRestoreCommand(entry);

    AssertEqual<bool?>(null, entry.IsAutomatic);
    AssertEqual(
        "Set-DnsClientServerAddress -InterfaceIndex 8 -ServerAddresses @('192.0.2.53')",
        command);
}

static void RefreshesRepeatedManagedRouteExpiration()
{
    var profileId = Guid.NewGuid();
    var now = DateTimeOffset.Parse("2026-07-18T12:00:00Z");
    var ip = IPAddress.Parse("203.0.113.7");
    var existing = new RouteEntry(
        ip,
        "youtube.com",
        profileId,
        now.AddMinutes(1),
        54,
        "VpnRouter.RoutePrototype");

    var update = ManagedRouteLifecycle.Update(
        [existing],
        new Dictionary<string, IReadOnlyList<IPAddress>> { ["www.youtube.com"] = [ip] },
        profileId,
        55,
        now,
        TimeSpan.FromMinutes(15));

    AssertEqual(0, update.Added.Count);
    AssertEqual(1, update.RefreshedCount);
    AssertEqual("www.youtube.com", update.Entries[0].Domain);
    AssertEqual(now.AddMinutes(15), update.Entries[0].ExpiresAt);
    AssertEqual(55, update.Entries[0].InterfaceIndex);
}

static void RetainsRotatingManagedRouteAnswers()
{
    var profileId = Guid.NewGuid();
    var now = DateTimeOffset.Parse("2026-07-28T12:00:00Z");
    var originalExpiration = now.AddMinutes(4);
    var originalAddress = IPAddress.Parse("203.0.113.10");
    var rotatedAddress = IPAddress.Parse("203.0.113.11");
    var existing = new RouteEntry(
        originalAddress,
        "www.youtube.com",
        profileId,
        originalExpiration,
        54,
        "VpnRouter.RoutePrototype");

    var update = ManagedRouteLifecycle.Update(
        [existing],
        new Dictionary<string, IReadOnlyList<IPAddress>>
        {
            ["www.youtube.com"] = [rotatedAddress]
        },
        profileId,
        54,
        now,
        TimeSpan.FromMinutes(15));

    AssertEqual(2, update.Entries.Count);
    AssertEqual(1, update.Added.Count);
    AssertEqual(0, update.RefreshedCount);
    AssertEqual(originalExpiration, update.Entries.Single(entry => entry.Ip.Equals(originalAddress)).ExpiresAt);
    AssertEqual(now.AddMinutes(15), update.Entries.Single(entry => entry.Ip.Equals(rotatedAddress)).ExpiresAt);
}

static void RejectsRoutePlanAboveLimitBeforeMutation()
{
    var profileId = Guid.NewGuid();
    var now = DateTimeOffset.Parse("2026-07-28T12:00:00Z");
    var existing = Enumerable.Range(0, ManagedRouteLifecycle.MaxActiveRoutesPerProfile)
        .Select(index => new RouteEntry(
            IPAddress.Parse($"10.0.{index / 256}.{index % 256}"),
            "example.invalid",
            profileId,
            now.AddMinutes(5),
            54,
            "test"))
        .ToArray();
    var originalEntries = existing.ToArray();

    AssertThrows<InvalidOperationException>(() => ManagedRouteLifecycle.Update(
        existing,
        new Dictionary<string, IReadOnlyList<IPAddress>>
        {
            ["rotated.example.invalid"] = [IPAddress.Parse("192.0.2.1")]
        },
        profileId,
        54,
        now,
        TimeSpan.FromMinutes(15)));

    AssertEqual(originalEntries.Length, existing.Length);
    Assert(originalEntries.SequenceEqual(existing), "Rejected route planning must not mutate existing entries.");
}

static void ValidatesBackendProtocolAndPayloadIdentity()
{
    var compatible = new BackendInformationDto(
        VpnRouterProtocol.CurrentVersion,
        "0.1.0",
        "payload-a");

    Assert(
        BackendCompatibility.Validate(compatible, "0.1.0", "payload-a").IsCompatible,
        "matching backend information should be accepted");
    Assert(
        !BackendCompatibility.Validate(compatible with { ProtocolVersion = 99 }, "0.1.0", "payload-a").IsCompatible,
        "a stale protocol should be rejected");
    Assert(
        !BackendCompatibility.Validate(compatible with { ProductVersion = "0.2.0" }, "0.1.0", "payload-a").IsCompatible,
        "a stale product version should be rejected");
    Assert(
        !BackendCompatibility.Validate(compatible with { PayloadIdentity = "payload-b" }, "0.1.0", "payload-a").IsCompatible,
        "a stale payload identity should be rejected");
}

static void RestrictsServicePipeToLaunchingUser()
{
    var launchingUser = new SecurityIdentifier("S-1-5-21-1000-1000-1000-1001");
    var security = NamedPipeSecurityFactory.CreateServicePipeSecurity(launchingUser);
    var rules = security
        .GetAccessRules(includeExplicit: true, includeInherited: false, typeof(SecurityIdentifier))
        .Cast<PipeAccessRule>()
        .ToArray();
    var interactiveSid = new SecurityIdentifier(WellKnownSidType.InteractiveSid, null);
    var administratorsSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
    var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);

    Assert(rules.Any(rule => launchingUser.Equals(rule.IdentityReference)), "launching user must have pipe access");
    Assert(rules.Any(rule => administratorsSid.Equals(rule.IdentityReference)), "administrators must retain pipe access");
    Assert(rules.Any(rule => systemSid.Equals(rule.IdentityReference)), "LocalSystem must retain pipe access");
    Assert(!rules.Any(rule => interactiveSid.Equals(rule.IdentityReference)), "InteractiveSid must not have pipe access");
    Assert(rules.All(rule => rule.AccessControlType == AccessControlType.Allow), "pipe ACL should contain only explicit allow rules");
}

static void CleansUpAfterDnsOwnershipFailure()
{
    CleansUpAfterDnsOwnershipFailureAsync().GetAwaiter().GetResult();
}

static async Task CleansUpAfterDnsOwnershipFailureAsync()
{
    var testRoot = Path.Combine(
        Path.GetTempPath(),
        $"VpnRouter-DnsOwnership-{Guid.NewGuid():N}");
    var markerPath = Path.Combine(testRoot, "active-connection.json");
    var legacyStatePath = Path.Combine(testRoot, "dns-filter-handoff.json");
    Directory.CreateDirectory(testRoot);

    try
    {
        var profileId = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        var profile = new VpnProfile(
            profileId,
            "DNS ownership cleanup test",
            VpnProfileType.WireGuard,
            true,
            "test-only",
            null,
            now,
            now);
        var rules = new[]
        {
            new DomainRule(
                Guid.NewGuid(),
                profileId,
                "ownership-test.invalid",
                true,
                true,
                now)
        };
        var calls = new ConcurrentQueue<string>();
        var vpnAdapter = new OwnershipTestVpnAdapter(calls);
        var snapshotStore = new OwnershipTestSnapshotStore(calls);
        var dnsController = new OwnershipTestDnsController(calls);
        var dnsSettings = new OwnershipTestDnsSettingsManager(calls);
        var resolver = new OwnershipTestDomainResolver(calls);
        var routeManager = new OwnershipTestRouteManager(calls);
        var recoveryStore = new ConnectionRecoveryStateStore(markerPath);
        var legacyRecovery = new LegacyDnsFilterRecovery(
            NullLogger<LegacyDnsFilterRecovery>.Instance,
            legacyStatePath);
        var stateStore = new ConnectionStateStore();
        var orchestrator = new ConnectionOrchestrator(
            vpnAdapter,
            snapshotStore,
            dnsController,
            dnsSettings,
            resolver,
            routeManager,
            recoveryStore,
            legacyRecovery,
            stateStore,
            NullLogger<ConnectionOrchestrator>.Instance);

        await orchestrator.ConnectAsync(
            profile,
            rules,
            IPAddress.Parse("192.0.2.53"),
            CancellationToken.None);
        stateStore.SetConnected(profileId, rules.Length);

        Assert(recoveryStore.HasActiveMarker, "connect should create a recovery marker before fault injection");
        AssertEqual(1, dnsController.StartCount);
        AssertEqual(1, routeManager.AddCount);

        dnsController.InjectOwnershipFailure(
            new InvalidDataException("Injected DNS ownership failure for testing."));

        var cleaned = false;
        for (var attempt = 0; attempt < 200; attempt++)
        {
            if (!recoveryStore.HasActiveMarker
                && dnsController.StopCount == 1
                && routeManager.RemoveCount >= 2
                && vpnAdapter.DisconnectCount == 1
                && snapshotStore.RestoreCount == 1)
            {
                cleaned = true;
                break;
            }

            await Task.Delay(10);
        }

        Assert(cleaned, "DNS ownership failure should complete all disconnect cleanup steps");
        Assert(!recoveryStore.HasActiveMarker, "successful cleanup should clear the recovery marker");
        AssertEqual(1, dnsController.StopCount);
        AssertEqual(2, routeManager.RemoveCount);
        AssertEqual(1, vpnAdapter.DisconnectCount);
        AssertEqual(1, snapshotStore.RestoreCount);
        Assert(!File.Exists(legacyStatePath), "test must not create or restore third-party DNS state");
        AssertEqual(ConnectionStateKind.Failed, stateStore.Snapshot().State);
        Assert(
            calls.Contains("dns.stop")
            && calls.Contains("routes.remove")
            && calls.Contains("vpn.disconnect")
            && calls.Contains("snapshot.restore"),
            "failure cleanup should execute every owned-state cleanup category");
    }
    finally
    {
        if (Directory.Exists(testRoot))
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }
}

static void RetainsActiveAndPreviousPortableCache()
{
    var cacheRoot = Path.Combine(Path.GetTempPath(), $"vpnrouter-cache-test-{Guid.NewGuid():N}");
    var activeRoot = Path.Combine(cacheRoot, "0.1.0-active");
    var previousRoot = Path.Combine(cacheRoot, "0.0.9-previous");
    var oldRoot = Path.Combine(cacheRoot, "0.0.8-old");
    var invalidRoot = Path.Combine(cacheRoot, ".invalid.staging");

    try
    {
        CreatePortableCache(activeRoot, DateTime.UtcNow);
        CreatePortableCache(previousRoot, DateTime.UtcNow.AddMinutes(-1));
        CreatePortableCache(oldRoot, DateTime.UtcNow.AddMinutes(-2));
        Directory.CreateDirectory(invalidRoot);

        var result = PortableCacheManager.CleanupCacheRoot(cacheRoot, activeRoot);

        AssertEqual(2, result.RemovedCacheCount);
        AssertEqual(2, result.RetainedCacheCount);
        Assert(Directory.Exists(activeRoot), "active payload must be retained");
        Assert(Directory.Exists(previousRoot), "immediately previous valid payload must be retained");
        Assert(!Directory.Exists(oldRoot), "older valid payload should be removed");
        Assert(!Directory.Exists(invalidRoot), "invalid staging payload should be removed");
    }
    finally
    {
        if (Directory.Exists(cacheRoot))
        {
            Directory.Delete(cacheRoot, recursive: true);
        }
    }
}

static void CreatePortableCache(string root, DateTime lastWriteTimeUtc)
{
    Directory.CreateDirectory(Path.Combine(root, "app"));
    Directory.CreateDirectory(Path.Combine(root, "backend"));
    File.WriteAllText(Path.Combine(root, ".complete"), new string('A', 64));
    File.WriteAllText(Path.Combine(root, "app", "VpnRouter.App.exe"), string.Empty);
    File.WriteAllText(Path.Combine(root, "backend", "VpnRouter.Service.exe"), string.Empty);
    Directory.SetLastWriteTimeUtc(root, lastWriteTimeUtc);
}

static void CreatesBoundedTroubleshootingSummary()
{
    var diagnostics = new DiagnosticsDto(
        ServiceReachable: true,
        WireGuardInstalled: true,
        WireGuardMessage: "Installed",
        ProfileCount: 2,
        ManagedRouteCount: 42,
        DnsObservationCount: 17,
        NetworkSnapshotExists: true,
        ManagedRoutesExists: true,
        DnsObservationsExists: true,
        EnableWireGuardActivation: true,
        EnableWindowsDnsMutation: true,
        EnableWindowsRouteMutation: true);
    var lines = DiagnosticsService.BuildTroubleshootingLines(
        diagnostics,
        DateTimeOffset.Parse("2026-07-28T12:00:00Z"));
    var text = string.Join(Environment.NewLine, lines);

    Assert(text.Contains("SchemaVersion: 1"), "troubleshooting schema should be versioned");
    Assert(text.Contains("ManagedRouteCount: 42"), "route output should be count-only");
    Assert(text.Contains("DnsObservationCount: 17"), "DNS output should be count-only");
    Assert(!text.Contains("Managed route plan:"), "managed route contents must not be exported");
    Assert(!text.Contains("DNS observations:"), "DNS observation contents must not be exported");
    Assert(lines.Count < 25, "troubleshooting output should remain bounded");
}

static void ExpiresOnlyEligibleManagedRoutes()
{
    var profileId = Guid.NewGuid();
    var otherProfileId = Guid.NewGuid();
    var now = DateTimeOffset.Parse("2026-07-18T12:00:00Z");
    var entries = new[]
    {
        new RouteEntry(IPAddress.Parse("203.0.113.1"), "youtube.com", profileId, now, 54, "test"),
        new RouteEntry(IPAddress.Parse("203.0.113.2"), ManagedRouteLifecycle.PersistentDnsDomain, profileId, now, 54, "test"),
        new RouteEntry(IPAddress.Parse("203.0.113.3"), "netflix.com", profileId, now.AddMinutes(1), 54, "test"),
        new RouteEntry(IPAddress.Parse("203.0.113.4"), "youtube.com", otherProfileId, now, 55, "test")
    };

    var expired = ManagedRouteLifecycle.FindExpired(entries, profileId, now);

    AssertEqual(1, expired.Count);
    AssertEqual("203.0.113.1", expired[0].Ip.ToString());

    var dnsUpdate = ManagedRouteLifecycle.Update(
        [],
        new Dictionary<string, IReadOnlyList<IPAddress>>
        {
            [ManagedRouteLifecycle.PersistentDnsDomain] = [IPAddress.Parse("10.100.0.1")]
        },
        profileId,
        54,
        now,
        TimeSpan.FromMinutes(15));
    AssertEqual(DateTimeOffset.MaxValue, dnsUpdate.Added[0].ExpiresAt);
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

static void ForcesRuntimeRoutingTableOff()
{
    var config = ValidConfig().Replace(
        "Address = 10.7.0.2/32",
        "Address = 10.7.0.2/32\nTable = auto");
    var runtimeConfig = WireGuardRuntimeConfigStore.ApplySplitRoutingTableOff(config);

    Assert(runtimeConfig.Contains("[Interface]", StringComparison.Ordinal), "interface section should be preserved");
    Assert(runtimeConfig.Contains("PrivateKey =", StringComparison.Ordinal), "interface keys should be preserved");
    Assert(runtimeConfig.Contains("Table = off", StringComparison.Ordinal), "runtime config must disable automatic routes");
    Assert(!runtimeConfig.Contains("Table = auto", StringComparison.Ordinal), "provider table setting must be overridden");
    AssertEqual(1, runtimeConfig.Split("Table =", StringSplitOptions.None).Length - 1);
}

static void SplitsRuntimeDefaultAllowedIps()
{
    var runtimeConfig = WireGuardRuntimeConfigStore.ApplySplitRoutingAllowedIps(ValidConfig());

    Assert(!runtimeConfig.Contains("0.0.0.0/0", StringComparison.Ordinal), "IPv4 default route must be split");
    Assert(!runtimeConfig.Contains("::/0", StringComparison.Ordinal), "IPv6 default route must be split");
    Assert(runtimeConfig.Contains("0.0.0.0/1, 128.0.0.0/1", StringComparison.Ordinal), "IPv4 coverage must be preserved");
    Assert(runtimeConfig.Contains("::/1, 8000::/1", StringComparison.Ordinal), "IPv6 coverage must be preserved");
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

static byte[] DnsAResponsePacket(string domain, byte[] address)
{
    var bytes = DnsQueryPacket(domain, 1).ToList();
    bytes[2] = 0x81;
    bytes[3] = 0x80;
    bytes[6] = 0;
    bytes[7] = 1;
    bytes.AddRange([
        0xC0, 0x0C,
        0x00, 0x01,
        0x00, 0x01,
        0x00, 0x00, 0x00, 0x3C,
        0x00, 0x04
    ]);
    bytes.AddRange(address);
    return bytes.ToArray();
}

static void PlansDesktopWfpPolicies()
{
    var fake = new FakeWfpNativeApi();
    using var session = WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42);

    AssertEqual(2, fake.Plans.Count);
    AssertEqual(WfpIpVersion.IPv4, fake.Plans[0].IpVersion);
    AssertEqual(WfpIpVersion.IPv6, fake.Plans[1].IpVersion);
    Assert(fake.Plans.All(p => p.IdentityKind == WfpAppIdentityKind.DesktopAppId), "desktop condition kind mismatch");
    Assert(fake.Plans.All(p => p.Weight == WfpPolicyPlanner.WfpSpikePolicyWeight), "policy weight mismatch");
}

static void PlansPackageWfpPolicies()
{
    var fake = new FakeWfpNativeApi();
    using var session = WfpPolicySession.Apply(fake, fake.PackageIdentity(), 42);
    Assert(fake.Plans.All(p => p.IdentityKind == WfpAppIdentityKind.PackageId), "package condition kind mismatch");
}

static void RejectsInvalidWfpInterface()
{
    var fake = new FakeWfpNativeApi();
    var ex = AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 0));
    AssertEqual(WfpSpikeResultCode.INTERFACE_NOT_FOUND, ex.Code);
    AssertEqual(0, fake.OpenCount);
}

static void RejectsMismatchedWfpInterface()
{
    var fake = new FakeWfpNativeApi { RoundTripIndex = 41 };
    var ex = AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42));
    AssertEqual(WfpSpikeResultCode.INTERFACE_IDENTITY_MISMATCH, ex.Code);
    AssertEqual(0, fake.OpenCount);
}

static void RollsBackPartialWfpPolicyFailure()
{
    var fake = new FakeWfpNativeApi { FailVersion = WfpIpVersion.IPv6 };
    var ex = AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42));
    AssertEqual(WfpSpikeResultCode.IPV6_POLICY_ADD_FAILED, ex.Code);
    AssertEqual(1, fake.DeleteCount);
    AssertEqual(1, fake.CloseCount);
    AssertEqual(0, fake.ActiveKeys.Count);
    AssertEqual(WfpOwnedPolicyKeys.DesktopIpv4, fake.DeletedKeys.Single());
}

static void CleansWfpPolicySessionOnlyOnce()
{
    var fake = new FakeWfpNativeApi();
    var session = WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42);
    session.CleanupOnce();
    session.CleanupOnce();
    AssertEqual(2, fake.DeleteCount);
    AssertEqual(1, fake.CloseCount);
    AssertEqual(WfpOwnedPolicyKeys.DesktopIpv6, fake.DeletedKeys[0]);
    AssertEqual(WfpOwnedPolicyKeys.DesktopIpv4, fake.DeletedKeys[1]);
}

static void ReappliesWfpPolicyAfterCleanup()
{
    var fake = new FakeWfpNativeApi();
    WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42).Dispose();
    WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42).Dispose();
    AssertEqual(4, fake.Plans.Count);
    AssertEqual(0, fake.ActiveKeys.Count);
    AssertEqual(2, fake.CloseCount);
}

static void KeepsLiveWfpAbiValidationFailClosed()
{
    var ex = AssertThrowsAndReturn<WfpSpikeException>(() => WfpSdkAbiValidator.ValidateOrThrow());
    AssertEqual(WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE, ex.Code);
}

static void RedactsProhibitedWfpResultContent()
{
    Assert(WfpResultRedactor.ContainsProhibitedContent("C:\\sensitive\\app.exe"), "path was not detected");
    Assert(WfpResultRedactor.ContainsProhibitedContent("PrivateKey"), "secret name was not detected");
    Assert(!WfpResultRedactor.ContainsProhibitedContent("{\"verdict\":\"PARTIAL\"}"), "bounded result was rejected");
}

static void RequiresAllLiveWfpGateConditions()
{
    AssertEqual(WfpSpikeResultCode.EXPLICIT_OPTION_REQUIRED, LiveApplyGate.Evaluate(false, true, true).ResultCode);
    AssertEqual(WfpSpikeResultCode.ADMIN_REQUIRED, LiveApplyGate.Evaluate(true, false, true).ResultCode);
    AssertEqual(WfpSpikeResultCode.AUTOMATED_GATE_FAILED, LiveApplyGate.Evaluate(true, true, false).ResultCode);
    Assert(LiveApplyGate.Evaluate(true, true, true).ApplyLiveWfp, "complete live gate must allow entry");
}

static void RejectsMissingWfpExecutable()
{
    var ex = AssertThrowsAndReturn<WfpSpikeException>(() => WfpInputValidator.OpenExecutable(Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.exe")));
    AssertEqual(WfpSpikeResultCode.APP_PATH_INVALID, ex.Code);
}

static void RejectsDirectoryWfpExecutable()
{
    var directory = Directory.CreateTempSubdirectory("wfp-dir-");
    try { AssertEqual(WfpSpikeResultCode.APP_PATH_INVALID, AssertThrowsAndReturn<WfpSpikeException>(() => WfpInputValidator.OpenExecutable(directory.FullName)).Code); }
    finally { directory.Delete(true); }
}

static void RejectsNonExecutableWfpFile()
{
    var path = Path.GetTempFileName();
    try { AssertEqual(WfpSpikeResultCode.APP_PATH_INVALID, AssertThrowsAndReturn<WfpSpikeException>(() => WfpInputValidator.OpenExecutable(path)).Code); }
    finally { File.Delete(path); }
}

static void ReportsWfpEngineAccessDenial()
{
    var fake = new FakeWfpNativeApi { OpenFailureCode = WfpSpikeResultCode.BFE_ACCESS_DENIED };
    AssertEqual(WfpSpikeResultCode.BFE_ACCESS_DENIED, AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42)).Code);
}

static void StopsAfterIpv4WfpAddFailure()
{
    var fake = new FakeWfpNativeApi { FailVersion = WfpIpVersion.IPv4 };
    AssertEqual(WfpSpikeResultCode.IPV4_POLICY_ADD_FAILED, AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42)).Code);
    AssertEqual(1, fake.Plans.Count); AssertEqual(0, fake.DeleteCount); AssertEqual(1, fake.CloseCount);
}

static void CleansWfpSessionAfterCancellation()
{
    var fake = new FakeWfpNativeApi(); using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
    AssertThrowsAndReturn<OperationCanceledException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42, cancellation.Token));
    AssertEqual(1, fake.CloseCount); AssertEqual(0, fake.Plans.Count);
}

static void RejectsChangedWfpInterface()
{
    var fake = new FakeWfpNativeApi { ChangeInterfaceAfterConversion = true };
    AssertEqual(WfpSpikeResultCode.INTERFACE_CHANGED, AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42)).Code);
    AssertEqual(1, fake.CloseCount);
}

static void RetriesWfpEngineCloseFailure()
{
    var fake = new FakeWfpNativeApi { CloseFailuresRemaining = 1 }; var session = WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42);
    AssertEqual(WfpSpikeResultCode.SESSION_CLOSE_FAILED, session.CleanupOnce());
    AssertEqual(WfpSpikeResultCode.NONE, session.CleanupOnce());
    AssertEqual(2, fake.CloseAttempts); AssertEqual(2, fake.DeleteCount);
}

static void AcceptsCompleteWfpCaseObservations() => Assert(OwnerHarnessRunner.ValidateCases(ValidWfpCases()), "complete case set rejected");
static void RejectsMissingWfpCaseObservations() => Assert(!OwnerHarnessRunner.ValidateCases(ValidWfpCases()[..63]), "missing case accepted");
static void RejectsDuplicateWfpCaseObservations()
{
    var cases = ValidWfpCases(); cases[63] = cases[0]; Assert(!OwnerHarnessRunner.ValidateCases(cases), "duplicate case accepted");
}
static void RejectsInvalidWfpCaseOutcomeCode()
{
    var cases = ValidWfpCases(); cases[0] = cases[0] with { FailureCode = WfpSpikeResultCode.OWNER_ABORTED }; Assert(!OwnerHarnessRunner.ValidateCases(cases), "PASS with failure accepted");
}
static void RejectsArbitraryWfpResultArgument()
{
    var result = OwnerHarnessRunner.RunAsync(["--result", "outside.json"], CancellationToken.None).GetAwaiter().GetResult();
    AssertEqual(WfpSpikeResultCode.AUTOMATED_GATE_FAILED, result.CleanupFailureCode);
}
static void RejectsMissingWfpMarker() => AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ConsumeAndValidate(["--automated-marker", "missing.json", "--expected-commit", new string('a', 40)]));
static void RejectsWfpMarkerPathTraversal() => AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ConsumeAndValidate(["--automated-marker", "..\\outside.json", "--expected-commit", new string('a', 40)]));
static void RejectsUnprotectedMarkerSpool()
{
    var directory = Directory.CreateTempSubdirectory("wfp-spool-");
    try { AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ValidateSpool(directory)); }
    finally { directory.Delete(true); }
}
static void RejectsExpiredWfpMarker()
{
    using var spool = CreateProtectedSpool(); var marker = ValidMarker(DateTimeOffset.UtcNow.AddMinutes(-16)); var path = WriteMarker(spool.Directory.FullName, marker);
    AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ConsumeAndValidate(["--automated-marker", path, "--expected-commit", marker.Commit]));
}
static void RejectsMalformedWfpMarkerHash()
{
    using var spool = CreateProtectedSpool(); var marker = ValidMarker(DateTimeOffset.UtcNow) with { HarnessSha256 = "bad" }; var path = WriteMarker(spool.Directory.FullName, marker);
    AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ConsumeAndValidate(["--automated-marker", path, "--expected-commit", marker.Commit]));
}
static void ConsumesWfpMarkerOnlyOnce()
{
    using var spool = CreateProtectedSpool(); var marker = ValidMarker(DateTimeOffset.UtcNow); var path = WriteMarker(spool.Directory.FullName, marker);
    AssertThrows<Exception>(() => OwnerHarnessRunner.TrustedGateEvidence.ConsumeAndValidate(["--automated-marker", path, "--expected-commit", marker.Commit]));
    Assert(!File.Exists(path), "marker must be consumed before live evidence validation");
}
static void KeepsPackageWfpIdentityEvidenceExplicit()
{
    var evidence = new PackageIdentityEvidence("family", "container", Convert.ToBase64String(new byte[8]));
    AssertEqual("container", evidence.AppContainerName); AssertEqual("family", evidence.PackageFamilyName);
}
static void ReportsWfpAppIdLookupFailure()
{
    var fake = new FakeWfpNativeApi { AppIdFailureCode = WfpSpikeResultCode.APP_ID_LOOKUP_FAILED };
    AssertEqual(WfpSpikeResultCode.APP_ID_LOOKUP_FAILED, AssertThrowsAndReturn<WfpSpikeException>(() => fake.GetAppId("test.exe")).Code);
}
static void RejectsDuplicateOwnedWfpPolicyKey()
{
    var fake = new FakeWfpNativeApi(); fake.ActiveKeys.Add(WfpOwnedPolicyKeys.DesktopIpv4);
    AssertEqual(WfpSpikeResultCode.POLICY_ALREADY_EXISTS, AssertThrowsAndReturn<WfpSpikeException>(() => WfpPolicySession.Apply(fake, fake.DesktopIdentity(), 42)).Code);
    AssertEqual(1, fake.CloseCount);
}
static void RejectsWfpCaseBeforeReady()
{
    var collector = new WfpObservationCollector(1, 32);
    AssertEqual(WfpSpikeResultCode.OWNER_ABORTED, AssertThrowsAndReturn<WfpSpikeException>(() => collector.Accept("{\"caseId\":\"M-001\",\"outcome\":\"PASS\",\"failureCode\":\"NONE\"}")).Code);
}
static void RejectsFailWithNoneCode() => Assert(!WfpObservationCollector.IsValidCombination(WfpSpikeOutcome.FAIL, WfpSpikeResultCode.NONE), "FAIL/NONE accepted");
static void MakesCleanupFailureVerdictFail()
{
    var result = OwnerHarnessRunner.BuildResultForValidation("LIVE", WfpSpikeResultCode.SESSION_CLOSE_FAILED, WfpSpikeOutcome.FAIL, ValidWfpCases());
    AssertEqual(WfpSpikeVerdict.FAIL, result.Verdict);
}
static void DetectsUntrackedFeatureContentMutation()
{
    var first = new FeatureManifest(1, [new("windows/VpnRouter.WfpSpike/new.cs", 1, new string('a', 64), null)]);
    var second = new FeatureManifest(1, [new("windows/VpnRouter.WfpSpike/new.cs", 1, new string('b', 64), null)]);
    Assert(FeatureManifestFingerprint.Compute(first) != FeatureManifestFingerprint.Compute(second), "untracked content mutation missed");
}
static void DetectsStagedFeatureIdentityMutation()
{
    var first = new FeatureManifest(1, [new("windows/VpnRouter.Tests/Program.cs", 1, new string('a', 64), new string('1', 40))]);
    var second = new FeatureManifest(1, [new("windows/VpnRouter.Tests/Program.cs", 1, new string('a', 64), new string('2', 40))]);
    Assert(FeatureManifestFingerprint.Compute(first) != FeatureManifestFingerprint.Compute(second), "staged identity mutation missed");
}
static void DiscoversRecursiveDirectoryBuildImports()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"build/nested.props\" /></Project>",
        new() { ["windows/build/nested.props"] = "<Project><Import Project=\"nested.targets\" /></Project>", ["windows/build/nested.targets"] = "<Project />" });
    var manifest = fixture.Discover();
    Assert(manifest.Files.Select(x => x.RelativePath).SequenceEqual(new[] { "windows/Directory.Build.props", "windows/build/nested.props", "windows/build/nested.targets" }), "recursive imports missing");
}
static void DetectsDiscoveredImportContentMutation()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"nested.props\" /></Project>", new() { ["windows/nested.props"] = "<Project><PropertyGroup><Value>A</Value></PropertyGroup></Project>" });
    var before = FeatureManifestFingerprint.Compute(fixture.Discover());
    File.AppendAllText(fixture.PathOf("windows/nested.props"), " ");
    var after = FeatureManifestFingerprint.Compute(fixture.Discover());
    Assert(before != after, "discovered import content mutation missed");
}
static void DetectsDiscoveredImportStagedIdentityMutation()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"nested.props\" /></Project>", new() { ["windows/nested.props"] = "<Project><PropertyGroup><Value>A</Value></PropertyGroup></Project>" });
    var before = FeatureManifestFingerprint.Compute(fixture.Discover());
    File.WriteAllText(fixture.PathOf("windows/nested.props"), "<Project><PropertyGroup><Value>B</Value></PropertyGroup></Project>");
    fixture.Git("add", "windows/nested.props");
    File.WriteAllText(fixture.PathOf("windows/nested.props"), "<Project><PropertyGroup><Value>A</Value></PropertyGroup></Project>");
    var after = FeatureManifestFingerprint.Compute(fixture.Discover());
    Assert(before != after, "discovered import staged identity mutation missed");
}
static void RejectsDynamicDirectoryBuildImport() => AssertDiscoveryRejected("<Project><Import Project=\"$(BuildRoot)/nested.props\" /></Project>");
static void RejectsGlobDirectoryBuildImport() => AssertDiscoveryRejected("<Project><Import Project=\"build/*.props\" /></Project>");
static void RejectsMissingDirectoryBuildImport() => AssertDiscoveryRejected("<Project><Import Project=\"missing.props\" /></Project>");
static void RejectsOutsideDirectoryBuildImport() => AssertDiscoveryRejected("<Project><Import Project=\"../../outside.props\" /></Project>");
static void RejectsNonMsBuildImportBeforeReading()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"secret.conf\" /></Project>", new() { ["windows/secret.conf"] = "must-not-be-read" });
    AssertThrows<InvalidOperationException>(() => fixture.Discover());
}
static void RejectsCyclicDirectoryBuildImports()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"nested.props\" /></Project>", new() { ["windows/nested.props"] = "<Project><Import Project=\"Directory.Build.props\" /></Project>" });
    AssertThrows<InvalidOperationException>(() => fixture.Discover());
}
static void RejectsReparseDirectoryBuildImport()
{
    using var fixture = BuildInputFixture.Create("<Project><Import Project=\"linked/nested.props\" /></Project>");
    var target = Directory.CreateDirectory(fixture.PathOf("target"));
    File.WriteAllText(Path.Combine(target.FullName, "nested.props"), "<Project />");
    fixture.CreateJunction("linked", "target");
    AssertThrows<InvalidOperationException>(() => fixture.Discover());
}
static void AssertDiscoveryRejected(string directoryBuildProps)
{
    using var fixture = BuildInputFixture.Create(directoryBuildProps);
    AssertThrows<InvalidOperationException>(() => fixture.Discover());
}

static void BlocksPayloadMutationWhileExecutionLeaseHeld()
{
    var directory = Directory.CreateTempSubdirectory("wfp-payload-");
    try
    {
        var payload = Path.Combine(directory.FullName, "harness.exe"); File.WriteAllText(payload, "safe");
        var entry = new PublishedFileEntry("harness.exe", Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(payload))), new FileInfo(payload).Length);
        var manifestPath = Path.Combine(directory.FullName, "manifest.json");
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(new WfpPublishManifest(1, [entry]), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
        using var lease = new PayloadIntegrityLease(directory.FullName, manifestPath);
        AssertThrows<IOException>(() => File.WriteAllText(payload, "changed"));
        lease.Revalidate();
    }
    finally { directory.Delete(true); }
}

static WfpSpikeCaseResult[] ValidWfpCases() => Enumerable.Range(1, 64)
    .Select(i => new WfpSpikeCaseResult($"M-{i:000}", WfpSpikeOutcome.PASS, WfpSpikeResultCode.NONE, DateTimeOffset.UtcNow)).ToArray();

static AutomatedMarker ValidMarker(DateTimeOffset createdAt) => new(1, createdAt, new string('a', 40), new string('b', 32), 0, 0, 0, 0, 0, 0, "MATCH",
    new string('1', 64), new string('2', 64), new string('3', 64), new string('4', 64), new string('5', 64), new string('6', 64), new string('7', 64), new string('8', 64), new string('9', 64));
static string WriteMarker(string directory, AutomatedMarker marker)
{
    var path = Path.Combine(directory, "automated-marker.json");
    File.WriteAllText(path, JsonSerializer.Serialize(marker, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
    return path;
}
static TemporarySpool CreateProtectedSpool()
{
    var directory = Directory.CreateTempSubdirectory("wfp-private-"); var current = WindowsIdentity.GetCurrent().User!;
    var security = new DirectorySecurity(); security.SetAccessRuleProtection(true, false); security.SetOwner(current);
    security.AddAccessRule(new FileSystemAccessRule(current, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
    directory.SetAccessControl(security); return new TemporarySpool(directory);
}

static TException AssertThrowsAndReturn<TException>(Action action) where TException : Exception
{
    try { action(); }
    catch (TException ex) { return ex; }
    throw new InvalidOperationException($"Expected {typeof(TException).Name} was not thrown.");
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

sealed class BuildInputFixture : IDisposable
{
    private readonly DirectoryInfo _root;
    private BuildInputFixture(DirectoryInfo root) => _root = root;
    public static BuildInputFixture Create(string directoryBuildProps, Dictionary<string, string>? extraFiles = null)
    {
        var root = Directory.CreateTempSubdirectory("wfp-feature-");
        var fixture = new BuildInputFixture(root);
        fixture.Write("windows/Test.csproj", "<Project />");
        fixture.Write("windows/Directory.Build.props", directoryBuildProps);
        foreach (var pair in extraFiles ?? []) fixture.Write(pair.Key, pair.Value);
        fixture.Git("init", "--quiet"); fixture.Git("add", ".");
        return fixture;
    }
    public string PathOf(string relativePath) => Path.Combine(_root.FullName, relativePath.Replace('/', Path.DirectorySeparatorChar));
    private void Write(string relativePath, string content)
    {
        var path = PathOf(relativePath); Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, content);
    }
    public FeatureManifest Discover()
    {
        var script = Path.GetFullPath("scripts/windows/build-portable.ps1");
        var start = new System.Diagnostics.ProcessStartInfo("pwsh") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in new[] { "-NoProfile", "-File", script, "-DiscoverWfpBuildInputs", "-FeatureRepositoryRoot", _root.FullName, "-FeatureProjectRelativePaths", "windows/Test.csproj" }) start.ArgumentList.Add(argument);
        using var process = System.Diagnostics.Process.Start(start) ?? throw new InvalidOperationException("PowerShell unavailable");
        var output = process.StandardOutput.ReadToEnd(); var error = process.StandardError.ReadToEnd(); process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "discovery rejected" : error);
        return JsonSerializer.Deserialize<FeatureManifest>(output, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new InvalidOperationException("invalid discovery result");
    }
    public void Git(params string[] arguments)
    {
        var start = new System.Diagnostics.ProcessStartInfo("git") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add("-C"); start.ArgumentList.Add(_root.FullName); foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = System.Diagnostics.Process.Start(start) ?? throw new InvalidOperationException("git unavailable"); process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(process.StandardError.ReadToEnd());
    }
    public void CreateJunction(string link, string target)
    {
        var start = new System.Diagnostics.ProcessStartInfo("pwsh") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        var linkPath = PathOf(link).Replace("'", "''"); var targetPath = PathOf(target).Replace("'", "''");
        foreach (var argument in new[] { "-NoProfile", "-Command", $"New-Item -ItemType Junction -Path '{linkPath}' -Target '{targetPath}' | Out-Null" }) start.ArgumentList.Add(argument);
        using var process = System.Diagnostics.Process.Start(start) ?? throw new InvalidOperationException("PowerShell unavailable"); process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(process.StandardError.ReadToEnd());
    }
    public void Dispose() { try { _root.Delete(true); } catch { } }
}

sealed class FakeWfpNativeApi : IWfpNativeApi
{
    public uint RoundTripIndex { get; set; } = 42;
    public WfpIpVersion? FailVersion { get; set; }
    public WfpSpikeResultCode? OpenFailureCode { get; set; }
    public WfpSpikeResultCode? AppIdFailureCode { get; set; }
    public bool ChangeInterfaceAfterConversion { get; set; }
    public int CloseFailuresRemaining { get; set; }
    private int _conversionCount;
    public int OpenCount { get; private set; }
    public int CloseCount { get; private set; }
    public int CloseAttempts { get; private set; }
    public int DeleteCount { get; private set; }
    public List<WfpPolicyPlan> Plans { get; } = [];
    public List<Guid> DeletedKeys { get; } = [];
    public HashSet<Guid> ActiveKeys { get; } = [];

    public IWfpIdentityLease DesktopIdentity() => new FakeIdentityLease(WfpAppIdentityKind.DesktopAppId);
    public IWfpIdentityLease PackageIdentity() => new FakeIdentityLease(WfpAppIdentityKind.PackageId);
    public IWfpIdentityLease GetAppId(string normalizedExecutablePath)
    {
        if (AppIdFailureCode is { } code) throw new WfpSpikeException(code);
        return DesktopIdentity();
    }
    public IWfpIdentityLease ResolvePackageIdentity(PackageIdentityEvidence evidence) => PackageIdentity();
    public WfpInterfaceIdentity ConvertIndexToLuidAndBack(uint interfaceIndex)
    {
        _conversionCount++;
        return ChangeInterfaceAfterConversion && _conversionCount > 1 ? new(RoundTripIndex, 0x9999UL) : new(RoundTripIndex, 0x1234UL);
    }
    public IWfpEngineLease OpenDynamicEngine() { OpenCount++; if (OpenFailureCode is { } code) throw new WfpSpikeException(code); return new FakeEngineLease(); }
    public void AddConnectionPolicy(IWfpEngineLease engine, WfpPolicyPlan plan, IWfpIdentityLease identity, Guid policyKey)
    {
        Plans.Add(plan);
        if (FailVersion == plan.IpVersion)
            throw new WfpSpikeException(plan.IpVersion == WfpIpVersion.IPv4
                ? WfpSpikeResultCode.IPV4_POLICY_ADD_FAILED : WfpSpikeResultCode.IPV6_POLICY_ADD_FAILED);
        if (!ActiveKeys.Add(policyKey)) throw new WfpSpikeException(WfpSpikeResultCode.POLICY_ALREADY_EXISTS);
    }
    public void DeleteConnectionPolicyByKey(IWfpEngineLease engine, Guid policyKey)
    {
        DeleteCount++;
        DeletedKeys.Add(policyKey);
        ActiveKeys.Remove(policyKey);
    }
    public void CloseEngine(IWfpEngineLease engine)
    {
        CloseAttempts++;
        if (CloseFailuresRemaining-- > 0) throw new WfpSpikeException(WfpSpikeResultCode.SESSION_CLOSE_FAILED);
        CloseCount++; ((FakeEngineLease)engine).Close();
    }
}

sealed class TemporarySpool(DirectoryInfo directory) : IDisposable
{
    public DirectoryInfo Directory { get; } = directory;
    public void Dispose() { if (Directory.Exists) Directory.Delete(true); }
}

sealed class FakeIdentityLease(WfpAppIdentityKind kind) : IWfpIdentityLease
{
    public WfpAppIdentityKind Kind { get; } = kind;
    public nint Value => 1;
    public void Dispose() { }
}

sealed class FakeEngineLease : IWfpEngineLease
{
    public bool IsClosed { get; private set; }
    public void Close() => IsClosed = true;
    public void Dispose() { }
}

sealed class OwnershipTestVpnAdapter(ConcurrentQueue<string> calls) : IVpnAdapter
{
    public VpnProfileType Type => VpnProfileType.WireGuard;

    public int DisconnectCount { get; private set; }

    public Task ValidateProfileAsync(VpnProfile profile, CancellationToken cancellationToken)
    {
        calls.Enqueue("vpn.validate");
        return Task.CompletedTask;
    }

    public Task ConnectAsync(VpnProfile profile, CancellationToken cancellationToken)
    {
        calls.Enqueue("vpn.connect");
        return Task.CompletedTask;
    }

    public Task DisconnectAsync(Guid profileId, CancellationToken cancellationToken)
    {
        DisconnectCount++;
        calls.Enqueue("vpn.disconnect");
        return Task.CompletedTask;
    }

    public Task<VpnInterfaceInfo> GetInterfaceInfoAsync(
        Guid profileId,
        CancellationToken cancellationToken) =>
        Task.FromResult(new VpnInterfaceInfo(42, "test-only", []));

    public Task<VpnConnectionStatus> GetConnectionStatusAsync(
        Guid profileId,
        CancellationToken cancellationToken) =>
        Task.FromResult(new VpnConnectionStatus(true, "test-only"));

    public Task<int> CleanupStaleConnectionsAsync(CancellationToken cancellationToken) =>
        Task.FromResult(0);
}

sealed class OwnershipTestSnapshotStore(ConcurrentQueue<string> calls) : INetworkSnapshotStore
{
    public int RestoreCount { get; private set; }

    public Task SaveCurrentAsync(CancellationToken cancellationToken)
    {
        calls.Enqueue("snapshot.save");
        return Task.CompletedTask;
    }

    public Task RestoreAsync(CancellationToken cancellationToken)
    {
        RestoreCount++;
        calls.Enqueue("snapshot.restore");
        return Task.CompletedTask;
    }
}

sealed class OwnershipTestDnsController(ConcurrentQueue<string> calls) : IDnsProxyController
{
    private readonly TaskCompletionSource<Exception> _failure =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public int StartCount { get; private set; }

    public int StopCount { get; private set; }

    public Task StartAsync(
        IReadOnlyList<DomainRule> rules,
        IPAddress? upstreamDnsServer,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken)
    {
        StartCount++;
        calls.Enqueue("dns.start");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        StopCount++;
        calls.Enqueue("dns.stop");
        return Task.CompletedTask;
    }

    public Task<Exception> WaitForFatalFailureAsync(CancellationToken cancellationToken) =>
        _failure.Task.WaitAsync(cancellationToken);

    public void InjectOwnershipFailure(Exception failure)
    {
        calls.Enqueue("dns.failure");
        if (!_failure.TrySetResult(failure))
        {
            throw new InvalidOperationException("DNS ownership failure was already injected.");
        }
    }
}

sealed class OwnershipTestDnsSettingsManager(ConcurrentQueue<string> calls) : IDnsSettingsManager
{
    public Task PointActiveAdaptersToLocalProxyAsync(CancellationToken cancellationToken)
    {
        calls.Enqueue("dns-settings.point");
        return Task.CompletedTask;
    }
}

sealed class OwnershipTestDomainResolver(ConcurrentQueue<string> calls) : IDomainPreResolver
{
    public Task<IReadOnlyDictionary<string, IReadOnlyList<IPAddress>>> ResolveAsync(
        IReadOnlyList<DomainRule> rules,
        CancellationToken cancellationToken)
    {
        calls.Enqueue("domains.resolve");
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> result =
            new Dictionary<string, IReadOnlyList<IPAddress>>(StringComparer.OrdinalIgnoreCase)
            {
                ["ownership-test.invalid"] = [IPAddress.Parse("192.0.2.10")]
            };
        return Task.FromResult(result);
    }
}

sealed class OwnershipTestRouteManager(ConcurrentQueue<string> calls) : IRouteManager
{
    public int AddCount { get; private set; }

    public int RemoveCount { get; private set; }

    public Task<IReadOnlyList<RouteEntry>> AddHostRoutesAsync(
        IReadOnlyDictionary<string, IReadOnlyList<IPAddress>> domainIps,
        Guid profileId,
        int interfaceIndex,
        CancellationToken cancellationToken)
    {
        AddCount++;
        calls.Enqueue("routes.add");
        return Task.FromResult<IReadOnlyList<RouteEntry>>([]);
    }

    public Task<int> RemoveExpiredRoutesAsync(
        Guid profileId,
        CancellationToken cancellationToken) =>
        Task.FromResult(0);

    public Task RemoveManagedRoutesAsync(Guid profileId, CancellationToken cancellationToken)
    {
        RemoveCount++;
        calls.Enqueue("routes.remove");
        return Task.CompletedTask;
    }

    public Task<bool> HasManagedRoutesAsync(CancellationToken cancellationToken) =>
        Task.FromResult(false);

    public Task RemoveAllManagedRoutesAsync(CancellationToken cancellationToken) =>
        Task.CompletedTask;
}
