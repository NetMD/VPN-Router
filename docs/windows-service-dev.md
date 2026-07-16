# Windows service development notes

The service install scripts are intentionally manual for the MVP phase.

## WireGuard dependency policy

WireGuard for Windows is an external prerequisite for the MVP.

VPN Router does not bundle, redistribute, or silently install WireGuard. Users must install WireGuard for Windows separately from the official WireGuard distribution before using WireGuard profiles.

Official install page:

```text
https://www.wireguard.com/install/
```

The app only detects whether `wireguard.exe` exists in the standard install locations and opens the official install page when it is missing.

Install from an elevated PowerShell session:

```powershell
.\scripts\windows\install-service.ps1
Start-Service VpnRouterService
```

Uninstall:

```powershell
.\scripts\windows\uninstall-service.ps1
```

Runtime feature flags live in `windows/VpnRouter.Service/appsettings.json`.

Defaults are safe:

- `EnableWireGuardActivation`: `false`
- `EnableWindowsDnsMutation`: `false`
- `EnableWindowsRouteMutation`: `false`

Do not enable mutation flags until the matching implementation has explicit recovery behavior and has been tested from an elevated service context.

Development run scripts:

```powershell
.\scripts\windows\run-service-dev.ps1
.\scripts\windows\run-app-dev.ps1
```

Or run both:

```powershell
.\scripts\windows\run-dev.ps1
```

To test actual WireGuard tunnel activation after importing a profile, start the development service with:

```powershell
.\scripts\windows\run-service-dev.ps1 -EnableWireGuardActivation
```

To test the full experimental path, run PowerShell as administrator and enable each mutation explicitly:

```powershell
.\scripts\windows\run-service-dev.ps1 -EnableWireGuardActivation -EnableWindowsRouteMutation -EnableWindowsDnsMutation
```

Notes:

- `EnableWireGuardActivation` runs WireGuard's tunnel service install/uninstall commands for imported profiles.
- `EnableWindowsRouteMutation` adds/removes IPv4 `/32` routes for resolved selected domains.
- `EnableWindowsDnsMutation` makes the DNS proxy listen on `127.0.0.1:53`; Windows DNS server mutation still needs a dedicated restore-tested implementation before it should be used on a primary machine.

Manual development recovery:

```powershell
.\scripts\windows\restore-network-dev.ps1
```

If DNS mutation was enabled and name resolution appears broken, run from an elevated PowerShell session:

```powershell
.\scripts\windows\restore-network-dev.ps1 -ResetDnsToDhcp
```

This stops development app/service processes, stops WireGuard test tunnel services, removes recorded VpnRouter host routes when possible, and optionally resets active non-WireGuard adapters' IPv4 DNS settings to DHCP/default.
