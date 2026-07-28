# VPN Router Windows release hardening

Last updated: 2026-07-28 KST

## Distribution decision

The current Windows `0.1.0` artifact is an **unsigned public-preview candidate**.
The owner chose unsigned distribution because a commercial code-signing
certificate is not cost-effective for this release. The x64 portable architecture, deterministic payload,
version metadata, checksum generation, extraction smoke test, backend compatibility
handshake, exact-user IPC ACL, and bounded troubleshooting output are implemented.

Public distribution remains blocked until:

1. the owner-operated lifecycle/network matrix passes on the exact unsigned artifact;
2. the published SHA-256 checksum is independently verified;
3. the exact artifact is scanned on the development machine;
4. the exact artifact-producing commit is tagged.

The supported `0.1.0` baseline is Windows 11 x64 with WireGuard for Windows
installed separately. No Windows Service or installer registration is created.
The portable build is per-user: its runtime and data stay under the launching
user's `%LOCALAPPDATA%`, and privileged IPC is limited to that launching user
plus Administrators and LocalSystem.

## Automated release verification

Run:

```powershell
.\scripts\windows\verify-release.ps1 -Version 0.1.0
```

The verification flow:

1. publishes the unpackaged WinUI app with trimming and ReadyToRun disabled;
2. publishes the elevated backend as a self-contained single file;
3. creates a sorted payload ZIP with normalized entry timestamps;
4. embeds that payload in the one-file launcher;
5. generates a SHA-256 checksum file;
6. verifies product version and checksum;
7. runs `--extract-only` without UAC, backend startup, or network mutation;
8. verifies the extracted app, backend, and completion marker.

Verified on 2026-07-28:

```text
Artifact: artifacts\portable\VpnRouter-0.1.0-x64.exe
Size: 195,529,964 bytes
SHA-256: 54D37DE05EDA397EB5BB4059EF76D98CC8DE920006796E5DE49966BAD7D236BC
Product version: 0.1.0
Signature: NotSigned
Extraction-only smoke check: Passed
Second clean publish SHA-256: identical
```

The current result proves deterministic assembly and safe extraction. It becomes
the public-preview artifact only after the pending owner-operated gates pass.

No local code-signing certificate with a private key was available in the current
user or local machine certificate stores during the 2026-07-28 verification.
`0.1.0` will remain `NotSigned`; users must expect an unknown-publisher or
SmartScreen warning and verify the checksum from the official release channel.

## Implemented lifecycle and security controls

- Backend information includes protocol version, product version, and payload
  identity.
- Launcher readiness rejects unsupported, stale, or differently built backends.
- The desktop app independently checks backend compatibility before enabling its
  controls.
- The elevated backend pipe grants access only to the launching user SID,
  Administrators, and LocalSystem. The broad `InteractiveSid` rule was removed.
- The desktop app is single-instance within the user's interactive session; a
  second launch signals the existing window.
- Closing the UI while connected leaves the elevated backend alive.
- Closing the UI while disconnected requests graceful backend shutdown.
- Reopening the UI derives connection state from the existing backend.
- Portable cleanup runs only while disconnected, retains the active and previous
  valid payload, and never targets profiles or DPAPI-protected secrets.
- Troubleshooting output contains schema-versioned bounded counts and flags only.
  Raw routes, domains, IP addresses, DNS observations, configs, keys, and logs are
  not exported.
- The unused `systemAIModels` restricted capability was removed from the future
  MSIX manifest.

## Owner-operated unsigned matrix

Do not treat compilation or extraction as evidence for these checks.

