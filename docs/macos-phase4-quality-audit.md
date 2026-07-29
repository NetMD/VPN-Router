# macOS Phase 4 quality audit

Last updated: 2026-07-24 KST

## Scope and context

This audit starts Phase 4 for the native SwiftUI macOS app after the signed Phase 3
networking decision. The target context is a resizable desktop window operated by
mouse, trackpad, keyboard, and VoiceOver. Networking remains native and isolated:
the host app, Packet Tunnel, and diagnostic DNS Proxy keep their existing
responsibilities.

The optional `impeccable` preparation skill required by the audit workflow was not
available in this session. The audit therefore uses the repository's macOS handoff,
the existing SwiftUI implementation, signed real-Mac findings, `swift test`, and
Xcode static analysis as its evidence.

## Audit health score

| # | Dimension | Score | Key finding |
|---|---|---:|---|
| 1 | Accessibility | 2/4 | Native labels help, but keyboard, focus, status announcements, and icon-only control labels are incomplete. |
| 2 | Performance | 2/4 | Serial `getaddrinfo`, file I/O, parsing, and Keychain work can run in the SwiftUI main execution path. |
| 3 | Responsive design | 2/4 | A 720-point detail minimum and fixed two-column layouts prevent compact-window adaptation. |
| 4 | Theming | 3/4 | Semantic system styles support dark mode, but the accent asset has no product color. |
| 5 | Anti-patterns | 3/4 | The native UI is restrained, but Phase 0/3 development controls remain mixed into consumer surfaces. |
| **Total** |  | **12/20** | **Acceptable — significant release-hardening work remains.** |

## Anti-pattern verdict

Pass with reservations. The app does not show common generated-design problems:
there are no gradients, glass panels, excessive cards, decorative animations, or
color-only status indicators. It does still feel like a development console in
places because **테스트 구성 설치**, System Extension activation, and DNS Proxy
spike controls are presented alongside consumer tunnel controls.

## Executive summary

- Health score: **12/20 (Acceptable)**
- Findings: **P0 0 / P1 5 / P2 5 / P3 2**
- First implementation target: move blocking profile, storage, Keychain, and DNS
  planning work away from the main actor and add one-operation-at-a-time state.
- No finding authorizes enabling a Network Extension or changing a third-party
  product automatically.

## P1 findings

### P1.1 — Blocking work can freeze the SwiftUI main actor

- Location: `VPNRouter/ContentView.swift` startup, import, route creation, connect,
  static restoration, and route refresh paths; `VPNRouter/Services/Rules/DomainResolver.swift`
  serial IPv4 and IPv6 `getaddrinfo` loops.
- Category: Performance / Accessibility
- Impact: resolving the expanded media-domain set can block window updates,
  keyboard focus, VoiceOver feedback, and cancellation for multiple DNS timeouts.
  Profile JSON, WireGuard parsing, Keychain calls, and file writes have the same
  synchronous-call risk.
- Recommendation: introduce async service boundaries and perform blocking work on
  a bounded background executor. Return immutable results to `MainActor` for UI
  state updates.
- Suggested command: `/optimize`

### P1.2 — Long actions have no shared in-flight guard

- Location: `VPNRouter/ContentView.swift` connect, install, import, route creation,
  refresh, and provider-diagnostics controls.
- Category: Performance / Accessibility
- Impact: repeated clicks can overlap preference saves, DNS planning, provider
  messages, or imports. The UI often remains visually idle while work runs.
- Recommendation: add scoped operation state, disable conflicting controls, show a
  `ProgressView`, and expose a concise current-operation label to VoiceOver.
- Suggested command: `/optimize`

### P1.3 — Development controls are exposed as consumer actions

- Location: `tunnelControls` and the Phase 3 sections in `diagnosticsView`.
- Category: Anti-pattern / Safety
- Impact: a user can install the obsolete Phase 0 stub or enter signed DNS Proxy
  experiments that the Phase 3 decision explicitly keeps out of the supported
  consumer path.
- Recommendation: remove the Phase 0 stub action and compile the DNS Proxy spike
  controls only into development builds or place them behind an explicit developer
  diagnostics mode.
- Suggested command: `/distill`

### P1.4 — Troubleshooting export and recovery surface are missing

