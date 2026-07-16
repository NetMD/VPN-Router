using System.Text.Json;
using VpnRouter.Core.Profiles;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Ipc.NamedPipes;
using VpnRouter.Vpn.WireGuard;

namespace VpnRouter.Service.Storage;

public sealed class ProfileImportService(
    ProfileStore profileStore,
    ISecretStore secretStore,
    ILogger<ProfileImportService> logger)
{
    public async Task<IpcResponseEnvelope> ImportWireGuardProfileAsync(
        ImportWireGuardProfileRequest request,
        CancellationToken cancellationToken)
    {
        var importResult = new WireGuardConfigParser().PrepareImport(request.ConfigText);
        var now = DateTimeOffset.UtcNow;
        var profileId = Guid.NewGuid();
        var profileName = string.IsNullOrWhiteSpace(request.ProfileName)
            ? "Imported WireGuard"
            : request.ProfileName.Trim();

        var privateKeyRef = await secretStore.SaveSecretAsync(
            profileId,
            "wireguard-private-key",
            importResult.PrivateKeySecret,
            cancellationToken);

        var profile = new VpnProfile(
            profileId,
            profileName,
            VpnProfileType.WireGuard,
            Enabled: true,
            ConfigRef: privateKeyRef,
            ProviderId: null,
            CreatedAt: now,
            UpdatedAt: now);

        await profileStore.SaveWireGuardProfileAsync(profile, importResult, privateKeyRef, cancellationToken);

        logger.LogInformation("Imported WireGuard profile {ProfileId} ({ProfileName}).", profile.Id, profile.Name);

        var response = new ImportWireGuardProfileResponse(
            profile.Id,
            profile.Name,
            importResult.Summary.PeerCount,
            importResult.Summary.InterfaceAddresses,
            importResult.Summary.DnsServers);

        return new IpcResponseEnvelope(
            true,
            $"Imported WireGuard profile: {profile.Name}.",
            JsonSerializer.SerializeToElement(response, VpnRouterIpcJson.Options));
    }
}
