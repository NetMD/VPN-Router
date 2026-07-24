# VPN Router macOS MVP progress

Last updated: 2026-07-25 KST

## Current phase

Phase 4 complete for signed private dogfooding: consumer UI and release hardening.

The signed DNS Proxy spike proved native UDP/TCP forwarding, XPC observations,
simultaneous Packet Tunnel operation, TTL-bounded dynamic IPv4 route updates, and
clean teardown on this development Mac. The macOS MVP nevertheless keeps static
pre-resolution as its default supported architecture because encrypted DNS,
actually connected second-VPN coexistence, continuous ownership monitoring,
Developer ID distribution provisioning, and IPv6 routing remain unverified.

The Phase 4 technical baseline and remediation audit are recorded in
`docs/macos-phase4-quality-audit.md`. The initial score was 12/20 with no P0
blockers and five P1 findings. The automated remediation pass raises it to 17/20;
the completed signed remediation and acceptance pass raises it to 18/20. Public
distribution still requires a clean Release optimizer result without the
documented Xcode 26.6 workaround.

The automated Phase 4 implementation and owner-operated signed UI/lifecycle
matrix are complete. Public Developer ID distribution remains intentionally
blocked; `0.1.0` is approved only as a signed private Apple Silicon dogfood build.
The connected-status VoiceOver announcement was owner-skipped and remains
explicitly unverified.

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
- Supported dogfood deployment target: macOS 15.0.

The active developer directory now points at Xcode, and an unqualified `xcodebuild`
successfully reports Xcode 26.6.

The Phase 4 private-dogfood baseline is macOS 15.0 on Apple Silicon. The release
verification script overrides older local project defaults without modifying or
committing the owner's signing settings.

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
- A Swift Package test harness now compiles the app's actual shared rule and route
  planner sources. The initial focused tests cover domain normalization, YouTube and
  Netflix expansion, disabled rules, IPv4 validation, subdomain matching, route
  deduplication, and route-count enforcement. `swift test` passes all eight tests.
- Static route plans now deduplicate by destination IPv4 address rather than by
  address/domain pair. If multiple selected CDN domains resolve to the same address,
  Network Extension receives one `/32` route with a deterministic source-domain
  label. Plans exceeding 512 unique IPv4 routes fail before tunnel installation.
- The unsigned Xcode build succeeds after preparing `libwg-go.a` in the selected
  temporary DerivedData products directory. A fresh DerivedData directory still
  requires the existing WireGuard Go bridge preparation step before linking.
- Static route plans now carry generation and expiration timestamps. The provisional
  Phase 2 policy refreshes after five minutes and expires a plan after fifteen
  minutes. Previously installed payloads without timestamps receive a bounded
  fifteen-minute lifetime when the provider loads them.
- While connected, the host app rebuilds the pre-resolved route plan every five
  minutes and sends a schema-versioned `replace-routes` provider message containing
  only the profile id and route plan. It does not send sanitized configuration text
  or Keychain material in the live-update message. A manual **Refresh Routes** action
  uses the same path.
- PacketTunnel validates the active profile, non-empty `/32` routes, uniqueness,
  expiry, and the 512-route limit before calling `WireGuardAdapter.update`. A failed
  update retains the previous bounded plan. A successful update replaces the
  WireGuard AllowedIPs and Network Extension settings and resets the provider-owned
  expiration timer. If no refresh succeeds before expiry, the provider requests
  tunnel cancellation instead of allowing an indefinitely stale split-route plan.
- A signed real-Mac run verified live route replacement. A manual update at
  01:09:08 KST and the next automatic five-minute update at 01:14:19 KST each
  entered `reasserting` briefly and returned to Connected without replacing
  `utun7`. After the automatic update, 25 selected `/32` routes remained on
  `utun7`, the control address and WireGuard endpoint remained on `en6`, and a
  forced YouTube request returned HTTP/2 200. Expiry cancellation remains an
  intentionally disruptive signed test and has not yet been run.
- Route planning now checks selected and media-expanded domains for usable AAAA
  answers without recording the IPv6 addresses themselves. Matching domains are
  carried as an IPv6 bypass-risk list in the versioned plan. Home, VPN Sites,
  connect/refresh status, and provider diagnostics clearly warn that the current
  IPv4-only MVP cannot route those IPv6 connections.