| Check | Expected result | Status |
|---|---|---|
| First portable launch | One UAC prompt, one backend, one dashboard | Passed locally, 2026-07-28 |
| Second portable launch | No second backend or dashboard; existing window activates | Passed by stable backend/UI PIDs and launcher exit 0, 2026-07-28 |
| Close while disconnected | UI closes and backend exits gracefully | Passed locally twice, 2026-07-28 |
| Close/reopen while connected | VPN stays connected and UI resynchronizes from backend | Passed for normal close and forced UI termination: backend PID stayed stable, tunnel/DNS state remained active, and the reopened UI reported `Connected`, 2026-07-28 |
| Stale backend | Useful compatibility error and no network mutation | Passed: the corrected candidate rejected a protocol-99 fake backend, showed the VPN Router error dialog, exited 1, and started neither the elevated backend nor desktop app; network state was unchanged, 2026-07-28 |
| Different interactive user | Privileged pipe access denied | Live second-account run waived by owner: the portable release is current-user-only and the focused ACL check proves that the broad Interactive SID is absent and only the launching user, Administrators, and LocalSystem are allowed, 2026-07-28 |
| UAC cancellation | No backend, DNS, route, or WireGuard mutation | Passed from normal Explorer launch: the owner selected No and closed the cancellation notice; no VPN Router process, tunnel, loopback DNS owner, active marker, or managed route remained, 2026-07-28 |
| DNS ownership loss | Full VPN Router cleanup without changing third-party products | Passed by owner-approved automated evidence: an internal fault-injection test passed 10 consecutive 30-check runs and proved DNS stop, managed-route removal, VPN disconnect, network-snapshot restore, active-marker cleanup, and failed-state reporting, 2026-07-28 |
| Backend termination | Next launch restores owned DNS, routes, and tunnel state | Passed: forced service termination left the expected owned state; relaunch removed 34 managed-route records, tunnel, loopback DNS, and active marker before reporting `Disconnected`, 2026-07-28 |
| Reboot while connected | Next launch restores owned network state | Passed: after reboot, startup recovery removed 38 managed-route records, the tunnel adapter, loopback DNS ownership, and the active marker before reporting `Disconnected`, 2026-07-28 |
| Cache cleanup disconnected | Active and previous payload retained; older caches removed | Passed: a synthetic older valid cache was removed while both pre-existing valid caches, user-data metadata, and network state were retained; the disconnected UI/backend then exited normally, 2026-07-28 |
| Cache cleanup connected | Request refused with no deletion | Passed: privileged request returned `success=false` while connected, 2026-07-28 |
| Redacted troubleshooting file | Counts/status only; no config, key, domain, IP, or DNS payload | Passed: schema v1, 19 lines, prohibited patterns absent, 2026-07-28 |
| Unsigned clean-machine launch | SHA-256 matches; Windows Security is clean; unknown-publisher and SmartScreen behavior recorded | Waived by owner for `v0.1.0`; no clean-machine, missing-WireGuard, or fresh SmartScreen reputation result is claimed, 2026-07-28 |

Real WireGuard profiles and LocalAppData diagnostics must not be attached to the
matrix. Record only sanitized counts, status, timestamps, error codes, and recovery
outcomes.

The owner waived the clean Windows 11 machine run for `v0.1.0`. This removes the
clean-machine, missing-WireGuard, and fresh SmartScreen-reputation checks from
the release gate; it does not record them as empirically passed. Public
documentation must retain the unsigned/unknown-publisher warning, checksum
verification instructions, and Windows 11 x64 plus separately installed
WireGuard prerequisite. The exact artifact should still receive a local Windows
Security scan before tagging.

The owner waived a live different-account run because the release machine has no
additional user account and `v0.1.0` is portable rather than installed. This is
not recorded as an empirical second-account pass. The release decision relies on
the exact-user pipe ACL implementation and focused regression check. Portable
use is supported only for the current launching user. A future installer must
offer an explicit `Current user` versus `All users` scope choice and apply
storage, service registration, ACLs, upgrades, and removal consistently with the
selected scope.

The attempted UAC-cancellation run was approved instead of cancelled and therefore
counts only as another successful normal launch. It does not satisfy the UAC
cancellation row.

A later UAC-cancellation run was started from the normal Explorer shell because
the Codex PowerShell session was already elevated and could not produce a UAC
prompt. The owner selected `No` and closed the cancellation notice. The
post-cancellation state contained zero VPN Router processes, tunnel adapters,
loopback DNS owners, active markers, and managed routes. Wi-Fi remained up with
automatic IPv4 DNS, one alive default route, working DNS and HTTPS, and AdGuard
`Running`. The empty managed-route file and network snapshot predated the manual
run and were not changed by the cancellation path.

