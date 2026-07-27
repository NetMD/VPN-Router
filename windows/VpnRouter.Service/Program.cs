using VpnRouter.Service;
using VpnRouter.Service.Connection;
using VpnRouter.Networking;
using VpnRouter.Networking.Abstractions;
using VpnRouter.Vpn.Abstractions;
using VpnRouter.Vpn.WireGuard;
using VpnRouter.Service.Ipc;
using VpnRouter.Service.Storage;
using VpnRouter.Service.Networking;
using VpnRouter.Service.Configuration;
using VpnRouter.Service.Diagnostics;
using VpnRouter.Service.Recovery;
using VpnRouter.Service.Portable;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.Configure<VpnRouterFeatureOptions>(
    builder.Configuration.GetSection(VpnRouterFeatureOptions.SectionName));
builder.Services.Configure<PortableRuntimeOptions>(
    builder.Configuration.GetSection(PortableRuntimeOptions.SectionName));
builder.Services.Configure<WireGuardAdapterOptions>(options =>
{
    var features = builder.Configuration
        .GetSection(VpnRouterFeatureOptions.SectionName)
        .Get<VpnRouterFeatureOptions>() ?? new VpnRouterFeatureOptions();
    options.EnableActivation = features.EnableWireGuardActivation;
});
builder.Services.AddSingleton<IVpnAdapter, WireGuardAdapter>();
builder.Services.AddSingleton<IDnsProxyController, WindowsDnsProxyController>();
builder.Services.AddSingleton<IDnsSettingsManager, WindowsDnsSettingsManager>();
builder.Services.AddSingleton<INetworkSnapshotStore, WindowsNetworkSnapshotStore>();
builder.Services.AddSingleton<IRouteManager, WindowsRouteManager>();
builder.Services.AddSingleton<LegacyDnsFilterRecovery>();
builder.Services.AddSingleton<IDomainPreResolver, SystemDomainPreResolver>();
builder.Services.AddSingleton<ConnectionOrchestrator>();
builder.Services.AddSingleton<ConnectionStateStore>();
builder.Services.AddSingleton<ProfileStore>();
builder.Services.AddSingleton<ISecretStore, DpapiFileSecretStore>();
builder.Services.AddSingleton<ProfileImportService>();
builder.Services.AddSingleton<WireGuardProfileLoader>();
builder.Services.AddSingleton<WireGuardRuntimeConfigStore>();
builder.Services.AddSingleton<DiagnosticsService>();
builder.Services.AddSingleton<IpcCommandHandler>();
builder.Services.AddSingleton<BackendRuntimeInformation>();
builder.Services.AddSingleton<PortableCacheManager>();
builder.Services.AddSingleton<ConnectionRecoveryStateStore>();
builder.Services.AddSingleton<StartupRecoveryGate>();
builder.Services.AddSingleton<StartupRecoveryCoordinator>();
builder.Services.AddHostedService<Worker>();
builder.Services.AddHostedService<NamedPipeIpcServer>();

var host = builder.Build();
host.Run();
