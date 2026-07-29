# macOS Codex next session

Last updated: 2026-07-30 KST

This is the first document Codex should read after `AGENTS.md` when work resumes
on the owner's Mac. It records the exact continuation point after the Windows
release-hardening pass and the owner-approved cross-platform parity decision.

## Read order

Read these files completely before editing:

1. `docs/macos-next-session.md`
2. `docs/platform-parity-contract.md`
3. `docs/platform-parity-audit.md`
4. `docs/macos-mvp-handoff.md`
5. `docs/macos-mvp-progress.md`
6. `docs/macos-phase3-dns-proxy-spike.md`
7. `docs/macos-phase4-quality-audit.md`
8. `docs/macos-phase4-release-hardening.md`
9. `docs/v0.1.0-release-plan.md`

Use `docs/windows-mvp-progress.md` and the current Windows UI as behavioral and
visual references only. Keep macOS networking, signing, storage, UI, and provider
code native and isolated.

## Owner decisions now in force

- Windows and macOS must provide the same user-visible selected-site routing and
  safety semantics.
- The Windows dashboard is the preferred product UI reference. macOS should adopt
  its status-first hierarchy, compact navigation, restrained light surfaces,
  coral accent, plain-language status, and lower diagnostic density.
- macOS must remain a native SwiftUI application with native windowing,
  Automatic/Light/Dark appearance, keyboard support, VoiceOver, increased
  contrast, and reduced-motion behavior.
- The already proven macOS DNS Proxy path is no longer intended to remain a
  Debug-only experiment. It is the target supported consumer connection path.
- Static pre-resolution may be used internally while starting, or remain as an
  explicitly labeled development/limited mode, but it must not be reported as
  equivalent to Windows dynamic routing.
- A consumer connection must not report `Connected` until VPN Router owns the DNS
  Proxy configuration, the provider is reachable through XPC, target publication
  succeeds, target AAAA filtering is active, and the dynamic route observation
  path is ready.
- If any required DNS Proxy condition fails, stop and clean up only VPN
  Router-owned Packet Tunnel, DNS Proxy, and route state. Never silently fall back
  to an unsafe connected state.
- Route-plan expiry protection is mandatory and must not have a user-disable
  control. When upgrading a legacy installation whose saved override was false,
  remove the override and re-arm an already-connected provider; disconnect VPN
  Router if re-arming cannot be confirmed.
- Never stop, disable, reconfigure, or change another VPN, DNS, ad-blocking,
  antivirus, or security product.
- Captive-portal sign-in remains out of scope. The user signs in while VPN Router
  is disconnected.

The complete product contract is in `docs/platform-parity-contract.md`.

## Repository continuation state

At the Windows-to-Mac handoff:

- branch: `main`;
- the Windows checkout was clean before this handoff documentation was created;
- `main` contained nine local commits beyond the previous `origin/main`, including
  Windows release hardening, owner-operated recovery evidence, the Windows
  `v0.1.0` release candidate, and the platform parity decision;
- this handoff is intended to be pushed with those commits, so verify that
  `git status --short --branch` shows no unexpected divergence after pulling;
- no `v0.1.0` tag has been created;
- the existing Windows portable artifact was produced before the parity-document
  commit and must be rebuilt and reverified from the eventual tag commit;
- no macOS public release or parity claim has been made.

Do not reset, squash, or discard the Windows commits when resuming macOS work.

## What is already implemented on macOS

The repository contains:

- a SwiftUI host app;
- a signed and real-Mac-tested Packet Tunnel using WireGuardKit;
- Keychain-backed private-key storage and sanitized profile metadata;
- profile import with a chosen display name, rename, selection, validation, and deletion;
- a shared VPN Sites list with YouTube and Netflix media expansion;
- bounded static IPv4 `/32` route planning;
- five-minute refresh, fifteen-minute per-answer retention/expiry, and a combined
  512-route cap;
- schema-versioned Packet Tunnel provider messaging and live route replacement;
- a separate DNS Proxy system extension with UDP/TCP forwarding;
- XPC publication of normalized target rules and bounded aggregate observations;
- target AAAA empty-success filtering while preserving target A and unrelated
  AAAA responses;
- encrypted-DNS preflight that reads supported Chrome/Edge policy without
  modifying it, plus explicit manual Private Relay guidance;
- DNS Proxy ownership/XPC monitoring and orphan cleanup;
- active IPv4 `utun` set monitoring that fails safe on a second-VPN transition;
- mandatory Packet Tunnel cancellation when the host cannot refresh a route plan
  before its fifteen-minute safety boundary, including safe migration of the
  removed legacy disable preference;
- bounded redacted troubleshooting export;
- a consumer connection coordinator that withholds `Connected` until DNS Proxy
  ownership, XPC target publication/readiness, and safety monitoring all succeed;
