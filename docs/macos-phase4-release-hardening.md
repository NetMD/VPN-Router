# macOS Phase 4 release hardening

Last updated: 2026-07-24 KST

## Distribution decision

The first macOS `0.1.0` remains a **signed private dogfood build**, not a public
Developer ID release. Packet Tunnel operation is proven with the owner's signed
development build, but Developer ID provisioning, notarization, a clean-machine
install, and the development-only DNS Proxy system extension's distribution
behavior are not yet proven.

The supported dogfood baseline is Apple Silicon and macOS 15 or later. Release
verification overrides local Xcode values with product version `0.1.0`, build
number `1`, and deployment target `15.0`; this avoids committing the owner's
private signing settings from `project.pbxproj`.

## Automated release verification

`scripts/macos/verify-release.sh`:

1. verifies required Xcode, Go, and packaging tools;
2. builds `libwg-go.a` for arm64;
3. builds an unsigned Release app with explicit version and deployment target;
4. checks the app version and embedded Packet Tunnel;
5. prints the WireGuard Go archive SHA-256.

The unsigned output is not a distributable VPN app. It is compile and packaging
evidence only.

Xcode 26.6 / Swift 6.3.3 currently crashes in the SIL performance inliner when
emitting the optimized host module. Incremental compilation alone and `-Osize`
both reproduce the crash. The verification script keeps Release `-O` compilation
but disables the crashing SIL performance-optimization pass with
`-disable-sil-perf-optzns`. This is an explicit toolchain workaround, not a clean
optimizer result. Remove the override and retry whenever Xcode is upgraded; public
release remains gated on a clean final Release archive.

## WireGuard archive warning disposition

Xcode Analyze succeeds but the current Go `c-archive` can produce a linker warning
about a malformed `LC_DYSYMTAB` in `libwg-go.a`. The archive links and the signed
Packet Tunnel has run on this development Mac, but the warning is not silently
accepted for public release.

Public distribution remains blocked until one of these is true:

- the pinned WireGuard/Go toolchain produces an archive without the warning; or
- the archive is validated by the final Xcode linker, Developer ID signing,
  notarization, Gatekeeper assessment, and a clean-machine signed runtime test,
  with the toolchain versions recorded.

## Signed owner-operated matrix

Do not run these checks with an unsigned build.

| Test | Expected result | Status |
|---|---|---|
| Compact and wide window | Every page scrolls; Profiles and Sites change between one and two columns | Passed in signed owner build, 2026-07-24 |
| Keyboard and VoiceOver | Named delete controls, focusable profile selection, shortcuts, and VPN status announcements work | Offline controls passed in signed owner build, 2026-07-24; owner skipped connected-status announcement |
| Connect and disconnect | Selected routes use Packet Tunnel; control traffic stays on the primary interface; disconnect cleans up | Passed in signed owner build, 2026-07-25 |
| Sleep and wake while connected | App records both events, reloads system VPN state, and does not change third-party products | Passed in signed owner build, 2026-07-25 |
| Network path change | Read-only counter changes; no automatic third-party or manual route mutation occurs | Passed in signed owner build, 2026-07-25 |
| App quit and relaunch | Packet Tunnel stays connected when appropriate and the app resynchronizes from `NEVPNStatus` | Passed in signed owner build, 2026-07-24 |
| Extension termination | VPN disconnects and Network Extension-owned routes disappear | Passed in final signed owner build, 2026-07-25 |
| Redacted export | JSON contains status/counts only and no config, key, domain, IP, DNS payload, or free-form tunnel log | Passed in signed owner build, 2026-07-24 |
| Owned configuration removal | Refuses while connected and removes only the matching VPN Router bundle identifier | Passed in signed owner build, 2026-07-25 |
| Dark/high-contrast appearance | Coral accent, warnings, selection, and disabled controls remain legible without color-only meaning | Passed in signed owner build, 2026-07-24 |
| Per-app screen theme | Automatic, Light, and Dark apply immediately and persist without changing macOS appearance | Passed in signed owner build, 2026-07-24 |