- `swift test` now passes thirteen focused tests, including deterministic lifetime,
  refresh/expiration boundaries, and backward-compatible decoding of older route
  plans plus IPv6 bypass-domain filtering. The unsigned Xcode host/extension build
  also succeeds. The new IPv6 warning UI still needs inspection in a signed build.
- Settings now provides **경로 계획 만료 시 자동으로 연결 해제**. The value is
  shared with PacketTunnel through App Group `UserDefaults`, defaults to enabled,
  and updates the active provider immediately through a schema-versioned message.
  Disabling it requires a destructive-style confirmation that explains stale routes
  may allow selected sites to bypass the VPN. Home also keeps an orange warning
  visible while the protection is disabled.
- The SwiftUI navigation, forms, buttons, empty states, confirmation dialogs, status
  messages, route summaries, diagnostics, and user-facing parser/runtime errors are
  now written in Korean. Protocol names such as WireGuard and Packet Tunnel, IP
  terminology, domain names, and internal configuration keys retain their technical
  names where translation would reduce clarity.
- Two focused settings tests verify that fail-safe protection defaults to enabled and
  persists both enabled and disabled values. `swift test` now passes fifteen tests,
  and the unsigned Xcode host/extension build succeeds.
- A signed real-Mac expiry test paused only the host app after a manual route refresh,
  leaving PacketTunnel connected without its five-minute refresh source. With the
  fail-safe at its default enabled value, the VPN changed from Connected to
  Disconnected at the fifteen-minute plan boundary. The selected `utun` routes were
  removed, and resuming the host app did not silently reconnect the expired tunnel.
- A connected-app lifecycle check confirmed that quitting the SwiftUI host leaves the
  Packet Tunnel connected, and reopening the signed app starts one host instance and
  resynchronizes to Connected. Terminating the PacketTunnel process changed the VPN
  to Disconnected within about five seconds and removed the selected routes; a normal
  reconnect launched a new extension process and restored the selected routes.
- Streaming dogfooding is only partially successful. Forcing `www.youtube.com` to a
  currently routed YouTube IPv4 address returned HTTP/2 200 and YouTube context
  country `JP`, confirming that selected traffic can use the Japanese exit. However,
  fresh `www.youtube.com` and `www.netflix.com` answers, and later rotating root-domain
  answers, were not always present in the static route plan and therefore used the
  normal `en6` route. The current pre-resolution expansion must cover the concrete
  `www` hosts and address DNS answer rotation before the combined YouTube/Netflix
  Japan-exit acceptance item can pass.

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

## Phase 2 progress

- [x] Add domain normalization tests.
- [x] Add YouTube and Netflix expansion tests.
- [x] Deduplicate resolved routes by destination IPv4 address.
- [x] Reject route plans above a bounded 512-route safety limit.
- [x] Add a five-minute refresh and fifteen-minute route-plan TTL policy.
- [x] Implement schema-versioned live route replacement through `WireGuardAdapter.update`.
- [x] Verify live route replacement on a signed real-Mac build.
- [x] Verify expiry cancellation on a signed real-Mac build.
- [x] Detect AAAA answers and clearly report IPv6 bypass risk.
- [x] Record YouTube and Netflix Japan-exit dogfooding checks (partial failure: static DNS answer coverage).

## Phase 3 progress

- [x] Recheck current Apple deployment and entitlement requirements using primary
  documentation.
- [x] Confirm that a macOS DNS Proxy must be packaged as a separate system extension,
  not added to the Packet Tunnel app-extension target.
- [x] Add a read-only signed-build probe that loads DNS Proxy preferences without
  saving, removing, or enabling a configuration.
- [x] Document the provisioning, activation, forwarding, privacy, coexistence, and
  fail-safe checkpoints in `docs/macos-phase3-dns-proxy-spike.md`.
- [x] Verify the Phase 3 probe with an unsigned host/extension build and rerun all
  fifteen focused tests.
- [x] Run signed checkpoint A. The host could read DNS Proxy preferences, a VPN
  Router configuration existed, and it was not enabled.
- [x] Add a separate minimal DNS Proxy system-extension target and embed it at
  `Contents/Library/SystemExtensions` using a bundle-matching filename.
- [x] Add an explicit diagnostic activation request. It does not save or enable the
  DNS Proxy configuration, and the checkpoint-B provider rejects unexpected flows.
- [x] Diagnose the first signed checkpoint-B activation failure. NetworkExtension
  category validation rejected an `NEMachServiceName` that was not prefixed by the
  extension's App Group; the system automatically removed the invalid staged copy.
