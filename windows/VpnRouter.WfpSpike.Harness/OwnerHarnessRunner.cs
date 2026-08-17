using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using VpnRouter.WfpSpike.Contracts;
using VpnRouter.WfpSpike.Native;

namespace VpnRouter.WfpSpike.Harness;

// 결과 스키마는 2입니다. InconclusiveCount 를 NotRunCount 바로 뒤에 넣어 13필드가 됩니다 (설계 R-05 · B-5).
public sealed record WfpSpikeResult(int SchemaVersion, DateTimeOffset StartedAtUtc, DateTimeOffset CompletedAtUtc,
    string Mode, WfpSpikeVerdict Verdict, int CaseTotal, int PassCount, int FailCount, int NotRunCount, int InconclusiveCount,
    WfpSpikeOutcome CleanupOutcome, WfpSpikeResultCode CleanupFailureCode, IReadOnlyList<WfpSpikeCaseResult> Cases);
public sealed record WfpSpikeCaseResult(string CaseId, WfpSpikeOutcome Outcome, WfpSpikeResultCode FailureCode, DateTimeOffset ObservedAtUtc);
public sealed record LiveInput(string Nonce, uint InterfaceIndex, string ExecutablePath, string? PackageFamilyName,
    string? PackageAppContainerName, string? PackageSidBase64, string ApprovalToken);
public sealed record WfpObservationInput(string CaseId, WfpSpikeOutcome Outcome, WfpSpikeResultCode FailureCode);
public sealed record WfpReadySignal(int SchemaVersion, string Signal, string IdentityKind, DateTimeOffset ReadyAtUtc);
public sealed record AutomatedMarker(int SchemaVersion, DateTimeOffset CreatedAtUtc, string Commit, string Nonce,
    int SolutionBuildExitCode, int VsSolutionBuildExitCode, int TestExitCode, int PublishExitCode, int ExtractionExitCode,
    int DryHarnessExitCode, string BeforeAfterFingerprint, string WorktreeFingerprint, string ArtifactSha256,
    string PublishManifestSha256, string HarnessSha256, string ScriptSha256, string FixturesManifestSha256,
    string AbiEvidenceSha256, string AbiProbeSourceSha256, string ApprovalTokenSha256);
public sealed record PublishedFileEntry(string RelativePath, string Sha256, long Length);
public sealed record WfpPublishManifest(int SchemaVersion, IReadOnlyList<PublishedFileEntry> Files);
public sealed record GateEvidence(int SchemaVersion, string WorktreeFingerprint, string ScriptSha256, string FixturesManifestSha256);
public sealed record FeatureFileEntry(string RelativePath, long Length, string Sha256, string? IndexBlobOid);
public sealed record FeatureManifest(int SchemaVersion, IReadOnlyList<FeatureFileEntry> Files);

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, UseStringEnumConverter = true)]
[JsonSerializable(typeof(WfpSpikeResult))]
[JsonSerializable(typeof(WfpSpikeCaseResult))]
[JsonSerializable(typeof(LiveInput))]
[JsonSerializable(typeof(WfpObservationInput))]
[JsonSerializable(typeof(WfpReadySignal))]
[JsonSerializable(typeof(AutomatedMarker))]
[JsonSerializable(typeof(WfpPublishManifest))]
[JsonSerializable(typeof(GateEvidence))]
[JsonSerializable(typeof(FeatureManifest))]
internal sealed partial class HarnessJsonContext : JsonSerializerContext;

public static class OwnerHarnessRunner
{
    private const int MaximumInputBytes = 64 * 1024;
    private static readonly string[] MarkerFields = ["schemaVersion","createdAtUtc","commit","nonce","solutionBuildExitCode","vsSolutionBuildExitCode","testExitCode","publishExitCode","extractionExitCode","dryHarnessExitCode","beforeAfterFingerprint","worktreeFingerprint","artifactSha256","publishManifestSha256","harnessSha256","scriptSha256","fixturesManifestSha256","abiEvidenceSha256","abiProbeSourceSha256","approvalTokenSha256"];
    private static readonly string[] InputFields = ["nonce","interfaceIndex","executablePath","packageFamilyName","packageAppContainerName","packageSidBase64","approvalToken"];

    public static Task<WfpSpikeResult> RunAsync(string[] args, CancellationToken cancellationToken) =>
        RunAsync(args, Console.In, Console.Out, cancellationToken);

