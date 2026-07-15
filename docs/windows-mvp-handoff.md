# VPN Router Windows MVP Handoff

Date: 2026-07-15

This document captures the current product and architecture decisions so the work can continue from a Windows PC with Codex.

## Product Goal

Build a standalone client app that lets a general user route only selected websites through an existing VPN connection.

This product does not provide a VPN service. It uses VPN profiles that the user already has, such as WireGuard, OpenVPN, L2TP, or later profiles imported from supported VPN providers.

Primary MVP target:

- Platform: Windows
- User: general consumer
- Routing target: specific websites/domains only
- First VPN protocol: WireGuard
- Later VPN protocols: OpenVPN, L2TP
- Later provider import: selected VPN provider adapters

Out of scope for the first MVP:

- App-specific routing
- macOS, iOS, Android implementation
- Own VPN server operation
- VPN provider account automation
- Full IPv6 split routing
- Advanced route editor

## Repository Layout Direction

The app should not be forced into one-source multi-use across all operating systems. VPN, DNS, routing, background execution, and permission models are OS-specific.

Recommended monorepo layout:

```text
vpn_router/
  docs/
    windows-mvp-handoff.md
  windows/
    VpnRouter.App/
    VpnRouter.Service/
    VpnRouter.Core/
    VpnRouter.Ipc/
    VpnRouter.Vpn/
    VpnRouter.Networking/
    VpnRouter.Installer/
  mac/
    app/
    network-extension/
  mobile/
    ios/
    android/
  providers/
    specs/
  test-assets/
```

Share product specs, provider specs, diagnostic schemas, and test assets across platforms. Do not try to share the low-level VPN, DNS, route, firewall, service, or installer implementation.

## Windows Technology Direction

Recommended stack:

- Language: C#
- Runtime: .NET, verify latest stable SDK on the Windows machine before implementation
- UI: WinUI 3 / Windows App SDK
- Background privileged process: .NET Windows Service
- IPC: Named Pipes
- Storage: SQLite
- Secrets: Windows DPAPI or Credential Manager
- First VPN engine: WireGuard
- Installer: evaluate WiX Toolset or MSIX plus service bootstrapper

Visual Studio Community is recommended for WinUI 3 and Windows App SDK work. VS Code can be used as an editor for service/core logic, but Visual Studio is the safer primary tool for project templates, XAML, packaging, debugging profiles, and Windows App SDK setup.

## Development Environment Notes

Windows MVP development should happen on a Windows PC, preferably Windows 11 x64.

Recommended tools:

- Visual Studio Community
- .NET SDK
- Windows App SDK / WinUI workload
- Git
- WireGuard for Windows
- OpenVPN client for later testing
- SQLite tooling
- Optional: VS Code as secondary editor

Mac can be used for planning and docs, but the product needs real Windows testing because it changes DNS, routes, firewall rules, Windows services, and VPN interfaces.

## Codex / IDE Notes

Official Codex documentation confirms these relevant surfaces:

- Codex can be used through the ChatGPT desktop app, Codex CLI, and Codex IDE extension.
- The Codex IDE extension documentation is centered on VS Code and compatible editors.
- The ChatGPT desktop app for Windows can set a preferred editor for opening files, including Visual Studio, VS Code, or another editor.

Practical conclusion:

- A native Codex extension inside Visual Studio Community is not confirmed by the current official Codex manual.
- Recommended workflow on Windows:
  - Use ChatGPT desktop app / Codex with the project folder.
  - Set the preferred editor to Visual Studio if desired.
  - Use Visual Studio Community for WinUI and Windows debugging.
  - Optionally use Codex CLI in a terminal for repo-local tasks.
  - Use VS Code only if the Codex IDE extension is desired directly inside the editor.

## Network Design

Windows routing is IP-based, not domain-based. The app therefore converts selected domains into IP-specific routes.

Core flow:

```text
User rule: youtube.com
  -> DNS query observed by local DNS proxy
  -> youtube.com resolves to one or more IPs
  -> app adds /32 IPv4 routes for those IPs via VPN interface
  -> only those IPs use VPN
  -> default internet route remains normal network
```

Recommended MVP network decisions:

- Local DNS proxy managed by the service
- Windows DNS temporarily points to local DNS proxy during connection
- Domain matching supports the root domain and subdomains by default
- IPv4 host routes only for MVP
- Target-domain AAAA responses should be blocked or filtered to reduce IPv6 leaks
- DNS over HTTPS is not forcefully controlled in MVP; detect or warn when necessary
- Default mode prioritizes connectivity
- Optional protection mode blocks selected sites when VPN routing cannot be applied

Connection sequence:

```text
1. Backup current DNS settings
2. Prepare VPN profile
3. Connect VPN interface
4. Detect VPN interface
5. Ensure default route still uses normal network
6. Start DNS proxy
7. Change Windows DNS to local proxy
8. Pre-resolve configured domains
9. Add discovered IPv4 routes through VPN interface
10. Show connected state
```

