namespace VpnRouter.Vpn.WireGuard;

public sealed record WireGuardInstallation(bool IsInstalled, string? ExecutablePath, string Message);

public static class WireGuardInstallationDetector
{
    private static readonly string[] CandidatePaths =
    [
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WireGuard", "wireguard.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "WireGuard", "wireguard.exe")
    ];

    public static WireGuardInstallation Detect()
    {
        var path = CandidatePaths.FirstOrDefault(File.Exists);
        return path is null
            ? new WireGuardInstallation(false, null, "WireGuard for Windows was not found.")
            : new WireGuardInstallation(true, path, "WireGuard for Windows was found.");
    }
}
