using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;

namespace VpnRouter.Service.Ipc;

public static class NamedPipeSecurityFactory
{
    public static PipeSecurity CreateServicePipeSecurity(SecurityIdentifier launchingUserSid)
    {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

        AddAllowRule(security, WellKnownSidType.LocalSystemSid, PipeAccessRights.FullControl);
        AddAllowRule(security, WellKnownSidType.BuiltinAdministratorsSid, PipeAccessRights.FullControl);
        security.AddAccessRule(new PipeAccessRule(
            launchingUserSid,
            PipeAccessRights.ReadWrite,
            AccessControlType.Allow));

        return security;
    }

    private static void AddAllowRule(PipeSecurity security, WellKnownSidType sidType, PipeAccessRights rights)
    {
        var sid = new SecurityIdentifier(sidType, null);
        security.AddAccessRule(new PipeAccessRule(sid, rights, AccessControlType.Allow));
    }
}