- Location: Diagnostics feature.
- Category: Accessibility / Release hardening
- Impact: users cannot create a bounded, redacted support artifact or clearly
  confirm recovery state after a failure. This also leaves the Phase 4 privacy and
  recovery acceptance items untestable.
- Recommendation: add a versioned redacted diagnostics model and save-panel export
  that excludes raw configurations, keys, target addresses, and DNS payloads.
  Provide status-only recovery guidance and VPN Router-owned cleanup actions.
- Suggested command: `/clarify`

### P1.5 — Release assets and build warnings are unresolved

- Location: empty `AppIcon.appiconset`; WireGuard Go archive linker warning during
  Xcode Analyze; provisional macOS 14 target versus the diagnostic DNS Proxy's
  macOS 15 requirement.
- Category: Performance / Theming / Release hardening
- Impact: the app has no distributable icon, the external archive warning may
  become a release-toolchain problem, and minimum-system messaging is ambiguous.
- Recommendation: add final app-icon assets, reproduce and resolve or formally
  disposition the archive warning, and document one supported minimum per shipped
  feature set before notarization.
- Suggested command: `/polish`

## P2 findings

### P2.1 — Compact-window adaptation is blocked

- Location: `ContentView` detail `minWidth: 720`; Profiles and Sites fixed
  360/280-point two-column layouts.
- Category: Responsive design
- Impact: the owner confirmed that the window cannot be narrowed enough to exercise
  existing fallback layouts. Smaller displays and larger text have less usable
  space than necessary.
- Recommendation: use content-driven `ViewThatFits` layouts and reduce the detail
  minimum after verifying Profiles, Sites, Home, and Settings at compact widths.
- Suggested command: `/adapt`

### P2.2 — Keyboard and VoiceOver semantics are incomplete

- Location: profile/domain trash icon buttons, connection controls, status/message
  views, and forms.
- Category: Accessibility
- Impact: icon-only controls are not consistently named with their target, status
  changes are not announced, and primary actions have no keyboard shortcuts or
  managed focus after errors.
- Recommendation: add target-specific accessibility labels and hints, keyboard
  shortcuts for safe primary actions, focused error recovery, and status
  announcements.
- Suggested command: `/clarify`

### P2.3 — Scroll behavior is inconsistent

- Location: Diagnostics scrolls, but Home, Profiles, Sites, and Settings use fixed
  vertical layouts; `DiagnosticMessageView` nests a vertical `ScrollView` inside
  the Diagnostics `ScrollView`.
- Category: Responsive design / Accessibility
- Impact: large text or long localized content can clip, while nested scrolling can
  make trackpad and keyboard navigation unpredictable.
- Recommendation: give each detail page one clear vertical scroll owner and let
  diagnostic messages expand or use a selectable disclosure area.
- Suggested command: `/adapt`

### P2.4 — Prototype and phase terminology leaks into product copy

- Location: **1단계**, **Phase 3 DNS Proxy 준비 상태**, **테스트 구성 설치**, and
  implementation-heavy diagnostic descriptions.
- Category: Anti-pattern / Accessibility
- Impact: consumer users must understand internal development phases to interpret
  the interface.
- Recommendation: replace phase language with task and safety language; keep
  technical identifiers only in developer diagnostics.
- Suggested command: `/clarify`

### P2.5 — Host lifecycle coverage is incomplete

- Location: only the Packet Tunnel implements `sleep`/`wake`; the host has no
  network-path or system sleep/wake coordination.
- Category: Performance / Release hardening
- Impact: UI state and route refresh behavior after sleep, wake, network changes,
  captive portals, and endpoint changes are not yet observable or tested.
- Recommendation: add read-only lifecycle diagnostics first, then signed tests
  before introducing any automatic recovery action.
- Suggested command: `/optimize`

## P3 findings

### P3.1 — Product accent identity is absent

- Location: `AccentColor.colorset` has no color values.
- Category: Theming
- Impact: the app inherits a generic system accent and lacks the restrained coral
  identity requested by the macOS handoff.
- Recommendation: add accessible light/dark accent variants and verify contrast in
  selected, disabled, and high-contrast states.
- Suggested command: `/colorize`

### P3.2 — Large view ownership increases regression risk

- Location: `ContentView.swift` owns navigation, every screen, networking
  orchestration, dialogs, accessibility, and diagnostics.
- Category: Performance / Anti-pattern
- Impact: changes to one feature cause broad recompilation and make focused UI or
  lifecycle tests difficult.
