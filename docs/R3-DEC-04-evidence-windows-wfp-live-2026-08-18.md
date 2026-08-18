# R3-DEC-04 근거표와 결정 — Windows 사용자 모드 WFP 앱 라우팅 (2026-08-18)

> 실기 기록: `%LOCALAPPDATA%\VpnRouter\wfp-spike-runs\` 아래 `20260818-110619Z-8ea6080d`(정방향) · `20260818-114242Z-d6ea0286`(역방향) · `r4-cause`(정책 상태 덤프)
> 절차: `docs/windows-wfp-live-run-runbook-v2-2026-08-17.md`
> 앞 시도: 2026-08-10(부분) · 2026-08-17(중단, 31분 끊김) — 둘 다 근거를 못 냈다

## 0. 한 줄

**Windows 사용자 모드 WFP 의 `FwpmConnectionPolicyAdd0` + `NEXT_HOP_INTERFACE` 가 실제 라우팅을 바꾸지 않았다.** 정책·조건·다음 홉이 모두 올바른 상태에서 **양방향으로** 확인했다. 트래픽은 두 번 다 정책이 아니라 경로표를 따랐다.

**결정(§7): 커널 driver 연구로 넘어간다.**

---

## 1. 실기 조건 (전부 실측)

| 항목 | 값 |
|---|---|
| 터널 | WireGuard split-tunnel · `AllowedIPs = 1.1.1.1/32` · 터널 index **54** |
| 서버 생존 | 손잡기 **3초** 성공(받은 124바이트) · 터널 너머 ping `OK` |
| 기준 인터페이스 | **8** (Wi-Fi 2) — `Up` 인 어댑터가 이것 하나뿐 |
| 대상 | `1.1.1.1:443` TCP · 고른 앱 `msedge.exe` · 안 고른 앱 `chrome.exe` |
| 소유 정책(시작 전) | **0건** · 세 신호 `AGREE` |
| 제3자 제품 | 5종 관측 · 실행 전후 **무변화** |
| Windows | 26200 · pwsh 7.6.5 |

**서버 설정이 만료돼 있었다.** 옛 설정은 15초 동안 손잡기 요청 592바이트를 보내고 **0바이트**를 받았다. 새로 받은 설정은 **3초 만에 124바이트**를 받았다. 이 확인에 36초가 걸렸고, 같은 조건에서 2026-08-17 은 31분 끊김을 치렀다.

---

## 2. 시험 1 — 정방향 (경로를 지우고, 고른 앱을 터널로 당김)

경로 처리: 터널이 심은 `1.1.1.1/32` 를 **지우기 전에 실제로 터널로 향하는 것을 확인**하고 지웠다(54 → 8).
관찰 A(정책 전): 안 고른 앱이 `BASELINE`(8) · 꾸러미 234 — 터널이 기본 경로를 안 가져갔음이 확인됐다.

| 사례 | 앱 | 기대 | **관측** | 인터페이스 | 꾸러미 | 흐름 |
|---|---|---|---|---|---|---|
| **`M-001`** | **고른 앱(Edge)** | `VPN` | **`BASELINE`** | **8** | 226 | `OK` |
| `M-005` | 고른 앱 + 겹치는 경로 | `VPN` | `UNOBSERVED` | — | 2 | `OK` |
| `M-017` | 안 고른 앱(Chrome) | `BASELINE` | `BASELINE` | 8 | 240 | `OK` |
| `M-021` | 안 고른 앱 + 겹치는 경로 | `BASELINE` | `UNOBSERVED` | — | 3 | `OK` |

꾸러미 수준(`M-001`): 대상으로 가는 105줄의 **출발 주소가 전부 `192.168.1.78`**(랜 주소)이고 **터널(54)에서 잡힌 꾸러미는 0개**.

**이 시험의 약점**: 단계 4 가 터널의 유일한 대상 경로를 지웠으므로, 「정책이 가리킨 인터페이스에 쓸 경로가 없어서 못 골랐다」는 설명이 남았다. 그래서 시험 2 를 했다.

---

## 3. 시험 2 — 역방향 (경로를 살리고, 안 고른 앱을 기준으로 밀어냄)

**약점을 없애는 설계**다. 경로를 지우지 않으므로 정책이 가리키는 인터페이스(8)에는 `1.1.1.1` 로 가는 **멀쩡한 기본 경로가 있다.** 정책이 고를 대상이 실제로 존재한다.

이 실행에서는 이름표의 뜻이 뒤집힌다 — **읽을 때 주의할 것.**

| 하네스 이름표 | 이 실행에서의 뜻 |
|---|---|
| `-LiveInterfaceIndex 8` | 정책이 가리키는 다음 홉 = Wi-Fi(기준) |
| `selectedAppPath` = Chrome | 정책이 **미는** 앱 |
| `VPN` 판정 = 인터페이스 **8** | 정책이 일한 것 |
| `BASELINE` 판정 = 인터페이스 **54** | 경로가 한 것 |

관찰 A(정책 전): Edge 가 `BASELINE`(54) — 경로가 살아 있어 모두가 터널로 가는 상태가 확인됐다.

| 사례 | 앱 | 정책 | 기대 | **관측** | 인터페이스 | 꾸러미 |
|---|---|---|---|---|---|---|
| **`M-001`** | **Chrome** | **→ 8 로 밀어냄** | `VPN`(=8) | **`BASELINE`** | **54** | 32 |
| **`M-005`** | Chrome + 겹치는 경로 | → 8 | `VPN`(=8) | **`BASELINE`** | **54** | 56 |
| `M-017` | Edge (정책 없음) | — | `BASELINE`(=54) | `BASELINE` | 54 | 34 |
| `M-021` | Edge + 겹치는 경로 | — | `BASELINE`(=54) | `BASELINE` | 54 | 51 |

**네 사례 전부 인터페이스 54 로 갔다.** 정책 대상이든 아니든 같다. 흐름은 전부 `OK`.

---

## 4. 정책이 실제로 어떻게 걸렸는가 (실행 중 상태 덤프)

정책이 걸린 순간에 `netsh wfp show state` 를 떠서(5.4MB) 직접 읽었다. 소유 정책 **2** · 세션 **1** · 하네스 **1**.

> 소유 GUID 4개 중 2개만 있는 것은 정상이다. `0601`=DesktopIpv4 · `0602`=DesktopIpv6 는 있고, `0603`·`0604`=Package 는 `-LivePackageFamilyName ''` 로 건너뛰었으므로 없다.

**IPv4 필터 원문**

```
계층      FWPM_CALLOUT_OUTBOUND_NETWORK_CONNECTION_POLICY_LAYER_V4
동작      FWP_ACTION_CALLOUT_TERMINATING
조건      FWPM_CONDITION_ALE_APP_ID = FWP_MATCH_EQUAL
          \device\harddiskvolume3\program files (x86)\microsoft\edge\application\msedge.exe
