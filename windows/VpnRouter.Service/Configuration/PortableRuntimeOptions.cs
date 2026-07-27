namespace VpnRouter.Service.Configuration;

public sealed class PortableRuntimeOptions
{
    public const string SectionName = "VpnRouter:Portable";

    public string? LaunchingUserSid { get; set; }

    public string? ProductVersion { get; set; }

    public string? PayloadIdentity { get; set; }
}
