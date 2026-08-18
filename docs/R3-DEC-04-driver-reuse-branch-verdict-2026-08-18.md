# Windows 앱별 라우팅 — 갈래 C(남의 서명된 드라이버 재사용) 종합 판정

작성일: 2026-08-18 · 대상: Windows 11 Pro 10.0.26200 x64 · 근거: 조사 렌즈 6건 + 반박 검증 2건(2/2 REFUTED)

---

## 1. 한 줄 판정

**갈래 C는 여기서 닫습니다. 다른 갈래로 갈아타지도 마십시오. 지금은 어느 드라이버 갈래도 시작하지 않는 것이 맞고, v0.1.0 출시 관문을 닫는 데 시간을 쓰는 것이 맞습니다.**

이유를 한 문장으로 줄이면 이렇습니다. **앱별 라우팅을 실제로 해내는 드라이버는 전부 소스만 공개되어 있어 우리가 직접 서명해야 하고, 바로 쓸 수 있게 서명된 드라이버는 전부 앱별 라우팅을 못 합니다.** 그래서 "남이 서명해 둔 것을 재사용한다"는 전제 자체가 성립하지 않습니다. 재사용처럼 보이는 길을 끝까지 따라가면 결국 EV 인증서를 사고 Microsoft에 법인으로 등록하는, 원래 피하려던 그 비용이 그대로 나옵니다.

---

## 2. 갈래별 표

| 갈래 (드라이버 파일) | 라이선스 | 우리 비용 | 앱별 "라우팅"이 실제로 되나 | Win11 26200에서 서명·적재 | 판정 |
|---|---|---|---|---|---|
| **WireSock Secure Connect** (`ndiswgc.sys`, `ndiswgc_lwf.inf`, `nt_ndiswgc`) | 독점 EULA. 개인·교육·비영리 전용, 영리 배포 금지 | 우리는 0원이지만 업무용 사용자마다 PRO $50 | **됩니다** (AllowedApps / DisallowedApps, NDIS 필터로 패킷 단계 가로채기) | 됩니다 (IP SMIRNOV VADIM VALERIEVICH 서명, 26200 지원 여부는 미확인) | **실격** — 라이선스 |
| **WinpkFilter** (`ndisrd.sys`, `ndisrd_lwf.inf`, `nt_ndisrd`) | 독점 freeware EULA + 유료 상업 라이선스 | 배포하려면 **$3,000**(바이너리) 또는 **$9,000**(소스), 추가 커스텀 빌드 $100, 갱신 연 $2,000~12,000 | **안 됩니다.** 드라이버에 앱 개념이 아예 없습니다. `STATIC_FILTER`는 링크/네트워크/전송 계층 필드만 봅니다 | **됩니다** — `ndisrd.cat`이 Microsoft Windows Hardware Compatibility Publisher 서명, 실측으로 `signtool verify /kp` 통과 | **실격** — 라이선스 + 기능 없음 |
| **WinDivert** (`WinDivert64.sys`, `WinDivert32.sys`) | LGPLv3 또는 GPLv2 선택. 상업 라이선스 별도 $500~$1,000/년 | 0원 (LGPLv3 의무만 이행) | **안 됩니다.** 공식 문서: *"For outbound injected packets, the `IfIdx` and `SubIfIdx` fields are currently ignored"* — 나가는 패킷의 출구 인터페이스를 못 고릅니다. NETWORK 계층에는 PID도 없습니다 | **됩니다** — Sectigo EV 서명(만료·미폐기) 위에 Microsoft 증명 서명이 중첩되어 있음을 실측 확인. 차단 목록에도 없음 | **조건부인데 불충분** |
| **VPN 업체 GPL 드라이버** (`mullvad-split-tunnel.sys`, `ProtonVPN.CalloutDriver.sys`, `windscribesplittunnel.sys`) | 소스는 GPL-3.0/MPL-2.0(Mullvad), GPL-3.0(Proton), GPL-2.0(Windscribe) | 소스는 0원. 하지만 직접 빌드하면 EV 인증서 + Partner Center 필수 | **정확히 됩니다.** Windscribe 코드에 포함 모드가 그대로 있습니다: `if (calloutData->isExclude) redirect(localIp) else redirect(vpnIp)` | 세 회사 바이너리 모두 Microsoft 증명 서명 확인. **다만 그 바이너리에는 라이선스가 없습니다** | **참고 설계용만** |
| **기타** (Wintun, WireGuardNT, tap-windows6, ovpn-dco-win, ProxiFyre, 라우팅 컴파트먼트) | 제각각 (Wintun 바이너리는 비-OSI, ProxiFyre는 AGPL-3.0) | 0원 | Wintun/WireGuardNT는 그냥 터널 어댑터라 앱 구분 기능 없음. `ovpn-dco-win`은 MIT지만 암호화 오프로드일 뿐. 라우팅 컴파트먼트는 인터페이스를 옮기는 사용자 모드 API가 없어서 막힘 | — | **해당 없음** |