- [x] Align `NEMachServiceName` with the shared App Group while keeping DNS Proxy
  configuration disabled.
- [x] Confirm development provisioning for the separate DNS Proxy system-extension
  target.
- [x] Activate the minimal system extension in a signed build without accepting DNS
  flows. macOS reported `activated enabled`, while the DNS Proxy configuration
  remained disabled.
- [x] Implement a bounded UDP and TCP forwarding candidate using Network.framework,
  preserving DNS payloads and applying flow metadata to forwarded connections.
- [x] Add defensive DNS response parsing tests for target matching, A records,
  CNAME TTL propagation, truncation, and compression-pointer loops.
- [x] Publish only the normalized, expanded saved target-domain set to the shared
  App Group and retain only bounded target address/TTL observations.
- [x] Add an explicit diagnostic enable action, an immediate-disable recovery
  action, and ownership checks that refuse to modify another provider's DNS Proxy
  configuration.
- [x] Add aggregate observation diagnostics that report counts and timestamps
  without displaying retained domains or addresses.
- [x] Run the first explicit signed UDP forwarding attempt. The DNS Proxy
  configuration activated, but the first UDP query received no response; the
  configuration was immediately disabled and normal DNS recovered.
- [x] Add privacy-preserving runtime counters for provider start/stop, accepted
  flow type, flow open, upstream readiness, response delivery, and error
  domain/code before retrying.
- [x] Verify one signed UDP query reaches its upstream resolver and returns a DNS
  response while the diagnostic configuration is enabled, then disable the
  configuration and confirm normal DNS recovery.
- [x] Diagnose why the host app could not read provider runtime observations even
  though both signed targets had the same App Group entitlement. The DNS Proxy
  provider runs as `root`, while the host app runs as the logged-in user, so an App
  Group `UserDefaults` file is not a suitable live IPC channel for this provider.
- [x] Replace the diagnostic App Group file exchange with the provider's
  `NEMachServiceName` XPC service. The provider now retains only bounded in-memory
  target and aggregate observation data; the host sends targets and fetches a
  schema-versioned snapshot over privileged Mach-service XPC with retry and timeout.
- [x] Verify the new XPC diagnostic channel in signed build 4 on a real Mac. The
  host successfully sent the expanded target-domain set, and a snapshot reported
  28 active and 4 expired target IPv4 observations without displaying retained
  domain or address values.
- [x] Repeat signed UDP forwarding with the XPC diagnostic channel. Runtime
  diagnostics reported provider start 1, UDP flows accepted/opened/upstream-ready
  64, responses received/delivered 63, and forwarding failures 0. A controlled
  `youtube.com` A query returned four answers through the system resolver.
- [x] Make the Diagnostics detail vertically scrollable and reflow its DNS Proxy
  controls vertically when the available width cannot fit the horizontal row.
- [x] Verify the Diagnostics scrolling change in signed build 5. The owner confirmed
  that the detail scrolls vertically and the bottom status message remains
  reachable. The current 720-point minimum detail width prevents shrinking the
  window far enough to exercise the vertical control fallback.
- [x] Verify TCP forwarding on a signed real-Mac run. One controlled
  `youtube.com` TCP A query returned four answers; runtime diagnostics reported
  TCP flows accepted 1, total flows opened/upstream-ready/responses
  received/delivered 15, and forwarding failures 0.
- [x] Verify Packet Tunnel and DNS Proxy simultaneous operation on a signed real
  Mac. With the Packet Tunnel connected, 33 selected IPv4 routes remained on its
  `utun` interface and the control address remained on the normal `en6` interface
  while one UDP and one TCP DNS query each returned four answers. The Packet Tunnel
  stayed connected, and DNS Proxy diagnostics reported 15 responses delivered,
  including one accepted TCP flow, with zero forwarding failures.
- [x] Verify ordered teardown after the simultaneous-provider run. Disabling only
  the DNS Proxy left the Packet Tunnel connected with all 33 selected routes and
  normal DNS available. Disconnecting the Packet Tunnel then stopped its provider,
  removed all routes from that `utun` interface, and left normal DNS healthy.
- [x] Add an explicit diagnostic route-update candidate that merges active DNS
  observations into the installed static route plan, deduplicates by IPv4 address,
  rejects invalid observations without displaying their value, enforces the
  combined 512-route limit, and bounds the plan by the earliest usable observation
  TTL. It reuses the existing schema-versioned Packet Tunnel `replace-routes`
  message and is not an automatic background refresh loop.
