# VPN Router macOS MVP progress

Last updated: 2026-07-21 KST

## Current phase

Phase 1: WireGuard static split-routing proof.

The macOS Xcode project has been generated at `macos/VPNRouter/VPNRouter.xcodeproj`
with a SwiftUI host app and an embedded stub Packet Tunnel extension. The host app
can install a stub `NETunnelProviderManager` configuration, request connect/disconnect,
derive display state from `NEVPNStatus`, and send a provider diagnostics message once
connected. The earlier JetBrains `.idea/` files have been removed from the Git index
and ignored.

## Environment inventory

- Hardware: MacBook Pro (`MacBookPro18,2`), Apple M1 Max, arm64, 10 cores, 64 GB RAM.
- macOS: 26.5.2 (build 25F84).
- Xcode app: 26.6 (build 17F113) at `/Applications/Xcode.app`.
- macOS SDK in Xcode: 26.5.
- Active developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Command Line Tools Swift: Apple Swift 6.3.3, targeting arm64 macOS 26.0.
- Xcode first-launch check: complete.
- Candidate minimum deployment target: macOS 14.0.

The active developer directory now points at Xcode, and an unqualified `xcodebuild`
successfully reports Xcode 26.6.

The macOS 14.0 deployment target is provisional. It keeps the first dogfooding build
focused on currently supported Apple Silicon systems while leaving room to revise
the support range after WireGuardKit integration and signed-device testing.

## Signing and entitlement inventory

- Apple Development or Mac Developer signing identities detected locally: none.
- Developer ID Application signing identity detected locally: present, but this does not confirm development provisioning for a Packet Tunnel extension.
- Xcode account/team configuration detected locally: none.
- Local provisioning profiles detected: none.
- Apple Developer Team ID: not confirmed; no value is recorded in this repository.
- Packet Tunnel entitlement/provisioning: not confirmed.
- The generated Xcode project currently contains local placeholder signing settings.
  Replace them in Xcode before Phase 0 exit; do not treat committed example values
  as approved product identifiers.

Packet Tunnel availability cannot be inferred from SDK presence, compilation, or a
Developer ID distribution certificate. It must be confirmed with the owner's Apple
Developer team by signing and launching an embedded Network Extension on this Mac.

## Proposed identifiers

These are documentation examples, not reserved production identifiers:

- Host app: `com.example.vpnrouter`
- Packet Tunnel extension: `com.example.vpnrouter.PacketTunnel`
- App Group: `group.com.example.vpnrouter.shared`
- Keychain access group suffix: `com.example.vpnrouter.shared`

Before project generation, replace the `com.example` prefix with an owner-approved
reverse-DNS namespace. Keep the host and extension identifiers stable after signing
and provisioning begin.

The Phase 0 host app currently derives the provider bundle identifier as
`<host bundle identifier>.PacketTunnel`. If the owner chooses a different extension
suffix in Xcode, update `TunnelIdentifiers.packetTunnelBundleIdentifier` in
`VPNRouter/ContentView.swift` to match before testing the signed launch.

## Phase 0 checklist

- [x] Run `sw_vers`, `uname -m`, `xcodebuild -version`, and `swift --version`.
- [x] Record Mac model/architecture, installed Xcode, SDK, and candidate deployment target.
- [x] Confirm the Apple Developer Team ID without committing it.
- [x] Confirm Packet Tunnel entitlement/provisioning availability.
- [x] Propose example bundle identifiers without private team data.
- [x] Confirm `git status` is clean before generating Xcode files.
- [x] Generate a minimal SwiftUI host app with an embedded stub Packet Tunnel extension.
- [x] Sign and launch the host app on this Mac.
- [x] Verify the extension reaches both `startTunnel` and `stopTunnel` on this Mac.

Phase 0 signed launch evidence was owner-operated in Xcode on 2026-07-20. The
owner reported that the host app launched, the stub tunnel configuration installed,
connect/disconnect succeeded, and provider diagnostics were reachable. The private
Team ID and owner-specific bundle identifiers are intentionally not recorded here.

## Build verification