### 렌즈끼리 갈린 지점과 제 판단

네 군데에서 조사 결과가 갈렸습니다. 어느 쪽을 믿는지 밝힙니다.

1. **WinpkFilter EULA를 MIT 저장소가 받아들일 수 있나.** `winpkfilter` 렌즈는 EULA에 *"The Software Product may be included in any free or non-profit packages or products"*가 있으니 가능하다고 봤고, `wiresock` 렌즈와 반박 검증은 불가능하다고 봤습니다. → **불가능 쪽을 믿습니다.** 우리 LICENSE.md는 받는 사람에게 *"sell copies"* 권리까지 줍니다. EULA는 바로 그 판매를 금지합니다. 우리가 줄 수 없는 권리를 준다고 적어 둔 저장소가 되고, 이건 포크한 사람에게 넘어가면서 계속 번집니다.

2. **WinDivert가 2026년 4월 교차 서명 신뢰 철회로 죽나.** 반박 검증은 위험하다고 봤고, `windivert` 렌즈는 이 PC에서 직접 `signtool`을 돌려 Microsoft 증명 서명이 중첩되어 있음을 확인했습니다. → **실측한 `windivert` 렌즈를 믿습니다.** 다만 실제 적재 시험은 아무도 안 했으므로 "서명은 통과, 적재는 미확인"입니다.

3. **업체 드라이버의 방향이 우리와 반대인가.** 반박 검증은 "제외 전용이라 우리 제품과 정반대"라고 했고, `mullvad-proton` 렌즈는 Windscribe/Proton 코드에 포함 모드가 그대로 있음을 인용했습니다. → **코드를 인용한 쪽을 믿습니다.** 방향은 걸림돌이 아닙니다. Mullvad만 제외 전용이고, Proton·Windscribe는 로컬 주소를 다시 쓰는 방식이라 방향을 자유롭게 고를 수 있습니다. **걸리는 건 방향이 아니라 서명과 라이선스입니다.**

4. **남은 최선이 무엇인가.** `alternatives` 렌즈만 "사용자 모드 전체 캡처 TUN 라우터"를 제시했고, 나머지는 드라이버 갈래 안에서만 봤습니다. → **`alternatives` 렌즈가 맞습니다.** 다만 그건 갈래 C가 아니라 완전히 다른 갈래이고, 2~4개월짜리 재작성입니다(6번 항목 참조).

---

## 3. 라이선스가 실제로 막는 것

우리 저장소는 공개된 MIT 저장소이고, GitHub Actions가 휴대용 EXE를 만들어 릴리스에 올립니다. 이 구조에서 법적 그림은 **"우리 EXE에 넣는다"**와 **"사용자가 직접 설치한다"**가 완전히 다릅니다.

### 3-A. 우리 EXE·릴리스 아티팩트에 넣는 경우 — 대부분 막힙니다