- Recommendation: split by feature only after operation state and service
  boundaries are stable; avoid a cosmetic file shuffle first.
- Suggested command: `/polish`

## Positive findings

- Native SwiftUI controls, semantic fonts, SF Symbols, and semantic foreground
  styles provide a solid accessibility and dark-mode baseline.
- Warnings include explanatory text, so risk is not communicated by color alone.
- Destructive profile deletion and fail-safe disabling require confirmation.
- Diagnostics messages are selectable and bounded.
- The Diagnostics detail now scrolls and its DNS controls have a width fallback.
- `xcodebuild analyze` succeeds with no Swift analyzer errors.
- `swift test` passes 33 focused checks.
- Network actions remain scoped to VPN Router-owned configurations.

## Recommended action order

1. **P1 `/optimize`** — background blocking work and add operation guards.
2. **P1 `/distill`** — separate development-only networking controls.
3. **P2 `/adapt`** — compact layouts and one scroll owner per screen.
4. **P1/P2 `/clarify`** — recovery/export UX, accessibility semantics, and copy.
5. **P3 `/colorize`** — add an accessible product accent.
6. **P1/P3 `/polish`** — app icon, archive warning, lifecycle matrix, and release checks.

Re-run `/audit` after fixes to measure the score change.

## Remediation audit

Re-audited: 2026-07-24 KST

| # | Dimension | Before | After | Remaining evidence |
|---|---|---:|---:|---|
| 1 | Accessibility | 2/4 | 3/4 | Final signed-build keyboard, VoiceOver, and high-contrast checks |
| 2 | Performance | 2/4 | 3/4 | Connected sleep/wake and network-change checks; clean Release optimizer result now passed |
| 3 | Responsive design | 2/4 | 4/4 | Signed compact/wide and scrolling checks passed |
| 4 | Theming | 3/4 | 4/4 | Final signed dark/high-contrast inspection |
| 5 | Anti-patterns | 3/4 | 4/4 | Development controls are Debug-only and opt-in |
| **Total** |  | **12/20** | **18/20** | **Good — private dogfood acceptance passed.** |

The implementation pass resolved the five original P1 product findings:

- blocking storage, Keychain, import, DNS, and route-planning work now runs behind
  async background service boundaries;
- one-operation-at-a-time state prevents overlapping preference, import, route,
  and provider actions while exposing progress to assistive technologies;
- obsolete and experimental networking controls are hidden behind a Debug-only
  developer option;
- Diagnostics now provides a schema-versioned redacted export and
  ownership-checked recovery actions;
- the app has complete icon assets, an accessible coral accent, a documented
  macOS 15/Apple Silicon baseline, and explicit Release warning dispositions.

Responsive layouts, a single scroll owner per detail page, keyboard shortcuts,
target-specific accessibility labels, focus recovery, status announcements, and
read-only lifecycle diagnostics address the original P2 findings. Automated
evidence includes 35 passing core tests, JSON/redaction checks, a successful Xcode
Analyze action, and a successful unsigned arm64 Release packaging check.

### Remaining findings

- **P2:** The connected-status VoiceOver announcement was not exercised because
  the owner chose to skip that interaction. Offline VoiceOver labels, focus,
  selection state, shortcuts, and control descriptions passed.
- **Resolved:** Xcode 26.6 / Swift 6.3.3 crashed while optimizing synthesized
  deinitializers for two generic continuation gates. Both gates now use
  non-generic one-shot ownership state, and a clean whole-module `-O` Release
  succeeds without disabling any optimizer pass.
- **Resolved:** The reproducible Go 1.26.5 `c-archive` no longer emits the prior
  linker warning, and minimum macOS 15 is verified. The DNS Proxy System Extension
  is required for dynamic discovery, target AAAA protection, and DNS ownership;
  it must remain embedded for a parity release.
- **P3:** `ContentView.swift` still owns several feature surfaces. Split it by
  feature after signed behavior is stable to reduce recompilation and regression
  risk.

The signed owner matrix passed compact/wide layout, scrolling, dark/high contrast,
per-app themes, redacted export, connect and split routing, Host App relaunch,
sleep/wake, network transition, extension termination, owned configuration
removal, and normal disconnect cleanup. No score increase is based only on an
unsigned Network Extension runtime claim.