Unsigned compile verification succeeds with code signing disabled:

```bash
xcodebuild -project /Users/netmd/project/vpn_router/macos/VPNRouter/VPNRouter.xcodeproj \
  -scheme VPNRouter \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/vpnrouter-xcode-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

This confirms only that the SwiftUI host app and Packet Tunnel extension compile and
embed. The Packet Tunnel extension entitlement file has been narrowed to
`packet-tunnel-provider` only. This does not satisfy the signed Network Extension
launch gate.

Phase 1 parser/rule foundation compile verification also succeeds with code signing
disabled after adding the new Swift files to the `VPNRouter` Host App target:

```bash
xcodebuild -project /Users/netmd/project/vpn_router/macos/VPNRouter/VPNRouter.xcodeproj \
  -scheme VPNRouter \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/vpnrouter-xcode-derived-phase1c \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

A fake-key `RunCodeSnippet` check verified that:

- `DomainRuleExpander` expands a YouTube rule to the expected related media domains;
- `WireGuardConfigParser.prepareImport` parses interface, DNS, peer, allowed IP, endpoint, and keepalive fields;
- sanitized WireGuard text does not contain the fake private key and does contain `<stored securely>`.
- `KeychainSecretStore` can save, load, and delete a fake WireGuard private key using
  a temporary verification service name.
- `ProfileStore` can save, load, upsert, and delete sanitized fake profile metadata
  in the app sandbox temporary directory.
- `ProfileImportService` can parse a fake WireGuard config, save its fake private key
  to Keychain, and persist only sanitized metadata to disk.
- `DomainRoutePlanner` can convert expanded fake domain rules and fake resolved IPv4
  addresses into `/32` route descriptors while excluding unrelated domains.
- `DomainRuleStore` and `DomainRoutePlanService` can persist fake selected domains
  and build a matching `/32` route plan from fake resolved IPv4 addresses.
- `DomainRoutePlanService` can resolve expanded selected domains through an injected
  resolver and build a route plan from the resolved IPv4 addresses.
- `SystemDomainResolver` now matches the Windows pre-resolver behavior: individual
  domain lookup failures produce no IPv4 addresses for that domain instead of
  failing the whole route plan.
- The macOS Sites UI now matches the Windows flow more closely with one-domain
  input, an add button, a saved domain list, and per-domain removal.
- `TunnelProfileConfigurationFactory` can build a safe `NETunnelProviderProtocol`
  provider configuration from fake imported metadata and a fake route plan without
  embedding private key material.
- `WireGuardKit` is linked from the local package, and `libwg-go.a` can be built
  for macOS arm64 into Xcode's Debug products directory using a temporary Go
  toolchain under `/private/tmp`.
- `PacketTunnelProvider` imports `WireGuardKit`, owns a `WireGuardAdapter`, reports
  WireGuardKit linkage through diagnostics, and applies planned IPv4 `/32` routes
  from provider configuration.
- Host app and Packet Tunnel entitlements now use the same Keychain access group
  and App Group. `KeychainSecretStore` stores private keys in the entitlement's
  shared access group when available.
- `PacketTunnelProvider` can rebuild a WireGuardKit `TunnelConfiguration` from
  sanitized provider configuration plus the shared Keychain private key, replace
  peer AllowedIPs with the selected `/32` route plan, and call
  `WireGuardAdapter.start`.
- The host app no longer passes a `phase0-stub` start option on every connect;
  PacketTunnel now uses the installed provider configuration mode, so an installed
  Phase 1 profile can start through the WireGuardKit path.
- The host app now prefers Phase 1 `NETunnelProviderManager` configurations when
  multiple `VPN Router` configurations exist, and reconnect installs the selected
  profile automatically if the current manager is still a Phase 0 stub.
- A signed run reached the WireGuardKit start path, but failed because the installed
  provider configuration contained zero selected routes. The visible
  `networkd_settings_read_from_file_locked` sandbox message was not the primary
  failure signal; the PacketTunnel log reported an empty route plan.