The disconnected cache-cleanup path was exercised against the corrected
candidate by adding one synthetic older valid cache under the per-user portable
cache root. Cleanup removed only that synthetic cache and retained both
pre-existing valid caches. Metadata outside the cache root and the route/DNS
state were unchanged. After the window became ready, normal UI close shut down
both the disconnected app and backend with no tunnel or loopback DNS owner left.

An attempted live DNS-ownership-loss injection used two temporary Windows
Firewall rules scoped only to the VPN Router backend and loopback UDP port 53.
Windows loopback handling bypassed those rules, so the ownership monitor
correctly remained healthy and this attempt does not satisfy the matrix row.
Both test rules were removed. A normal IPC disconnect then removed 38 managed
routes, the tunnel, loopback DNS ownership, and the active marker; DNS and HTTPS
connectivity recovered, AdGuard remained running, and the disconnected app and
backend exited normally.

Automated coverage now injects a fatal DNS ownership signal through a test-only
DNS controller and executes the production `ConnectionOrchestrator` health
monitor and disconnect path. Recovery-marker and legacy DNS-filter paths are
redirected to a temporary directory, so the test cannot touch LocalAppData or a
third-party service. It verifies DNS proxy stop, managed-route removal, VPN
disconnect, network-snapshot restore, recovery-marker removal, and failed-state
reporting. The 30-check executable passed 10 consecutive runs; both Windows
solutions then built with zero warnings and zero errors. No test command was
added to the product IPC or UI. This automated result does not claim a live
external ownership collision. The owner accepted this automated evidence as
sufficient for the `v0.1.0` release gate; a live external collision is no longer
required for this release.

A later pre-commit release build from the current source produced a
199,261,420-byte unsigned candidate with SHA-256
`B4E2A75D1F3DACCE025D734BE3C880AA1609ECE7AF5C8E490135451C5BE5879C`.
Version, checksum, and extraction verification passed. Windows Security was
enabled with real-time protection and current-day signatures; its custom scan
reported zero candidate-specific detections. The freshly extracted payload
contained 526 files under only `app` and `backend`, with zero WireGuard
configuration, key/certificate, profile, recovery, diagnostic, reparse-point, or
out-of-root files. This is a pre-commit candidate, not the final tag artifact,
and must be rebuilt and rescanned after the release commit.

The same candidate completed a non-mutating sanitized-profile lifecycle test:
import, rename, rule add/list/remove, connection-plan validation, and delete all
passed. The existing profile count and secret-file name set were restored,
network state remained unchanged, and the disconnected app/backend exited
normally. No real configuration or private key was read.

The owner matrix also accepts the failure-independent troubleshooting evidence:
the focused prohibited-pattern test and a real 19-line schema-v1 report prove
the same bounded counts/status format used after every failure state. Launcher
readiness evidence combines automated protocol, extraction, and cache checks
with live stale-backend rejection and UAC cancellation.

A subsequent real-profile run connected successfully. Closing the dashboard left
one backend, the tunnel adapter, loopback DNS ownership, and the active marker in
place. Reopening the same portable executable reused the backend and resynchronized
to `Connected`. Connected cache cleanup was refused. A normal privileged
`Disconnect` request then removed the tunnel adapter, loopback DNS ownership, active
marker, and all managed-route records. The original single default route remained,
AdGuard remained `Running` with `Automatic` start type, and both VPN Router
processes exited. No raw profile, key, domain, endpoint, or route value was read or
recorded.

The forced-UI variant was also exercised against the same unsigned artifact.
Terminating only `VpnRouter.App` left the original `VpnRouter.Service` PID, tunnel
adapter, loopback DNS ownership, and active marker intact. Relaunching created one
new UI process, reused the original backend, and returned `Connected` with an
active profile. Normal disconnect and UI close then restored the same clean
baseline.

