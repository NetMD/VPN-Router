using VpnRouter.Core.Profiles;
using VpnRouter.Vpn.WireGuard;

namespace VpnRouter.Service.Storage;

public sealed class WireGuardProfileLoader(
    ProfileStore profileStore,
    ISecretStore secretStore)
{
    public async Task<StoredWireGuardProfile> LoadAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var profile = await profileStore.GetProfileAsync(profileId, cancellationToken)
            ?? throw new InvalidOperationException($"Profile not found: {profileId}");

        if (profile.Type != VpnProfileType.WireGuard)
        {
            throw new InvalidOperationException($"Profile {profileId} is not a WireGuard profile.");
        }

        var configRecord = await profileStore.GetWireGuardConfigRecordAsync(profileId, cancellationToken)
            ?? throw new InvalidOperationException($"WireGuard config not found for profile: {profileId}");

        var privateKey = await secretStore.LoadSecretAsync(configRecord.PrivateKeyRef, cancellationToken);
        var configText = configRecord.SanitizedConfig.Replace("<stored securely>", privateKey, StringComparison.Ordinal);
        var parsedConfig = new WireGuardConfigParser().Parse(configText);

        return new StoredWireGuardProfile(profile, configText, parsedConfig);
    }
}
