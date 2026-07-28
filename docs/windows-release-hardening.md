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
2. Windows Security, SmartScreen, and clean-machine behavior are recorded;
3. the published SHA-256 checksum is independently verified;
4. the exact artifact-producing commit is tagged.

The supported `0.1.0` baseline is Windows 11 x64 with WireGuard for Windows
installed separately. No Windows Service or installer registration is created.

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
| Stale backend | Useful compatibility error and no network mutation | Pending |
| Different interactive user | Privileged pipe access denied | Pending |
| UAC cancellation | No backend, DNS, route, or WireGuard mutation | Pending |
| DNS ownership loss | Full VPN Router cleanup without changing third-party products | Pending |
| Backend termination | Next launch restores owned DNS, routes, and tunnel state | Passed: forced service termination left the expected owned state; relaunch removed 34 managed-route records, tunnel, loopback DNS, and active marker before reporting `Disconnected`, 2026-07-28 |
| Reboot while connected | Next launch restores owned network state | Pending |
| Cache cleanup disconnected | Active and previous payload retained; older caches removed | Partial: active/previous retention passed with two caches; no older cache existed, 2026-07-28 |
| Cache cleanup connected | Request refused with no deletion | Passed: privileged request returned `success=false` while connected, 2026-07-28 |
| Redacted troubleshooting file | Counts/status only; no config, key, domain, IP, or DNS payload | Passed: schema v1, 19 lines, prohibited patterns absent, 2026-07-28 |
| Unsigned clean-machine launch | SHA-256 matches; Windows Security is clean; unknown-publisher and SmartScreen behavior recorded | Pending |

Real WireGuard profiles and LocalAppData diagnostics must not be attached to the
matrix. Record only sanitized counts, status, timestamps, error codes, and recovery
outcomes.

The attempted UAC-cancellation run was approved instead of cancelled and therefore
counts only as another successful normal launch. It does not satisfy the UAC
cancellation row.

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
6. run the same unsigned artifact on a clean supported Windows 11 x64 machine with WireGuard installed and
   missing;
7. scan the exact artifact with Windows Security and the chosen release scanning
   service;
8. inspect the extracted payload for raw configs, secrets, and local data;
9. publish the README, checksum, known limitations, and recovery guidance;
10. tag only the exact artifact-producing commit.