- **WireSock**: `https://www.wiresock.net/license/wiresock_eula` — *"WireSock Secure Connect is being distributed Freeware for personal (non-commercial), or educational ... use. It may not be distributed for profit, nor may it be included in products or otherwise distributed by commercial entities to their clients or customers without the prior written permission of the author."* 게다가 *"Its component parts may not be separated"*, *"You may not reverse engineer, decompile, or disassemble"*라서 `.sys`만 빼 오는 것도, 인터페이스를 알아내는 것도 금지입니다. → **막힙니다.**
- **WinpkFilter**: `https://www.ntkernel.com/windows-packet-filter/licensing/` — *"Windows Packet Filter is free for personal or educational use, including non-profit organizations."* 이건 쓸 권리이지 배포할 권리가 아닙니다. 배포는 Developer $3,000 / Source $9,000이고, 벤더 스스로 *"For those who need to redistribute the WinpkFilter drivers as part of their software, it is advisable to create or request a custom build"*이라고 안내합니다. 발급자별 커스텀 빌드는 MIT가 보장하는 "포크해서 마음대로 쓰기"와 구조적으로 안 맞습니다. → **막힙니다.**
- **VPN 업체 드라이버 바이너리**: 이게 가장 조용한 함정입니다. Mullvad 소스는 MPL-2.0 선택지가 있어서 MIT 프로젝트가 파일 단위로 같이 배포할 수 있습니다. 그런데 정작 필요한 **서명된 바이너리는 다른 저장소(`mullvad/mullvadvpn-app-binaries`)에 있고, 그 저장소에는 LICENSE 파일이 아예 없습니다.** GitHub API가 `"license": null`을 돌려줍니다. 권리 부여가 0입니다. 그걸 릴리스에 올리면 공개 저장소의 커밋 이력과 릴리스 자산에 저작권 침해 결과물이 영구히 남습니다. → **막힙니다.** Proton·Windscribe 바이너리도 같은 상태입니다.
- **상표 문제**(저작권과 별개): 파일명, INF의 `ManufacturerName="Mullvad AB"` / `"Proton AG"` / `"Windscribe Limited"`, 서비스 이름, 서명 주체가 전부 남의 브랜드입니다. 그리고 그 문자열은 Microsoft 카탈로그가 해시한 대상이라 **바꾸는 순간 서명이 깨집니다.** MPL-2.0 §2.3, GPL 모두 상표권은 안 줍니다.
- **WinDivert만 예외**: LGPLv3을 골라 동적 연결(`WinDivert.dll`)하면 우리 코드는 MIT로 유지할 수 있습니다. 의무는 (a) 라이브러리 사용 사실 고지, (b) GPL·LGPL 전문 동봉, (c) 저작권 표시, (d) 공유 라이브러리 방식 사용, 그리고 `.sys`를 릴리스에 올리므로 같은 릴리스에 `WinDivert-2.2.2-Source.zip`도 함께 올리기입니다. mitmproxy가 실제로 이렇게 하고 있습니다(본체 MIT, WinDivert를 담은 하위 패키지만 LGPL-3.0-or-later로 선언). → **법적으로는 통과. 그런데 기능이 안 됩니다**(4번·6번 참조).

### 3-B. 사용자가 직접 설치하는 경우 — 법적으로는 깨끗한데, 남는 게 없습니다

"README에 'WireSock을 직접 설치하세요'라고 적는다"는 어떤 라이선스도 위반하지 않습니다. 이 프로젝트는 이미 WireGuard for Windows에 대해 똑같이 하고 있고, 그게 지금 릴리스가 라이선스상 깨끗한 이유입니다.

그런데 실익이 없습니다.

