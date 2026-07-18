using Microsoft.Win32;

namespace VpnRouter.Service.Networking;

public static class BrowserSecureDnsDetector
{
    public static IReadOnlyList<string> DetectWarnings()
    {
        var warnings = new List<string>();
        AddBrowserWarning(
            warnings,
            "Chrome",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
            @"SOFTWARE\Policies\Google\Chrome");
        AddBrowserWarning(
            warnings,
            "Edge",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe"),
            @"SOFTWARE\Policies\Microsoft\Edge");
        return warnings;
    }

    private static void AddBrowserWarning(
        ICollection<string> warnings,
        string browserName,
        string executablePath,
        string policyPath)
    {
        var warning = BuildWarning(browserName, File.Exists(executablePath),
            ReadPolicy(Registry.LocalMachine, policyPath)
                ?? ReadPolicy(Registry.CurrentUser, policyPath));
        if (warning is not null)
        {
            warnings.Add(warning);
        }
    }

    public static string? BuildWarning(string browserName, bool isInstalled, string? mode)
    {
        if (!isInstalled)
        {
            return null;
        }

        if (string.Equals(mode, "off", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return mode is null
            ? $"{browserName} 보안 DNS가 로컬 사이트 경로를 우회할 수 있습니다. 브라우저 설정에서 보안 DNS를 끄거나 관리 정책을 적용하세요."
            : $"{browserName} 보안 DNS 정책이 '{mode}'입니다. 선택 사이트 경로를 보장하려면 'off'로 설정하세요.";
    }

    private static string? ReadPolicy(RegistryKey root, string path)
    {
        using var key = root.OpenSubKey(path);
        return key?.GetValue("DnsOverHttpsMode")?.ToString();
    }
}