    public static async Task<WfpSpikeResult> RunAsync(string[] args, TextReader inputReader, TextWriter outputWriter, CancellationToken cancellationToken)
    {
        var started = DateTimeOffset.UtcNow;
        if (args.Contains("--result", StringComparer.Ordinal)) return Result(started, "DRY_RUN", WfpSpikeResultCode.AUTOMATED_GATE_FAILED, WfpSpikeOutcome.NOT_RUN, []);
        if (!args.Contains("--apply-live-wfp", StringComparer.Ordinal)) return Result(started, "DRY_RUN", WfpSpikeResultCode.EXPLICIT_OPTION_REQUIRED, WfpSpikeOutcome.NOT_RUN, []);

        AutomatedMarker marker;
        try { marker = TrustedGateEvidence.ConsumeAndValidate(args); }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"AUTOMATED_GATE_FAILED:{ex.Message}");
            return Result(started, "LIVE", WfpSpikeResultCode.AUTOMATED_GATE_FAILED, WfpSpikeOutcome.NOT_RUN, []);
        }
        var decision = LiveApplyGate.Evaluate(true, LiveApplyGate.IsElevatedAdministrator(), true);
        if (!decision.ApplyLiveWfp) return Result(started, "LIVE", decision.ResultCode, WfpSpikeOutcome.NOT_RUN, []);

        LiveInput input;
        try
        {
            input = await ReadBootstrapAsync(inputReader, cancellationToken);
            if (!string.Equals(input.Nonce, marker.Nonce, StringComparison.Ordinal) ||
                !FixedHashEquals(marker.ApprovalTokenSha256, input.ApprovalToken))
                throw new InvalidDataException();
        }
        catch { return Result(started, "LIVE", WfpSpikeResultCode.AUTOMATED_GATE_FAILED, WfpSpikeOutcome.NOT_RUN, []); }

        using var mutex = new Mutex(false, "Local\\VpnRouter.WfpSpike.OwnerHarness");
        var lockTaken = false;
        var liveStage = "OWNER_MUTEX";
        // 사례 목록을 try 밖에 둡니다. catch 에서도 보여야 중단·실패 때 사례를 버리지 않습니다 (설계 B-4 · F-2~F-4).
        var observations = new List<WfpSpikeCaseResult>(64);
        try
        {
            lockTaken = mutex.WaitOne(TimeSpan.Zero);
            if (!lockTaken) return Result(started, "LIVE", WfpSpikeResultCode.POLICY_ALREADY_EXISTS, WfpSpikeOutcome.NOT_RUN, []);
            liveStage = "EXECUTABLE";
            using var executable = WfpInputValidator.OpenExecutable(input.ExecutablePath);
            liveStage = "ABI";
            var nativeApi = WfpNativeApiFactory.CreateLive();
            liveStage = "APP_ID";
            var identity = nativeApi.GetAppId(executable.NormalizedPath);
            liveStage = "EXECUTABLE_REVALIDATE";
            executable.Revalidate();
            liveStage = "DESKTOP_POLICY";
            var desktopCleanup = await RunObservationPhaseAsync(nativeApi, identity, input.InterfaceIndex, "DESKTOP", 1, 32, inputReader, outputWriter, observations, cancellationToken);
            if (desktopCleanup != WfpSpikeResultCode.NONE) return Result(started, "LIVE", desktopCleanup, WfpSpikeOutcome.FAIL, FillMissing(observations));

            var hasNoPackage = input.PackageFamilyName is null && input.PackageAppContainerName is null && input.PackageSidBase64 is null;
            if (hasNoPackage)
            {
                for (var number = 33; number <= 64; number++) observations.Add(new($"M-{number:000}", WfpSpikeOutcome.NOT_RUN, WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE, DateTimeOffset.UtcNow));
            }
            else if (input.PackageFamilyName is not null && input.PackageAppContainerName is not null && input.PackageSidBase64 is not null)
            {
                try
                {
                    var packageIdentity = nativeApi.ResolvePackageIdentity(new(input.PackageFamilyName, input.PackageAppContainerName, input.PackageSidBase64));
                    var packageCleanup = await RunObservationPhaseAsync(nativeApi, packageIdentity, input.InterfaceIndex, "PACKAGE", 33, 64, inputReader, outputWriter, observations, cancellationToken);
                    if (packageCleanup != WfpSpikeResultCode.NONE) return Result(started, "LIVE", packageCleanup, WfpSpikeOutcome.FAIL, FillMissing(observations));
                }
                catch (WfpSpikeException ex) when (ex.Code == WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE)
                {
                    for (var number = 33; number <= 64; number++) observations.Add(new($"M-{number:000}", WfpSpikeOutcome.NOT_RUN, ex.Code, DateTimeOffset.UtcNow));
                }
            }
            // 패키지 세 값 가운데 일부만 들어온 경우입니다. 예외를 던져 사례를 버리지 않고
            // 33~64를 근거 있는 NOT_RUN 으로 채웁니다 (설계 F-1 · AC-06-4).
            //
            // 다만 최종 판정은 여기서 PASS 로 흘려보내지 않습니다. 세 값 가운데 일부만 온 것은
            // "패키지 신원을 못 얻었다"가 아니라 "부트스트랩 입력이 규약을 어겼다"입니다.
            // 그대로 아래 PASS 반환으로 흘리면 1~32가 전건 PASS 일 때 입력 규약 위반이
            // 최종 PASS 로 나옵니다. 사례는 지키고 판정은 닫습니다.
            else return PartialPackageInputResult(started, observations);
            return Result(started, "LIVE", WfpSpikeResultCode.NONE, WfpSpikeOutcome.PASS, observations);
        }
        catch (WfpSpikeException ex)
        {
            Console.Error.WriteLine($"LIVE_FAILURE:{liveStage}:{ex.Code}");
            return Result(started, "LIVE", ex.Code, WfpSpikeOutcome.FAIL, FillMissing(observations));
        }
        catch (OperationCanceledException) { return Result(started, "LIVE", WfpSpikeResultCode.OWNER_ABORTED, WfpSpikeOutcome.FAIL, FillMissing(observations)); }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"LIVE_FAILURE:{liveStage}:{ex.GetType().Name}");
            return Result(started, "LIVE", WfpSpikeResultCode.ENVIRONMENT_UNAVAILABLE, WfpSpikeOutcome.FAIL, FillMissing(observations));
        }
        finally { if (lockTaken) mutex.ReleaseMutex(); }
    }

    private static async Task<LiveInput> ReadBootstrapAsync(TextReader reader, CancellationToken cancellationToken)
    {
        var json = await reader.ReadLineAsync(cancellationToken) ?? throw new InvalidDataException();
        if (Encoding.UTF8.GetByteCount(json) > MaximumInputBytes) throw new InvalidDataException();
        using var document = JsonDocument.Parse(json);
        if (!HasOnlyProperties(document.RootElement, InputFields)) throw new InvalidDataException();
        return JsonSerializer.Deserialize(json, HarnessJsonContext.Default.LiveInput) ?? throw new InvalidDataException();
    }

    private static async Task<WfpSpikeResultCode> RunObservationPhaseAsync(IWfpNativeApi nativeApi, IWfpIdentityLease identity, uint interfaceIndex,
        string identityKind, int firstCase, int lastCase, TextReader input, TextWriter output, List<WfpSpikeCaseResult> observations, CancellationToken cancellationToken)
    {
        await using var session = WfpPolicySession.Apply(nativeApi, identity, interfaceIndex, cancellationToken);
        var collector = new WfpObservationCollector(firstCase, lastCase); collector.MarkReady();
        await output.WriteLineAsync(JsonSerializer.Serialize(new WfpReadySignal(1, "READY", identityKind, DateTimeOffset.UtcNow), HarnessJsonContext.Default.WfpReadySignal));
        await output.FlushAsync(cancellationToken);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); timeout.CancelAfter(TimeSpan.FromMinutes(30));
        for (var count = firstCase; count <= lastCase; count++)
        {
            var line = await input.ReadLineAsync(timeout.Token) ?? throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
            observations.Add(collector.Accept(line));
        }
        var complete = await input.ReadLineAsync(timeout.Token) ?? throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        if (!string.Equals(complete, "{\"control\":\"COMPLETE\"}", StringComparison.Ordinal)) throw new WfpSpikeException(WfpSpikeResultCode.OWNER_ABORTED);
        return session.CleanupOnce();
    }

    public static bool ValidateCases(IReadOnlyList<WfpSpikeCaseResult> cases)
    {
        if (cases.Count != 64) return false;
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in cases)
        {
            if (!ids.Add(item.CaseId) || item.CaseId.Length != 5 || !item.CaseId.StartsWith("M-", StringComparison.Ordinal) ||
                !int.TryParse(item.CaseId.AsSpan(2), out var number) || number is < 1 or > 64) return false;
            if (!WfpObservationCollector.IsValidCombination(item.Outcome, item.FailureCode)) return false;
        }
        return Enumerable.Range(1, 64).All(i => ids.Contains($"M-{i:000}"));
    }

    private static bool FixedHashEquals(string expectedHex, string value)
    {
        if (!IsHash(expectedHex)) return false;
        var actual = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return CryptographicOperations.FixedTimeEquals(Convert.FromHexString(expectedHex), actual);
    }
    internal static bool IsHash(string value) => value.Length == 64 && value.All(Uri.IsHexDigit);
    internal static bool HasOnlyProperties(JsonElement root, params string[] names)
    {
        if (root.ValueKind != JsonValueKind.Object) return false; var expected = names.ToHashSet(StringComparer.Ordinal); var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in root.EnumerateObject()) if (!expected.Contains(property.Name) || !seen.Add(property.Name)) return false;
        return seen.SetEquals(expected);
    }

    // 1~64 가운데 아직 판정이 없는 번호를 근거 있는 NOT_RUN 으로 채워 64건을 맞춥니다 (설계 B-5).
    // 32까지만 채우면 ValidateCases 의 64건 요구를 통과하지 못합니다.
    private static IReadOnlyList<WfpSpikeCaseResult> FillMissing(IReadOnlyList<WfpSpikeCaseResult> observed)
    {
        var byCaseId = new Dictionary<string, WfpSpikeCaseResult>(StringComparer.Ordinal);
        foreach (var item in observed) byCaseId.TryAdd(item.CaseId, item);
        var filled = new List<WfpSpikeCaseResult>(64);
        for (var number = 1; number <= 64; number++)
        {
            var caseId = $"M-{number:000}";
            filled.Add(byCaseId.TryGetValue(caseId, out var found)
                ? found
                : new(caseId, WfpSpikeOutcome.NOT_RUN, WfpSpikeResultCode.OWNER_ABORTED, DateTimeOffset.UtcNow));
        }
        return filled;
    }

    // 패키지 세 값 가운데 일부만 온 부트스트랩 입력을 닫는 자리입니다.
    // 사례 33~64는 근거 있는 NOT_RUN 으로 채워 1~32를 지키고, 판정은 FAIL 로 닫습니다.
    // 실기 경로와 집중 시험이 같은 함수를 부르므로 시험이 실제 동작을 확인합니다.
    private static WfpSpikeResult PartialPackageInputResult(DateTimeOffset started, List<WfpSpikeCaseResult> observations)
    {
        FillPackageUnavailable(observations);
        return Result(started, "LIVE", WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE, WfpSpikeOutcome.FAIL, observations);
    }

    public static WfpSpikeResult BuildPartialPackageResultForValidation(IReadOnlyList<WfpSpikeCaseResult> observed) =>
        PartialPackageInputResult(DateTimeOffset.UtcNow, observed.ToList());

    // 패키지 신원을 얻지 못했을 때 33~64를 채웁니다.
    private static void FillPackageUnavailable(List<WfpSpikeCaseResult> observations)
    {
        for (var number = 33; number <= 64; number++)
            observations.Add(new($"M-{number:000}", WfpSpikeOutcome.NOT_RUN, WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE, DateTimeOffset.UtcNow));
    }

    private static WfpSpikeResult Result(DateTimeOffset started, string mode, WfpSpikeResultCode code, WfpSpikeOutcome cleanup, IReadOnlyList<WfpSpikeCaseResult> cases)
    {
        // 네 칸을 각각 셉니다. 빼기로 구하면 INCONCLUSIVE 가 오류 없이 notRun 에 섞입니다 (설계 R-03 · §2.3 암묵 흡수).
        var pass = cases.Count(x => x.Outcome == WfpSpikeOutcome.PASS); var fail = cases.Count(x => x.Outcome == WfpSpikeOutcome.FAIL);
        var notRun = cases.Count(x => x.Outcome == WfpSpikeOutcome.NOT_RUN); var inconclusive = cases.Count(x => x.Outcome == WfpSpikeOutcome.INCONCLUSIVE);
        var requiredPass = cases.Where(x => int.Parse(x.CaseId.AsSpan(2)) <= 32).All(x => x.Outcome == WfpSpikeOutcome.PASS);
        var optional = cases.Where(x => int.Parse(x.CaseId.AsSpan(2)) > 32).ToArray();
        var optionalValid = optional.All(x => x.Outcome == WfpSpikeOutcome.PASS) || optional.All(x => x.Outcome == WfpSpikeOutcome.NOT_RUN && x.FailureCode == WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE);
        var cleanupFailed = mode == "LIVE" && (cleanup == WfpSpikeOutcome.FAIL || code != WfpSpikeResultCode.NONE);
        var verdict = cleanupFailed || fail > 0 ? WfpSpikeVerdict.FAIL : cases.Count == 64 && requiredPass && optionalValid && cleanup == WfpSpikeOutcome.PASS ? WfpSpikeVerdict.PASS : WfpSpikeVerdict.PARTIAL;
        return new(2, started, DateTimeOffset.UtcNow, mode, verdict, cases.Count, pass, fail, notRun, inconclusive, cleanup, code, cases);
    }

    public static WfpSpikeResult BuildResultForValidation(string mode, WfpSpikeResultCode code, WfpSpikeOutcome cleanup, IReadOnlyList<WfpSpikeCaseResult> cases) =>
        Result(DateTimeOffset.UtcNow, mode, code, cleanup, cases);

    // 아래 두 자리는 집중 시험이 중단·부분 입력 경로를 그대로 지나가게 하려고 연 것입니다.
    // 실기 경로(:122·:124·:128 · :116)와 같은 함수를 부르므로 시험이 실제 동작을 확인합니다.
    public static WfpSpikeResult BuildAbortedResultForValidation(WfpSpikeResultCode code, IReadOnlyList<WfpSpikeCaseResult> observed) =>
        Result(DateTimeOffset.UtcNow, "LIVE", code, WfpSpikeOutcome.FAIL, FillMissing(observed));

    public static IReadOnlyList<WfpSpikeCaseResult> FillPackageUnavailableForValidation(IReadOnlyList<WfpSpikeCaseResult> observed)
    {
        var list = observed.ToList();
        FillPackageUnavailable(list);
        return list;
    }

    public static class TrustedGateEvidence
    {
        public static AutomatedMarker ConsumeAndValidate(string[] args)
        {
            var stage = "OPTIONS";
            try
            {
            var markerPath = GetOption(args, "--automated-marker") ?? throw new InvalidDataException(); var expectedCommit = GetOption(args, "--expected-commit") ?? throw new InvalidDataException();
            var fullPath = Path.GetFullPath(markerPath); var spool = Directory.GetParent(fullPath) ?? throw new InvalidDataException();
            stage = "SPOOL"; ValidateSpool(spool); if ((File.GetAttributes(fullPath) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            byte[] bytes; using (var stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.None)) { if (stream.Length > MaximumInputBytes) throw new InvalidDataException(); bytes = new byte[stream.Length]; stream.ReadExactly(bytes); }
            File.Delete(fullPath);
            stage = "MARKER"; using var document = JsonDocument.Parse(bytes); if (!HasOnlyProperties(document.RootElement, MarkerFields)) throw new InvalidDataException();
            var marker = JsonSerializer.Deserialize(bytes, HarnessJsonContext.Default.AutomatedMarker) ?? throw new InvalidDataException(); var age = DateTimeOffset.UtcNow - marker.CreatedAtUtc;
            if (marker.SchemaVersion != 1 || age < TimeSpan.Zero || age > TimeSpan.FromMinutes(15) || expectedCommit.Length is not (40 or 64) || !expectedCommit.All(Uri.IsHexDigit) ||
                !string.Equals(marker.Commit, expectedCommit, StringComparison.OrdinalIgnoreCase) || marker.Nonce.Length is < 16 or > 128 || marker.BeforeAfterFingerprint != "MATCH" ||
                new[] { marker.SolutionBuildExitCode, marker.VsSolutionBuildExitCode, marker.TestExitCode, marker.PublishExitCode, marker.ExtractionExitCode, marker.DryHarnessExitCode }.Any(x => x != 0)) throw new InvalidDataException();
            stage = "HASHES"; foreach (var hash in new[] { marker.WorktreeFingerprint, marker.ArtifactSha256, marker.PublishManifestSha256, marker.HarnessSha256, marker.ScriptSha256, marker.FixturesManifestSha256, marker.AbiEvidenceSha256, marker.AbiProbeSourceSha256, marker.ApprovalTokenSha256 }) if (!IsHash(hash)) throw new InvalidDataException();
            stage = "PUBLISHED_EVIDENCE"; ValidatePublishedEvidence(marker); return marker;
            }
            catch (Exception ex) { throw new InvalidDataException($"{stage}:{ex.Message}", ex); }
        }

        public static void ValidateSpool(DirectoryInfo spool)
        {
            if (!spool.Exists || (spool.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            var security = spool.GetAccessControl(); if (!security.AreAccessRulesProtected) throw new InvalidDataException();
            var owner = security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier ?? throw new InvalidDataException();
            var current = WindowsIdentity.GetCurrent().User; var administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null); var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            if (owner != current && owner != administrators) throw new InvalidDataException();
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                if (rule.AccessControlType == AccessControlType.Allow && (rule.FileSystemRights & (FileSystemRights.Write | FileSystemRights.Modify | FileSystemRights.FullControl)) != 0 && rule.IdentityReference != current && rule.IdentityReference != administrators && rule.IdentityReference != system) throw new InvalidDataException();
        }

        private static void ValidatePublishedEvidence(AutomatedMarker marker)
        {
            var basePath = AppContext.BaseDirectory; var manifestPath = Path.Combine(basePath, "wfp-spike.manifest.json"); var evidencePath = Path.Combine(basePath, "wfp-sdk-abi-x64.json"); var probePath = Path.Combine(basePath, "WfpSdkAbiProbe.cpp"); var gateEvidencePath = Path.Combine(basePath, "wfp-gate-evidence.json"); var featureManifestPath = Path.Combine(basePath, "wfp-feature-manifest.json");
            var missing = string.Join(",", new[] {
                !File.Exists(manifestPath) ? "MANIFEST" : null,
                !File.Exists(evidencePath) ? "ABI" : null,
                !File.Exists(probePath) ? "PROBE" : null,
                !File.Exists(gateEvidencePath) ? "GATE" : null,
                !File.Exists(featureManifestPath) ? "FEATURE" : null,
                Environment.ProcessPath is null ? "PROCESS" : null
            }.Where(static value => value is not null));
            if (missing.Length != 0) throw new InvalidDataException($"EVIDENCE_FILES:{missing}");
            var processPath = Environment.ProcessPath!;
            if (!HashEquals(manifestPath, marker.PublishManifestSha256) || !HashEquals(processPath, marker.HarnessSha256) || !HashEquals(evidencePath, marker.AbiEvidenceSha256) || !HashEquals(probePath, marker.AbiProbeSourceSha256)) throw new InvalidDataException("EVIDENCE_HASHES");
            var gateEvidence = JsonSerializer.Deserialize(File.ReadAllBytes(gateEvidencePath), HarnessJsonContext.Default.GateEvidence) ?? throw new InvalidDataException("GATE_PARSE");
            if (gateEvidence.SchemaVersion != 1 || !string.Equals(gateEvidence.WorktreeFingerprint, marker.WorktreeFingerprint, StringComparison.OrdinalIgnoreCase) || !string.Equals(gateEvidence.ScriptSha256, marker.ScriptSha256, StringComparison.OrdinalIgnoreCase) || !string.Equals(gateEvidence.FixturesManifestSha256, marker.FixturesManifestSha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("GATE_FIELDS");
            if (!HashEquals(featureManifestPath, marker.WorktreeFingerprint)) throw new InvalidDataException("FEATURE_HASH");
            var manifest = JsonSerializer.Deserialize(File.ReadAllBytes(manifestPath), HarnessJsonContext.Default.WfpPublishManifest) ?? throw new InvalidDataException("MANIFEST_PARSE");
            foreach (var entry in manifest.Files) { var full = Path.GetFullPath(Path.Combine(basePath, entry.RelativePath)); if (!full.StartsWith(basePath, StringComparison.OrdinalIgnoreCase) || !File.Exists(full) || new FileInfo(full).Length != entry.Length || !HashEquals(full, entry.Sha256)) throw new InvalidDataException("MANIFEST_ENTRY"); }
        }
        private static bool HashEquals(string path, string expected) => string.Equals(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))), expected, StringComparison.OrdinalIgnoreCase);
        private static string? GetOption(string[] args, string name) { var index = Array.IndexOf(args, name); return index >= 0 && index + 1 < args.Length ? args[index + 1] : null; }
    }
}