- WireSock 무료판은 개인·비영리 전용입니다. 업무용 사용자는 각자 PRO $50을 사야 합니다. **비용이 사라진 게 아니라 사용자에게 넘어갈 뿐입니다.**
- WireSock Secure Connect는 그 자체가 완성된 WireGuard 클라이언트입니다. 사용자에게 "우리 제품이 하려던 걸 이미 다 하는 경쟁 제품을 까세요"라고 안내하는 셈입니다.
- 붙일 수 있는 접점은 CLI(`wiresock-client.exe run -config <path>`)와 설정 파일의 `#@ws:AllowedApps = chrome, msoffice` 뿐입니다. 명명 파이프도, REST도, gRPC도 없습니다. SDK 무료 등급은 *"Strictly non-commercial"*이고 재배포 불가, 상업 등급은 가격 비공개입니다.
- 게다가 정작 그 기능에 미해결 버그가 열려 있습니다. `wiresock/WireSockUI#93`(2024-12-13, 답변 없음): Windows 11 26100에서 `AllowedApps = msedge`인데 **모든 트래픽이 VPN으로 갑니다.** `#95`도 같은 내용으로 열려 있습니다.

**앞서 이 패턴을 끝까지 가 본 선례가 있습니다.** TunnlTo는 "오픈소스 GUI + 독점 드라이버" 조합이었고, WireSock의 비영리 제한을 그대로 물려받았고, 상업화했다가, 지금은 중단되었습니다. 저자의 결론: *"Using an open-source GUI for a proprietary driver offers little practical benefit."*

---

## 4. 서명·적재 관문

이 PC의 실제 상태를 측정했습니다(브리핑에서 "미확인"이라던 항목이 확정되었습니다).

| 항목 | 측정값 |
|---|---|
| OS | Windows 11 Pro 10.0.26200(.9168) x64 |
| Secure Boot | **꺼짐** (`Confirm-SecureBootUEFI` = False) |
| HVCI / 메모리 무결성 | **켜짐, 동작 중** (`SecurityServicesRunning=2`, `CodeIntegrityPolicyEnforcementStatus=2`) |
| Smart App Control | 꺼짐 (`VerifiedAndReputablePolicyState=0`) |
| 취약 드라이버 차단 목록 | **켜짐** (`VulnerableDriverBlocklistEnable=1`) |
| test signing / nointegritychecks | 둘 다 없음 |
| WDK 커널 헤더 | **없음** (`fwpsk.h` 부재, `Include\10.0.26100.0\km` 없음) |
| 이미 올라와 있는 남의 커널 네트워크 드라이버 | Realtek NDIS 필터 `nt_rtf64`, 그리고 `wireguard.sys` (Microsoft 증명 서명) |

여기서 나오는 결론 네 가지입니다.

**(1) 플랫폼은 문제가 아닙니다.** HVCI가 켜지고 차단 목록이 켜진 상태에서도 남의 NDIS 필터 드라이버가 이미 정상 동작 중입니다. 기술이 막는 게 아닙니다.

**(2) 우리가 통제하는 드라이버를 내보내려면 회사가 필요합니다.** Windows 10 1607 이후로 Microsoft가 서명하지 않은 새 커널 드라이버는 적재되지 않습니다. Microsoft 문서: *"Starting with Windows 10, version 1607, Windows will not load any new kernel-mode drivers which are not signed by the Dev Portal."* 증명 서명(attestation, HLK 시험 없음)만으로도 Windows 11 데스크톱에서는 충분하지만, 그러려면 ① Microsoft Entra ID 테넌트를 가진 검증된 법인, ② D-U-N-S로 조회되는 회사 정보, ③ EV 코드 서명 인증서, ④ Partner Center 등록과 서약 서명이 전부 필요합니다. EV 인증서는 DigiCert 정가 *"$62 / month / certificate"*(연 약 744달러), 리셀러 Sectigo EV는 연 280달러선, Certum은 *"from €359.00"*입니다. 게다가 2026년 2월 23일부터 최대 유효기간이 459일(약 15개월)로 줄어 **매년 갱신되는 고정비**이고, FIPS 하드웨어 토큰이나 HSM 보관이 의무입니다.

