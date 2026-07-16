namespace VpnRouter.Service.Storage;

public interface ISecretStore
{
    Task<string> SaveSecretAsync(Guid profileId, string secretName, string secretValue, CancellationToken cancellationToken);

    Task<string> LoadSecretAsync(string secretRef, CancellationToken cancellationToken);

    Task DeleteSecretAsync(string secretRef, CancellationToken cancellationToken);
}