- native lifecycle, compact-layout, theme, keyboard, VoiceOver, and recovery work;
- Windows-referenced five-screen information hierarchy with one Home
  Connect/Disconnect action and technical controls contained in Troubleshooting.

The Swift package test suite last passed 59 focused checks. The latest unsigned
arm64 Debug app, Packet Tunnel, and DNS Proxy build also succeeded. Treat those as
recorded evidence to reproduce on the Mac, not as proof from the Windows host.

Later owner-signed optimized Release builds installed under `/Applications`
completed the atomic consumer connection, DNS/route checks, normal disconnect,
unexpected-provider cleanup/reconnect, and connected close/reopen lifecycle.
The compact-window status is now fully scrollable and copyable. The latest
installed dogfood build at this handoff is `0.1.0 (14)` from commit `8e7c4ae`.
It repeated the signed DNS/route and connected close/reopen checks, plus
current-build profile
rename, redacted export, theme, compact/wide scrolling, and explicit sidebar
VoiceOver labels. A 16-minute-30-second run crossed the safety boundary while
routes changed from 41 to 85 and then 74 without a failure. No signing identity,
Team ID, profile content, key, or network detail was recorded.

## Latest signed real-Mac evidence

The latest signed DNS Proxy validation was build 20 on 2026-07-28:

- initial XPC target setup used bounded retries and reached ready state;
- Packet Tunnel and DNS Proxy ran together while Tailscale/no-exit-node was
  already connected;
- target IPv4 answers used VPN Router, target UDP/TCP AAAA answers were empty,
  unrelated AAAA remained available, and default/control traffic stayed on the
  primary interface;
- control, YouTube, and Netflix HTTPS returned 200;
- disconnecting and reconnecting Tailscale changed the active IPv4 tunnel set;
- VPN Router failed safe about one second after the observed transition;
- VPN Router routes were removed, Tailscale was preserved, and control DNS/HTTPS
  remained healthy.

Earlier signed runs also proved dynamic DNS-observed route insertion, DNS Proxy
preference-loss cleanup, app relaunch, provider termination, sleep/wake, network
change, normal disconnect, redacted export, and selected/control routing. The
detailed chronology and limitations are in `docs/macos-mvp-progress.md`.

These results prove a development configuration on one real Mac. They do not
prove Developer ID distribution, notarization, clean-machine installation, every
encrypted-DNS environment, or public parity.

## Current continuation point: core signed path passed, release matrix pending

On 2026-07-29 the consumer-path and UI parity implementation was completed:

- the consumer state machine has stable stages and bounded failure codes;
- a normal Connect requests DNS Proxy System Extension activation before any
  Packet Tunnel mutation and awaits macOS approval/completion;
- Connect keeps product state pending through Packet Tunnel start, owned DNS
  Proxy enablement, XPC target publication, provider readiness, and the
  tunnel-interface safety prerequisite;
- partial starts clean up owned DNS Proxy state before Packet Tunnel;
- relaunch refuses to treat a connected static-only Packet Tunnel as ready;
- route refresh and ownership monitors are gated on consumer readiness;
- troubleshooting schema 2 records only stage and failure code;
- profile rename now preserves the profile ID and Keychain secret reference and is
  blocked while connected;
- Home, VPN Profiles, VPN Sites, Troubleshooting, and Settings now follow the
  Windows information hierarchy with native adaptive SwiftUI cards;
- Home has one large Connect/Disconnect action and status/profile/site summaries;
  route/provider/recovery controls are isolated in Troubleshooting;
- all 59 focused checks pass, including every injected failure stage,
  disconnect ordering, and profile-rename identity/secret-reference invariants;
- the unsigned arm64 Host/Packet Tunnel/DNS Proxy Debug build succeeds. Xcode
  26.6 required `SWIFT_ENABLE_EXPLICIT_MODULES=NO` and
  `CLANG_ENABLE_EXPLICIT_MODULES=NO` after a temporary explicit-module cache race.

The later signed run exposed and fixed the initial Packet Tunnel status race,
stale connected UI after provider loss, provider callback synchronization, and
connected host-quit lifecycle. Connected Quit closes only the main window so the
host continues DNS ownership and route-refresh work; reopening restores the
existing window. Resume with the remaining release matrix rather than repeating
the already-passed atomic sequence unless a new build changes networking or
lifecycle code.

## Immediate implementation order

### 1. Reproduce the automated baseline

From the repository root on the Mac:

```bash
git status --short --branch
git pull --ff-only
git log --oneline -12
sw_vers
uname -m
xcodebuild -version
swift --version
cd macos/VPNRouter
swift test
```

Expect 59 focused checks unless new committed tests intentionally change the
count. Record the actual toolchain and result in `docs/macos-mvp-progress.md`.

Do not run broad commands that print `.conf`, Keychain, provisioning, signing, or
system-log contents. Do not commit Team IDs, certificate names, provisioning
profiles, Apple account data, or notarization credentials.

