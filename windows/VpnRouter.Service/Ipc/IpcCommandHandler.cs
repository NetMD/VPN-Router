using System.Text.Json;
using System.Net;
using VpnRouter.Core.Profiles;
using VpnRouter.Core.Rules;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Ipc.NamedPipes;
using VpnRouter.Service.Connection;
using VpnRouter.Service.Storage;
using VpnRouter.Service.Diagnostics;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Service.Configuration;
using VpnRouter.Service.Networking;
using VpnRouter.Vpn.WireGuard;
using Microsoft.Extensions.Options;
using VpnRouter.Service.Recovery;

namespace VpnRouter.Service.Ipc;

public sealed class IpcCommandHandler(
    ConnectionOrchestrator connectionOrchestrator,
    ConnectionStateStore connectionStateStore,
    ProfileImportService profileImportService,
    ProfileStore profileStore,
    WireGuardProfileLoader wireGuardProfileLoader,
    WireGuardRuntimeConfigStore wireGuardRuntimeConfigStore,
    DiagnosticsService diagnosticsService,
    IDomainPreResolver domainPreResolver,
    IOptions<VpnRouterFeatureOptions> featureOptions,
    ISecretStore secretStore,
    StartupRecoveryGate startupRecoveryGate,
    ILogger<IpcCommandHandler> logger)
{
    private static readonly Guid PlaceholderProfileId = Guid.Parse("11111111-1111-1111-1111-111111111111");

    public async Task<IpcResponseEnvelope> HandleAsync(IpcRequestEnvelope request, CancellationToken cancellationToken)
    {
        try
        {
            return request.Command switch
            {
                IpcCommandKind.Connect => await HandleConnectAsync(request.Payload, cancellationToken),
                IpcCommandKind.Disconnect => await HandleDisconnectAsync(request.Payload, cancellationToken),
                IpcCommandKind.RestoreNetwork => await HandleRestoreNetworkAsync(request.Payload, cancellationToken),
                IpcCommandKind.GetConnectionState => HandleGetConnectionState(),
                IpcCommandKind.ImportWireGuardProfile => await HandleImportWireGuardProfileAsync(request.Payload, cancellationToken),
                IpcCommandKind.ListProfiles => await HandleListProfilesAsync(cancellationToken),
                IpcCommandKind.GetDiagnostics => await HandleGetDiagnosticsAsync(cancellationToken),
                IpcCommandKind.SaveDomainRules => await HandleSaveDomainRulesAsync(request.Payload, cancellationToken),
                IpcCommandKind.ListDomainRules => await HandleListDomainRulesAsync(request.Payload, cancellationToken),
                IpcCommandKind.CreateTroubleshootingFile => await HandleCreateTroubleshootingFileAsync(cancellationToken),
                IpcCommandKind.RenameProfile => await HandleRenameProfileAsync(request.Payload, cancellationToken),
                IpcCommandKind.DeleteProfile => await HandleDeleteProfileAsync(request.Payload, cancellationToken),
                IpcCommandKind.ValidateConnectionPlan => await HandleValidateConnectionPlanAsync(request.Payload, cancellationToken),
                _ => new IpcResponseEnvelope(false, $"Unsupported IPC command: {request.Command}.")
            };
        }
        catch (JsonException ex)
        {
            logger.LogWarning(ex, "Invalid IPC payload for command {Command}.", request.Command);
            return new IpcResponseEnvelope(false, $"Invalid payload for {request.Command}.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "IPC command {Command} failed.", request.Command);
            connectionStateStore.SetFailed(ex.Message);
            return new IpcResponseEnvelope(false, ex.Message);
        }
    }

    private async Task<IpcResponseEnvelope> HandleConnectAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        if (!startupRecoveryGate.Succeeded)
        {
            return new IpcResponseEnvelope(
                false,
                $"Startup network recovery failed. Restore network settings before connecting. {startupRecoveryGate.FailureMessage}".Trim());
        }

        var request = payload.Deserialize<ConnectRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Connect payload is missing.");

        var profileId = request.ProfileId == Guid.Empty ? PlaceholderProfileId : request.ProfileId;
        var storedProfile = await wireGuardProfileLoader.LoadAsync(profileId, cancellationToken);
        var runtimeConfigPath = await wireGuardRuntimeConfigStore.MaterializeAsync(
            storedProfile.Profile.Id,
            storedProfile.ConfigText,
            cancellationToken);

        var profile = storedProfile.Profile with { ConfigRef = runtimeConfigPath };
        logger.LogInformation(
            "Loaded WireGuard profile {ProfileId} with {PeerCount} peer(s).",
            profile.Id,
            storedProfile.ParsedConfig.Peers.Count);

        connectionStateStore.SetConnecting(profile.Id, request.Rules.Count);
        var upstreamDnsServer = storedProfile.ParsedConfig.Interface.DnsServers
            .Select(value => IPAddress.TryParse(value, out var address) ? address : null)
            .FirstOrDefault(address => address?.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);
        await connectionOrchestrator.ConnectAsync(
            profile,
            request.Rules,
            upstreamDnsServer,
            request.ProtectionMode,
            cancellationToken);
        connectionStateStore.SetConnected(profile.Id, request.Rules.Count);
        return new IpcResponseEnvelope(true, $"Connect accepted for {request.Rules.Count} site(s).");
    }

    private async Task<IpcResponseEnvelope> HandleDisconnectAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<DisconnectRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Disconnect payload is missing.");

        var profileId = request.ProfileId == Guid.Empty ? PlaceholderProfileId : request.ProfileId;
        connectionStateStore.SetDisconnecting(profileId);
        await connectionOrchestrator.DisconnectAsync(profileId, cancellationToken);
        await wireGuardRuntimeConfigStore.DeleteAsync(profileId, cancellationToken);
        connectionStateStore.SetDisconnected("Disconnected.");
        return new IpcResponseEnvelope(true, "Disconnect accepted.");
    }

    private async Task<IpcResponseEnvelope> HandleRestoreNetworkAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<RestoreNetworkRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Restore payload is missing.");

        logger.LogWarning("Network restore requested. Reason: {Reason}", request.Reason);
        connectionStateStore.SetRestoringNetwork(request.Reason);
        await connectionOrchestrator.RestoreNetworkAsync(cancellationToken);
        connectionStateStore.SetDisconnected("Network settings restored.");
        return new IpcResponseEnvelope(true, "Network restore accepted.");
    }

    private IpcResponseEnvelope HandleGetConnectionState()
    {
        var state = connectionStateStore.Snapshot();

        return new IpcResponseEnvelope(
            true,
            "Connection state returned.",
            JsonSerializer.SerializeToElement(state, VpnRouterIpcJson.Options));
    }

    private async Task<IpcResponseEnvelope> HandleImportWireGuardProfileAsync(
        JsonElement payload,
        CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<ImportWireGuardProfileRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Import payload is missing.");

        var response = await profileImportService.ImportWireGuardProfileAsync(request, cancellationToken);
        connectionStateStore.AddMessage(response.Message);
        return response;
    }

    private async Task<IpcResponseEnvelope> HandleListProfilesAsync(CancellationToken cancellationToken)
    {
        var profiles = await profileStore.ListProfilesAsync(cancellationToken);
        var summaries = await profileStore.ListWireGuardSummariesAsync(cancellationToken);
        var response = new ListProfilesResponse(profiles
            .Select(profile => new ProfileSummaryDto(
                profile.Id,
                profile.Name,
                profile.Type.ToString(),
                profile.Enabled,
                profile.UpdatedAt,
                summaries.TryGetValue(profile.Id, out var summary) ? summary.Endpoints : []))
            .ToArray());

        return new IpcResponseEnvelope(
            true,
            $"Returned {response.Profiles.Count} profile(s).",
            JsonSerializer.SerializeToElement(response, VpnRouterIpcJson.Options));
    }

    private async Task<IpcResponseEnvelope> HandleGetDiagnosticsAsync(CancellationToken cancellationToken)
    {
        var diagnostics = await diagnosticsService.GetAsync(cancellationToken);
        return new IpcResponseEnvelope(
            true,
            "Diagnostics returned.",
            JsonSerializer.SerializeToElement(diagnostics, VpnRouterIpcJson.Options));
    }

    private async Task<IpcResponseEnvelope> HandleSaveDomainRulesAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<SaveDomainRulesRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Save domain rules payload is missing.");

        await profileStore.SaveDomainRulesAsync(request.ProfileId, request.Rules, cancellationToken);
        connectionStateStore.AddMessage($"Saved {request.Rules.Count} domain rule(s).");
        return new IpcResponseEnvelope(true, $"Saved {request.Rules.Count} domain rule(s).");
    }

    private async Task<IpcResponseEnvelope> HandleListDomainRulesAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<ListDomainRulesRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("List domain rules payload is missing.");

        var rules = await profileStore.ListDomainRulesAsync(request.ProfileId, cancellationToken);
        var response = new ListDomainRulesResponse(rules);
        return new IpcResponseEnvelope(
            true,
            $"Returned {rules.Count} domain rule(s).",
            JsonSerializer.SerializeToElement(response, VpnRouterIpcJson.Options));
    }

    private async Task<IpcResponseEnvelope> HandleCreateTroubleshootingFileAsync(CancellationToken cancellationToken)
    {
        var filePath = await diagnosticsService.CreateTroubleshootingFileAsync(cancellationToken);
        return new IpcResponseEnvelope(
            true,
            "Troubleshooting file created.",
            JsonSerializer.SerializeToElement(new TroubleshootingFileResponse(filePath), VpnRouterIpcJson.Options));
    }

    private async Task<IpcResponseEnvelope> HandleRenameProfileAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<RenameProfileRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Rename profile payload is missing.");

        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return new IpcResponseEnvelope(false, "Profile name is empty.");
        }

        await profileStore.RenameProfileAsync(request.ProfileId, request.Name, cancellationToken);
        connectionStateStore.AddMessage($"Renamed profile to {request.Name.Trim()}.");
        return new IpcResponseEnvelope(true, $"Renamed profile to {request.Name.Trim()}.");
    }

    private async Task<IpcResponseEnvelope> HandleDeleteProfileAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<DeleteProfileRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Delete profile payload is missing.");

        var secretRefs = await profileStore.DeleteProfileAsync(request.ProfileId, cancellationToken);
        foreach (var secretRef in secretRefs)
        {
            await secretStore.DeleteSecretAsync(secretRef, cancellationToken);
        }
        connectionStateStore.AddMessage("Deleted profile.");
        return new IpcResponseEnvelope(true, "Deleted profile.");
    }

    private async Task<IpcResponseEnvelope> HandleValidateConnectionPlanAsync(JsonElement payload, CancellationToken cancellationToken)
    {
        var request = payload.Deserialize<ValidateConnectionPlanRequest>(VpnRouterIpcJson.Options)
            ?? throw new JsonException("Validate connection plan payload is missing.");

        var checks = new List<string>();
        var warnings = new List<string>();
        var features = featureOptions.Value;
        var wireGuard = WireGuardInstallationDetector.Detect();

        if (request.ProfileId == Guid.Empty)
        {
            warnings.Add("VPN 프로필이 선택되지 않았습니다.");
        }
        else
        {
            var storedProfile = await wireGuardProfileLoader.LoadAsync(request.ProfileId, cancellationToken);
            checks.Add($"WireGuard 프로필을 읽었습니다: {storedProfile.Profile.Name}");
            checks.Add($"WireGuard peer 수: {storedProfile.ParsedConfig.Peers.Count}");
            foreach (var endpoint in storedProfile.ParsedConfig.Peers
                .Select(peer => peer.Endpoint)
                .Where(endpoint => !string.IsNullOrWhiteSpace(endpoint))
                .Cast<string>())
            {
                checks.Add($"WireGuard Endpoint: {endpoint}");
                if (endpoint.Contains("example.com", StringComparison.OrdinalIgnoreCase))
                {
                    warnings.Add("현재 WireGuard Endpoint가 example.com 예제 주소입니다. 실제 VPN 제공자의 .conf를 다시 가져오세요.");
                }
            }
        }

        if (wireGuard.IsInstalled)
        {
            checks.Add($"WireGuard 설치 확인: {wireGuard.ExecutablePath}");
        }
        else
        {
            warnings.Add($"WireGuard가 설치되어 있지 않습니다: {wireGuard.Message}");
        }

        var enabledRules = request.Rules.Where(rule => rule.Enabled).ToArray();
        if (enabledRules.Length == 0)
        {
            warnings.Add("VPN으로 열 사이트가 없습니다.");
        }
        else
        {
            checks.Add($"사이트 규칙 {enabledRules.Length}개를 확인했습니다.");
        }

        var effectiveRules = DomainRuleExpander.Expand(enabledRules);
        if (effectiveRules.Count > enabledRules.Length)
        {
            checks.Add($"미디어 재생에 필요한 관련 도메인 {effectiveRules.Count - enabledRules.Length}개를 자동으로 포함합니다.");
        }

        var resolved = await domainPreResolver.ResolveAsync(effectiveRules, cancellationToken);
        var routePlans = resolved
            .Select(pair => new RoutePlanDto(
                pair.Key,
                pair.Value
                    .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    .Select(address => address.ToString())
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToArray()))
            .ToArray();

        foreach (var plan in routePlans)
        {
            if (plan.Ipv4Addresses.Count == 0)
            {
                warnings.Add($"{plan.Domain}: IPv4 주소를 찾지 못했습니다.");
            }
            else
            {
                checks.Add($"{plan.Domain}: IPv4 {plan.Ipv4Addresses.Count}개 확인");
            }
        }

        if (!features.EnableWireGuardActivation)
        {
            warnings.Add("실제 WireGuard 실행 플래그가 꺼져 있어 연결 버튼은 dry-run에 가깝게 동작합니다.");
        }

        if (!features.EnableWindowsRouteMutation)
        {
            warnings.Add("실제 라우트 변경 플래그가 꺼져 있어 /32 라우트는 기록만 됩니다.");
        }

        if (!features.EnableWindowsDnsMutation)
        {
            warnings.Add("실제 DNS 변경 플래그가 꺼져 있어 브라우저 DNS 질의는 로컬 프록시로 강제되지 않습니다.");
        }

        var dnsConflict = features.EnableWindowsDnsMutation ? DnsConflictDetector.Detect() : null;
        if (dnsConflict is not null)
        {
            warnings.Add(dnsConflict);
        }

        foreach (var browserWarning in BrowserSecureDnsDetector.DetectWarnings())
        {
            warnings.Add(browserWarning);
        }

        if (request.ProtectionMode)
        {
            checks.Add("보호 모드가 켜져 있습니다.");
        }

        var canConnect = request.ProfileId != Guid.Empty
            && wireGuard.IsInstalled
            && enabledRules.Length > 0
            && routePlans.Any(plan => plan.Ipv4Addresses.Count > 0);

        var response = new ValidateConnectionPlanResponse(
            canConnect,
            checks,
            warnings,
            routePlans,
            RequiresAdminForActualConnect: true,
            WouldMutateWindowsDns: features.EnableWindowsDnsMutation,
            WouldMutateWindowsRoutes: features.EnableWindowsRouteMutation,
            WouldActivateWireGuard: features.EnableWireGuardActivation);

        return new IpcResponseEnvelope(
            true,
            canConnect ? "Connection plan validated." : "Connection plan has warnings.",
            JsonSerializer.SerializeToElement(response, VpnRouterIpcJson.Options));
    }
}
