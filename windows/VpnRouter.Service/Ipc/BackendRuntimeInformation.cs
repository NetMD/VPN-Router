using System.Reflection;
using System.Security.Principal;
using Microsoft.Extensions.Options;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Service.Configuration;

namespace VpnRouter.Service.Ipc;

public sealed class BackendRuntimeInformation
{
    public BackendRuntimeInformation(IOptions<PortableRuntimeOptions> options)
    {
        var configured = options.Value;
        LaunchingUserSid = ParseLaunchingUserSid(configured.LaunchingUserSid);
        ProductVersion = string.IsNullOrWhiteSpace(configured.ProductVersion)
            ? GetAssemblyProductVersion()
            : configured.ProductVersion.Trim();
        PayloadIdentity = string.IsNullOrWhiteSpace(configured.PayloadIdentity)
            ? "development"
            : configured.PayloadIdentity.Trim();
    }

    public SecurityIdentifier LaunchingUserSid { get; }

    public string ProductVersion { get; }

    public string PayloadIdentity { get; }

    public BackendInformationDto ToDto() =>
        new(VpnRouterProtocol.CurrentVersion, ProductVersion, PayloadIdentity);

    private static SecurityIdentifier ParseLaunchingUserSid(string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            return new SecurityIdentifier(value);
        }

        return WindowsIdentity.GetCurrent().User
            ?? throw new InvalidOperationException("The backend could not determine the launching user SID.");
    }

    private static string GetAssemblyProductVersion()
    {
        var informationalVersion = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        return informationalVersion?.Split('+', 2)[0] ?? "0.1.0";
    }
}
