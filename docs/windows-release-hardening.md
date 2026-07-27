# VPN Router Windows release hardening

Last updated: 2026-07-28 KST

## Distribution decision

The current Windows `0.1.0` artifact is an **unsigned private release candidate**,
not a public download. The x64 portable architecture, deterministic payload,
version metadata, checksum generation, extraction smoke test, backend compatibility
handshake, exact-user IPC ACL, and bounded troubleshooting output are implemented.

Public distribution remains blocked until:

1. an Authenticode code-signing identity and timestamp policy are selected;
2. the signed owner-operated lifecycle/network matrix passes;
3. the signed artifact passes Windows Security, SmartScreen, and clean-machine
   verification;
4. the exact signed artifact-producing commit is tagged.

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

The unsigned result is not a public release. It proves deterministic assembly and
safe extraction only.

No local code-signing certificate with a private key was available in the current
user or local machine certificate stores during the 2026-07-28 verification. The
artifact therefore remains `NotSigned`; obtaining or connecting the chosen signing
identity is an external release prerequisite.

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

## Signed owner-operated matrix

Do not treat compilation or extraction as evidence for these checks.

| Check | Expected result | Status |
|---|---|---|
| First portable launch | One UAC prompt, one backend, one dashboard | Pending |
| Second portable launch | No second backend or dashboard; existing window activates | Pending |
| Close while disconnected | UI closes and backend exits gracefully | Pending |
| Close/reopen while connected | VPN stays connected and UI resynchronizes from backend | Pending |
| Stale backend | Useful compatibility error and no network mutation | Pending |
| Different interactive user | Privileged pipe access denied | Pending |
| UAC cancellation | No backend, DNS, route, or WireGuard mutation | Pending |
| DNS ownership loss | Full VPN Router cleanup without changing third-party products | Pending |
| Backend termination | Next launch restores owned DNS, routes, and tunnel state | Pending |
| Reboot while connected | Next launch restores owned network state | Pending |
| Cache cleanup disconnected | Active and previous payload retained; older caches removed | Pending |
| Cache cleanup connected | Request refused with no deletion | Pending |
| Redacted troubleshooting file | Counts/status only; no config, key, domain, IP, or DNS payload | Pending |
| Signed clean-machine launch | Signature valid; Windows Security clean; expected SmartScreen behavior recorded | Pending |

Real WireGuard profiles and LocalAppData diagnostics must not be attached to the
matrix. Record only sanitized counts, status, timestamps, error codes, and recovery
outcomes.

## Authenticode signing gate

The build accepts an optional certificate thumbprint:

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
3. sign and timestamp the portable artifact;
4. verify the signature and published checksum;
5. run the signed owner matrix on the development machine;
6. run on a clean supported Windows 11 x64 machine with WireGuard installed and
   missing;
7. scan the exact artifact with Windows Security and the chosen release scanning
   service;
8. inspect the extracted payload for raw configs, secrets, and local data;
9. publish the README, checksum, known limitations, and recovery guidance;
10. tag only the exact signed artifact-producing commit.