컨텍스트   {32458d2e-…-c70601} → FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP_INTERFACE
가중치     10000
```

**다음 홉 LUID 해독**: `14918723538255872` → `IfType=53`(가상) · `NetLuidIndex=32769` → **정확히 `r4split` 터널(index 54)**. 같은 기계의 `VPN Unlimited TAP`(32768) · 이더넷(IfType 6) · Wi-Fi(IfType 71) 어느 것도 아니다.

**쓴 API**: `NativeMethods.cs:19` 이 `FwpmConnectionPolicyAdd0` 을 그대로 호출한다. 손으로 흉내 낸 것이 아니다.

---

## 5. 배제된 가설

| 가설 | 배제 근거 |
|---|---|
| 정책이 안 걸렸다 | 실행 중 상태 덤프에 존재 (소유 정책 2 · 세션 1 · 하네스 1) |
| 잘못된 API 를 썼다 | `FwpmConnectionPolicyAdd0` — Microsoft 문서가 **process-based routing** 용으로 지목한 함수 |
| 앱 신원이 안 맞았다 | `ALE_APP_ID` 가 실행 파일 장치 경로를 정확히 가리킴 |
| 잘못된 인터페이스를 가리켰다 | LUID 해독 결과 정확히 터널(54) |
| 다음 홉에 쓸 경로가 없었다 | **시험 2 에서 경로가 있는데도 안 먹음** |
| 측정 수단이 실패했다 | 여덟 사례 전부 `flowStatus: OK` · 꾸러미 32~240개 관측 |

---

## 6. 문서가 말하는 것

Microsoft 공식 문서:

> **`FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4`** — A callout layer where **a WFP filter driver** can inspect an outgoing IPv4 connection and **read/write the routing policy** that was configured for this connection. See `FwpmConnectionPolicyAdd0`.

> **`FwpmConnectionPolicyAdd0`** — allows you to configure more expressive routing policies for outbound connections, and thereby to enable more complex scenarios such as source address-based routing, **process-based routing**, port-based routing, and others.

두 문장을 함께 읽으면 이렇게 읽힌다 — 사용자 모드에서 정책을 **등록**할 수는 있으나, 그 계층에서 정책을 **집행**하는 주체는 커널 모드 filter driver 다. 드라이버가 없으면 등록된 정책이 아무 일도 하지 않는다.

**다만 이것은 문서 문장에서 읽어 낸 해석이지 실측이 아니다.** 확정하려면 커널 드라이버를 만들어 봐야 하고, 그것이 곧 아래 결정이 가리키는 방향이다.

출처: [Filtering layer identifiers](https://learn.microsoft.com/en-us/windows/win32/fwp/management-filtering-layer-identifiers-) · [FwpmConnectionPolicyAdd0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmconnectionpolicyadd0)

---

## 7. 결정 — `R3-DEC-04`

**결정: 커널 driver 연구로 넘어간다.**
**결정자: 사용자 · 결정일: 2026-08-18 · 근거: 이 문서 §2~§6**

R4 프리브리프가 "R4·R5 는 근거만 모으고 결정하지 않는다"로 정해 둔 대로, 근거가 갖춰진 이 시점에 사용자가 결정했다.

**함께 닫히는 것**
- 사용자 모드 WFP 로 Windows 앱별 라우팅을 계속 시도하는 갈래는 닫는다
- `R3-DEC-01`(helper·renderer 자동 포함)·`R3-DEC-02`(기존 연결 처리)는 이 결과를 **근거로만** 받는다. 사용자 모드 경로가 닫혔으므로 그 두 물음은 커널 방향에서 다시 물어야 한다

**대비**: macOS 는 `NETransparentProxyProvider` 로 같은 제품 목표를 달성했다 (R3, `signedMac` PASS 실행 11 · 통과 11 · 실패 0). Windows 는 OS 가 사용자 모드에 같은 수준의 정식 수단을 주지 않는다는 것이 이번 결론이다.

---

## 8. 이번 실기의 안전 (전부 실측)

| 확인 | 정방향 | 역방향 |
|---|---|---|
| `cleanupOutcome` | `PASS` | `PASS` |
| `beforeAfterFingerprint` | `MATCH` | `MATCH` |
| 소유 WFP 정책(끝난 뒤) | 0건 · 세 신호 `AGREE` | 0건 · `AGREE` |
| 제3자 제품 5종 | 무변화 | 무변화 |
| 터널 서비스 · 어댑터 · pktmon 거르개 | 0 · 0 · 없음 | 0 · 0 · 없음 |
| **인터넷 끊김** | **0** | **0** |
| 걸린 시간 | 3.0분 | 1.4분 |

---

## 9. 이 결과로 평가하면 안 되는 것

**결과 JSON 의 `verdict: FAIL` 을 "측정 실패"로 읽으면 안 된다.** FAIL 이 한 건이라도 있으면 전체가 FAIL 인 설계이고, 여기서 FAIL 은 **"정책 대상 앱이 기대한 인터페이스로 안 갔다는 사실을 측정했다"** 는 뜻이다. 그것이 이 실기가 알고자 한 것이고, 실제로 알아냈다.

못 잰 것들은 전부 근거와 함께 닫혔다 — UDP·QUIC·DNS 는 브라우저로 흐름을 만들 수단이 없고, IPv6 16건은 이 회선에 없고, 패키지 32건은 신원 증명 코드가 아직 없다(`R3-DEC-05` 미결).

---

## 10. 승인 기록 (GR-17)

`-LiveOwnerConfirmation 'APPLY LIVE WFP'` 를 **AI 가 명령줄에 입력했다.** 사용자가 2026-08-18 이 세션에서 명시 승인했다. 저장소 안 코드가 이 값을 채우는 일은 0건이다.

## 11. 이 문서가 안 하는 것

- 커널 driver **설계·구현** — 이 문서는 방향 결정까지다
- `R3-DEC-05`(패키지 신원) 결정 — 미결 유지
- 설정 파일 내용 기록 — 경로와 바꾼 항목 이름만 적었다
