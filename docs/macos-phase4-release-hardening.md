# macOS Phase 4 release hardening

Last updated: 2026-07-29 KST

## Distribution decision

The current macOS `0.1.0` candidate remains a **signed private dogfood build**,
not yet a public Developer ID release. Under the dual-platform parity release
policy, the shared `v0.1.0` tag now requires a distributable signed macOS
artifact. Packet Tunnel operation is proven with the owner's signed development
build, but Developer ID provisioning, notarization, a clean-machine install, and
the DNS Proxy system extension's distribution behavior are not yet proven. The
DNS Proxy system extension is a required product component: excluding it would
remove dynamic discovery, target AAAA protection, and DNS ownership, so it would
violate the platform parity contract.

The supported dogfood baseline is Apple Silicon and macOS 15 or later. Release
verification overrides local Xcode values with product version `0.1.0`, build
number `1`, and deployment target `15.0`; this avoids committing the owner's
private signing settings from `project.pbxproj`.

## Automated release verification

`scripts/macos/verify-release.sh`:

1. verifies required Xcode, Go, and packaging tools and records the Go version;
2. builds `libwg-go.a` for arm64;
3. builds an unsigned Release app with explicit version and deployment target;
4. checks the app version and both embedded Network Extensions;
5. verifies minimum-OS load commands in the Host App, both extensions, and
   representative Go/CGO archive members;
6. signs an isolated app copy ad hoc and runs the signed-bundle verifier against
   its full structure and entitlement contract;
7. prints the WireGuard Go archive SHA-256.

The unsigned output is not a distributable VPN app. It is compile and packaging
evidence only.

Xcode 26.6 / Swift 6.3.3 previously crashed in the SIL performance inliner while
optimizing synthesized deinitializers for two generic continuation gates.
Incremental compilation alone and `-Osize` both reproduced the crash. The gates
now use non-generic one-shot ownership state, and a clean whole-module `-O`
Release succeeds without disabling any optimizer pass. The compiler workaround
is no longer a distribution blocker.

## WireGuard archive warning disposition

On 2026-07-29 the checksum-verified official Go 1.26.5 arm64 toolchain rebuilt
`libwg-go.a` in a clean release directory. The canonical unsigned Release build
completed without the earlier malformed `LC_DYSYMTAB` or newer-deployment-target
warning. The Host App, Packet Tunnel, DNS Proxy System Extension, `go.o`, and a
representative CGO object all report minimum macOS 15.0. The archive SHA-256 is
`29177134ad37d6105857d926977f0669759e1e4b542803d27dd5b794f10fd3fd`.
The bridge Makefile clears the path-dependent Go build ID, omits VCS stamping,
and uses deterministic archive metadata; two independent clean bridge builds
produced that same checksum.

This resolves the unsigned toolchain-warning gate. Public distribution still
requires the same archive to pass final Developer ID nested signing, notarization,
Gatekeeper assessment, and a clean supported-Mac signed runtime test.

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

1. confirm Developer ID Application, Packet Tunnel, and DNS Proxy System
   Extension provisioning;
2. keep both required Network Extensions embedded in the public archive;
3. archive with the explicit `0.1.0` version and macOS 15 target;
4. run `scripts/macos/verify-signed-app.sh --mode distribution` to inspect nested
   signatures, entitlements, bundle identity/version, architecture, and minimum
   OS without printing signing identities or Team identifiers;
5. submit the archive with `notarytool` using a Keychain profile;
6. staple, then run the verifier again with `--notarized` to validate the ticket
   and Gatekeeper assessment;
7. run `spctl` assessment and launch on a clean supported Mac;
8. execute the signed matrix above;
9. calculate the final app or disk-image SHA-256;
10. tag only the exact artifact-producing commit.

Credential names, Team identifiers, signing identities, provisioning profiles,
and notarization output containing private account details must not be committed.
