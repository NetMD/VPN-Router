using System.Security.Cryptography;
using System.Text;

namespace VpnRouter.Service.Storage;

public sealed class DpapiFileSecretStore : ISecretStore
{
    private readonly string _secretsDirectory;

    public DpapiFileSecretStore()
    {
        _secretsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VpnRouter",
            "secrets");
    }

    public async Task<string> SaveSecretAsync(
        Guid profileId,
        string secretName,
        string secretValue,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_secretsDirectory);

        var secretRef = $"{profileId:N}-{secretName}.bin";
        var path = Path.Combine(_secretsDirectory, secretRef);
        var plaintext = Encoding.UTF8.GetBytes(secretValue);
        var protectedBytes = ProtectedData.Protect(plaintext, optionalEntropy: null, DataProtectionScope.CurrentUser);

        await File.WriteAllBytesAsync(path, protectedBytes, cancellationToken);
        return secretRef;
    }

    public async Task<string> LoadSecretAsync(string secretRef, CancellationToken cancellationToken)
    {
        var path = Path.Combine(_secretsDirectory, secretRef);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Secret file was not found.", path);
        }

        var protectedBytes = await File.ReadAllBytesAsync(path, cancellationToken);
        var plaintext = ProtectedData.Unprotect(protectedBytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
        return Encoding.UTF8.GetString(plaintext);
    }

    public Task DeleteSecretAsync(string secretRef, CancellationToken cancellationToken)
    {
        var path = Path.Combine(_secretsDirectory, secretRef);
        if (File.Exists(path))
        {
            File.Delete(path);
        }

        return Task.CompletedTask;
    }
}
