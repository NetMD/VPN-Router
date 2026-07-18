using System.Diagnostics;

namespace VpnRouter.Service.Networking;

public static class DnsConflictDetector
{
    public static string? Detect()
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            ArgumentList =
            {
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "if ((Get-Service -Name 'Adguard Service' -ErrorAction SilentlyContinue).Status -eq 'Running') { exit 10 }"
            },
            UseShellExecute = false,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("Failed to inspect DNS filter services.");
        process.WaitForExit();

        return process.ExitCode == 10
            ? "AdGuard는 VPN 연결 중 자동으로 일시 중지되고 연결을 끊으면 원래 상태로 복원됩니다."
            : null;
    }
}