- [x] Confirm the dynamic-plan fail-safe behavior during the first signed update
  attempt. The Packet Tunnel accepted 17 new observed routes and reported 48 total,
  but the earliest observation TTL was too close for manual inspection and the
  expiration timer disconnected the tunnel before the route table was sampled.
  The `utun` routes were removed and normal DNS remained healthy.
- [x] Repeat the signed update with at least 60 seconds of remaining TTL. Queries
  for six known media subdomains produced addresses that were not in the static
  pre-resolution plan. The Packet Tunnel accepted 22 new observed routes and
  reported 49 total; the system `utun` route count increased from 29 to 52 while
  the tunnel stayed connected, the control address stayed on `en6`, and DNS
  remained healthy.
- [x] Add a diagnostic-only 15-second refresh loop that runs only while both the
  Packet Tunnel and explicitly enabled DNS Proxy are active. It reapplies the
  bounded active observation set, returns to the static plan after observations
  expire, and leaves the Packet Tunnel's earliest-TTL expiration fail-safe in
  control if the host or XPC refresh path stops.
- [x] Run the first signed automatic-refresh attempt. The loop added the observed
  routes without a button press, increasing the system route count from 29 to 54,
  but a later identical refresh overlapped the Packet Tunnel's reasserting state
  and left the VPN reconnecting. Testing stopped and both providers were manually
  disabled.
- [x] Repeat signed automatic refresh after skipping identical plans and requiring
  the live `NETunnelProviderSession` to be connected before every update. Over
  approximately 85 seconds, the VPN remained connected while the system route
  count changed from the static 29 to between 40 and 60 as observations appeared
  and expired. No second reconnecting state occurred.
- [x] Add explicit DNS Proxy shutdown cleanup. When the user disables the diagnostic
  proxy while Packet Tunnel is connected, the host now rebuilds and reapplies a
  fresh static plan. If that restoration fails, it stops only the VPN Router Packet
  Tunnel instead of leaving dynamic routes active until their TTL fail-safe.
- [x] Verify signed DNS Proxy shutdown returns the connected Packet Tunnel to a
  freshly resolved static plan without disconnecting. In build 10, disabling the
  proxy while the tunnel was connected reduced the system `utun` route count from
  74 to 31, kept the VPN connected, kept the control address on `en6`, and left DNS
  healthy.
- [x] Verify baseline coexistence without altering third-party products. Two
  non-VPN Router system extensions remained activated while DNS Proxy UDP/TCP,
  Packet Tunnel simultaneous operation, dynamic route updates, and cleanup passed.
- [x] Record encrypted DNS, Private Relay, captive portal, and actually connected
  second-VPN tests as unverified release blockers rather than changing those
  products automatically.
- [x] Choose the Phase 3 product direction: keep bounded static pre-resolution as
  the supported macOS MVP path and retain DNS Proxy as an explicit development
  diagnostic until the remaining distribution, ownership, coexistence, lifecycle,
  minimum-version, and IPv6 blockers are resolved.
- [x] Add a five-second host-to-Packet-Tunnel provider-message timeout so dynamic
  refresh or static restoration cannot wait indefinitely. Signed build 11 returned
  normal provider diagnostics through the guarded path with 27 applied routes,
  fail-safe enabled, and seven IPv6 bypass-risk domains reported.

## Phase 4 progress

- [x] Record a scored technical audit with P0-P3 priorities.
- [x] Move profile, Keychain, rule persistence, DNS resolution, and route planning
  work away from the SwiftUI main execution path.
- [x] Add one-operation-at-a-time state, disabled conflicting controls, visible
  progress, and VoiceOver progress labels.
- [x] Hide the Phase 0 stub and DNS Proxy spike behind a Debug-only developer
  option.
- [x] Reduce the detail minimum width from 720 to 440 points.
- [x] Reflow Profiles, Sites, tunnel controls, and action groups between horizontal
  and vertical layouts using content-driven `ViewThatFits`.
- [x] Give each detail page one vertical scroll owner and remove nested message and
  route-list scroll views.
- [x] Add target-specific delete labels, focusable profile selection, form hints,
  keyboard shortcuts, and VPN status VoiceOver announcements.
- [x] Add a schema-versioned troubleshooting export containing only bounded status,
  counts, and timestamps. It has no fields for raw configuration, keys, domains,
  addresses, DNS payloads, or free-form provider logs.
