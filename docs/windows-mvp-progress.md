# Windows MVP progress

Last updated: 2026-07-16 KST

## Current product decision

- WireGuard for Windows is an external prerequisite.
- VPN Router does not bundle, redistribute, or silently install WireGuard.
- Users import a WireGuard `.conf` from their VPN provider.
- MVP test provider used so far: KeepSolid VPN Unlimited WireGuard config.

## Verified environment

- Windows development machine.
- WireGuard installed at `C:\Program Files\WireGuard\wireguard.exe`.
- KeepSolid WireGuard profile imported as `63543_jp_wg`.
- Test rules used:
  - `youtube.com`
  - `netflix.com`

## Verified feature flags

### Safe/import/preflight

Command:

```powershell
.\scripts\windows\run-service-dev.ps1
```

Verified:

- WireGuard `.conf` import.
- PrivateKey stored separately from SQLite via DPAPI-backed file secret store.
- Profile list loads in UI.
- Endpoint summary is visible in profile details.
- Connection preflight works.
- `youtube.com` and `netflix.com` pre-resolve to IPv4 addresses.

### WireGuard activation only

Command:

```powershell
.\scripts\windows\run-service-dev.ps1 -EnableWireGuardActivation
```

Verified:

- KeepSolid tunnel service creation succeeds.
- VPN interface detection succeeds.
- Example successful log:

```text
Detected VPN interface VpnRtr-0bce1a8871744621878b4426 with index 54.
```

Issues fixed during this phase:

- `Tunnel name is not valid`
  - Fixed by shortening tunnel names to `VpnRtr-{24 chars}`.
- `No such host is known` from stale/example endpoint
  - Root cause was selecting an old test profile with `vpn.example.com`.
  - UI now surfaces Endpoint details and warns on `example.com`.
- Endpoint pre-resolution failure
  - Runtime config generation now keeps original Endpoint when DNS pre-resolution fails instead of failing the connection.
- App IPC timeout during connect
  - Connect/disconnect IPC timeout increased from 3s to 30s.

### WireGuard activation + route mutation

Command:

```powershell
.\scripts\windows\run-service-dev.ps1 -EnableWireGuardActivation -EnableWindowsRouteMutation
```

Verified:

- WireGuard tunnel creation succeeds.
- VPN interface detection succeeds.
- `youtube.com` and `netflix.com` pre-resolve to 7 total IPv4 addresses.
- `/32` IPv4 host routes are actually added.
- Routes are removed on disconnect.
- Network snapshot restore flow runs.
- Example successful logs:

```text
Pre-resolved youtube.com to 4 IPv4 address(es).
Pre-resolved netflix.com to 3 IPv4 address(es).
Detected VPN interface VpnRtr-0bce1a8871744621878b4426 with index 54.
Added 7 IPv4 host route(s) for profile 0bce1a88-7174-4621-878b-4426f892d285.
Removed 7 recorded route plan(s) for profile 0bce1a88-7174-4621-878b-4426f892d285.
Network restore loaded snapshot from ...
```

## Safety work completed after route test

- `ConnectionOrchestrator` now attempts automatic cleanup if connect fails:
  - stop DNS proxy;
  - remove managed routes;
  - disconnect WireGuard;
  - restore network snapshot.
- `WindowsDnsSettingsManager` now previews/logs target non-WireGuard adapters before DNS mutation.
- DNS mutation fails fast if no active non-WireGuard adapter is found.
- `WindowsNetworkSnapshotStore` logs each IPv4 DNS restore operation.
- Manual recovery script added:

```powershell
.\scripts\windows\restore-network-dev.ps1
```

If DNS mutation was enabled and DNS is broken:

```powershell
.\scripts\windows\restore-network-dev.ps1 -ResetDnsToDhcp
```

## Current verification

After the safety changes, run:

```powershell
dotnet build windows\VpnRouter.slnx --no-restore -nr:false
dotnet run --project windows\VpnRouter.Tests\VpnRouter.Tests.csproj --no-build
```

Expected tests include:

```text
PASS Parse valid WireGuard config
PASS Prepare import sanitizes private key
PASS Reject missing peer section
PASS Reject invalid CIDR
PASS Parse DNS AAAA query
PASS Create empty DNS NoError response
PASS Keep WireGuard endpoint when DNS pre-resolution fails
```

## Next task

Do not start with all flags enabled.

Next recommended step is DNS mutation testing with recovery ready.

1. Ensure no stale development service/app is running.
2. Build and test.
3. Start the service as administrator:

```powershell
.\scripts\windows\run-service-dev.ps1 -EnableWireGuardActivation -EnableWindowsRouteMutation -EnableWindowsDnsMutation
```

4. In the UI:
   - select KeepSolid profile `63543_jp_wg`;
   - confirm rules `youtube.com` and `netflix.com`;
   - click `연결 전 점검`;
   - click `연결`.
5. Confirm logs:
   - DNS proxy starts on `127.0.0.1:53`;
   - DNS mutation target adapter is logged;
   - DNS server settings change to `127.0.0.1`;
   - VPN interface is detected;
   - 7 `/32` host routes are added.
6. Verify from another terminal:

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4
Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "*/32" -and $_.InterfaceIndex -eq 54 }
```

7. In the UI, click `연결 끊기`.
8. Confirm logs:
   - DNS proxy stopped;
   - managed routes removed;
   - WireGuard disconnected;
   - DNS restored from snapshot.
9. If DNS is broken, run from elevated PowerShell:

```powershell
.\scripts\windows\restore-network-dev.ps1 -ResetDnsToDhcp
```

## Notes for next session

- Avoid reading raw `.conf` contents unless the user explicitly approves; it contains PrivateKey.
- It is safe to inspect Endpoint lines only if needed, but prefer UI/summary output.
- Avoid enabling DNS mutation until the recovery script and current build are confirmed.
- Keep `.slnx` and `VpnRouterVs.sln` both building; Visual Studio uses the classic `.sln` more reliably.
