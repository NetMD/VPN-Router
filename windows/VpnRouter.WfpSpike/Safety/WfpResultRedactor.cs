using System.Text.RegularExpressions;

namespace VpnRouter.WfpSpike;

public static partial class WfpResultRedactor
{
    public static bool ContainsProhibitedContent(string value) =>
        WindowsPath().IsMatch(value) || IpAddress().IsMatch(value) || SecretName().IsMatch(value);

    [GeneratedRegex(@"(?i)(?:[a-z]:\\|\\\\Device\\)")]
    private static partial Regex WindowsPath();
    [GeneratedRegex(@"(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])|(?i)(?:[a-f0-9]{0,4}:){2,}[a-f0-9]{0,4}")]
    private static partial Regex IpAddress();
    [GeneratedRegex(@"(?i)(?:PrivateKey|PresharedKey|Endpoint|AllowedIPs|exceptionMessage|stackTrace|rawError|logLines|\.conf)")]
    private static partial Regex SecretName();
}