- [x] Add disconnected-only removal of VPN Router-owned system preferences with
  bundle-identifier ownership checks.
- [x] Add read-only network path and sleep/wake diagnostics. Wake reloads
  `NEVPNStatus`; no third-party or manual route state is changed.
- [x] Add an accessible coral accent and a complete original 16-1024 pixel macOS
  app icon set.
- [x] Add an arm64/macOS 15 `0.1.0 (1)` release-verification script, privacy and
  recovery README, distribution decision, notarization gate, and signed test
  matrix.
- [x] Verify the unsigned Release app, embedded Packet Tunnel, explicit version,
  minimum OS override, and WireGuard Go archive checksum.
- [x] Inspect compact/wide behavior in the final signed build. The owner confirmed
  horizontal/vertical reflow, no clipping or overlap, full-page scrolling, visible
  bottom status messages, and no trapped nested list scrolling on 2026-07-24.
- [x] Inspect offline keyboard and VoiceOver behavior in the final signed build.
  The owner confirmed the import shortcut, forward/reverse focus order, named
  profile and site controls, selection state, and meaningful primary-button
  descriptions on 2026-07-24. The owner chose to skip the connected-status
  VoiceOver announcement check, so that item remains explicitly unverified.
- [x] Inspect dark/high-contrast behavior in the final signed build. The owner
  confirmed legible text, controls, selection, accent, warnings, disabled states,
  and compact content with increased contrast on 2026-07-24.
- [x] Add a persisted per-app screen-theme choice in Settings. Automatic follows
  the current macOS appearance; Light and Dark override only VPN Router.
- [x] Verify the per-app theme selector in the signed owner build. All three
  choices applied immediately, Dark persisted across relaunch, and Automatic
  followed the current macOS appearance on 2026-07-24.
- [x] Run signed sleep/wake and network-change checks while connected.
  Sleep/wake passed on 2026-07-25: both counters incremented, the Packet Tunnel
  remained healthy with a future route-plan expiry, primary and `utun` routes
  remained correctly separated, and selected/control sites worked. USB LAN path
  transition also passed: the read-only counter advanced, 31 static routes were
  refreshed, the tunnel stayed healthy, the default route returned to USB LAN,
  and selected/control sites continued working.
- [x] Save and inspect a redacted troubleshooting file from the signed UI.
  The first attempt hit `EXC_BREAKPOINT` while constructing a direct
  `NSSavePanel`. That modal AppKit path has been replaced with SwiftUI
  `fileExporter`. The next attempt exposed a missing user-selected file write
  entitlement; the Host App now has read/write access only for files selected
  through the system panel. The final signed retry saved valid schema-versioned
  JSON; owner inspection confirmed bounded status/count fields and no
  configuration, key, domain, IP, DNS payload, or free-form log on 2026-07-24.
- [x] Restore the arm64 Debug `libwg-go.a` after the signed-test Clean Build Folder
  action removed the manually prepared WireGuard Go bridge product. This is the
  known upstream Swift package integration limitation; another clean requires
  rebuilding the bridge before Packet Tunnel can link.
- [x] Re-test owned configuration removal while disconnected. The signed recovery
  action removed the only VPN Router system preference and left zero connected
  services and no routes on the previous `utun`, while preserving one imported
  profile and three selected sites. After reinstalling from the preserved profile,
  the owner also confirmed removal was disabled while connected and enabled after
  disconnect.
- [x] Re-run connect, selected/control routing, disconnect, relaunch, and extension
  termination checks for the final signed build.
  Signed connect and split-routing passed on 2026-07-24: 31 app routes were
  applied, the system default route remained on the primary interface, VPN routes
  were present on one `utun`, and both selected and control sites loaded. The
  Host quit/relaunch also passed: the tunnel and routes survived without the Host
  App, and relaunch resynchronized to connected without another connect request.
  Sleep/wake, network transition, and final-build extension termination also
  passed. Force-terminating only Packet Tunnel changed the app to disconnected,
  removed all routes from its previous `utun`, preserved the primary default
  route, and left ordinary internet access working. Disconnected owned
  configuration removal and the final normal disconnect also passed. After normal
  disconnect, the preference remained installed while the connection, provider
  process, and VPN `utun` routes were gone.
- [x] Decide/fix findings from the signed matrix, re-run the final audit at 18/20,
  pass 35 core tests and Xcode Analyze, and verify the unsigned arm64/macOS 15
  `0.1.0 (1)` Release package.

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
