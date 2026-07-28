# Windows Codex next session

Last updated: 2026-07-28 KST

This is the first document Windows Codex should read after `AGENTS.md`. It turns
the current repository state, the completed macOS safety work, and the
`v0.1.0` release plan into an executable Windows work order.

> Resume update (2026-07-28): the baseline/parity group and the Phase 2
> launcher lifecycle/IPC implementation are complete. Release packaging is
> deterministic, extraction/checksum verification passes, and the current
> candidate is intentionally unsigned because the owner declined the cost of a
> commercial code-signing certificate.
> The owner subsequently defined the portable release as current-user-only and
> waived a live second-account run on the single-user release machine. Keep the
> exact-user ACL regression test; a future installer must explicitly distinguish
> `Current user` from `All users`.
> The owner also accepted the DNS ownership fault-injection test as sufficient
> for `v0.1.0`: all 30 focused checks passed 10 consecutive runs and both
> solutions built cleanly. Do not describe it as a live external DNS collision.
> The owner waived the clean Windows 11, missing-WireGuard, and fresh
> SmartScreen-reputation run for `v0.1.0`. Do not describe those cases as tested;
> keep the unsigned warning, checksum guidance, and supported prerequisites.
> Resume with the owner-operated matrix in
> `docs/windows-release-hardening.md`, then finish the remaining local artifact
> and release-tag gates. The detailed original work order remains below as implementation
> history.

## Safety and platform boundary

- Work from Windows 11 x64 for Windows code, builds, launcher behavior, UAC,
  WireGuard, DNS, route, adapter, and recovery tests.
- Read `docs/windows-mvp-handoff.md`, `docs/windows-mvp-progress.md`, and
  `docs/v0.1.0-release-plan.md` before editing.
- Never read, print, commit, or attach a real WireGuard `.conf` or private key.
  Use the existing fake-key fixtures for automated tests.
- Never stop, disable, reconfigure, or change the startup mode of AdGuard,
  antivirus, security DNS, another VPN, or another third-party product.
- Keep Windows networking native. Reuse macOS product semantics and tests where
  useful, but do not port Network Extension, `utun`, SwiftUI, XPC, or macOS
  packaging code into Windows.
- Captive-portal discovery, sign-in, and recovery are outside `v0.1.0`. The user
  authenticates with VPN Router disconnected and connects only after normal
  internet access works.

## Start-of-session baseline

Run these from the repository root in PowerShell:

```powershell
git status --short --branch
git pull --ff-only
dotnet --info
Test-Path 'C:\Program Files\WireGuard\wireguard.exe'
dotnet build .\windows\VpnRouter.slnx -nr:false
dotnet build .\windows\VpnRouterVs.sln -nr:false
dotnet run --project .\windows\VpnRouter.Tests\VpnRouter.Tests.csproj --no-build
```

The current focused test executable contains 26 checks. Reconcile the progress
document if the Windows baseline produces a different count. Do not run a
network-mutating script until the normal build/tests pass and
`scripts/windows/restore-network-dev.ps1` has been inspected without using the
`-ResetDnsToDhcp` option.

## Current verified cross-platform semantics

The signed macOS build-20 run adds evidence and semantics that Windows should
match natively:

- Explicitly expand the media roots to include `www.youtube.com` and
  `www.netflix.com`, in addition to the existing CDN families.
- Retain rotating IPv4 answers for their original 15-minute lifetime across
  refreshes instead of dropping an address merely because one lookup rotated.
- Bound an active route plan to 512 IPv4 host routes and fail before partial
  mutation when the limit would be exceeded.
- Filter target-domain AAAA responses while leaving target A and unrelated AAAA
  responses unchanged.
- Treat browser secure DNS as a preflight limitation. Never change Chrome or
  Edge policy automatically.
- Continuously prove ownership of the DNS response path and fail safe through
  complete VPN Router cleanup when ownership is lost.
- Do not alter another VPN. Test a second-VPN transition using Windows adapter
  and DNS state; add a Windows-native fail-safe only if the existing DNS
  ownership monitor does not already catch it.
- Diagnostic/troubleshooting output contains bounded state, counts, timestamps,
  and failure codes only. It must not contain raw configs, keys, domains,
  addresses, DNS payloads, or unrestricted logs.

Windows already implements several of these behaviors, including target AAAA
filtering, 15-minute managed-route expiry, browser `DnsOverHttpsMode` inspection,
DNS ownership monitoring, and crash recovery. Verify before changing them; add
only missing behavior and regression tests.

## Immediate implementation order

### 1. Reconcile the Windows baseline and parity gaps

1. Update `DomainRuleExpander` and its focused test for the two explicit `www`
   media entry points.
2. Confirm `ManagedRouteLifecycle` retains distinct rotating answers until their
   original expiry. Add a focused test if the existing refresh tests do not prove
   it.
3. Add a 512-route combined static/dynamic limit before Windows route mutation,
   with a no-partial-write test.
4. Re-run the focused tests and both solution builds.

### 2. Finish Phase 2 launcher lifecycle and IPC security

1. Add a backend information/handshake command containing a protocol version,
   product version, and payload identity. Make both launcher readiness and the
   desktop app reject an incompatible stale backend.
2. Replace the named-pipe `InteractiveSid` allow rule with the actual launching
   user SID plus administrators/System. Add ACL tests; a different interactive
   user must not receive privileged IPC access.
3. Make the desktop app single-instance. A second portable launch must activate
   or reconnect to the existing UI and must not start a second backend.
4. Define UI-close behavior:
   - connected: the elevated backend remains alive and recoverable;
   - disconnected: request a graceful backend exit;
   - reopening: reconnect and derive state from the backend.
5. Retain only the active and immediately previous valid payload cache while
   disconnected.
6. Add a visible portable-data cleanup action that refuses while connected and
   does not delete imported profiles or DPAPI secrets unless the UI explicitly
   says so.

### 3. Run the owner-operated Phase 1/2 acceptance

- First portable launch produces one UAC prompt and one dashboard.
- Second launch produces no second backend or duplicate dashboard.
- Closing/reopening the UI while connected preserves and resynchronizes state.
- Backend/protocol version mismatch produces a useful error without mutating the
  network.
- Failed UAC, extraction, or readiness leaves DNS, routes, and WireGuard
  unchanged.
- DNS ownership loss and backend termination restore network state without
  changing third-party products.

### 4. Continue Phase 3, then Phase 4

Use the unchecked matrix in `docs/v0.1.0-release-plan.md`. Record only sanitized
counts and outcomes. After the dogfooding matrix passes, complete release
warnings/tests, version metadata, README, checksums, signing decision, and the
exact release tag.

## Do not start with

- OpenVPN, L2TP, provider-account automation, installer/MSIX, automatic update,
  ARM64/x86, application routing, or full IPv6 split routing.
- Account-dependent Netflix automation; the release plan already accepts
  observed Japan-exit media/CDN traffic.
- More YouTube player automation unless a routing regression appears. The
  previous HTTP/media and Japan-exit evidence is sufficient for `v0.1.0`.

## Completion record

After each task group:

1. Update `docs/windows-mvp-progress.md` with the exact test/build and
   owner-operated evidence.
2. Update checkbox state in `docs/v0.1.0-release-plan.md`.
3. Run `git diff --check`.
4. Commit only sanitized source, tests, and docs. Never add LocalAppData
   artifacts, logs, imported profiles, raw troubleshooting files, or WireGuard
   configs.
