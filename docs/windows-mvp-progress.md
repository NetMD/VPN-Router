# Windows MVP progress

Last updated: 2026-07-18 KST

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
PASS Parse DNS IPv4 answers
PASS Proxy returns empty response for target AAAA query
PASS Record concurrent DNS observations
PASS Batch concurrent dynamic route discoveries
PASS Refresh repeated managed route expiration
PASS Expire only eligible managed routes
PASS Force WireGuard runtime routing table off
PASS Split WireGuard default allowed IPs
PASS Keep WireGuard endpoint when DNS pre-resolution fails
```

## DNS mutation integration

Completed on 2026-07-18 with AdGuard temporarily stopped.

Verified:

- WireGuard runtime config uses `Table = off`.
- Default `AllowedIPs` are split into equivalent `/1` ranges so WireGuard does not enable its full-tunnel firewall.
- The normal Wi-Fi default route remains active.
- Seven site IPv4 routes plus one VPN DNS route are added through the WireGuard interface.
- The DNS proxy uses the WireGuard profile DNS server.
- An A query for `youtube.com` returns four IPv4 answers.
- An AAAA query for `youtube.com` returns an empty successful response.
- Recovery removes the VPN interface and routes and restores the original DNS server.

Environment conflict:

- `Adguard Service` intercepts local UDP port 53 responses on this machine.
- Preflight reports the conflict and refuses connection while AdGuard is running.
- AdGuard must be paused before DNS mutation until coexistence is designed.

Safety fixes:

- DNS proxy port binding is verified before Windows DNS is changed.
- Windows UDP connection-reset behavior no longer terminates the proxy loop.
- Upstream DNS requests have a timeout and use the VPN profile DNS server.
- DNS and site routes are installed before Windows DNS mutation.
- Disconnect cleanup continues through all steps after an individual failure.
- The recovery script restores DNS from the saved snapshot by default.
- The unsupported `Set-DnsClientServerAddress -AddressFamily` argument was removed.

## Browser-level split-routing verification

Completed on 2026-07-18 with `scripts/windows/test-browser-routing-dev.ps1` running as administrator.

Verified:

- Chrome opened YouTube, Netflix, and Example Domain using an isolated test profile.
- The DNS proxy observed seven matching A queries, including YouTube and Netflix subdomains.
- Dynamic A answers were added to the WireGuard interface in short batches.
- The WireGuard interface `/32` route count increased from 10 to 30 while the pages loaded.
- Concurrent observation writes no longer fail with file-sharing errors.
- The test runner stops Chrome before reading the observation snapshot, so result collection terminates reliably.
- Cleanup restored Wi-Fi DNS to `192.168.1.1`, removed the WireGuard adapter, restarted AdGuard with automatic startup, and removed the temporary Chrome DNS-over-HTTPS policy.

Result artifact:

```text
%LOCALAPPDATA%\VpnRouter\logs\browser-routing-result.json
```

## Dynamic route lifecycle

Completed on 2026-07-18.

- Repeated DNS answers refresh the existing route expiration instead of creating duplicate entries.
- Dynamic site routes expire after 15 minutes without another matching answer.
- A maintenance task runs every minute while the DNS proxy is active and removes expired routes.
- The VPN DNS route uses a persistent lifetime and is only removed during disconnect cleanup.
- Expired-route cleanup and disconnect cleanup remove routes in a single PowerShell batch.
- Concurrent observation writes and dynamic route accumulation have focused tests.
- The test suite now contains 16 passing checks.
- The administrator Chrome test observed 7 matching DNS requests and 20 new `/32` routes; repeated answers refreshed 4 existing routes.
- Final cleanup left `managed-routes.json` empty, restored DNS to `192.168.1.1`, removed the VPN adapter, and restarted AdGuard.

## Persistent route worker

Completed on 2026-07-18.

- A single privileged PowerShell worker is reused for route add/remove batches instead of spawning a process for every batch.
- Commands use a request-ID protocol over redirected standard input/output and propagate terminating errors to the service.
- Cancellation or protocol failure discards the worker so a later command cannot consume stale output.
- Service disposal closes the worker input pipe and terminates it if it does not exit promptly.
- A focused test verifies that multiple commands reuse the same worker PID and that command failures propagate.
- The administrator Chrome test completed with one worker start, zero route-batch timeouts, zero withheld DNS responses, and zero DNS proxy failures.
- Chrome loaded YouTube, Netflix, and Example Domain while 20 new VPN `/32` routes were installed.

## Simplified dashboard UI

Completed on 2026-07-18.

- The first screen now focuses on connection state, VPN profile, routed sites, and the primary connect action.
- Profile management, protection mode, diagnostics, and network recovery are available in collapsed secondary sections.
- Site removal uses a standard delete icon with a tooltip, and import/add/recovery actions use familiar system icons.
- Technical endpoint details are no longer shown in the main profile summary.
- The layout uses restrained 6 px framing, stable 960 px content width, and theme resources for light/dark mode.
- The x64 app build completed with zero warnings and the 1120 x 780 rendered window was checked for clipping and overlap.

## Startup crash recovery

Completed on 2026-07-18.

- A connection marker is written before VPN/DNS/route mutation and cleared only after complete cleanup.
- The named-pipe server waits for startup recovery before accepting commands.
- A failed startup recovery leaves diagnostics available but blocks new connect commands.
- Startup recovery removes all recorded routes and stale `VpnRtr-*` tunnels, restores DNS, and clears recovery state.
- A forced process termination test left DNS at `127.0.0.1`, one VPN adapter, 26 managed routes, and AdGuard stopped.
- Restarting only the service restored DNS to `192.168.1.1`, removed the adapter and routes, restarted AdGuard, and cleared both recovery markers.

Result artifact:

```text
%LOCALAPPDATA%\VpnRouter\logs\startup-recovery-result.json
```

## DNS filter and browser DNS handling

Completed on 2026-07-18.

- AdGuard state and startup mode are saved before VpnRouter takes local UDP port 53.
- AdGuard is paused automatically for the connection and restored after disconnect, connect failure, startup recovery, or manual recovery.
- Chrome and Edge secure-DNS policies are inspected during connection-plan validation.
- Installed browsers without an explicit `DnsOverHttpsMode=off` policy receive a user-facing warning.
- Secure-DNS policy interpretation has focused tests.

## Media CDN routing verification

Completed on 2026-07-18 with one remaining player-level limitation.

- `youtube.com` expands internally to Googlevideo, YTImg, YouTube API, GGpht, and YouTube NoCookie domains.
- `netflix.com` expands internally to Netflix video, image, service, and external asset domains.
- Two user rules expanded to 12 effective routing rules without changing the saved UI list.
- The browser test observed Googlevideo, YTImg, GGpht, NflxSo, and NflxExt DNS traffic and installed 37-44 new VPN routes depending on CDN rotation.
- Netflix Fast identified the VPN exit as Tokyo, Japan.
- A Googlevideo media probe returned HTTP 200 and VPN traffic increased by about 11.3 MB.
- YouTube returned playability `OK`, but automated Chrome still displayed a player error and did not advance `currentTime`.
- Netflix opened its public title page and CDN requests used the VPN; catalog/playback verification remains account-dependent.
- Graceful disconnect restored DNS, removed the VPN adapter, restarted AdGuard, and cleared recovery state.

## Next task

Resolve the remaining external playback verification gaps:

1. Investigate why automated Chrome reports a YouTube player error even though playability is `OK` and Googlevideo HTTP probes succeed.
2. Run a signed-in Netflix playback/catalog check with a user-provided test account session; credentials must not be stored by VpnRouter.

## Notes for next session

- Avoid reading raw `.conf` contents unless the user explicitly approves; it contains PrivateKey.
- It is safe to inspect Endpoint lines only if needed, but prefer UI/summary output.
- Avoid enabling DNS mutation until the recovery script and current build are confirmed.
- Keep `.slnx` and `VpnRouterVs.sln` both building; Visual Studio uses the classic `.sln` more reliably.
