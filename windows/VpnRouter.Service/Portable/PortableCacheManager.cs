using VpnRouter.Ipc.Contracts;

namespace VpnRouter.Service.Portable;

public sealed class PortableCacheManager(ILogger<PortableCacheManager> logger)
{
    public Task<PortableCacheCleanupResponse> CleanupAsync(CancellationToken cancellationToken)
    {
        var expectedVersionsRoot = Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VpnRouter",
            "app"));
        var activeRoot = Directory.GetParent(AppContext.BaseDirectory.TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar))?.FullName;

        if (activeRoot is null
            || !string.Equals(
                Directory.GetParent(activeRoot)?.FullName,
                expectedVersionsRoot,
                StringComparison.OrdinalIgnoreCase))
        {
            logger.LogInformation(
                "Portable cache cleanup skipped because the backend is not running from the portable cache.");
            return Task.FromResult(new PortableCacheCleanupResponse(0, 0));
        }

        return Task.Run(
            () => CleanupCacheRoot(expectedVersionsRoot, activeRoot, cancellationToken),
            cancellationToken);
    }

    public static PortableCacheCleanupResponse CleanupCacheRoot(
        string versionsRoot,
        string activeRoot,
        CancellationToken cancellationToken = default)
    {
        var resolvedVersionsRoot = Path.GetFullPath(versionsRoot);
        var resolvedActiveRoot = Path.GetFullPath(activeRoot);
        if (!string.Equals(
                Directory.GetParent(resolvedActiveRoot)?.FullName,
                resolvedVersionsRoot,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("The active payload is outside the portable cache root.");
        }

        if (!Directory.Exists(resolvedVersionsRoot))
        {
            return new PortableCacheCleanupResponse(0, 0);
        }

        var directories = new DirectoryInfo(resolvedVersionsRoot)
            .EnumerateDirectories()
            .Where(directory => !directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
            .ToArray();
        var validPrevious = directories
            .Where(directory =>
                !string.Equals(directory.FullName, resolvedActiveRoot, StringComparison.OrdinalIgnoreCase)
                && IsValidPayload(directory.FullName))
            .OrderByDescending(directory => directory.LastWriteTimeUtc)
            .FirstOrDefault();
        var retained = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            resolvedActiveRoot
        };
        if (validPrevious is not null)
        {
            retained.Add(validPrevious.FullName);
        }

        var removedCount = 0;
        foreach (var directory in directories)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (retained.Contains(directory.FullName))
            {
                continue;
            }

            Directory.Delete(directory.FullName, recursive: true);
            removedCount++;
        }

        return new PortableCacheCleanupResponse(removedCount, retained.Count);
    }

    private static bool IsValidPayload(string root)
    {
        var markerPath = Path.Combine(root, ".complete");
        if (!File.Exists(markerPath)
            || !File.Exists(Path.Combine(root, "app", "VpnRouter.App.exe"))
            || !File.Exists(Path.Combine(root, "backend", "VpnRouter.Service.exe")))
        {
            return false;
        }

        var marker = File.ReadAllText(markerPath).Trim();
        return marker.Length == 64 && marker.All(Uri.IsHexDigit);
    }
}
