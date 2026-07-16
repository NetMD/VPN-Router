namespace VpnRouter.Ipc.NamedPipes;

public enum IpcCommandKind
{
    Connect = 1,
    Disconnect = 2,
    RestoreNetwork = 3,
    GetConnectionState = 4,
    ImportWireGuardProfile = 5,
    ListProfiles = 6,
    GetDiagnostics = 7,
    SaveDomainRules = 8,
    ListDomainRules = 9,
    CreateTroubleshootingFile = 10,
    RenameProfile = 11,
    DeleteProfile = 12,
    ValidateConnectionPlan = 13
}