- The host app now rejects install/connect when the selected profile has no
  resolvable IPv4 routes, and Connect refreshes the selected profile's
  `NETunnelProviderManager` payload immediately before starting so the provider
  receives the current route plan.
- A signed app run then showed all selected domains unresolved in the host app.
  Host app and PacketTunnel entitlements now include outbound network client
  permission so sandboxed DNS lookup and WireGuard UDP traffic are not blocked by
  the app sandbox. Long status/diagnostic messages are now scrollable and
  selectable in the SwiftUI UI.
- The next signed check reported provider diagnostics with 26 routes, but system
  inspection showed the VPN service disconnected and PacketTunnel logs reported
  `WireGuardKit: Unable to update bind: listen udp4 :0: bind: operation not permitted`.
  PacketTunnel now also has the sandbox network server entitlement for UDP bind,
  and provider diagnostics now return the latest WireGuardKit runtime message
  instead of only reporting that WireGuardKit is linked.
- A follow-up signed run reported `WireGuardKit: Routine: receive incoming v4 -
  started`. System logs show `utun7` DNS and IPv4 settings applied, VPN Router
  status changed to connected, and the selected `/32` IPv4 routes appeared on
  `utun7`. A later stop/uninstall command removed `utun7` IPv4, DNS, and routes,
  confirming disconnect cleanup for this run.
- A later signed split-route check confirmed selected traffic routing: `route -n
  get 172.217.209.136` resolved to `utun7` through a `/32` route, while `route -n
  get 1.1.1.1` stayed on the normal `en6` default gateway.
- The macOS profile list now supports deletion. Deleting a profile removes profile
  metadata and its Keychain private key. Shared VPN Sites are deliberately kept
  separate from profiles, so deleting or replacing a VPN profile does not discard
  the user's site list. If the deleted profile is currently installed in
  `NETunnelProviderManager`, the app stops that tunnel if needed and removes the
  stale manager configuration.
- VPN Sites are now stored in a shared rule bucket instead of under the selected
  profile ID. Existing profile-scoped site rules are migrated into the shared list
  when the Sites view loads and no shared list exists yet.
- Phase 1 split-route now leaves imported WireGuard DNS servers out of the active
  tunnel configuration. The MVP uses pre-resolved `/32` routes, so installing
  tunnel DNS globally can break unrelated DNS queries or conflict with tools such
  as AdGuard while the routed site IPs still use the tunnel.
- A signed split-route run after the DNS change kept `utun7` alive with selected
  `/32` routes. The selected WireGuard endpoint `45.63.126.216` geolocated to JP
  and remained routed through the normal `en6` gateway, while a selected YouTube
  address (`172.217.209.136`) routed through `utun7`. A forced HTTPS request to
  `www.youtube.com` resolved to that routed IP returned `HTTP/2 200`, confirming
  selected traffic can pass through the tunnel.

No real WireGuard `.conf` or private key was read, printed, or stored during this
verification.

## Phase 1 progress

- [x] Add Swift domain rule model and media-domain expansion semantics for YouTube and Netflix.
- [x] Add Swift WireGuard config models, parser, sanitizer, import result, and summary.
- [x] Verify parser and expansion behavior with sanitized fake data.
- [x] Store imported private keys in Keychain.
- [x] Store sanitized profile metadata on disk.
- [x] Add a profile import service that separates Keychain secrets from stored metadata.
- [x] Connect file-based WireGuard import UI with sanitized metadata storage.
- [x] Store selected domain rules on disk.
- [x] Resolve selected domains before tunnel route application.
- [x] Build static IPv4 `/32` included-route plans from selected domains.
- [x] Build `NETunnelProviderManager` configurations from imported profile metadata.
- [x] Pin WireGuardKit and build `wireguard-go-bridge`.
- [x] Connect parsed configuration to WireGuardKit and the Packet Tunnel provider.
- [x] Keep profile deletion separate from the shared VPN Sites list.
- [x] Avoid installing WireGuard profile DNS globally in Phase 1 split-route mode.

## Expected work list

### Phase 1: WireGuard static split-routing proof

