# UWP VPN 플러그인 갈래 — 앱별 라우팅 판별 시험 재료

`R3-DEC-04` 재개(2026-08-18)에 딸린 시험 재료다. 판정과 조건은
`docs/R3-DEC-04-uwp-vpn-plugin-branch-verdict-2026-08-18.md` 와
`docs/R3-DEC-04-evidence-windows-wfp-live-2026-08-18.md` §12 에 있다.

## 이게 무엇인가

Windows 의 사용자 모드 VPN 플러그인 플랫폼(`Windows.Networking.Vpn`)이
`VpnChannel.StartWithTrafficFilter` + `VpnTrafficFilter` 로 **앱을 실행 파일 경로로 지목해**
터널에 붙일 수 있는지를 확인하는 한 번짜리 시험이다.

**제품 후보가 아니라 싸게 확인해 볼 가설이다.** 적대 반박 3명이 전원 REFUTED 를 냈다.
그럼에도 하는 이유는 4시간이면 답이 나오기 때문이다.

## 바탕

- 참조 구현: https://github.com/luqmana/wireguard-uwp-rs — 커밋 `328e622` (2021-12-12)
- Rust WireGuard UWP VPN 플러그인. 앱별 거르개는 원래 없다(경로 제외만 있다).

## 이 폴더의 것

- `per-app-traffic-filter.patch` — `328e622` 에 `git apply` 하는 패치.
  `<TunnelApp>` 설정 항목을 더하고, 그 목록이 비어 있지 않으면 `Start` 대신
  `StartWithTrafficFilter` 를 부른다. 앱마다
  `VpnAppId::Create(FilePath, 경로)` → `VpnTrafficFilter::Create`
  → `SetRoutingPolicyType(ForceAllTrafficOverVpn)`.
  `AllowOutbound`/`AllowInbound` 를 **명시적으로 `true`** 로 둔다(기본값이 문서에 없다).

## 되살리는 법

```powershell
git clone --depth 1 https://github.com/luqmana/wireguard-uwp-rs.git
cd wireguard-uwp-rs
git apply ..\per-app-traffic-filter.patch
cargo build --release
copy appx\* target\release
Add-AppxPackage -Register .\target\release\AppxManifest.xml   # 개발자 모드 ON 이면 서명 불필요
```

## 이 기계에서 실측된 것 (2026-08-18)

| 확인 | 결과 |
|---|---|
| `windows` 크레이트 0.28 에 필요한 API 가 있는가 | 전부 있음 |
| 2021년 코드가 Rust 1.97.1 로 빌드되는가 | 됨 — 릴리스 3분 22초 · exit 0 |
| 패치가 빌드되는가 | 됨 — exit 0 · DLL 626,176 → 650,752 바이트 |

## 하지 않는 것

- WireGuard 설정과 개인 키는 **사람이 직접** 다룬다. AI 는 열지도 만들지도 않는다.
- PFN 거르개와 FilePath 거르개를 한 `VpnTrafficFilterAssignment` 에 섞지 않는다
  (`MicrosoftDocs/winrt-api#1798` — 액세스 위반).
