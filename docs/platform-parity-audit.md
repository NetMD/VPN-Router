# VPN Router platform parity audit

Last updated: 2026-07-29 KST

This audit maps every requirement in `docs/platform-parity-contract.md` to current
implementation and evidence. A row marked **signed rerun pending** is not release
proof even when earlier development builds passed the same low-level behavior.

## Common behavior

| Requirement | Windows implementation/evidence | macOS implementation/evidence | Current verdict |
|---|---|---|---|
| Profile lifecycle | Native service profile store and DPAPI import/rename/select/delete; Windows release matrix recorded in `docs/windows-mvp-progress.md`. | Keychain-backed import/select/delete plus `ProfileRenamePolicy`; four focused rename tests prove trimming, targeted mutation, stable identity/secret reference, and bounded failures. | Implemented; current macOS signed persistence rerun pending. |
| Secret storage | DPAPI-protected material; redacted diagnostics tests and release evidence. | `KeychainSecretStore`; metadata contains only sanitized configuration and summary. Existing signed import/delete evidence is recorded in `docs/macos-mvp-progress.md`. | Implemented; no raw configuration or key was used in this audit. |
| Site rules | Shared product semantics in native C# expander and Windows tests. | `DomainRuleExpander` and five focused normalization/media-expansion tests. | Automated on both recorded matrices. |
| Dynamic discovery | Local DNS proxy observes target A answers and updates host routes; Windows signed matrix recorded. | DNS Proxy XPC observations feed `DynamicRoutePlanMerger` and live Packet Tunnel route replacement; signed build 20 evidence recorded. | Implemented; current consumer-path signed rerun pending. |
| Route lifetime | Five-minute refresh and individual fifteen-minute expiration in Windows. | Five-minute refresh, bounded static history, observation TTL merge, and fifteen-minute expiry tests. | Automated; signed long-duration rerun pending for current build. |
| Route bound | Windows rejects more than 512 combined routes before mutation. | Static planner and dynamic merger reject more than 512 unique IPv4 routes before provider update. | Automated. |
| IPv6 protection | Windows DNS proxy returns target AAAA empty-success and preserves unrelated AAAA. | macOS UDP/TCP DNS parser/provider does the same; parser tests and signed build 20 cover target/control behavior. | Automated plus historical signed evidence; current signed rerun pending. |
| Normal traffic | Windows signed route matrix preserves default/control traffic. | Network Extension uses selected IPv4 `/32` included routes and preserves the primary default route; historical signed matrix passed. | Current signed rerun pending. |
| Encrypted DNS | Windows detects browser policy and DNS conflicts without changing them. | `EncryptedDNSPreflightService` and `DNSProxyConfigurationPolicy` block enabled/unknown policy, allow explicit disablement, and require manual Private Relay confirmation. | Automated policy evidence; manual current-build check pending. |
| DNS ownership | Windows owns its local DNS path and health monitor before final connected state. | `ConsumerConnectionCoordinator` withholds ready through owned preference, XPC publication, provider readiness, and safety arming. | Eight injected failure cases pass; signed atomic sequence pending. |
| Fail-safe | Windows DNS health/recovery cleanup stops only VPN Router-owned proxy/routes/VPN and restores its snapshot. | Coordinator cleans DNS Proxy before Packet Tunnel; ownership and active-`utun` monitors fail safe without altering another provider. | Automated plus historical Tailscale evidence; current signed rerun pending. |
| Lifecycle | Windows privileged service owns state and startup recovery. | `NEVPNStatus`, owned preference reconciliation, relaunch rejection of static-only state, wake/network observation, and orphan cleanup. | Historical signed matrix passed; current consumer relaunch/restart rerun pending. |
| Diagnostics | Windows schema-bounded troubleshooting artifact and redaction tests. | Troubleshooting schema 2 contains bounded counts/state/timestamps/stage/failure code only. | Automated plus historical signed export; current UI export rerun pending. |
| Captive portals | Disconnect-first manual guidance; no automatic mutation. | Same disconnect-first guidance; no portal or third-party mutation code. | In scope statement satisfied. |