1. Add Keychain storage for imported WireGuard private keys.
2. Add sanitized profile metadata storage.
3. Connect file-based WireGuard import UI with sanitized metadata storage.
4. Add profile deletion that removes profile metadata and Keychain secrets without
   deleting the shared VPN Sites list.
5. Pin WireGuardKit.
6. Add the macOS `wireguard-go-bridge` build target required by WireGuardKit.
7. Link WireGuardKit where required.
8. Build `NETunnelProviderManager` configurations from imported profile metadata.
9. Load parsed tunnel configuration in the Packet Tunnel provider without logging secrets.
10. Connect WireGuardKit adapter start/stop to the Packet Tunnel lifecycle.
11. Resolve selected domains before tunnel route application.
12. Build IPv4 `/32` included-route plans.
13. Apply `NEPacketTunnelNetworkSettings.ipv4Settings.includedRoutes`.
14. Keep the VPN endpoint outside recursive tunnel routing.
15. Verify selected test traffic uses the VPN exit and control traffic keeps the normal route.
16. Verify disconnect removes Network Extension-owned route and DNS state.
17. Verify app relaunch resynchronizes from `NEVPNStatus`.

### Phase 2: rules, media expansion, and refresh

1. Add domain normalization tests.
2. Add YouTube and Netflix expansion tests.
3. Deduplicate DNS resolution results.
4. Add route count limits.
5. Add route TTL and refresh policy.
6. Reapply tunnel settings safely as route plans change.
7. Detect or clearly report IPv6 bypass risk.
8. Record YouTube and Netflix Japan-exit dogfooding checks.

### Phase 3: DNS discovery decision

1. Confirm DNS Proxy entitlement availability.
2. Spike Packet Tunnel and DNS Proxy simultaneous operation.
3. Verify UDP and TCP DNS flow visibility.
4. Test coexistence with AdGuard, security DNS, and another VPN without altering them.
5. Verify dynamic route updates can be sent to the Packet Tunnel safely.
6. If the DNS Proxy approach fails, explicitly scope the MVP to pre-resolved routes.

### Phase 4: UI and release hardening

1. Implement real navigation for Home, VPN Profiles, VPN Sites, Diagnostics, and Settings.
2. Build profile import, rename, select, and delete workflows.
3. Build site rule management.
4. Build diagnostics and recovery views.
5. Build settings for safety behavior and limitations.
6. Write user-facing conflict and error messages.
7. Add troubleshooting export with secret redaction.
8. Add signed real-Mac integration checklists.
9. Document minimum macOS, architecture support, privacy, limitations, and recovery.
10. Add packaging and notarization only after the owner chooses distribution.

## Phase 0 resolved blockers

1. The owner selected an approved Team in Xcode without committing the Team ID.
2. The owner replaced the generated `com.simple...` identifiers with approved
   reverse-DNS identifiers in Xcode.
3. The Host App target has the Network Extensions capability connected, and the
   Packet Tunnel extension remains embedded in the host app.

## Owner Xcode setup used for signed launch

Perform these in Xcode rather than editing `project.pbxproj` by hand while the
project is open:

1. Select the `VPNRouter` project, then the `VPNRouter` Host App target.
2. In Signing & Capabilities, select the owner-approved Team.
3. Replace the Host App bundle identifier with the owner-approved reverse-DNS value,
   for example `com.owner.vpnrouter`.
4. Add the Network Extensions capability and enable Packet Tunnel.
5. Select the `PacketTunnel` target, use the same Team, and set its bundle identifier
   to the host identifier plus `.PacketTunnel`, for example
   `com.owner.vpnrouter.PacketTunnel`.
6. Confirm both App IDs can provision the Network Extensions entitlement, then build
   and launch from Xcode on the development Mac.

## Phase 0 exit evidence required

The phase is complete only after a signed development build provides real-Mac
evidence that:

1. the host app launches with the Packet Tunnel extension embedded;
2. `NETunnelProviderManager` installs and starts the configuration;
3. the stub provider records entry into `startTunnel`;
4. disconnect records entry into `stopTunnel`; and
5. the status shown by the host app is derived from `NEVPNStatus`.

Compilation alone does not satisfy this gate.
