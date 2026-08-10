using System.Security.Cryptography;
using System.Text.Json;

namespace VpnRouter.WfpSpike.Harness;

public sealed class PayloadIntegrityLease : IDisposable
{
    private readonly string _root;
    private readonly WfpPublishManifest _manifest;
    private readonly List<FileStream> _handles = [];

    public PayloadIntegrityLease(string root, string manifestPath)
    {
        _root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        _manifest = JsonSerializer.Deserialize(File.ReadAllBytes(manifestPath), HarnessJsonContext.Default.WfpPublishManifest) ?? throw new InvalidDataException();
        try
        {
            foreach (var entry in _manifest.Files)
            {
                var path = Resolve(entry.RelativePath);
                var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                _handles.Add(stream);
                Verify(stream, entry);
            }
        }
        catch { Dispose(); throw; }
    }

    public void Revalidate()
    {
        for (var index = 0; index < _handles.Count; index++) Verify(_handles[index], _manifest.Files[index]);
    }

    private string Resolve(string relativePath)
    {
        var path = Path.GetFullPath(Path.Combine(_root, relativePath));
        if (!path.StartsWith(_root, StringComparison.OrdinalIgnoreCase) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
        return path;
    }

    private static void Verify(FileStream stream, PublishedFileEntry entry)
    {
        if (stream.Length != entry.Length) throw new InvalidDataException();
        stream.Position = 0;
        var hash = Convert.ToHexString(SHA256.HashData(stream));
        if (!string.Equals(hash, entry.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
    }

    public void Dispose()
    {
        foreach (var handle in _handles) handle.Dispose();
        _handles.Clear();
    }
}

public static class FeatureManifestFingerprint
{
    public static string Compute(FeatureManifest manifest)
    {
        var ordered = new FeatureManifest(1, manifest.Files.OrderBy(x => x.RelativePath, StringComparer.Ordinal).ToArray());
        var bytes = JsonSerializer.SerializeToUtf8Bytes(ordered, HarnessJsonContext.Default.FeatureManifest);
        return Convert.ToHexString(SHA256.HashData(bytes));
    }
}
