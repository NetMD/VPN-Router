# VPN Router macOS MVP progress

Last updated: 2026-07-20 KST

## Current phase

Phase 0: environment and entitlement inventory.

No Xcode project has been generated yet. The repository was not clean at the start
of this phase, and the existing `.idea/` changes have been left untouched.

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

Packet Tunnel availability cannot be inferred from SDK presence, compilation, or a
Developer ID distribution certificate. It must be confirmed with the owner's Apple
Developer team by signing and launching an embedded Network Extension on this Mac.

## Proposed identifiers

These are documentation examples, not reserved production identifiers:

- Host app: `com.example.vpnrouter`
- Packet Tunnel extension: `com.example.vpnrouter.packet-tunnel`
- App Group: `group.com.example.vpnrouter.shared`
- Keychain access group suffix: `com.example.vpnrouter.shared`

Before project generation, replace the `com.example` prefix with an owner-approved
reverse-DNS namespace. Keep the host and extension identifiers stable after signing
and provisioning begin.

## Phase 0 checklist

- [x] Run `sw_vers`, `uname -m`, `xcodebuild -version`, and `swift --version`.
- [x] Record Mac model/architecture, installed Xcode, SDK, and candidate deployment target.
- [ ] Confirm the Apple Developer Team ID without committing it.
- [ ] Confirm Packet Tunnel entitlement/provisioning availability.
- [x] Propose example bundle identifiers without private team data.
- [ ] Confirm `git status` is clean before generating Xcode files.
- [ ] Generate a minimal SwiftUI host app with an embedded stub Packet Tunnel extension.
- [ ] Sign and launch the host app on this Mac.
- [ ] Verify the extension reaches both `startTunnel` and `stopTunnel` on this Mac.

## Current blockers

1. `.idea/` has been removed from the Git index and added to the root `.gitignore`.
   The remaining working tree changes are the intentional Phase 0 documentation and
   ignore-file updates. Commit or stash those before generating Xcode project files
   if a strictly clean tree is required for the scaffold checkpoint.
2. No local Apple Development or Mac Developer signing identity, configured Developer
   Team, or provisioning profile was detected, so a signed Packet Tunnel launch
   cannot yet be performed. The detected Developer ID Application identity is not
   sufficient evidence for the Phase 0 Network Extension launch gate.

## Phase 0 exit evidence required

The phase is complete only after a signed development build provides real-Mac
evidence that:

1. the host app launches with the Packet Tunnel extension embedded;
2. `NETunnelProviderManager` installs and starts the configuration;
3. the stub provider records entry into `startTunnel`;
4. disconnect records entry into `stopTunnel`; and
5. the status shown by the host app is derived from `NEVPNStatus`.

Compilation alone does not satisfy this gate.
