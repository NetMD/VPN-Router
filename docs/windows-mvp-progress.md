# Windows MVP progress

Last updated: 2026-07-28 KST

## Windows Codex resume point

Start with `docs/windows-next-session.md`. The network proof, dynamic DNS route
lifecycle, AAAA filtering, DNS ownership fail-safe, crash recovery, dashboard,
and portable extraction foundation already exist. Do not restart from the
original greenfield checklist.

The immediate order is:

1. Reconcile the current 20-test Windows baseline and the small shared-semantic
   gaps (`www` media entry points, rotating-answer proof, 512-route cap).
2. Finish portable lifecycle and IPC security: version handshake, exact-user pipe
   ACL, single-instance/reconnect behavior, close semantics, cache retention, and
   disconnected-only cleanup.
3. Run the owner-operated Phase 1/2 launcher matrix.
4. Continue the remaining Phase 3 and Phase 4 release gates.

Captive-portal handling is outside `v0.1.0`. Never change another DNS/security/VPN
product automatically. The signed macOS build-20 results provide product
semantics and tests only; Windows must keep its native service, DNS, adapter,
route, UI, and portable-launcher implementation.

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

The focused executable contains 26 checks as of 2026-07-28. Expected tests include:

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
PASS Retain rotating managed route answers
PASS Reject route plan above limit before mutation
PASS Validate backend protocol and payload identity
PASS Restrict service pipe to launching user
PASS Retain active and previous portable cache
PASS Create bounded troubleshooting summary
PASS Expire only eligible managed routes
PASS Force WireGuard runtime routing table off
PASS Split WireGuard default allowed IPs
PASS Keep WireGuard endpoint when DNS pre-resolution fails
```

## Windows parity baseline

Completed on 2026-07-28 without enabling DNS, WireGuard, or route mutation.

- Both `windows\VpnRouter.slnx` and `windows\VpnRouterVs.sln` build with zero
  warnings and zero errors on Windows x64 with .NET SDK 10.0.302.
- The focused executable passes all 22 checks.
- Media expansion now includes explicit `www.youtube.com` and
  `www.netflix.com` entry points while retaining the existing CDN families.
- A focused rotating-answer check proves that an address omitted by a later DNS
  response remains managed until its original expiration; the new address gets
  its own 15-minute lifetime.
- A profile's combined static, dynamic, and VPN DNS plan is limited to 512 IPv4
  host routes. An over-limit plan fails before the route manager invokes Windows
  mutation or writes the updated managed-route snapshot.
- The existing restore script was inspected without running it and without
  using `-ResetDnsToDhcp`.

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

Revised on 2026-07-19 after dogfooding feedback.

- VPN Router no longer stops, disables, or otherwise changes AdGuard or another third-party service.
- Preflight checks actual exclusive availability of local UDP port 53 instead of looking for a product or service name.
- The DNS proxy binds the port exclusively and proves response ownership with a random local self-test query before Windows DNS is changed.
- Response ownership is checked every five seconds while connected.
- If another DNS/security product takes or intercepts the response path, VPN Router fails safe by disconnecting and restoring DNS, routes, and the WireGuard tunnel.
- The old AdGuard handoff file is read only to restore state left by an earlier build; new connections never create it.
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

## Portable lifecycle, IPC, and release hardening

Implemented and automatically verified on 2026-07-28 without starting the
elevated backend or mutating DNS, routes, or WireGuard.

- Launcher and desktop readiness now require a matching protocol version,
  product version, and payload identity. A stale or differently built backend is
  rejected before the UI is enabled.
- The portable launcher passes the original Windows user SID to the elevated
  backend. The named pipe ACL contains only that SID, Administrators, and
  LocalSystem; the broad `InteractiveSid` rule was removed.
- The desktop app is single-instance per interactive user session. A second
  process signals the first window instead of creating a duplicate dashboard.
- Closing the UI keeps a connected backend alive. When the backend reports
  `Disconnected`, the UI requests graceful backend shutdown.
- Reopening derives state from the existing backend rather than an optimistic UI
  flag.
- Portable cache cleanup is refused unless disconnected, retains the active and
  immediately previous valid payload, and only targets
  `%LOCALAPPDATA%\VpnRouter\app`. Profiles and DPAPI secrets are outside that
  scope.
- Troubleshooting output no longer previews network snapshots, route files, or
  DNS observations. It contains schema-versioned bounded counts and flags only.
- App, backend, launcher, and manifest versions are aligned to `0.1.0`; trimming
  and ReadyToRun are disabled for the portable Release path.
- The unused `systemAIModels` restricted capability was removed.
- `scripts\windows\verify-release.ps1` verifies version, checksum, extraction,
  and payload completeness. It can require a valid Authenticode signature.
- Two consecutive Release builds produced the same 195,529,964-byte artifact and
  SHA-256:
  `54D37DE05EDA397EB5BB4059EF76D98CC8DE920006796E5DE49966BAD7D236BC`.
- The owner chose an unsigned `0.1.0` public preview because a commercial
  code-signing certificate is not cost-effective. The owner-operated lifecycle
  matrix, unsigned clean-machine/SmartScreen validation, and exact release tag
  remain pending.

## Local portable lifecycle matrix

The initial launcher and disconnected checks were completed without pressing
`Connect` on 2026-07-28. A second run exercised a real connection.

- The artifact checksum matched the recorded unsigned candidate before launch.
- The first portable launch produced one elevated backend and one dashboard with
  no active-connection marker.
- A second launch exited with code 0 while both backend and UI process counts
  remained one and both PIDs remained unchanged.
- Closing the disconnected UI caused both UI and backend to exit gracefully.
- Disconnected cache cleanup retained the active and previous valid caches. No
  older cache existed in this run; the automated test covers actual older-cache
  removal.
- A newly generated schema-v1 troubleshooting report contained 19 lines and no
  private-key label, known media domain, or IPv4-address pattern.
- The UAC cancellation case remains pending because the attempted cancellation
  launch was approved and completed as a normal launch.
- The final state was zero VPN Router processes, no active-connection marker, and
  two valid portable cache directories.
- While connected, closing the UI preserved the backend PID, tunnel adapter,
  loopback DNS ownership, and active marker.
- Reopening the portable executable reused the existing backend and reported
  `Connected`.
- Connected portable-cache cleanup was refused with no deletion.
- A normal privileged disconnect removed the tunnel adapter, loopback DNS
  ownership, active marker, and all managed-route records. The baseline default
  route remained, AdGuard stayed `Running`/`Automatic`, and the UI and backend
  exited.
- DNS ownership loss, forced backend termination, forced UI termination, reboot
  recovery, different-user ACL, and unsigned clean-machine behavior remain
  pending.

## Next task

Continue the pending owner-operated unsigned lifecycle checks in
`docs/windows-release-hardening.md`, then repeat the matrix with the exact unsigned
public-preview candidate on a clean Windows 11 x64 machine. External player
automation and account-dependent Netflix checks are not release blockers.

## Notes for next session

- Avoid reading raw `.conf` contents unless the user explicitly approves; it contains PrivateKey.
- It is safe to inspect Endpoint lines only if needed, but prefer UI/summary output.
- Avoid enabling DNS mutation until the recovery script and current build are confirmed.
- Keep `.slnx` and `VpnRouterVs.sln` both building; Visual Studio uses the classic `.sln` more reliably.