**(3) 제대로 된 길은 헌장을 어기지 않습니다. 지름길은 전부 어깁니다.** 올바르게 서명된 드라이버라면 사용자가 승낙할 것은 관리자 권한(UAC) 한 번뿐입니다. Secure Boot도, 메모리 무결성도, 차단 목록도 건드릴 필요가 없습니다. 반대로 Partner Center를 피하려는 모든 지름길 — `bcdedit /set testsigning on`, `nointegritychecks`, 코어 격리 끄기, 차단 목록 끄기 — 은 README 23행 *"다른 VPN, 광고 차단기, 보안 DNS, 백신을 자동으로 끄거나 바꾸지 않습니다"*를 정면으로 어깁니다. **어떤 형태로든 사용자에게 보안 설정을 낮추라고 안내하는 방안은 검토 대상에서 빼야 합니다.** 참고로 이 갈래를 이미 시도한 사람이 있습니다(`HaiPingCao/NRST`, Proton 드라이버 재사용). 서명 문제를 못 풀어서 사용자에게 test signing을 켜라고 요구합니다. 별 0개입니다.

**(4) 이 PC에서 잘 돌아가도 근거가 안 됩니다.** Secure Boot가 꺼져 있어서, Microsoft가 명시한 예외 *"Cross-signed drivers are still permitted if ... Secure Boot is off in the BIOS"*가 지금 적용되고 있습니다. 즉 **이 개발 PC는 실제 사용자 PC보다 관대합니다.** 여기서 드라이버가 올라갔다는 사실은 배포 근거가 되지 못합니다.

추가로 남의 드라이버를 공유해 쓸 때만 생기는 위험이 하나 있습니다. `ndisrd.sys`나 `WinDivert64.sys`가 **남의 취약점 때문에** Microsoft 차단 목록에 오르면, 우리 코드는 한 줄도 안 바뀌었는데 전 사용자에게서 동시에 고장 납니다. 차단 목록 기준에는 악성이 아니어도 *"circumvent the Windows Security Model"*이 포함되며, 트래픽 방향을 바꾸는 필터는 정확히 그 모양입니다. 이 프로젝트는 자동 업데이트도 범위 밖이라 회수 수단이 없습니다.

---

## 5. 아무도 안 말한 것

여기서는 완곡하게 쓰지 않겠습니다.

**앱별 라우팅은 이 릴리스의 범위가 아닙니다.** README "제품 범위와 현재 한계"의 "아직 릴리스 범위 밖인 항목"에 *"앱별 라우팅과 전체 IPv6 분할 라우팅"*이라고 직접 적혀 있습니다. `docs/v0.1.0-release-plan.md`에도 v0.1.0 이후로 미룬다고 적혀 있습니다.

**정작 범위 안에 있는 기능은 이미 작동합니다.** 루트 도메인·하위 도메인 사이트 규칙, YouTube·Netflix 미디어/CDN 확장 규칙, IPv4 사이트 경로와 대상 도메인 AAAA 보호, DNS 소유권 확인, 연결 해제 정리와 다음 실행 복구 — 이게 다 평범한 라우팅 테이블 조작과 DNS 관찰만으로 돌아갑니다. 커널 드라이버 없이, 서명 없이, 돈 없이 돌아갑니다.

**macOS는 이미 앱별 라우팅이 끝났습니다.** `NETransparentProxyProvider`로 서명된 Mac에서 11/11 통과했습니다. 즉 **플랫폼 동등성 압박이 Windows 드라이버를 지금 강제하지 않습니다.**

**그런데 v0.1.0은 아직 태그도 안 붙었습니다.** `docs/platform-parity-audit.md`는 *"no release tag should be created"*로 끝나고, 세 개의 게이트가 열려 있습니다. `docs/windows-release-hardening.md`에는 네 개가 더 있습니다. 그리고 같은 문서 7~9행에는 이렇게 적혀 있습니다: *"The owner chose unsigned distribution because a commercial code-signing certificate is not cost-effective for this release."*

**이 세 사실을 나란히 놓으면 이렇습니다.** 사용자 모드 코드 서명 인증서조차 "비용 대비 효과가 없다"고 판단한 프로젝트가, **범위 밖 기능** 하나를 위해 **더 비싼 EV 인증서 + 법인 등록 + Partner Center 관계 + 커널 드라이버 영구 유지보수**를 떠안는 것을, **아직 첫 릴리스도 못 낸 상태에서** 검토하고 있는 것입니다.