### 2. Reconfirm the owner-signed consumer path on the release candidate

Use the existing private Xcode signing configuration without recording it:

1. launch a signed build with Packet Tunnel and DNS Proxy extensions embedded;
2. press the normal Home Connect action;
3. if macOS requests System Extension approval, confirm the UI remains
   `Connecting` and no final connected state appears before approval;
4. verify the stage advances through owned DNS Proxy enablement, XPC publication,
   readiness, and safety monitoring;
5. confirm `Connected` appears only after the complete sequence;
6. disconnect and confirm DNS Proxy cleanup precedes Packet Tunnel stop;
7. preserve the recorded approval-cancellation and unexpected-provider cleanup
   results; rerun them only if the candidate changes the affected code.

### 3. Preserve the proven safety semantics

Do not regress:

- five-minute route refresh;
- fifteen-minute rotating-answer lifetime;
- 512 unique IPv4 route limit before mutation;
- target AAAA filtering for UDP and TCP;
- default-route and unrelated-traffic preservation;
- XPC timeouts and bounded startup retry;
- owned preference checks;
- fail-safe on active IPv4 tunnel-interface set change;
- orphan DNS Proxy cleanup after host relaunch;
- normal shutdown ordering: owned DNS Proxy first, Packet Tunnel second;
- redacted diagnostics containing no raw domains, addresses, DNS payloads,
  configuration text, keys, or unrestricted logs.

### 4. Inspect the five native screens

At compact and wide window sizes, confirm Home, VPN Profiles, VPN Sites,
Troubleshooting, and Settings reflow without clipping or nested scrolling. Check
keyboard focus, VoiceOver names/state, Automatic/Light/Dark, and increased
contrast. Confirm profile rename persists across relaunch and never changes or
exposes Keychain material.

### 5. Run the signed parity matrix

Compilation and unsigned builds are only preliminary checks. On the owner's Mac,
use the existing private signing configuration without committing it, then verify:

- fresh connection and system-extension approval behavior;
- UDP and TCP target A/AAAA plus unrelated controls;
- live dynamic CDN observations and route updates;
- rotating-answer retention and expiry;
- legacy disabled-expiry preference cleanup while disconnected, plus re-arm or
  owned disconnect while already connected;
- 512-route rejection before partial mutation;
- default route and control destination preservation;
- DNS Proxy preference/ownership loss;
- Tailscale stable coexistence and transition fail-safe;
- host quit/relaunch;
- Packet Tunnel and DNS Proxy provider termination;
- sleep/wake and primary-network change;
- normal disconnect and restart/orphan recovery;
- bounded troubleshooting export;
- the Windows-referenced UI at compact/wide, keyboard, VoiceOver, light/dark,
  and increased-contrast settings.

Record sanitized counts, states, durations, interfaces, and pass/fail results only.
Do not record resolver addresses, selected domains beyond the public test rules,
raw DNS payloads, real profile content, private keys, Team IDs, or account data.

## Build and release limitations

- `scripts/macos/verify-release.sh` builds the WireGuard Go bridge and verifies an
  unsigned arm64/macOS 15 Release package. It also verifies the minimum-OS load
  command in the Host App, both extensions, and representative Go/CGO archive
  members.
- Xcode 26.6 / Swift 6.3.3 previously crashed while optimizing synthesized
  deinitializers for two generic continuation gates. They were replaced by
  non-generic one-shot gates; the canonical script now completes a clean
  whole-module `-O` Release without disabling optimizer passes.
- Go 1.26.5 rebuilt the bridge without the earlier `LC_DYSYMTAB` or newer-minimum-
  OS linker warnings. Preserve the recorded version/checksum and validate the
  bridge through final signing, notarization, Gatekeeper, and clean-machine
  runtime evidence.
- Developer ID Network Extension provisioning, nested signing, notarization,
  stapling, `spctl`, and clean supported-Mac installation remain unproven.
- `scripts/macos/verify-signed-app.sh` validates a development or distribution
  app's required Host/Packet Tunnel/DNS Proxy signatures, entitlements, versions,
  arm64 slices, and minimum macOS without printing signing identities. In
  distribution mode, `--notarized` additionally requires a valid stapled ticket
  and Gatekeeper acceptance.
- The prior private dogfood baseline was Apple Silicon, macOS 15 or later.

Do not tag or claim a public macOS release until these gates and the signed parity
matrix pass.

## Completion record for each Mac work group

1. Update `docs/macos-mvp-progress.md` with exact sanitized evidence.
2. Update this document if the next starting point changes.
3. Update `docs/platform-parity-contract.md` only for an owner-approved semantic
   decision, not to excuse an implementation gap.
4. Run `swift test` and the applicable unsigned/signed build checks.
5. Run `git diff --check`.
6. Review `git status --short` for generated signing, DerivedData, archives,
   profiles, logs, and imported configs.
7. Commit only sanitized source, tests, and documentation.