Disconnect sequence:

```text
1. Restore original DNS settings
2. Remove all app-managed routes
3. Stop DNS proxy
4. Disconnect VPN
5. Remove firewall/leak-protection rules
6. Show disconnected state
```

Recovery is critical. The Windows Service must be able to restore DNS/routes after UI crash or service restart.

## Windows Process Architecture

Use two main processes:

```text
User Desktop App
  -> Named Pipe IPC
Privileged Windows Service
  -> VPN Adapter Layer
  -> DNS Proxy Controller
  -> Route Manager
  -> Firewall / Leak Guard
  -> Recovery Manager
  -> Profile Store Access
```

Desktop App responsibilities:

- Show UI
- Add/import VPN profiles
- Add/remove website rules
- Start/stop connection
- Display state and diagnostics

Windows Service responsibilities:

- Connect/disconnect VPN
- Run DNS proxy
- Modify Windows DNS settings
- Add/remove routes
- Apply optional firewall/leak protection
- Store and restore network snapshots
- Clean up after crashes

Use Named Pipe ACLs so arbitrary local processes cannot control the service.

## Suggested Windows Projects

```text
windows/
  VpnRouter.App/          # WinUI 3 desktop UI
  VpnRouter.Service/      # privileged Windows Service
  VpnRouter.Core/         # domain models, profile/rule logic
  VpnRouter.Ipc/          # named pipe contracts and DTOs
  VpnRouter.Vpn/          # WireGuard/OpenVPN/L2TP adapters
  VpnRouter.Networking/   # DNS proxy, route manager, DNS control
  VpnRouter.Installer/    # installer/bootstrapper
```

Core adapter interface concept:

```text
VpnAdapter
- validateProfile(profile)
- connect(profile)
- disconnect(profileId)
- getInterfaceInfo(profileId)
- getConnectionStatus(profileId)
- normalizeConfig(profile)
```

MVP implementation should complete `WireGuardAdapter` first and leave OpenVPN/L2TP as later adapters.

## Data Storage

Use SQLite for non-sensitive app state and Windows DPAPI or Credential Manager for secrets.

SQLite entities:

```text
profiles
- id
- name
- type
- created_at
- updated_at
- enabled
- config_ref
- provider_id

domain_rules
- id
- profile_id
- domain
- include_subdomains
- enabled
- created_at

route_entries
- ip
- domain
- profile_id
- expires_at
- interface_index
- added_by

settings
- key
- value
```

Sensitive data must not be stored in plain SQLite:

- WireGuard private key
- VPN username/password
- provider tokens
- L2TP PSK

Logs must mask secrets.

## MVP UI Flow

Keep the UI simple. The user should only need to understand:

- Which VPN profile to use
- Which websites should use VPN
- Whether the app is connected

Main dashboard concept:

```text
Connection status

VPN profile
[ WireGuard - Japan v ]

Sites to open with VPN
[ youtube.com        x ]
[ netflix.com        x ]
[ + Add site ]

[ Connect ]

Recent status
- youtube.com is ready to use VPN
- Other internet traffic uses the normal network
```

First-run flow:

```text
1. Launch app
2. Add VPN configuration
3. Import WireGuard config
4. Confirm profile name
5. Add websites
6. Connect
```

Avoid technical terms in the main UI:

- Avoid: DNS proxy, route table, interface metric, host route, AAAA record
- Prefer: site path, open with VPN, normal internet, protection mode, browser secure DNS

Settings screen:

```text
General
- Start with Windows
- Minimize after connecting

Connection
- Protection mode
- Use VPN DNS
- Prevent IPv6 bypass

Diagnostics
- View connection log
- Create troubleshooting file
- Restore network settings
```

The `Restore network settings` action is mandatory for user trust.

## Known Risks

- CDN domains: a single domain like `youtube.com` may not include all media traffic.
- DNS over HTTPS: browsers can bypass local DNS proxy.
- IPv6 leaks: IPv6 can bypass IPv4-only routes.
- VPN config conflicts: imported profiles can try to force full-tunnel routing.
- Admin permission UX: route/DNS/firewall changes require privileged service operations.
- Recovery: DNS or routes must not remain broken after crash.

## Recommended Next Steps On Windows

1. Create `windows/` solution structure.
2. Create WinUI 3 app skeleton.
3. Create .NET Windows Service skeleton.
4. Define `VpnRouter.Core` domain models.
5. Define `VpnRouter.Ipc` command/response DTOs.
6. Implement Named Pipe proof of concept.
7. Implement WireGuard config parser.
8. Implement service-side network snapshot/restore prototype.
9. Implement DNS proxy prototype.
10. Implement IPv4 route add/remove prototype.
11. Integrate WireGuard connection.
12. Build the first simple dashboard UI.

Do not start with OpenVPN, L2TP, provider import, mobile, or macOS until the Windows WireGuard split-domain MVP proves the network model.
