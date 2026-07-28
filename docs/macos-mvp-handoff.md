# VPN Router macOS MVP handoff

Last updated: 2026-07-20 KST

## Start here

This document is the entry point for Codex continuing development on a Mac. Read
this file completely before creating the Xcode project or changing product scope.
Also read:

1. `docs/windows-mvp-progress.md` for behavior already proven on Windows;
2. `docs/v0.1.0-release-plan.md` for the current product and safety decisions;
3. `windows/VpnRouter.Core/Rules/DomainRuleExpander.cs` for the current media-domain behavior;
4. `windows/VpnRouter.Vpn/WireGuard/WireGuardConfigParser.cs` for parsing cases and sanitization semantics, not for source reuse.

The Windows implementation is a validated product prototype, not a portable
networking library. Reproduce its user-visible behavior with macOS-native APIs.

## Product goal and fixed decisions

Build a standalone consumer macOS app that imports a WireGuard configuration and
routes only user-selected websites through that tunnel. Other traffic must continue
to use the normal network.

Fixed MVP decisions:

- first protocol: WireGuard only;
- user supplies a provider `.conf`; VPN Router is not a VPN provider;
- rules match the root domain and subdomains;
- YouTube and Netflix expand to known media/CDN domains internally;
- success for initial streaming validation means both services identify a Japanese exit;
- IPv4 host routes are sufficient for the first routing proof, but IPv6 bypass must be blocked or clearly reported;
- private keys go to Keychain, never UserDefaults, plist, logs, diagnostics, or Git;
- never stop or reconfigure AdGuard, Unicorn Pro, antivirus, security DNS, or another VPN automatically;
- if another product makes the required DNS path unavailable, refuse or fail safe and explain what the user must change;
- app-specific routing, OpenVPN, L2TP, mobile, provider login automation, and account-dependent Netflix automation remain out of scope.

### Owner-approved parity direction

As of 2026-07-28, `docs/platform-parity-contract.md` is authoritative for shared
user-visible behavior. The proven DNS Proxy path is the target supported macOS
consumer architecture rather than a permanently diagnostic-only feature. Static
pre-resolution may remain an internal bootstrap or explicitly labeled limited
mode, but it must not be presented as equivalent to Windows dynamic routing.

The Windows dashboard is also the product UI reference. Preserve native SwiftUI,
Keychain, Network Extension, XPC, accessibility, windowing, and appearance
behavior, but align macOS information hierarchy, visual density, product
language, navigation, and primary actions with Windows.

## What Windows already proved

The Windows MVP has verified the following product model on real traffic:

- imported WireGuard profiles can be sanitized and the private key stored separately;
- a full-tunnel provider configuration can be transformed into split-domain behavior;
- root rules for YouTube and Netflix require expansion to media/CDN domains;
- DNS answers change over time, so routes need refresh and expiration rather than permanent accumulation;
- unrelated traffic must retain the primary network route;
- crash recovery and DNS/route restoration are release-critical;
- local DNS ownership must be verified by behavior, not inferred from a process name;
- third-party security software must never be disabled automatically;
- the consumer UI works best as a status-first dashboard with profile, site, diagnostics, and settings pages.

Do not port the following Windows mechanisms:

- Windows Service or named-pipe security implementation;
- PowerShell route mutation;
- Wintun interface discovery;
- DPAPI file storage;
- local UDP port 53 ownership tricks;
- MSIX, portable EXE launcher, or Windows recovery scripts;
- WinUI/XAML source.

## Required macOS architecture

Use Swift and Apple frameworks. The recommended initial layout is:

```text
macos/
  VPNRouter.xcodeproj
  App/
    VPNRouterApp.swift
    Features/
      Dashboard/
      Profiles/
      Sites/
      Diagnostics/
      Settings/
    Services/
      TunnelManager.swift
      ProfileStore.swift
      KeychainSecretStore.swift
  PacketTunnel/
    PacketTunnelProvider.swift
    TunnelConfigurationBuilder.swift
  Shared/
    Models/
    Rules/
    Diagnostics/
    IPC/
  Tests/
    ConfigParserTests/
    DomainRuleExpanderTests/
    RoutePlanTests/
```

Target responsibilities:

```text
SwiftUI host app
  -> import and sanitize profiles
  -> store secrets in Keychain
  -> store user rules and non-secret metadata
  -> configure and control NETunnelProviderManager
  -> display NEVPNStatus and diagnostics

Packet Tunnel Provider extension
  -> NEPacketTunnelProvider lifecycle
  -> WireGuardKit adapter
  -> NEPacketTunnelNetworkSettings
  -> IPv4 includedRoutes for selected destinations
  -> split DNS settings where supported
  -> extension-side diagnostics and fail-safe stop
```

Use an App Group for intentionally shared non-secret state and a Keychain access
group for secrets needed by both the app and extension. Keep the app/extension
message contract small and versioned. Prefer `NETunnelProviderSession` provider
messages for live commands or diagnostics; do not invent a local privileged daemon
before Network Extension limitations prove one necessary.

## Apple API constraints

The design must follow current Apple guidance:

- `NEPacketTunnelProvider` supplies a virtual interface through `packetFlow` and
  applies IP, DNS, proxy, MTU, included-route, and excluded-route settings through
  `setTunnelNetworkSettings`.
- `NEIPv4Settings.includedRoutes` sends matching destinations to the tunnel;
  `excludedRoutes` sends matching destinations to the primary interface.
- Do not put `0.0.0.0/0` or `::/0` in the MVP route plan; that would create a full tunnel.
- `NEDNSSettings.matchDomains` can provide split DNS for named suffixes, but split DNS
  alone does not discover every rotating media IP needed for dynamic host routes.
- Apple explicitly says not to misuse a Packet Tunnel Provider as a general content
  filter, listener, or proxy. Do not hide a Windows-style local DNS listener inside it.
- A separate `NEDNSProxyProvider` is the supported API for taking responsibility for
  system DNS flows, but its entitlement, consumer distribution, coexistence, and
  simultaneous operation with the Packet Tunnel must be proven in a dedicated spike
  before it becomes the product architecture.
- Network Extension capability, signing, provisioning, and a real Developer Team are
  required to run the extension. A successful unsigned unit-test build is not tunnel validation.

Primary references, verified 2026-07-20:

- [NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
- [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic)
- [NEDNSSettings.matchDomains](https://developer.apple.com/documentation/networkextension/nednssettings/matchdomains)
- [DNS proxy provider](https://developer.apple.com/documentation/networkextension/dns-proxy-provider)
- [TN3120: Expected use cases for packet tunnel providers](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)
- [TN3134: Network Extension provider deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)

## WireGuard integration

Use WireGuardKit from the WireGuard project rather than shelling out to a separately
installed WireGuard application. The upstream repository documents Swift Package
integration plus an external build target for `wireguard-go-bridge`.

- Package source: `https://git.zx2c4.com/wireguard-apple`
- Read the current upstream README before pinning a revision.
- Record the pinned revision in the project and this document.
- Add the required `WireGuardGoBridge<PLATFORM>` external build target exactly as
  documented upstream for macOS.
- Link WireGuardKit to both the host app and Packet Tunnel target only where required.
- Preserve the upstream MIT license and notices in distribution.

Reference:

- [WireGuard for Apple platforms and WireGuardKit integration](https://github.com/WireGuard/wireguard-apple)

Do not copy real profiles into the repository to make WireGuardKit compile. Create a
sanitized test fixture whose keys are obviously fake and cannot connect anywhere.

## Routing plan for the first macOS proof

Phase 1 should prove split routing without promising full dynamic DNS parity:

1. Parse and sanitize an imported WireGuard profile.
2. Resolve the WireGuard endpoint before applying tunnel routes.
3. Expand the user rules using the same product semantics as Windows.
4. Pre-resolve the effective domains to IPv4 addresses.
5. Build one `NEIPv4Route` with a `255.255.255.255` mask for each selected address.
6. Apply those routes as `includedRoutes`; do not include a default route.
7. Configure VPN DNS and `matchDomains` only after a real-device spike confirms the
   resolver behavior for root and subdomains.
8. Start WireGuardKit and confirm the VPN endpoint remains reachable outside recursive tunnel routing.
9. Verify a selected test endpoint uses the VPN exit while a control endpoint retains the normal public IP.
10. Stop the tunnel and verify the system removes Network Extension routes and DNS settings.

The first proof may periodically re-resolve expanded domains and reapply network
settings. It must label this as provisional. It does not count as dynamic browser/CDN
coverage until DNS answers observed during real browsing can update the route plan.

## Dynamic DNS discovery spike

Run this as an explicit experiment after the static route proof:

Questions to answer with a signed development build:

1. Can this Developer Team provision both Packet Tunnel and DNS Proxy providers for
   the intended non-MDM consumer distribution?
2. Can both providers run together reliably on the minimum supported macOS version?
3. Does the DNS Proxy receive UDP and TCP DNS flows while the Packet Tunnel is active?
4. Can it forward non-target traffic without breaking system resolver behavior,
   Private Relay expectations, or another local security product? Captive-portal
   discovery, sign-in, and recovery are excluded from the `v0.1.0` scope.
5. Can route updates be sent to the Packet Tunnel and applied without interrupting
   existing connections?
6. What happens when AdGuard, Unicorn Pro, antivirus DNS protection, encrypted DNS,
   or another VPN is enabled before or during the session?

Required safety policy:

- inspect capability and actual behavior, never a hard-coded product/process name;
- never terminate or alter another product;
- if exclusive behavior is required and unavailable, refuse connection before
  changing tunnel state;
- if ownership is lost during a session, stop the VPN through Network Extension and
  return a clear failure reason;
- restore only state owned by VPN Router.

If the DNS Proxy approach cannot meet entitlement or coexistence requirements, stop
and document the evidence. Do not work around Apple policy with an unsupported local
listener inside the Packet Tunnel. Re-scope the macOS MVP to pre-resolved routes or
investigate another Apple-supported provider type with primary-source justification.

## Storage and privacy

Suggested model:

```text
ProfileMetadata
- id
- displayName
- type
- createdAt / updatedAt
- sanitizedConfigurationReference
- endpointSummary

DomainRule
- id
- profileId
- domain
- includeSubdomains
- enabled

Secret
- profileId/privateKey -> Keychain item
```

Rules:

- use `kSecClassGenericPassword` or the WireGuardKit-supported Keychain pattern;
- grant extension access only through the minimum Keychain access group;
- use App Group Application Support for shared sanitized metadata if needed;
- apply file protection and atomic writes where available;
- use `Logger`/OSLog privacy annotations and never interpolate secrets publicly;
- troubleshooting exports must exclude raw configs, private keys, provider tokens,
  browsing history outside matched domains, and full DNS payloads;
- do not read a user profile in Codex/terminal output. Import it through the app.

## UI continuity

Implement the macOS UI natively in SwiftUI. Match the current Windows product
language and dashboard hierarchy, not its XAML implementation:

- light, spacious status-first dashboard;
- coral accent, original VPN Router identity, no copied Unicorn assets;
- compact sidebar with Home, VPN Profiles, VPN Sites, Diagnostics, and Settings;
- large primary connect control and plain-language status;
- profile management, site rules, recovery/diagnostics, and protection behavior remain separate;
- expose technical details only in Diagnostics;
- support keyboard navigation, VoiceOver labels, reduced motion, and macOS window resizing.

The owner prefers the Windows UI direction. Use its status-first hierarchy,
compact navigation, restrained light surfaces, coral accent, and lower technical
density as the cross-platform visual reference. Retain the macOS
Automatic/Light/Dark choice and native accessibility behavior.

Do not build pixel-perfect UI before Packet Tunnel activation works. A plain SwiftUI
shell is enough through Phase 1; visual parity comes after the networking proof.

## Recovery and lifecycle

Network Extension owns tunnel route and DNS lifetime; use that lifecycle rather than
manual `route` or `networksetup` commands.

Required behavior:

- host app derives state from `NEVPNStatus`, not an optimistic local boolean;
- app relaunch reconnects to the existing `NETunnelProviderManager` configuration;
- extension stop removes only VPN Router-owned runtime state;
- extension crash and Mac restart do not leave manual DNS or route mutations behind;
- provider messages and persisted diagnostics have schema versions;
- connection failure reports the exact stage without logging secrets;
- sleep, wake, network change, and endpoint reachability are explicit tests;
- captive-portal discovery, sign-in, and recovery are outside `v0.1.0`; authenticate
  with VPN Router disconnected before connecting it.

Do not add a launch daemon, privileged helper, shell route mutation, or System
Configuration write unless a documented Network Extension limitation requires it and
the user explicitly approves the architecture change.

## Development phases

### Phase 0: environment and entitlement inventory

- [ ] Run `sw_vers`, `uname -m`, `xcodebuild -version`, and `swift --version`.
- [ ] Record Mac model/architecture, installed Xcode, SDK, and candidate deployment target.
- [ ] Confirm the Apple Developer Team ID without committing it.
- [ ] Confirm Packet Tunnel entitlement/provisioning availability.
- [ ] Decide bundle identifiers for app and extension; document examples, not private team data.
- [ ] Confirm `git status` is clean before generating Xcode files.

Exit gate: a minimal signed host app with an embedded Packet Tunnel extension launches
on the development Mac and reaches `startTunnel`/`stopTunnel` with a stub provider.

### Phase 1: WireGuard static split-routing proof

- [ ] Create the macOS directory and Xcode targets.
- [ ] Pin WireGuardKit and build `wireguard-go-bridge`.
- [ ] Add sanitized config parsing tests.
- [ ] Store a fake test secret in Keychain; never import a real key through tests.
- [ ] Configure `NETunnelProviderManager` and start the extension.
- [ ] Apply pre-resolved IPv4 `/32` included routes without a default route.
- [ ] Verify selected and control public-IP endpoints.
- [ ] Verify stop, app relaunch, extension crash, and Mac restart behavior.

Exit gate: selected traffic uses the WireGuard exit, control traffic does not, and
disconnect leaves normal networking healthy.

### Phase 2: rules, media expansion, and route refresh

- [ ] Port domain normalization and media expansion semantics with Swift tests.
- [ ] Add route deduplication, refresh, expiration, and bounded route counts.
- [ ] Reapply tunnel network settings safely when provisional route plans change.
- [ ] Add YouTube and Netflix Japan-exit dogfooding checks.

Exit gate: expanded pre-resolved media endpoints use Japan without converting the Mac
to a full tunnel.

### Phase 3: dynamic DNS discovery decision

- [ ] Complete the DNS Proxy spike above.
- [ ] Record entitlement, coexistence, UDP/TCP, encrypted-DNS, and route-update results.
- [ ] Choose supported dynamic discovery or explicitly ship provisional pre-resolution.

Exit gate: an evidence-backed product decision is committed; no unsupported provider
misuse or third-party service manipulation is present.

### Phase 4: consumer UI and release hardening

- [ ] Implement the SwiftUI navigation and dashboard.
- [ ] Add profile, site, diagnostics, settings, and user-facing conflict guidance.
- [ ] Add unit tests and signed real-Mac integration checklists.
- [ ] Add signing/notarization packaging only after the owner chooses distribution.
- [ ] Document minimum macOS, architecture support, limitations, privacy, and recovery.

## First commands on the Mac

Run read-only inventory before creating files:

```bash
pwd
git status --short --branch
git log --oneline -5
sw_vers
uname -m
xcodebuild -version
swift --version
```

Then read this document and inspect only the sanitized Windows source files named in
the Start here section. Do not run a broad search that prints `.conf` contents.

Before scaffolding, write the discovered environment and proposed bundle identifiers
into a new `docs/macos-mvp-progress.md`. Do not put Team IDs, signing certificates,
provisioning profiles, Apple account information, or Keychain data in that file.

## Definition of the first useful macOS checkpoint

The first useful checkpoint is not a polished window. It is a signed development app
and Packet Tunnel extension that:

1. imports a profile through the UI without exposing its private key;
2. connects through WireGuardKit;
3. routes a finite IPv4 host set through the VPN using included routes;
4. leaves a control destination on the normal network;
5. disconnects without manual DNS or route repair;
6. survives app relaunch and accurately reports tunnel status;
7. has reproducible tests with sanitized fixtures and a written real-Mac result.

Commit that checkpoint before beginning dynamic DNS or visual polish.