The forced-backend variant terminated only the elevated `VpnRouter.Service` while
connected. The UI, active marker, 34 managed-route records, tunnel adapter, and
loopback DNS ownership initially remained, establishing the intended crash
condition. Relaunching the portable executable started a new backend and completed
startup recovery before serving IPC: the marker, managed routes, tunnel, and
loopback DNS were removed, and the backend reported `Disconnected` with no active
profile. The original default route and AdGuard `Running`/`Automatic` state were
unchanged.

The connected-reboot variant was exercised with the exact recorded unsigned
candidate. Immediately after reboot there were no VPN Router processes, while the
active marker, 38 managed-route records, one tunnel adapter, and one loopback-DNS
owner remained as the expected recovery input. Launching the candidate produced
one UI and one backend; startup recovery removed those four classes of owned
state and IPC reported `Disconnected` with no active profile. The single default
route remained alive, AdGuard remained `Running`/`Automatic`, and DNS plus HTTPS
connectivity succeeded over the user's current mobile hotspot. No saved Wi-Fi
profile or third-party product was changed.

### DNS source-mode regression follow-up

The earlier disconnect checks proved that a usable DNS server was restored but
did not prove that an adapter originally using automatic DNS remained automatic.
A 2026-07-28 user report exposed that the saved DHCP-provided address was being
restored as a manual DNS address.

The corrected dogfood build records automatic/manual IPv4 DNS mode and restores
automatic mode with `-ResetServerAddresses`. Its focused 29-check test run, both
solution builds, extraction verification, and a real connect/disconnect run
passed. The post-disconnect state retained automatic DNS, had no loopback DNS,
managed routes, or VPN tunnel, and had working DNS and HTTPS connectivity.
Corrected-build SHA-256:
`A4D41597A1C25373AC70FF1029299533DE9065178B3DC823E5CB325E652FA2F1`.
A physical reboot after the corrected disconnect also passed. The Wi-Fi adapter
returned `Up` with DHCP and automatic IPv4 DNS enabled, owned the single alive
default route, and had working DNS resolution and HTTPS connectivity. There were
no VPN Router processes, tunnel adapters, or loopback DNS owners, and AdGuard
remained running.

### Stale-backend rejection

The corrected unsigned candidate was run against a temporary local IPC server
that returned protocol version 99. The real launcher showed its `VPN Router`
error dialog and exited with code 1. It did not start an elevated backend or the
desktop app. Before/after fingerprints of the IPv4 route table, DNS settings,
active marker, managed-route state, and network snapshot were identical. The
single alive default route, zero tunnel adapters, zero loopback DNS owners, and
AdGuard `Running` state were also unchanged. The temporary IPC server was removed
after the test.

## Unsigned distribution and optional future signing

Authenticode is not a `0.1.0` release requirement. The public-preview page must
clearly state that the artifact is unsigned, show its exact SHA-256 checksum, and
explain the expected Windows warning without instructing users to disable
SmartScreen or Windows Security.

The build keeps optional signing support for a future sponsored or commercial
release. To use it, provide a certificate thumbprint:

```powershell
.\scripts\windows\build-portable.ps1 `
  -Version 0.1.0 `
  -CertificateThumbprint '<certificate thumbprint>'
```

The certificate must be available in the current user or local machine personal
certificate store and must have its private key. The script applies a SHA-256
Authenticode signature with a timestamp service and fails if PowerShell does not
report the signature as valid.

Verify a signed candidate with:

```powershell
.\scripts\windows\verify-release.ps1 `
  -Version 0.1.0 `
  -SkipBuild `
  -RequireSignature
```

Never commit certificate files, PFX passwords, hardware-token credentials, signing
service tokens, or private keys.

## Public release gate

Before tagging `v0.1.0`:

1. run both Windows solutions and the focused test executable;
2. produce the candidate from a clean checkout;
3. confirm that the candidate is intentionally `NotSigned`;
4. verify and publish the exact SHA-256 checksum;
5. run the owner matrix on the development machine;
6. scan the exact artifact with Windows Security and the chosen release scanning
   service;
7. inspect the extracted payload for raw configs, secrets, and local data;
8. publish the README, checksum, known limitations, and recovery guidance;
9. tag only the exact artifact-producing commit.