## UI and native implementation audit

Both platforms expose Home, VPN Profiles, VPN Sites, Troubleshooting, and Settings.
The macOS Home now matches the Windows task hierarchy: consumer state, one
Connect/Disconnect action, connection-plan readiness, selected profile/site/route
summary, and recent status. Technical status, route refresh, export, and recovery
are isolated in Troubleshooting.

Platform-only controls are not feature gaps:

- Windows shows WireGuard installation guidance because it depends on a separate
  Windows installation; macOS embeds native WireGuardKit.
- Windows portable-cache cleanup exists because the portable launcher extracts a
  runtime cache; macOS has no equivalent portable extraction cache.
- macOS requests native System Extension approval; Windows uses service/UAC
  installation instead.
- Recovery uses native ownership boundaries: Windows restores its service-owned
  DNS/routes/snapshot, while macOS removes or disables only its Network Extension
  preferences and providers.

The previous Windows Settings toggle claimed that Protection Mode blocked selected
sites on route failure, but its value was only logged and echoed by validation.
That false user-visible promise has been removed together with the unused IPC
field. Settings now describes the actually implemented mandatory owned-state
cleanup, matching the common fail-safe contract. The native Windows test suite
must still be rerun on Windows.

The new macOS card hierarchy follows the layout-system spacing and responsive
guidance while retaining native SwiftUI resizing, keyboard focus, VoiceOver,
increased contrast, and Automatic/Light/Dark appearance. Compilation is not visual
or accessibility runtime proof; compact/wide and assistive-technology inspection
remains in the signed matrix.

## Automated evidence at this audit point

- macOS: 25 XCTest cases plus 30 Swift Testing cases pass (55 focused checks).
- macOS: unsigned arm64 Debug build and Xcode Analyze pass for the Host App,
  Packet Tunnel, and DNS Proxy System Extension when `libwg-go.a` is staged.
- macOS: the canonical release script rebuilt `libwg-go.a` with Go 1.26.5 and
  completed a clean optimized unsigned arm64 Release build for macOS 15 with the
  documented Swift optimizer workaround. The Host App, both extensions, and
  inspected Go/CGO archive members all report minimum macOS 15.0; the archive
  SHA-256 is reproducibly
  `89f244ce627d843b775b29a401009c0309266267e2ffecaca9841e024364e1ca`.
- Repository: `git diff --check` passes.
- Windows: a temporary official .NET 10.0.301 SDK cross-targeted the current
  Core, IPC, Networking, VPN, Launcher, Service, and Tests projects successfully
  with zero warnings/errors. The focused executable passed 28 of 30 checks on
  macOS; only the PowerShell worker and Windows Principal ACL checks failed
  because their Windows APIs are absent.
- Windows: the Settings XAML is well-formed XML. WinUI compilation remains
  Windows-only because its packaged `XamlCompiler.exe` cannot execute on macOS;
  the previously recorded signed release matrix remains historical evidence.

## Gates still required before declaring parity

1. Run the current source as an owner-signed macOS build and prove the normal Home
   Connect action remains pending through System Extension approval and complete
   DNS readiness.
2. Run all current-build DNS, dynamic-route, expiry/bound, default-route,
   ownership-loss, second-VPN, relaunch/provider/lifecycle, disconnect/restart,
   redaction, profile/Keychain, and UI/accessibility checks listed in
   `docs/macos-next-session.md`.
3. Rerun the Windows tests and signed recovery/UI smoke checks after removal of the
   false Protection Mode control.
4. Complete Developer ID signing, nested entitlement validation, notarization,
   stapling, Gatekeeper, and clean supported-Mac installation.

Until all four gates pass, the implementation is aligned but public platform
parity is not proven and no release tag should be created.