The first signed redacted-export attempt stopped at `NSSavePanel()` with
`EXC_BREAKPOINT`. The direct AppKit modal panel path was removed and replaced by
SwiftUI `fileExporter`, which owns the save-panel lifecycle and sandbox-selected
destination. The replacement compiles and the automated redaction tests pass; its
signed UI retry then identified that the Host App allowed user-selected file reads
but not writes. The Host App now explicitly grants
`com.apple.security.files.user-selected.read-write`, scoped to files the user
chooses through the system panel. The entitlement file validates and the app
builds; the signed UI retry remains pending.

Cleaning the owner's Xcode build folder also removed the manually prepared
WireGuard Go bridge archive, causing Packet Tunnel linking to fail with
`Library 'wg-go' not found`. The arm64 Debug archive was rebuilt in that Xcode
DerivedData products directory and validated before the signed retry.

The final retry saved and decoded the JSON successfully. Owner inspection
confirmed schema version, app/system state, bounded connection/routing/storage/
protection/lifecycle fields, and no configuration text, private key, domain, IP,
DNS payload, or free-form provider log.

The final signed connection applied 31 selected routes, reported a healthy
WireGuardKit peer keepalive, a future plan expiry, seven explicit IPv6-risk
domains, and enabled expiry disconnect. Read-only route inspection kept the
default route on the primary interface and found the VPN routes on one `utun`;
both a selected site and a control site loaded normally. Disconnect cleanup
remains pending.

The owner then quit only the Host App while connected. Read-only inspection found
no Host App process, one connected VPN Router service, the default route still on
the primary interface, and the Packet Tunnel routes still on the same `utun`.
Relaunch automatically displayed the connected state without another connect
request, and the same system connection and routes remained active.

With the tunnel connected, one sleep/wake cycle incremented both lifecycle
counters, kept the VPN connected, returned a normal Packet Tunnel response with
27 app routes and a future expiry, retained the default route on the primary
interface and VPN routes on the same `utun`, and left selected and control sites
working.

The owner then disconnected and reconnected the active USB LAN while Wi-Fi
provided path transition coverage. The read-only network-change counter advanced,
the host rebuilt 31 static routes, the Packet Tunnel remained connected with a
healthy keepalive and future expiry, the default route returned to the USB LAN,
VPN routes remained on the same `utun`, and selected/control sites worked.

The owner force-terminated only the final-build Packet Tunnel process. The Host
App resynchronized to disconnected, the VPN Router system connection count became
zero, every route on its previous `utun` disappeared, the default route remained
on the USB LAN, and ordinary internet access continued. A selected site that
requires the VPN was unavailable while disconnected, as expected for that network.

The disconnected owner-recovery action then removed the VPN Router system
preference. Read-only inspection found zero VPN Router preferences, zero connected
VPN Router services, no routes on the previous `utun`, and the default route still
on the USB LAN. The imported profile count remained one and the shared selected
site count remained three.

The owner reinstalled from that preserved profile, connected, confirmed the
configuration-removal action was disabled while connected, and performed a normal
disconnect. The removal action became available only after disconnect. Final
read-only inspection found one installed preference, zero connected VPN Router
services, zero Packet Tunnel processes, no VPN `utun` IPv4 routes, and the default
route on the USB LAN.

## Developer ID and notarization gate

Before a public build:

1. confirm Developer ID Application and Network Extension provisioning for the
   host and Packet Tunnel;
2. decide whether the development-only DNS Proxy target is excluded from the
   public archive;
3. archive with the explicit `0.1.0` version and macOS 15 target;
4. inspect nested signatures and entitlements with `codesign`;
5. submit the archive with `notarytool` using a Keychain profile;
6. staple and validate the ticket;
7. run `spctl` assessment and launch on a clean supported Mac;
8. execute the signed matrix above;
9. calculate the final app or disk-image SHA-256;
10. tag only the exact artifact-producing commit.

Credential names, Team identifiers, signing identities, provisioning profiles,
and notarization output containing private account details must not be committed.
