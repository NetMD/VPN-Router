using VpnRouter.Core.Rules;

namespace VpnRouter.Ipc.Contracts;

public sealed record ConnectRequest(Guid ProfileId, IReadOnlyList<DomainRule> Rules, bool ProtectionMode);

public sealed record DisconnectRequest(Guid ProfileId);

public sealed record RestoreNetworkRequest(string Reason);

public sealed record ImportWireGuardProfileRequest(string ProfileName, string ConfigText);

public sealed record ImportWireGuardProfileResponse(
    Guid ProfileId,
    string ProfileName,
    int PeerCount,
    IReadOnlyList<string> InterfaceAddresses,
    IReadOnlyList<string> DnsServers);

public sealed record ProfileSummaryDto(
    Guid Id,
    string Name,
    string Type,
    bool Enabled,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<string> Endpoints);

public sealed record ListProfilesResponse(IReadOnlyList<ProfileSummaryDto> Profiles);

public sealed record DiagnosticsDto(
    bool ServiceReachable,
    bool WireGuardInstalled,
    string WireGuardMessage,
    int ProfileCount,
    bool NetworkSnapshotExists,
    bool ManagedRoutesExists,
    bool DnsObservationsExists,
    bool EnableWireGuardActivation,
    bool EnableWindowsDnsMutation,
    bool EnableWindowsRouteMutation);

public sealed record SaveDomainRulesRequest(Guid ProfileId, IReadOnlyList<DomainRule> Rules);

public sealed record ListDomainRulesRequest(Guid ProfileId);

public sealed record ListDomainRulesResponse(IReadOnlyList<DomainRule> Rules);

public sealed record TroubleshootingFileResponse(string FilePath);

public sealed record RenameProfileRequest(Guid ProfileId, string Name);

public sealed record DeleteProfileRequest(Guid ProfileId);

public sealed record ValidateConnectionPlanRequest(Guid ProfileId, IReadOnlyList<DomainRule> Rules, bool ProtectionMode);

public sealed record ValidateConnectionPlanResponse(
    bool CanConnect,
    IReadOnlyList<string> Checks,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<RoutePlanDto> RoutePlans,
    bool RequiresAdminForActualConnect,
    bool WouldMutateWindowsDns,
    bool WouldMutateWindowsRoutes,
    bool WouldActivateWireGuard);

public sealed record RoutePlanDto(string Domain, IReadOnlyList<string> Ipv4Addresses);

public sealed record CommandResult(bool Success, string Message)
{
    public static CommandResult Ok(string message) => new(true, message);

    public static CommandResult Fail(string message) => new(false, message);
}