그리고 이번이 **세 번째**입니다. R3에서 사용자 모드 WFP로 두 번의 실측 시도, R3-DEC-04에서 UWP VPN 플러그인 조사(3/3 REFUTED), 그리고 이번 갈래 C. 세 번 연속으로 범위 밖 기능에 조사 역량을 썼고, 그동안 범위 안의 출시 관문 일곱 개는 그대로 열려 있습니다.

**여기에 몇 주를 더 쓰는 것은 잘못된 배분입니다.** 조사 자체는 잘 됐고 결과물도 값집니다 — 다만 그 값어치는 "지금 만들 것"이 아니라 "나중에 만들 때 처음부터 옳게 만들 수 있는 설계도"입니다.

---

## 6. 남은 후보 순위

앞으로 앱별 라우팅이 실제로 범위에 들어왔을 때를 가정한 순위입니다. **지금 착수하라는 뜻이 아닙니다.**

**1위 — 아무것도 만들지 않고 기록만 남기기.** 비용: 문서 작업 반나절. Windscribe·Proton 설계(사용자 모드에서 `FWPM_CONDITION_ALE_APP_ID` 필터 + provider context로 IP 전달, 커널에서 `ALE_BIND_REDIRECT`/`ALE_CONNECT_REDIRECT`에 `localAddressAndPort` 재작성)를 결정 기록에 보존합니다. 이 설계 정보는 공짜이고, 나중에 무엇을 하든 출발점이 됩니다.

**2위 — 기능 재정의: "이 앱이 접속한 도메인을 관찰해서 사이트 규칙으로 추가"하는 흐름.** 비용: 몇 주, 기존 기계장치 위에 얹음. 커널 없음, 인증서 없음, 라이선스 문제 없음. 실사용자가 원하는 것의 상당 부분("이 앱만 VPN으로")을 이미 도는 사이트 규칙으로 커버합니다. **가성비가 압도적으로 좋은 후보입니다.** 남는 위험은 앱 내부 DoH로 도메인 관찰을 우회하는 경우와, ETW DNS 이벤트가 요청한 앱의 PID를 제대로 주는지 미확인이라는 점입니다.

**3위 — 사용자 모드 전체 캡처 TUN 분할 라우터.** 비용: **2~4개월** 전면 재작성. Wintun 어댑터를 기본 경로로 올리고, 새 연결마다 `GetExtendedTcpTable`/`GetExtendedUdpTable` + `QueryFullProcessImageNameW`로 소유 프로세스를 알아낸 뒤, 고른 앱만 WireGuard로 보내고 나머지는 `IP_UNICAST_IF`로 물리 랜카드로 되돌려 보냅니다. mihomo와 sing-box가 Windows에서 실제로 이렇게 돌리고 있습니다. **우리 커널 드라이버도, EV 인증서도, Microsoft 증명 서명도, WDK도 필요 없습니다.** Wintun 배포 라이선스에는 *"except insofar as the Software is distributed alongside other software that uses the Software only via the Permitted API"*라는 예외가 있어 MIT 앱과 함께 배포 가능합니다(단 비-OSI 라이선스라 별도 고지 필요, 수정 금지). **대가**: VPN Router가 그 PC의 **모든** 트래픽을 책임지게 됩니다. 지금 제품의 "나머지 인터넷은 평소 네트워크에 그대로 둔다"는 안전 약속과 성격이 정반대로 바뀝니다. 착수 전 2시간짜리 선행 시험 필수 — **Wintun 0.14.1(2021년 이후 갱신 없음)이 HVCI 켜진 26200에서 아직 적재되는지** 확인.

**4위 — Windscribe/Proton 소스를 참고해 약 600행짜리 자체 WFP callout 드라이버 작성.** 비용: EV 인증서 연 280~900달러(15개월마다 재발급, HSM 필수) + 법인화 + Partner Center 등록·심사 + 커널 드라이버 영구 유지보수 + WDK 설치. 기능적으로는 가장 정확한 답이고, 방향(포함/제외)도 자유롭게 고를 수 있습니다. **이 프로젝트가 회사가 되기 전에는 불가능합니다.**

