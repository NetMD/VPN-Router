# VPN Router for Windows

VPN Router routes only the websites selected by the user through an existing
WireGuard connection. It does not provide a VPN account or VPN server.

## Supported private-release baseline

- Windows 11 x64
- WireGuard for Windows installed separately
- One-file portable `VpnRouter-0.1.0-x64.exe`
- User-supplied WireGuard configuration imported through the app
- Current-user-only portable runtime, storage, and privileged IPC access

The first public preview is intentionally unsigned. The owner waived
clean-machine, missing-WireGuard, and fresh SmartScreen-reputation testing for
`v0.1.0`; those cases are not claimed as verified. The artifact remains blocked
until the remaining local matrix, security scan, checksum, and release-tag gates
are complete.

## Installation and first launch

1. Install WireGuard for Windows from its official distribution.
2. Place the VPN Router portable executable in a user-controlled folder.
3. Verify the published SHA-256 checksum. Version `0.1.0` is unsigned and Windows
   may show an unknown-publisher or SmartScreen warning.
4. Run the executable and approve its single UAC prompt.
5. Import a WireGuard configuration through the app, add site rules, and connect.

VPN Router does not install a Windows Service or create an uninstall entry. Its
versioned runtime payload is cached under:

```text
%LOCALAPPDATA%\VpnRouter\app
```

Profiles, DPAPI-protected secrets, recovery state, and bounded diagnostics are
stored separately under:

```text
%LOCALAPPDATA%\VpnRouter
```

The portable release is supported only for the Windows user who launches it.
Another interactive user is not granted access to its privileged IPC endpoint.
A future installer will present separate `Current user` and `All users` scope
choices instead of silently selecting a machine-wide installation.

The in-app cache cleanup action removes only old runtime payloads. It retains the
active and immediately previous valid payload and refuses to run while connected.
It does not delete imported profiles or DPAPI-protected secrets.

## Safety behavior

- Only selected IPv4 destinations are routed through WireGuard.
- Target-domain AAAA responses are filtered to reduce IPv6 bypass.
- Browser secure DNS is reported as a limitation and is never changed
  automatically.
- VPN Router verifies exclusive local DNS response ownership before changing
  Windows DNS and monitors ownership while connected.
- If DNS ownership is lost, VPN Router disconnects and restores its own DNS,
  routes, and tunnel state.
- VPN Router never stops, disables, or reconfigures third-party DNS, ad-blocking,
  antivirus, security, or VPN products.
- The elevated IPC pipe grants access only to the launching Windows user,
  Administrators, and LocalSystem.
- The desktop app and launcher reject a backend with a mismatched protocol,
  product version, or portable payload identity.

## Known limitations

- Windows 11 x64 is the only supported `0.1.0` target.
- WireGuard for Windows is an external prerequisite.
- IPv4 split routing is supported; full IPv6 split routing is not.
- Browsers using secure DNS may bypass the local DNS proxy until the user turns
  that browser feature off.
- Another product that owns or intercepts local DNS port 53 can prevent
  connection. VPN Router asks the user to resolve the conflict manually.
- Captive-portal sign-in must be completed while VPN Router is disconnected.
- OpenVPN, L2TP, application routing, automatic updates, and provider account
  automation are not included.

## Recovery

Use the dashboard's network restore action first. If the UI or backend cannot
start, open an elevated PowerShell prompt in the repository checkout and run:

```powershell
.\scripts\windows\restore-network-dev.ps1
```

Use `-ResetDnsToDhcp` only when the saved network snapshot cannot restore DNS and
the user has explicitly confirmed that DHCP/default DNS is appropriate.

## Troubleshooting privacy

Troubleshooting output is schema-versioned and contains bounded status, counts,
timestamps, and feature flags. It does not include raw WireGuard configurations,
private keys, domains, IP addresses, DNS packets, managed-route contents, or
unrestricted logs. Review every file before sharing it.

## Release verification

Build and verify the unsigned public-preview candidate:

```powershell
.\scripts\windows\verify-release.ps1 -Version 0.1.0
```

If a future release is signed, require a valid Authenticode signature with:

```powershell
.\scripts\windows\verify-release.ps1 -Version 0.1.0 -SkipBuild -RequireSignature
```

Optional future signing remains supported. Provide the thumbprint of a locally
installed code-signing certificate that has a private key:

```powershell
.\scripts\windows\build-portable.ps1 `
  -Version 0.1.0 `
  -CertificateThumbprint '<certificate thumbprint>'
```

Never commit certificate material, signing credentials, imported WireGuard
profiles, LocalAppData state, or troubleshooting artifacts.
