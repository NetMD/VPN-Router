using VpnRouter.WfpSpike.Contracts;

namespace VpnRouter.WfpSpike;

public static class WfpInputValidator
{
    public const int MaximumInputLineLength = 64 * 1024;
    public const int MaximumPathLength = 32_766;

    public static string NormalizeExecutablePath(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > MaximumPathLength)
            throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);

        string path;
        try { path = Path.GetFullPath(value); }
        catch { throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID); }

        if (!string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(path) ||
            (File.GetAttributes(path) & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
            throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);

        return path;
    }

    public static ValidatedExecutableLease OpenExecutable(string value)
    {
        var path = NormalizeExecutablePath(value);
        RejectReparseChain(path);
        try
        {
            var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var buffer = new char[MaximumPathLength + 1];
            var length = Native.NativeMethods.GetFinalPathNameByHandle(stream.SafeFileHandle.DangerousGetHandle(), buffer, (uint)buffer.Length, 0);
            if (length == 0 || length >= buffer.Length)
            {
                stream.Dispose();
                throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);
            }
            var finalPath = new string(buffer, 0, (int)length);
            if (finalPath.StartsWith("\\\\?\\", StringComparison.Ordinal)) finalPath = finalPath[4..];
            if (!string.Equals(Path.GetFullPath(finalPath), path, StringComparison.OrdinalIgnoreCase))
            {
                stream.Dispose();
                throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);
            }
            return new ValidatedExecutableLease(path, stream);
        }
        catch (WfpSpikeException) { throw; }
        catch { throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID); }
    }

    private static void RejectReparseChain(string path)
    {
        var current = new FileInfo(path).Directory;
        while (current is not null)
        {
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);
            current = current.Parent;
        }
    }
}

public sealed class ValidatedExecutableLease(string normalizedPath, FileStream stream) : IDisposable
{
    public string NormalizedPath { get; } = normalizedPath;
    public void Revalidate()
    {
        if (!File.Exists(NormalizedPath) || stream.Length != new FileInfo(NormalizedPath).Length)
            throw new WfpSpikeException(WfpSpikeResultCode.APP_PATH_INVALID);
    }
    public void Dispose() => stream.Dispose();
}