**5위 — WinDivert 기반.** 비용: 3위와 같은 사용자 공간 재발신 경로를 **똑같이** 다 만들어야 하고, 그 위에 2022-09-21 이후 갱신이 멈춘 드라이버와 원인까지 규명된 미수정 커널 오류(`0xD1`, issue #408, 수정 PR #409 미병합)를 얹습니다. 그 오류를 고치려면 우리가 EV 인증서로 재서명해야 하므로 4위 비용이 그대로 딸려옵니다. **3위의 완전한 하위 호환입니다. 고를 이유가 없습니다.**

**실격 — WireSock 번들, WinpkFilter 번들, 업체 서명 바이너리 재배포.** 3번 항목대로 라이선스가 막습니다.

**막다른 길로 확인된 것들**(다시 파지 마십시오):
- 터널 인터페이스에서 WFP로 차단하면 물리 랜카드로 되돌아갈 거라는 발상 → **틀렸습니다.** Windows는 ALE 인가보다 **먼저** 경로 조회로 출구 인터페이스를 정합니다. 차단은 폐기(`FWPM_LAYER_ALE_AUTH_CONNECT_V4_DISCARD`)일 뿐 재라우팅이 아닙니다. Mullvad가 드라이버를 만든 이유가 정확히 이것입니다.
- 라우팅 컴파트먼트(`SetJobCompartmentId`) → API는 실재하고 이 PC의 `iphlpapi.dll`에도 들어 있습니다. 그런데 **인터페이스를 다른 컴파트먼트로 옮기는 사용자 모드 API가 없습니다**(커널 NDIS 작업). 인터페이스 없는 컴파트먼트는 그냥 인터넷 없는 앱입니다.
- Windows Sandbox / 컨테이너 → 같은 이유로 막히고, GUI 앱도 못 돌립니다.
- 앱별 프록시 실행 인자(`--proxy-server`) → 가장 싸지만 **UDP와 QUIC이 죽습니다.** Chromium 문서: *"In Chrome SOCKSv5 is only used to proxy TCP-based URL requests. It cannot be used to relay UDP traffic."* 하필 YouTube·Netflix가 이 프로젝트의 대표 규칙입니다.

---

## 7. 권고

### 하나만 하십시오

**갈래 C를 "라이선스와 서명 관문 때문에 종결"로 기록하고 닫은 뒤, v0.1.0 출시 관문 일곱 개를 닫는 데 다음 몇 주를 쓰십시오.**

**바로 할 일 (이름까지 지정합니다):** `docs/R3-DEC-04-evidence-windows-wfp-live-2026-08-18.md` §13 (이 문서가 그 근거다)를 작성해 다음을 남기십시오.

1. **판정**: Windows 앱별 라우팅은 무기한 보류. 갈래 C 종결.
2. **핵심 사유 한 줄**: 앱별 라우팅을 하는 드라이버는 전부 소스뿐이라 우리가 서명해야 하고, 서명된 드라이버는 전부 앱별 라우팅을 못 한다.
3. **보존할 설계 자산**(공짜로 얻은 것, 이게 이 조사의 진짜 산출물입니다):
   - 올바른 구조 = 사용자 모드에서 `FWPM_CONDITION_ALE_APP_ID` 조건 필터 + provider context로 IP 전달, 커널 callout이 `ALE_BIND_REDIRECT_V4/V6`·`ALE_CONNECT_REDIRECT_V4/V6`에서 `localAddressAndPort`를 재작성. Windscribe `callout_filter.cpp` / Proton `Callout.cpp`가 완전한 참고 구현.
   - 포함 모드는 실제로 존재함: `if (calloutData->isExclude) redirect(localIp) else redirect(vpnIp)`.
   - 차단→물리 랜카드 되돌림은 원천적으로 불가(경로 조회가 ALE 인가보다 앞섬). 이걸로 R3-DEC-04의 "go kernel" 결론이 독립적으로 재확인됨.
   - 드라이버 없이 가능한 유일한 대안 = Wintun 전체 캡처 + `GetExtendedTcpTable`/`GetExtendedUdpTable` + `IP_UNICAST_IF` (mihomo·sing-box 방식).
4. **측정된 환경 사실**(재조사 금지): 26200.9168, Secure Boot 꺼짐, HVCI 켜짐·동작 중, Smart App Control 꺼짐, 취약 드라이버 차단 목록 켜짐, WDK 커널 헤더 없음. 그리고 **이 PC는 Secure Boot가 꺼져 있어 실제 사용자 환경보다 관대하므로 여기서의 적재 성공은 배포 근거가 되지 않는다**는 경고.
5. **재개 조건**: 앱별 라우팅이 정식으로 범위에 들어오면, 첫걸음은 코드가 아니라 **서류 결정**입니다 — "이 프로젝트가 법인을 만들고 EV 인증서를 상시 유지할 것인가?" 답이 아니오면 3위(사용자 모드 TUN)만 남고, 그마저도 Wintun HVCI 적재 2시간 선행 시험이 통과해야 합니다.

로드맵에 올릴 것은 하나뿐입니다: **"앱이 접속한 도메인을 관찰해서 사이트 규칙으로 추가하는 흐름"**(6번 2위). 이건 이미 있는 기계장치 위에 몇 주면 얹을 수 있고, 사용자가 실제로 원하는 것의 대부분을 커버합니다.

### 명시적으로 하지 말 것

- ❌ **EV 코드 서명 인증서를 사지 마십시오.** Partner Center 하드웨어 개발자 등록도 하지 마십시오. 이건 회사 설립 결정이지 개발 작업이 아닙니다.
- ❌ **어떤 `.sys` 파일도 저장소나 릴리스 자산에 넣지 마십시오.** 특히 `mullvad-split-tunnel.sys`, `ProtonVPN.CalloutDriver.sys`, `windscribesplittunnel.sys` — 이 셋은 라이선스가 **아예 없습니다**. 공개 저장소 이력에 한 번 들어가면 지울 수 없습니다.
- ❌ **WireSock이나 WinpkFilter 설치 관리자를 번들하거나, 설치 과정에서 내려받게 하지 마십시오.** 둘 다 영리 배포를 금지합니다.
- ❌ **NT Kernel에 $3,000을 쓰지 마십시오.** 돈이 아까워서가 아니라, 그 라이선스는 NetMD에게만 주어지고 MIT가 초대한 포크에게 넘어가지 않아서 구조가 안 맞습니다.
- ❌ **사용자에게 test signing, 메모리 무결성 끄기, 취약 드라이버 차단 목록 끄기를 요구하는 어떤 방안도 검토하지 마십시오.** README 23행 위반입니다.
- ❌ **"README에 WireSock 설치 안내를 넣자"도 하지 마십시오.** 법적으로는 깨끗하지만, 사용자에게 우리 제품의 목표를 이미 다 하는 경쟁 제품을 설치시키면서, 업무용 사용자에게는 $50을 떠넘기고, 정작 그 기능에는 미해결 버그(`#93`, `#95`)가 열려 있습니다. TunnlTo가 이 길 끝까지 가서 문을 닫았습니다.
- ❌ **네 번째 앱별 라우팅 조사를 시작하지 마십시오.** 세 번의 조사가 같은 벽 — 서명과 라이선스 — 을 세 방향에서 확인했습니다. 벽의 위치는 이제 충분히 압니다.

### 솔직한 마무리

**지금 이 중에 할 만한 것은 없습니다. 되는 걸 출시하십시오.** 사이트 기반 라우팅은 이미 작동하고, 커널도 인증서도 필요 없고, macOS 앱별 라우팅은 이미 끝났습니다. v0.1.0을 막고 있는 건 드라이버가 아니라 검증 게이트 일곱 개입니다. 그걸 닫으십시오.
