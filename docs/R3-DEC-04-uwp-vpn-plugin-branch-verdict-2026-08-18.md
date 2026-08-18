# R3-DEC-04 재개 판정서 — Windows 앱별 라우팅 UWP VPN 플러그인 갈래

작성일: 2026-08-18
대상 결정: **R3-DEC-04** (Windows 앱별 라우팅 방식 결정)
조사 인원: 조사 6명 / 반박 3명 (조사 1명은 결과 없이 실패 — 5절 주의사항 참조)

---

## 1. 판정

**조건부 GO — 단, "제품을 만들자"가 아니라 "반나절짜리 판별 시험을 딱 한 번 해보자"는 조건부 GO입니다.**

- 반박 담당 **3명 중 3명 전원이 REFUTED** 판정을 냈습니다.
- 조사 담당 6명 중 **단 한 명도** 이 조합이 실제로 동작한 사례(제품·샘플·블로그·이슈·논문 어디에서도)를 찾지 못했습니다.
- 그럼에도 조건부 GO인 이유는 딱 하나입니다. **시험 비용이 거의 0에 가깝기 때문입니다.** 새로 깔 것이 없고, 코드는 이미 컴파일까지 끝났으며, 되돌리기는 명령 두 줄입니다. 반면 커널 드라이버 갈래는 시작하는 데만 며칠이 듭니다.

> 솔직한 한 줄 요약: **문서는 "된다"고 읽히지만, 11년 동안 아무도 해본 적이 없고, 반박 담당 세 명이 각각 다른 이유로 "안 될 것"이라고 했습니다.** 기대값은 실패 쪽에 두시고, 실패를 빨리 확인하는 데 시험의 목적을 두시기 바랍니다.

**기한 상한: 실제 작업 4시간, 달력 기준 1일.** 이 안에 3단계 관측이 끝나지 않으면 무조건 중단하고 커널 갈래로 넘어갑니다.

---

## 2. 무엇이 확실해졌나

"문서에 적혀 있다"와 "이 컴퓨터에서 실제로 확인했다"를 엄격히 구분해서 적습니다.

### 2-A. 실제로 이 컴퓨터에서 관측된 것 (관측)

| # | 관측 사실 | 근거 |
|---|---|---|
| O1 | `windows` 크레이트 **0.28** (참조 구현이 고정해 쓰는 버전)에 `StartWithTrafficFilter`, `VpnTrafficFilter`, `VpnTrafficFilterAssignment`, `VpnAppId`, `VpnAppIdType`, `VpnRoutingPolicyType`이 **이미 다 있습니다.** 크레이트 올릴 필요 없습니다. | `C:\Users\NetMD\.cargo\registry\src\index.crates.io-1949cf8c6b5b557f\windows-0.28.0\src\Windows\Networking\Vpn\mod.rs:2365`(StartWithTrafficFilter, 내부에서 `IVpnChannel2`로 캐스팅), `:2013`(VpnAppId::Create), `:6357`(VpnTrafficFilter::Create), `:6422`(VpnTrafficFilterAssignment) |
| O2 | 참조 구현(wireguard-uwp-rs)이 **Rust 1.97.1로 지금 이 컴퓨터에서 깨끗하게 빌드됩니다.** 종료코드 0, 2분 57초, 오류 0. `wireguard_uwp_plugin.dll`과 `wireguard-uwp.exe`가 나옵니다. | 조사(codebase) 실측 빌드 로그 |
| O3 | 앱별 필터를 넣는 **패치도 그 위에서 깨끗하게 빌드됩니다.** 종료코드 0, 20.7초, 새 경고 0. | 패치 파일: `C:\Users\NetMD\AppData\Local\Temp\claude\C--dev-vpn-router\f2e28a03-be97-467a-b864-d8688123e368\scratchpad\per-app-traffic-filter.patch` / 빌드 트리: `...\scratchpad\wg-baseline` |
| O4 | **관리자 권한만 있으면** (SYSTEM도, MDM 등록도, Intune도 필요 없이) 이 워크그룹 PC에서 앱별 `TrafficFilter`가 들어간 **플러그인 VPN 프로필을 실제로 만들 수 있었습니다.** msedge.exe 경로를 넣으니 플랫폼이 `Type=FilePath`로 알아서 판정했고, MSTeams PFN은 `Type=PackageFamilyName`으로 판정했습니다. | 조사(profile-creation) 실행 결과. `root\cimv2\mdm\dmmap` / `MDM_VPNv2_TrafficFilterList02_App04` 읽기 결과 |
| O5 | 위 프로필은 **깨끗하게 삭제되었고 기준 상태가 복원**되었습니다. VPN 프로필 0개, Wi-Fi 2 (ifIndex 8) 정상, 1.1.1.1 도달 정상. | 같은 출처 |
| O6 | AppxManifest에 **`windows.vpnPlugin`이라는 확장 범주는 존재하지 않습니다.** makeappx가 거부하며 유효 목록을 출력합니다: `windows.backgroundTasks / windows.preInstalledConfigTask / windows.updateTask / windows.restrictedLaunch`. 올바른 형태는 `windows.backgroundTasks` + `<uap:Task Type="vpnClient"/>` 입니다. | makeappx 10.0.26100.8249 실제 실행 + `AppxManifestTypes.xsd:695-702`, `:1125-1132` |
| O7 | makeappx는 **제한 기능(rescap) 이름을 검증하지 않습니다.** `networkingVpnProviderBogus`라고 오타를 내도 패키징이 성공합니다(종료코드 0). 오타는 배포 시점에야 터집니다. 눈으로 확인해야 합니다. | 같은 출처(음성 대조 시험) |
| O8 | `VpnClient` PowerShell 모듈에는 **트래픽 필터를 다루는 명령이 하나도 없습니다.** 이름에 `TrafficFilter`가 들어간 명령이 이 컴퓨터 전체에 0개입니다. `Add-VpnConnection -PlugInApplicationID`는 프로필만 만들 뿐입니다. | 실제 `Get-Command` 실행 |
| O9 | 로컬 참조 클론이 **깨끗한 상태가 아닙니다.** `plugin/src/config.rs`, `plugin/src/plugin.rs`에 커밋되지 않은 수정이 이미 들어 있고, 그 수정이 바로 지금 검증하려는 그 코드입니다(`<TunnelApp>` 요소 → FilePath → ForceAllTrafficOverVpn). **upstream 코드라고 착각하면 안 됩니다.** | `git status` / `git show HEAD:plugin/src/plugin.rs \| grep -c -i trafficfilter` → **0** |

### 2-B. 마이크로소프트 문서에만 적혀 있는 것 (문서)

| # | 문서 사실 | 출처 |
|---|---|---|
| D1 | `VpnAppId`의 Win32 앱 식별자는 **파일 경로 또는 FQBN**입니다. `VpnAppIdType.FilePath = 2`. | https://learn.microsoft.com/en-us/uwp/api/windows.networking.vpn.vpnappid , .../vpnappidtype |
| D2 | `VpnRoutingPolicyType`은 값이 둘뿐입니다. `SplitRouting=0`("앱이 스플릿 터널되어 다른 인터페이스로도 통신 가능"), `ForceAllTrafficOverVpn=1`("앱이 VPN 인터페이스로 강제 터널됨"). | .../vpnroutingpolicytype |
| D3 | **`StartWithTrafficFilter`의 `IVectorView` 오버로드는 1803이 아니라 Windows 10 10240부터 있습니다.** 1803(계약 v6.0)이 필요한 건 다중 전송(`IIterable`) 오버로드뿐입니다. **즉 이 기능은 2015년부터 존재했습니다.** (사전 브리핑의 "1803에 추가" 서술은 정정이 필요합니다.) | .../vpnchannel.startwithtrafficfilter |
| D4 | 제한 기능(rescap)은 **사이드로드에 마이크로소프트 승인이 필요 없습니다.** "you can sideload apps that declare restricted capabilities without needing to receive any approval. Approval is only required when submitting these apps to the Store." | https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations |
| D5 | VPNv2 CSP의 `TrafficFilterList`는 **Pro 에디션에서도 지원**됩니다(Home만 제외). 이 PC는 Pro입니다. | https://learn.microsoft.com/en-us/windows/client-management/mdm/vpnv2-csp |
| D6 | `mtuSize`는 "at most 1400", `maxFrameSize`는 "<=1500, 플랫폼이 1500으로 제한". **참조 구현은 1500/1600으로 둘 다 어깁니다.** | .../vpnchannel.startwithtrafficfilter , `plugin/src/plugin.rs:231-232` |
| D7 | `StartWithTrafficFilter`는 `Start`와 달리 5번째 인자가 `VpnDomainNameAssignment`입니다(`Start`는 `VpnNamespaceAssignment`). **다른 타입이라 DNS 쪽 코드를 통째로 바꿔야 합니다.** | windows-0.28.0 `mod.rs:2371` vs `Start`의 시그니처 |
| D8 | 전송 소켓은 호출 시점에 **연결되어 있지 않아야 한다**고 문서에 적혀 있습니다. 그런데 참조 구현은 `plugin.rs:222`에서 먼저 `ConnectAsync().get()`을 하고 `:225`에서 `Start`를 부릅니다. | .../vpnchannel.startwithtrafficfilter , `plugin.rs:222,225` |

---

## 3. 무엇이 반박되었나

**이 절이 이 문서에서 가장 중요합니다.** 반박 담당 세 명이 각각 다른 각도에서 들어갔는데, 세 명 다 REFUTED를 냈습니다.

### 3-A. 【치명】 "허용 목록"과 "경로 지정"은 다른 것입니다 — 반박1(refute-api), 반박2(refute-reality) 공통

이게 핵심입니다. 두 사람이 독립적으로 같은 결론에 도달했습니다.

**윈도우에는 앱별 라우팅 테이블이 없습니다.** 라우팅 테이블은 컴퓨터에 하나뿐이고, 목적지 주소만 보고 인터페이스를 고릅니다. 앱 정보가 들어갈 칸 자체가 없습니다.

`VpnTrafficFilter`가 할 수 있는 일은 **"이 VPN 인터페이스를 어떤 앱이 써도 되는가"를 정하는 것**뿐입니다. **"어떤 앱을 이 VPN 인터페이스로 데려올 것인가"가 아닙니다.**

문서 문장이 전부 "허용" 언어입니다. 하나도 "재지정" 언어가 아닙니다.

- `VpnTrafficFilter` 클래스 설명: "A description of the type of network traffic that will be **ALLOWED OVER** the VPN connection."
- `AppId` 속성: "Gets or sets the ID of the app that is **ALLOWED BY** this traffic filter"
- VPNv2 CSP `TrafficFilterList`: "A list of rules **ALLOWING TRAFFIC OVER** the VPN Interface." / "Once a TrafficFilterList is added, **all traffic is blocked** other than the ones matching the rules."
- VPNv2 CSP `App`: "Per App VPN Rule. This will **ALLOW ONLY** the Apps specified **TO BE ALLOWED OVER** VPN Interface."
- VPN 보안 기능 문서: "IT admins can use Traffic Filters to apply **interface-specific firewall rules** to the VPN Interface." — **방화벽 규칙이라고 직접 적어놨습니다.**
- 마이크로소프트 자체 앱별 VPN 예제의 주석: "Microsoft Edge is configured as split tunnel, so whether data goes over VPN or the physical interface is **dictated by the routing configuration**." — 인터페이스를 고르는 건 라우팅이라고 명시.
- VPN 라우팅 문서: "**Network routes are required for the stack to understand which interface to use** for outbound traffic." / "**The only implication of force tunnel is the manipulation of routing entries**: VPN V4 and V6 default routes (for example 0.0.0.0/0) are added to the routing table..."

그리고 플러그인이 쓸 수 있는 유일한 라우팅 API인 `VpnRouteAssignment`의 멤버 전체는 다음 다섯 개입니다: `Ipv4InclusionRoutes`, `Ipv6InclusionRoutes`, `Ipv4ExclusionRoutes`, `Ipv6ExclusionRoutes`, `ExcludeLocalSubnets`. **어디에도 AppId가 없습니다.**

그래서 원하는 결과가 두 갈래로 갈리는데 둘 다 실패합니다.

**갈래 A — 터널에 좁은 경로만 있는 경우 (지금 r4split.conf 상태, AllowedIPs=1.1.1.1/32)**
Edge가 8.8.8.8로 가려 하면 라우팅 테이블은 Wi-Fi를 고릅니다. `ForceAllTrafficOverVpn`은 경로를 만들어내지 못하므로, 기껏해야 Edge가 Wi-Fi로 나가는 걸 막습니다. → **Edge는 터널로 가는 게 아니라 인터넷이 아예 끊깁니다.** 터널 인터페이스 패킷 0개. **R3 WFP 실패와 똑같은 모양입니다.**

**갈래 B — 터널에 기본 경로(0.0.0.0/0)를 주는 경우**
모든 앱이 터널을 선호하게 됩니다. 그다음 "필터 목록이 붙는 순간 나머지는 전부 차단" 규칙이 발동해서 **Chrome이 차단됩니다.** Wi-Fi로 넘어가는 게 아니라 그냥 막힙니다. → 청구 주장의 후반부("다른 앱은 계속 Wi-Fi로")가 성립하지 않습니다.

**세 번째 갈래는 없습니다.** 제외 경로도 목적지 기반이고 전역입니다. 두 번째 프로필을 동시에 띄우는 것도 안 됩니다(Device Tunnel은 IKEv2 전용 + 도메인 가입 Enterprise/Education 전용 + "third-party 제어 미지원").

> **제가 이 해석에 동의하는 이유**: 조사(api-spec)는 CSP의 "ForceTunnel: all IP traffic **must** go through the VPN Interface **only**"를 "라우팅 테이블을 무시하고 강제로 보낸다"로 읽었습니다. 반박1은 같은 문장을 "다른 데로 못 나간다는 금지"로 읽었습니다. **저는 반박1 쪽이 맞다고 봅니다.** 이유는 바로 옆 SplitTunnel 설명이 "only the traffic meant for the VPN interface (**as determined by the networking stack**) goes over the interface"라고 되어 있기 때문입니다. 인터페이스를 고르는 주체가 네트워크 스택(=라우팅 테이블)이라고 마이크로소프트가 스스로 적어놨습니다. 그리고 `ForceAllTrafficOverVpn`이 실제로 무엇을 하는지에 대한 Remarks가 참조 문서에 **아예 없습니다.** 마이크로소프트가 설명하기를 포기한 부분에 몇 주를 걸 수는 없습니다.
>
> **다만 이건 문서 해석이지 관측이 아닙니다.** 그래서 NO-GO가 아니라 조건부 GO입니다.

### 3-B. 【치명】 마이크로소프트가 "Win32 앱 ID는 아예 쓰지 마라"고 했습니다 — 조사(counter-evidence) + 반박2

`MicrosoftDocs/winrt-api` 이슈 #1798 (2020-09-02 개설, 2021-03-26 미해결 종료)

개발자 bdbai의 보고:
- 패키지 앱(PFN) `VpnAppId`만 넣으면 → `VpnPacketBuffer`에서 AppId가 정상적으로 나옴
- **Win32 `VpnAppId`만 넣으면 → 어떤 `VpnPacketBuffer`도 AppId를 실어오지 않음**
- **둘을 섞으면 → `Windows.Networking.Vpn.dll`에서 액세스 위반이 나며 VPN 프로세스 전체가 죽음**

7개월간 기능 팀에 에스컬레이션한 끝에 마이크로소프트 문서 담당자(stevewhims)가 남긴 종료 코멘트:

> "It's looking like we're able to reproduce **a data corruption** that's causing the crash you saw. I think for the time being (that is, until the root cause of the issue can be located and corrected within the platform), **it seems safest to avoid using Win32 appids at all.**"

**고쳤다는 발표도, KB도, 문서 각주도 5년째 없습니다.** 26200에서 고쳐졌는지는 밖에서 알 방법이 없습니다.

이 주장이 딛고 선 바로 그 지점 — `VpnAppIdType.FilePath` + Win32 실행 파일 — 을 마이크로소프트가 "쓰지 마라"고 한 겁니다.

**시험 시 필수 안전 규칙: PFN 필터와 FilePath 필터를 절대 한 `VpnTrafficFilterAssignment`에 같이 넣지 마십시오.** 별도 실행으로 분리합니다.

### 3-C. 【치명】 데이터 경로가 백그라운드 작업 안에 있고, 그 수명은 윈도우가 정합니다 — 반박3(refute-packaging)

반박3은 흥미롭게도 **권한/패키징 쪽은 깨지 못했습니다.** 사이드로드 + rescap는 정말로 됩니다. 자체 서명 인증서도 필요 없습니다(`Add-AppxPackage -Register`). UDP 소켓도 문제없습니다. 26200에 배관도 다 살아 있습니다.

대신 **수명(lifetime)** 에서 깼습니다.

- 모든 패킷이 `vpnClient` 백그라운드 작업 안의 `Encapsulate`/`Decapsulate`를 지나갑니다. 그 작업의 생사는 윈도우 앱 수명 정책과 **사용자에게 노출된 "백그라운드 앱" 권한**이 결정합니다. 우리 코드가 아닙니다.
- MS Q&A 264773: 정상 동작하던 C++/WinRT 플러그인이 **연결 2~5분 뒤 `Encapsulate` 호출이 조용히 멈추는데 시스템은 계속 "연결됨"으로 표시**됩니다. 보고자 원문: "The same functionality works perfectly when programmed with low-level Win32 API, suggesting the root cause relates to UWP resource management (thread pool, background task limitations)." 마이크로소프트 답변은 유료 지원 티켓 안내였고, 공개 해결책은 없습니다.
- 마이크로소프트 **자기네 1st-party UWP VPN 플러그인(Azure VPN Client)** 도 Windows 11에서 "VPN Platform did not trigger connection"으로 실패하며, 대표 해결책이 **설정 > 앱 > Azure VPN Client > 백그라운드 앱 권한 > 항상**입니다. 그리고 "The Azure VPN is getting suspended now and then... **This issue is only noticed on Windows 11 users and not Windows 10.**"
- 탈출구도 막혀 있습니다. `extendedBackgroundTaskTime`은 실행 시간 제한만 풀고 "still subject to all other memory and energy usage limits"이며, 실제로 시도한 개발자는 "that didn't seem to affect anything"이라고 보고했습니다.
- **WireGuard에 특히 나쁩니다.** 참조 구현 README가 인정합니다: 플러그인은 주기적 작업을 스스로 못 하고, keepalive 간격은 "cannot be controlled by the plugin author or the user but rather the platform itself"입니다. Noise 재키(약 120초)와 핸드셰이크 재시도가 타이머 기반인데 타이머를 못 씁니다. **서버 쪽 PersistentKeepalive에 의존해야 합니다** — 주장에 없던 외부 의존성입니다.
- 출구가 없습니다. Windows App SDK에 VPN 플러그인 API가 없습니다. `microsoft/WindowsAppSDK#3419`에서 마이크로소프트 담당자: "We reached out to the owner of this API who confirmed it doesn't work in Win32, we don't have a timeframe of when or if this will be supported in the future."

### 3-D. 【강함】 11년 동안 아무도 안 했습니다 — 조사(counter-evidence) + 반박2

- **한 업체가 실제로 시도했다가 버렸습니다.** VMware Workspace ONE Tunnel은 원래 UWP VPN 플러그인이었는데 2020년 1월 네이티브 Win32 클라이언트로 갈아엎었습니다. 사유: "The UWP app relies on the native Windows 10 per-app VPN framework, which **has some instabilities and bugs**. Combined with the limitations of the UWP framework made VMware decide to build a new VPN client from scratch." **앱별 VPN을 포기한 게 아니라 UWP 방식을 포기한 겁니다.**
- **마이크로소프트 자신의 앱별 VPN 제품(Microsoft Tunnel)은 Windows를 지원하지 않습니다.** iOS/iPadOS/Android뿐입니다. 이게 되면 자기들이 썼을 겁니다.
- **마이크로소프트 공식 UWP VPN 플러그인 샘플조차 `RoutingPolicyType`을 한 번도 설정하지 않습니다.** 저장소 전체 grep 결과 0건. FilePath AppId는 파싱하는데(`CustomConfiguration.cs:352-371`), 정작 터널로 끌어오는 그 속성은 안 건드립니다. 그리고 그 저장소는 **archived**입니다(마지막 코드 커밋 2022-03, 2025-12에 비활성 봇 이슈).
- **마이크로소프트 플러그인용 ProfileXML 샘플에서는 `<RoutingPolicyType>` 두 줄이 모두 주석 처리되어 있습니다.** 바로 위 네이티브 프로필 샘플에서는 살아 있습니다. 이 비대칭은 설명된 적이 없습니다.
- **실제로 앱별 스플릿 터널을 파는 곳은 전부 커널 드라이버입니다**: Mullvad(`mullvad-split-tunnel.sys`, KMDF+WFP), Proton(WFP 콜아웃 드라이버), WireSock/TunnlTo(WinpkFilter NDIS 드라이버), Windscribe(`WindscribeSplitTunnel.sys`). Cloudflare WARP·Tailscale은 wintun 어댑터만 쓰고 **앱별 기능이 아예 없습니다.**
- GitHub 코드 검색에서 `VpnTrafficFilter` / `StartWithTrafficFilter` / `VpnAppIdType` 저장소 **총 0건**.
- 참조 구현(wireguard-uwp-rs)은 **2021-12-13 이후 손이 안 갔고**, 열린 이슈 6개 전부 미응답, 그중 하나가 "Is this project dead?"입니다. README는 Windows 10 21H1(19043.1348)에서만 시험했다고 적혀 있습니다.
- **반대 증거도 정직하게 적습니다**: 2026-01-06에 한 사용자가 "It is working for me. I am able to use the default win11 ui to connect to my server."라고 보고했습니다. **즉 플러그인 플랫폼 자체는 Win11에서 살아 있습니다.** 죽은 건 앱별 필터 부분의 검증 여부입니다.

### 3-E. 반박이 깨지 못한 것 (정직하게)

반박 담당들이 시도했다가 **실패한** 공격들입니다. 이건 청구 주장에 유리한 사실입니다.

- 제한 기능(rescap `networkingVpnProvider`)이 사이드로드에서 거부된다 → **거짓.** 문서가 명시적으로 허용하고, MS 직원도 확인했고, 마이크로소프트 자체 샘플도 자체 서명(`CN=TestingCertForDebugging`)으로 배포됩니다.
- 앱 컨테이너가 WireGuard용 UDP 소켓을 못 연다 → **거짓.** 참조 구현이 실제로 하고 있고, 플랫폼이 소켓을 브로커링해서 자기 터널로 되돌아가지 않게 처리합니다.
- 26200에서 배관이 제거되었다 → **거짓.** `Windows.Networking.Vpn.dll` 존재, `vpnClient` 작업 타입 SDK 스키마에 존재, 참조 문서에 폐기 배너 없음.
- SKU/MDM 게이팅 → **거짓.** Pro에서 지원되고, 플러그인 경로는 CSP를 안 거칩니다. 실제로 이 PC에서 MDM 등록 없이 프로필 생성이 됐습니다(O4).

---

## 4. 남은 모름

라이브 시험만이 답할 수 있는 것들입니다. 추측하지 않고 UNKNOWN으로 둡니다.

| # | 모르는 것 | 왜 중요한가 |
|---|---|---|
| U1 | **플러그인이 공급한 `ForceAllTrafficOverVpn` 필터가, 터널에 경로가 없는 목적지로 가는 트래픽을 실제로 터널로 끌어오는가.** | **이것이 전체 판정을 가르는 단 하나의 질문입니다.** 이슈 #1798은 "패킷 버퍼의 앱 귀속(attribution)"이 안 된다는 얘기지 "라우팅"이 안 된다는 얘기가 아닙니다. 성공 사례도 실패 사례도 공개된 게 없습니다. |
| U2 | 이슈 #1798의 데이터 손상이 고쳐졌는지 | 5년째 공식 언급 없음. 밖에서 알 수 없음 |
| U3 | `VpnTrafficFilterAssignment.AllowOutbound` / `AllowInbound`의 **기본값** | 문서에 기본값이 없습니다. 기본이 false면 필터를 붙이는 순간 조용히 블랙홀이 되는데, 그 모습이 "필터가 무시됐다"와 **똑같이 보입니다.** 반드시 명시적으로 true를 세팅해야 합니다 |
| U4 | 프로필 쪽 필터(`VpnPlugInProfile.TrafficFilters` / ProfileXML)와 연결 시점 필터(`StartWithTrafficFilter`)가 **둘 다 있을 때 합쳐지는지, 덮어쓰는지, 오류인지** | 문서 없음. **첫 실행에서는 반드시 둘 중 하나만 채웁니다** |
| U5 | `FilePath` 매칭 규칙: 대소문자 구분? 환경변수 확장? 심볼릭 링크 해석? **Edge/Chrome 같은 다중 프로세스 브라우저의 자식 프로세스 귀속?** | 조용한 무동작의 가장 흔한 원인 후보 |
| U6 | 강제 터널된 앱의 **DNS가 앱을 따라 터널로 가는지** | Mullvad는 Windows에서 DNS가 `dnscache`(svchost)에서 나가므로 프로세스 귀속이 안 된다고 문서화했습니다. 브라우저 라우팅 용도에서는 치명적일 수 있습니다 |
| U7 | WireGuard UWP 플러그인이 **26200에서 터널을 세우기는 하는지** | 2021년 Windows 10 19043에서만 검증됨. 이게 안 되면 이후 모든 관측이 해석 불가입니다 |
| U8 | 필터의 "기본 차단"이 **플러그인 자신의 바깥 전송 소켓(UDP)** 을 막지는 않는지 | 막히면 연결 자체가 실패하고, 증상이 플러그인 버그처럼 보입니다 |
| U9 | 장시간 안정성 — `Encapsulate`가 2~5분 뒤 멈추는 현상이 26200에서도 나는지 | 3-C. 앱별 라우팅이 되더라도 여기서 죽으면 제품이 안 됩니다 |
| U10 | UWP VPN 플러그인의 **처리량 수치** | 공개된 벤치마크가 전 세계에 0건입니다. "아마 괜찮겠지"가 아니라 "완전히 미측정"으로 취급하십시오 |

---

## 5. 가장 싼 판별 시험

### 5-0. 이 절에 대한 경고 (꼭 읽어주십시오)

**측정·안전 담당 조사원이 결과 없이 실패했습니다.** 따라서 아래 절차는 독립적인 안전 검토를 거치지 않았습니다. 제가 다른 조사원들의 안전 관련 발견을 모아 직접 구성했습니다. **실행 전에 사람이 한 번 더 읽어주십시오.**

지켜야 할 규칙:
1. **DNS·백신·보안·VPN 제품을 끄거나 멈추게 하는 절차는 여기 하나도 없습니다.** 있으면 그건 잘못된 절차입니다.
2. **`pktmon filter remove`를 부르지 않습니다.** 1차 관측은 pktmon 없이 합니다. 굳이 pktmon을 쓴다면, 먼저 `pktmon filter list`를 저장하고 **결과가 비어 있을 때만** 사용합니다. 비어 있지 않으면 pktmon을 쓰지 않습니다.
3. **순서 자물쇠**: 끊기 → 프로필 확인 → 프로필 삭제 → 0개 확인 → 패키지 제거 → 인터넷 확인. 역순으로 하지 않습니다.
4. `C:\Users\NetMD\Downloads\r4split.conf`와 모든 WireGuard 설정·개인키는 **사람이 직접 옮겨 적습니다.** AI가 읽거나 복사하지 않습니다.
5. 시험 내내 **IPv4만** 씁니다. 트래픽 필터 규칙에 IPv6 요소가 들어가면 VPN이 통째로 안 됩니다(문서화된 사실).

### 5-1. 사전 스냅숏 (관리자 PowerShell, 읽기 전용, 위험 0)

```powershell
# ── R4 사전 스냅숏 ── 관리자 권한 PowerShell 7에서 실행
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snap  = "$env:USERPROFILE\r4-snapshot-$stamp"
New-Item -ItemType Directory -Force -Path $snap | Out-Null
"SNAPSHOT DIR = $snap"

# 네트워크 기준 상태
Get-NetAdapter                          | Export-Clixml "$snap\adapters.xml"
Get-NetAdapter | Format-Table -AutoSize | Out-File    "$snap\adapters.txt"
Get-NetIPAddress -AddressFamily IPv4    | Export-Clixml "$snap\ipaddr.xml"
Get-NetRoute -AddressFamily IPv4        | Export-Clixml "$snap\routes.xml"
Get-NetRoute -AddressFamily IPv4 | Sort-Object ifIndex |
    Format-Table -AutoSize              | Out-File    "$snap\routes.txt"
Get-NetIPInterface                      | Export-Clixml "$snap\ipiface.xml"
Get-DnsClientServerAddress              | Export-Clixml "$snap\dns.xml"
Get-DnsClientNrptPolicy -Effective -ErrorAction SilentlyContinue |
                                          Export-Clixml "$snap\nrpt.xml"

# VPN / 패키지 기준 상태
Get-VpnConnection -ErrorAction SilentlyContinue                    | Export-Clixml "$snap\vpn-user.xml"
Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue | Export-Clixml "$snap\vpn-machine.xml"
Get-AppxPackage | Where-Object { $_.Name -match 'WireGuard|Vpn' }  | Export-Clixml "$snap\appx.xml"

# pktmon 필터는 '읽기만' 합니다. 절대 remove 하지 않습니다.
pktmon filter list | Out-File "$snap\pktmon-filters.txt"
Write-Host "pktmon 필터 목록을 저장했습니다. 목록이 비어있지 않다면 이번 시험에서 pktmon을 쓰지 마십시오."

# WFP 전체 상태 (읽기 전용 덤프) — 5-2 단계의 핵심 증거가 됩니다
netsh wfp show state file="$snap\wfp-before.xml" | Out-Null

# 인터넷 정상 확인 (이게 True가 아니면 시험을 시작하지 마십시오)
$ok = Test-NetConnection -ComputerName 1.1.1.1 -Port 443 -InformationLevel Quiet
"internet_before=$ok" | Tee-Object -FilePath "$snap\health.txt"
if (-not $ok) { throw '기준 상태에서 이미 인터넷이 안 됩니다. 시험 중단.' }

# 나중에 쓰기 위해 스냅숏 경로를 파일로 남깁니다
$snap | Out-File "$env:USERPROFILE\r4-last-snapshot.txt" -NoNewline
```

### 5-2. 【0단계】 연결 없이, 코드 없이, 1000원짜리 판별 (10분, 위험 0)

**이 단계만으로 결론이 날 수도 있습니다. 반드시 먼저 하십시오.**

목적: 플랫폼이 앱별 필터를 **WFP의 허용/차단 필터로 구현하는지**, 아니면 **리다이렉트 계층을 쓰는지** 보는 것입니다.

먼저 2-A의 O4에서 검증된 방법으로 **연결하지 않고** 프로필만 만듭니다(플러그인이 없어도 됩니다 — PFN 검증을 안 하는 것도 확인됨). 그리고 WFP 상태를 다시 떠서 비교합니다.

```powershell
# 5-2. 연결 없는 WFP 관측
$snap = Get-Content "$env:USERPROFILE\r4-last-snapshot.txt" -Raw

# (A) 프로필을 만든 뒤 (5-4 참조) 연결한 상태에서 다시 덤프
netsh wfp show state file="$snap\wfp-after.xml" | Out-Null

# (B) 우리 앱 경로가 WFP 필터에 등장하는지
Select-String -Path "$snap\wfp-after.xml" -Pattern 'msedge' -SimpleMatch -Context 4,25 |
    Out-File "$snap\wfp-msedge.txt"

# (C) 결정적 지표: 어떤 계층에, 어떤 액션으로 붙었는가
Select-String -Path "$snap\wfp-after.xml" `
  -Pattern 'ALE_AUTH_CONNECT_V4|ALE_BIND_REDIRECT_V4|ALE_CONNECT_REDIRECT_V4|FWP_ACTION_PERMIT|FWP_ACTION_BLOCK|FWP_ACTION_CALLOUT_TERMINATING|FWP_ACTION_CALLOUT_UNKNOWN' |
    Group-Object { $_.Line.Trim() } | Sort-Object Count -Descending |
    Select-Object Count, Name | Out-File "$snap\wfp-actions.txt"

Get-Content "$snap\wfp-actions.txt"
```

**판독**

| 관측 | 의미 |
|---|---|
| msedge.exe가 `ALE_BIND_REDIRECT_V4` 또는 `ALE_CONNECT_REDIRECT_V4` 계층에 등장 | 청구 주장 **유망**. 3단계로 진행 |
| msedge.exe가 `ALE_AUTH_CONNECT_V4`에 `FWP_ACTION_PERMIT`/`FWP_ACTION_BLOCK`으로만 등장 | **반박 담당들이 맞습니다.** 허용/차단 기계일 뿐이고 리다이렉트가 아닙니다. 여기서 중단해도 됩니다 |
| msedge.exe가 아예 안 나옴 | 필터가 커널에 반영조차 안 됨. 이슈 #1798의 "Win32 앱 ID 무시" 증상과 일치 |

### 5-3. 【1단계】 필터 없이 터널만 세우기 (30분) — U7 게이트

**필터 변수를 넣기 전에 플러그인이 26200에서 되는지부터 확인합니다.** 여기서 실패하면 이후 모든 관측이 무의미합니다.

```powershell
# ── 빌드 & 등록 (개발자 모드 ON이므로 인증서/서명 불필요) ──
# 주의: 로컬 클론은 dirty 상태입니다. 깨끗한 체크아웃에 패치를 적용하십시오.
$src = 'C:\Users\NetMD\AppData\Local\Temp\claude\C--dev-vpn-router\f2e28a03-be97-467a-b864-d8688123e368\scratchpad\wg-baseline'
Set-Location $src
cargo build --release
Copy-Item .\appx\* .\target\release\ -Force
Add-AppxPackage -Register .\target\release\AppxManifest.xml

$pfn = (Get-AppxPackage -Name 'WireGuard-UWP').PackageFamilyName
"PackageFamilyName = $pfn"     # 기본 매니페스트 기준 WireGuard-UWP_zjr0dfhgjwvde

# ── 프로필 생성 (필터 없음: CustomConfiguration에 AppFilePath를 넣지 않습니다) ──
# r4-phase1.xml 은 사람이 직접 작성합니다 (5-6 참조). AI가 키를 만지지 않습니다.
$cfg = Get-Content -Raw .\r4-phase1.xml
Add-VpnConnection -Name 'R4-PerApp' `
                  -ServerAddress '<서버-호스트-또는-IP>' `
                  -PlugInApplicationID $pfn `
                  -CustomConfiguration ([xml]$cfg) `
                  -Force -PassThru

rasdial 'R4-PerApp'
Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, ifIndex, InterfaceDescription
$tun = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.ifIndex -ne 8 }
"터널 ifIndex = $($tun.ifIndex)"
```

**게이트 조건**
- 통과: 터널 어댑터가 올라오고, `Test-NetConnection 1.1.1.1 -Port 443`이 True이며, 그 트래픽이 터널 ifIndex로 나감
- **중단 조건**: 연결이 15초 안에 실패하거나(`ConnectProfileAsync` 타임아웃 알려진 이슈), 터널 어댑터가 안 뜨거나, 5분간 켜둔 뒤 통신이 죽으면 → **U7/U9 실패. 즉시 5-7 롤백 후 커널 갈래로.**

### 5-4. 【2단계】 결정적 관측 — 필터 켜기 (30분)

터널 경로는 **여전히 좁게(AllowedIPs=1.1.1.1/32)** 둡니다. 이게 핵심입니다.

```powershell
# 1단계와 완전히 동일한 조건에서, CustomConfiguration만 바꿉니다.
# r4-phase2.xml = r4-phase1.xml + <AppFilePath> + <AppRoutingPolicy>Force</AppRoutingPolicy>
rasdial 'R4-PerApp' /disconnect
Start-Sleep -Seconds 2
Set-VpnConnection -Name 'R4-PerApp' -CustomConfiguration ([xml](Get-Content -Raw .\r4-phase2.xml))
rasdial 'R4-PerApp'
```

관측 스크립트:

```powershell
# ── 관측 도우미 ──
function Get-AppBinding {
    param([string]$ProcName, [string]$RemoteIp)
    $procIds = (Get-Process -Name $ProcName -ErrorAction SilentlyContinue).Id
    if (-not $procIds) { return @() }
    Get-NetTCPConnection -RemoteAddress $RemoteIp -ErrorAction SilentlyContinue |
      Where-Object { $procIds -contains $_.OwningProcess } |
      Select-Object @{n='App';e={$ProcName}}, LocalAddress, RemoteAddress, RemotePort, State,
                    @{n='ifIndex';e={ (Get-NetIPAddress -IPAddress $_.LocalAddress -ErrorAction SilentlyContinue).InterfaceIndex }}
}

function Measure-IfCounters {
    param([scriptblock]$Action)
    $b = Get-NetAdapterStatistics | Select-Object Name, @{n='ifIndex';e={(Get-NetAdapter -Name $_.Name).ifIndex}}, SentUnicastPackets, ReceivedUnicastPackets
    & $Action
    Start-Sleep -Seconds 3
    $a = Get-NetAdapterStatistics | Select-Object Name, @{n='ifIndex';e={(Get-NetAdapter -Name $_.Name).ifIndex}}, SentUnicastPackets, ReceivedUnicastPackets
    foreach ($x in $a) {
        $y = $b | Where-Object Name -eq $x.Name
        [pscustomobject]@{
            Name = $x.Name; ifIndex = $x.ifIndex
            SentDelta = $x.SentUnicastPackets - $y.SentUnicastPackets
            RecvDelta = $x.ReceivedUnicastPackets - $y.ReceivedUnicastPackets
        }
    }
}

# ── 4가지 경우를 하나씩. 각 경우 사이에 브라우저 캐시 상황이 섞이지 않도록 30초 간격 ──
# 경우 1: Edge → 1.1.1.1 (터널 경로 안, 필터 대상)      기대: 터널
# 경우 2: Edge → 8.8.8.8 (터널 경로 밖, 필터 대상)      ★★ 이게 질문입니다 ★★
# 경우 3: Chrome → 1.1.1.1 (터널 경로 안, 필터 비대상)  기대: 차단 or Wi-Fi
# 경우 4: Chrome → 8.8.8.8 (터널 경로 밖, 필터 비대상)  기대: Wi-Fi

Measure-IfCounters { Start-Process msedge 'https://8.8.8.8/' }   # 경우 2
Start-Sleep -Seconds 5
Get-AppBinding -ProcName msedge -RemoteIp '8.8.8.8' | Format-Table -AutoSize
Get-AppBinding -ProcName chrome -RemoteIp '8.8.8.8' | Format-Table -AutoSize
```

**세 가지 결과를 반드시 구분하십시오. 두 번째와 첫 번째가 헷갈리기 쉽고, 의미는 정반대입니다.**

| 결과 | 관측 모습 | 의미 |
|---|---|---|
| ① 필터 무시 | Edge 패킷이 Wi-Fi ifIndex 8으로, 터널 카운터 0, Edge 인터넷 정상 | **R3 재현.** 청구 주장 실패 |
| ② 블랙홀 | Edge 패킷이 **어느 쪽에도 없음**, Edge가 타임아웃, Chrome은 정상 | **허용/차단 기계임이 확정.** 반박 담당들이 맞음. 청구 주장 실패 |
| ③ 성공 | Edge 패킷이 **터널 ifIndex에만**, Chrome은 Wi-Fi ifIndex 8에 | **청구 주장 성립.** 6절로 |

> ①과 ②를 구분하지 못하면 판정을 그르칩니다. pktmon으로 Wi-Fi만 보면 ②가 "Edge 패킷이 사라졌다"로 보여 성공처럼 오독됩니다. **반드시 두 인터페이스를 동시에 봐야 합니다.**

### 5-5. 【3단계 · 선택】 대조군 (결과가 ①/②일 때만, 15분)

패키지 앱(PFN) 필터로 **플랫폼이 필터를 존중하기는 하는지** 확인합니다. FilePath 문제인지 플랫폼 문제인지 갈립니다.

**필수: FilePath 필터를 전부 빼고 PFN 필터만 넣습니다. 절대 섞지 않습니다** (이슈 #1798의 액세스 위반).

- PFN 대조군이 동작 → **FilePath(Win32)만 안 되는 것.** 이슈 #1798과 일치. 결론: 이 갈래는 Win32 앱에 못 씁니다
- PFN 대조군도 무동작 → 26200에서 플랫폼 전체가 죽은 것. 26200 회귀로 기록

### 5-6. 시험용 CustomConfiguration (사람이 직접 작성)

`r4-phase1.xml` (필터 없음):

```xml
<WireGuard>
  <Interface>
    <PrivateKey>여기에-본인이-직접-옮겨-적으십시오</PrivateKey>
    <Address>10.0.0.2/32</Address>
  </Interface>
  <Peer>
    <PublicKey>여기에-서버-공개키를-직접-옮겨-적으십시오</PublicKey>
    <Port>51820</Port>
    <AllowedIPs>1.1.1.1/32</AllowedIPs>
    <PersistentKeepalive>25</PersistentKeepalive>
  </Peer>
</WireGuard>
```

`r4-phase2.xml` (필터 있음 — 위에서 두 줄만 추가):

```xml
<WireGuard>
  <Interface>
    <PrivateKey>여기에-본인이-직접-옮겨-적으십시오</PrivateKey>
    <Address>10.0.0.2/32</Address>

    <!-- 아래 두 줄이 유일한 변경점입니다 -->
    <AppFilePath>C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe</AppFilePath>
    <AppRoutingPolicy>Force</AppRoutingPolicy>
  </Interface>
  <Peer>
    <PublicKey>여기에-서버-공개키를-직접-옮겨-적으십시오</PublicKey>
    <Port>51820</Port>
    <AllowedIPs>1.1.1.1/32</AllowedIPs>
    <PersistentKeepalive>25</PersistentKeepalive>
  </Peer>
</WireGuard>
```

주의사항:
- **서버 주소는 이 XML에 없습니다.** 플러그인은 `config.ServerHostNameList()[0]`에서 읽으므로 `Add-VpnConnection -ServerAddress`가 실제로 쓰입니다. 포트만 XML에서 옵니다.
- `msedge.exe`의 정확한 경로는 `(Get-Process msedge | Select-Object -First 1).Path`로 확인해서 그대로 넣으십시오. 따옴표·후행 공백 없이 절대 경로.
- `PersistentKeepalive`는 `Option<u16>`인데 serde default가 없습니다. 명시적으로 넣으십시오.
- **IPv6는 넣지 마십시오.**

### 5-7. 비상 복구 (독립 실행 가능, 언제든 이것만 돌리면 됩니다)

```powershell
# ── R4 비상 복구 ── 관리자 PowerShell. 이것만 돌려도 원상복구됩니다.
$ProfileName = 'R4-PerApp'
$PkgName     = 'WireGuard-UWP'

Write-Host '[1/6] VPN 연결 끊기'
rasdial $ProfileName /disconnect 2>$null
Start-Sleep -Seconds 2

Write-Host '[2/6] 프로필 상태 확인 (끊긴 것을 먼저 확인합니다)'
$p = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue
if ($p) { $p | Select-Object Name, ConnectionStatus | Format-Table -AutoSize }

Write-Host '[3/6] 프로필 삭제'
Remove-VpnConnection -Name $ProfileName -Force -ErrorAction SilentlyContinue

Write-Host '[4/6] 프로필이 0개인지 확인 — 여기서 실패하면 패키지를 건드리지 않습니다'
if (Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue) {
    throw '중단: VPN 프로필이 아직 남아 있습니다. 패키지를 제거하지 마십시오.'
}

Write-Host '[5/6] 앱 패키지 제거'
Get-AppxPackage -Name $PkgName | Remove-AppxPackage -ErrorAction SilentlyContinue

Write-Host '[6/6] 인터넷 복구 확인'
$ok = Test-NetConnection -ComputerName 1.1.1.1 -Port 443 -InformationLevel Quiet
Get-NetAdapter | Select-Object Name, ifIndex, Status | Format-Table -AutoSize
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object ifIndex, NextHop, RouteMetric | Format-Table -AutoSize

if ($ok) {
    Write-Host 'ROLLBACK COMPLETE — 인터넷 정상 확인됨.' -ForegroundColor Green
} else {
    Write-Warning '인터넷이 아직 안 됩니다. 아래 순서로만 진행하십시오.'
    Write-Warning '  (1) 스냅숏의 adapters.txt / routes.txt 와 현재 상태를 비교'
    Write-Warning '  (2) 꺼진 어댑터가 있으면: Get-NetAdapter | Where Status -ne Up | Enable-NetAdapter -Confirm:$false'
    Write-Warning '  (3) 남은 NRPT 규칙 확인: Get-DnsClientNrptPolicy -Effective'
    Write-Warning '  (4) DNS/백신/보안/VPN 제품은 절대 끄지 마십시오. pktmon filter remove 도 금지.'
}
```

### 5-8. 중단 조건 요약

즉시 중단하고 5-7을 실행하는 경우:
- 5-3 게이트에서 터널이 안 서거나 5분을 못 버팀 (U7/U9 실패)
- `StartWithTrafficFilter`가 예외를 던짐 → 단, **DNS 타입 교체(D7) 때문일 수 있으므로** 필터를 빼고 `VpnDomainNameAssignment`만 바꿔서 한 번 더 시험한 뒤 판단
- 인터넷이 30초 이상 끊김
- Chrome(비대상 앱)이 인터넷을 잃음 → "기본 차단"이 발동한 것. 관측은 유효하지만 즉시 롤백
- 누적 실작업 4시간 초과

---

## 6. 구현 계획 (5-4에서 ③ 성공이 나온 경우에만)

### 6-1. 이미 있는 것 (다시 만들지 않습니다)

| 자산 | 위치 | 상태 |
|---|---|---|
| WireGuard UWP 플러그인 본체 | `scratchpad\wireguard-uwp-rs` (HEAD 328e622) | 빌드 검증 완료 |
| 앱별 필터 패치 | `scratchpad\per-app-traffic-filter.patch` | 빌드 검증 완료 |
| 검증된 빌드 트리 | `scratchpad\wg-baseline` | 빌드 검증 완료 |
| AppxManifest | 참조 클론 `appx\AppxManifest.xml` | 필요한 것 전부 이미 선언됨. **수정 불필요** |
| 프로필 생성 절차 | `Add-VpnConnection -PlugInApplicationID` / MDM Bridge WMI 스크립트 | 이 PC에서 실행 검증 완료 |

### 6-2. 순서

**1주차 — 뼈대 다지기 (기능 추가 금지)**
1. 깨끗한 저장소로 참조 구현을 `windows/` 아래 vendoring. **dirty 워킹 트리는 버리고** 검증된 패치만 적용합니다(설정 요소 이름을 `AppFilePath`/`AppRoutingPolicy`로 통일 — dirty 트리의 `<TunnelApp>`은 폐기).
2. `mtuSize`/`maxFrameSize`를 1500/1600 → **1420/1500** 으로 교정(D6). 단, 판별 시험 중에는 1500/1600을 유지해서 변수를 하나로 묶습니다.
3. `plugin.rs:461,466,504,557,562`의 **패킷 버퍼 누수 TODO 5곳을 먼저 막습니다.** 장시간 운용에서 버퍼 풀이 마릅니다.
4. `AllowOutbound=true`/`AllowInbound=true` 명시 유지(U3).

**2주차 — 장시간 안정성 (여기가 진짜 관문입니다)**
5. **8시간 무중단 시험.** `Encapsulate` 호출 간격을 계속 로깅합니다. 3-C의 "2~5분 뒤 정지"가 재현되는지가 제품화 가능 여부를 가릅니다.
6. 재현되면: 앱 설정 > 백그라운드 앱 권한 "항상"으로 완화되는지 확인. **안 되면 여기서 커널 갈래로 전환합니다.**
7. 서버 쪽 `PersistentKeepalive` 의존성을 문서화합니다(플러그인이 타이머를 못 씁니다).
8. **처리량 측정.** 공개 수치가 0건이므로 우리가 처음 재는 겁니다.

**3주차 — 다중 앱 / DNS / 재기동**
9. 앱 목록을 여러 개로. `Chrome`, `msedge`의 자식 프로세스 귀속 확인(U5).
10. DNS가 앱을 따라가는지 확인(U6). 안 따라가면 제품 문서에 명시하거나 별도 처리 설계.
11. 프로필 생성/삭제 자동화. 재부팅 후 복구.

**4주차 — 포장**
12. 패키징 서명 경로(`makeappx` + `signtool /fd SHA256` + `LocalMachine\TrustedPeople`). **주의: 제한 기능이 있으면 .appx 더블클릭 설치가 거부됩니다.** PowerShell `Add-AppxPackage`만 지원 경로입니다.
13. macOS 쪽과 설정 형식 통일.

### 6-3. 중간 이탈 지점

각 주차 끝에서 "커널 갈래로 갈아탈까"를 다시 묻습니다. 특히 2주차 5·6번에서 안정성이 안 나오면 **더 붙들지 않습니다.** VMware가 딱 이 지점에서 갈아엎었습니다.

---

## 7. 커널 갈래와의 비교

| 항목 | **갈래 A: UWP VPN 플러그인** | **갈래 B: WFP 콜아웃 커널 드라이버 직접 작성** | **갈래 C: 기존 서명 드라이버 재사용** (WinpkFilter/ndisapi, WinDivert) |
|---|---|---|---|
| 새로 설치할 것 | **없음.** Rust·SDK·개발자모드 전부 준비됨 | **WDK(km 헤더) 미설치.** VS 워크로드 + WDK 수 GB 설치 필요 | 드라이버 바이너리 + 라이선스 확인 |
| 지금 당장 빌드되나 | **예** (검증됨, 종료코드 0) | 아니오 | 미확인 |
| 서명 | 사이드로드는 **서명 불필요**. 배포 시 자체 서명 + TrustedPeople | **EV 코드서명 인증서 + MS 증명 서명 필수.** 개발 중엔 테스트 서명 모드(bcdedit + 재부팅 = 보안 태세 변경) | 배포자가 이미 서명함 |
| 앱별 라우팅 실현 가능성 | **미검증.** 3/3 반박, 11년간 사례 0건 | **검증됨.** Mullvad·Proton·Windscribe가 실제로 이 방식으로 팝니다 | **검증됨.** WireSock/TunnlTo가 "Chrome은 터널, Firefox는 직결"을 실제로 함 |
| 실패 시 피해 | 프로필 삭제 + 패키지 제거로 복구. **재부팅 불필요** | **BSOD / 부팅 루프.** Mullvad도 2025-10 베타에서 부팅 루프 이슈 있었음 | 드라이버 품질에 종속. 상대적으로 낮음 |
| 롤백 | 명령 2줄 | 안전 모드 진입 가능성 | 언인스톨 |
| 장시간 안정성 | **최대 위험 지점.** 2~5분 정지 미해결 보고, MS 자체 제품도 Win11에서 중단됨 | 우리가 통제 | 드라이버가 성숙 |
| 처리량 | **전 세계 측정치 0건** | 커널 경로, 예측 가능 | WireSock이 고성능으로 알려짐 |
| 플랫폼 수명 | **UWP는 2021-10부터 유지보수 전용.** Windows App SDK에 후속 API **없음**(MS 공식 확인). 편도 문 | WFP는 현재 진행형 | 서드파티 의존 |
| Win32 앱 ID 신뢰성 | **MS가 "쓰지 마라"고 함**(이슈 #1798, 미해결) | 해당 없음 | 해당 없음 |
| 시험까지 걸리는 시간 | **4시간** | 며칠 (WDK 설치 + 부트 설정 + 첫 드라이버) | 1~2일 (라이선스 검토 포함) |
| 라이선스 | 자체 코드 | 자체 코드 | **확인 필요.** WinpkFilter는 상용 폐쇄소스, WinDivert는 LGPL 계열 — 실제 조건 미확인 |

**정직한 평가**: 갈래 A의 유일한 장점은 **"지금 당장 4시간이면 답이 나온다"** 이고, 이건 진짜 큰 장점입니다. 하지만 성공하더라도 갈래 A는 **유지보수 전용 플랫폼 위의 편도 문**이고, 처리량도 안정성도 아무도 모릅니다. 반대로 갈래 B/C는 시장에서 실제로 팔리는 방식입니다.

**따라서 갈래 A는 "제품 후보"가 아니라 "싸게 확인해볼 가설"로만 취급하는 것이 맞습니다.** 시험이 성공해도 6-2의 2주차 안정성 관문을 넘기 전까지는 갈래 B/C를 후보에서 지우지 마십시오.

또한 **갈래 C를 진지하게 검토할 것을 권합니다.** WireSock Secure Connect가 우리 목표와 거의 동일한 제품(WireGuard + AllowedApps/DisallowedApps)을 이미 팔고 있고, 그 기반이 서명된 NDIS 패킷 필터 드라이버입니다. 드라이버를 우리가 쓰고 서명하지 않아도 되는 길입니다. 조사 범위에 없었던 갈래이므로 별도 확인이 필요합니다.

---

## 8. R3-DEC-04 에 어떻게 반영할 것인가

아래 문단을 결정 기록에 **그대로 붙여넣으실 수 있게** 작성했습니다.

```markdown
### R3-DEC-04 — 재개(REOPENED) 및 조건부 재판정

**상태 변경**: 종결(CLOSED, "커널 드라이버로 간다") → **조건부 재개(REOPENED, 시험 한정)**
**변경일**: 2026-08-18
**변경 사유**: 사용자 모드 WFP `FwpmConnectionPolicyAdd0` 실패(2026-08-18 라이브 2회)와
무관한 별도 경로가 확인되었기 때문입니다. Windows.Networking.Vpn(UWP VPN 플러그인)
플랫폼의 `VpnChannel.StartWithTrafficFilter` + `VpnTrafficFilter`가 그것입니다.
이 경로는 흐름을 사후에 돌리는 방식이 아니라, 채널을 여는 시점에 어떤 앱이
VPN L3 인터페이스에 붙을 수 있는지를 선언하는 방식이라 구조가 다릅니다.

**재개는 "구현 재개"가 아니라 "판별 시험 1회 허가"입니다.**

**조사 결과 요약**
- 조사 6명 / 반박 3명 투입. **반박 3명 전원 REFUTED.**
- API·타입·매니페스트·패키징·권한·빌드는 전부 실재하며 이 PC에서 검증되었습니다.
  windows 크레이트 0.28에 이미 있고, 패치가 컴파일되며, 앱별 필터가 들어간
  플러그인 VPN 프로필이 MDM 없이 관리자 권한만으로 실제로 생성·삭제되었습니다.
- 그러나 **핵심 의미론이 미검증입니다.** 문서 언어는 전부 "허용(allow)"이지
  "재지정(redirect)"이 아닙니다. 윈도우에는 앱별 라우팅 테이블이 없고,
  `VpnRouteAssignment`에 AppId 칸이 없습니다. 따라서
  `ForceAllTrafficOverVpn`이 "다른 인터페이스 사용 금지"인지
  "터널로 강제 유입"인지가 결정적 미지수입니다.
- **11년간(Win10 10240부터) 이 조합을 실제로 성공시킨 사례가 공개된 바 없습니다.**
  마이크로소프트 공식 샘플조차 `RoutingPolicyType`을 한 번도 설정하지 않습니다.
- **마이크로소프트가 Win32 앱 ID 사용을 명시적으로 만류한 기록이 있습니다.**
  MicrosoftDocs/winrt-api#1798 (2021-03-26 미해결 종료):
  "we're able to reproduce a data corruption ... it seems safest to avoid
  using Win32 appids at all." 이후 5년간 수정 발표 없음.
- 별도 위험: `vpnClient` 백그라운드 작업의 수명을 윈도우가 통제하므로,
  앱별 라우팅이 되더라도 터널이 2~5분 뒤 조용히 멈출 수 있습니다
  (MS Q&A 264773 미해결, MS 자체 Azure VPN Client도 Win11에서 동일 증상).

**재개 조건 (전부 충족해야 시험 진행)**
1. 실작업 4시간, 달력 1일 상한. 초과 시 자동 종결.
2. 사전 스냅숏 + 검증된 비상 복구 절차를 먼저 마련합니다.
3. DNS·백신·보안·VPN 제품을 끄는 절차 금지. `pktmon filter remove` 금지.
4. 순서 자물쇠 준수: 끊기 → 프로필 0개 확인 → 패키지 제거 → 인터넷 확인.
5. WireGuard 설정 파일과 개인키는 사람이 직접 다룹니다.
6. PFN 필터와 FilePath 필터를 한 assignment에 섞지 않습니다(#1798 액세스 위반).

**종료 조건 (셋 중 하나가 관측되면 즉시 판정)**
- 관측 ③ 성공: Edge 패킷이 터널 ifIndex에만, Chrome은 Wi-Fi ifIndex 8에.
  → R3-DEC-04를 "UWP VPN 플러그인 갈래 채택(단, 8시간 안정성 관문 조건부)"으로 개정.
- 관측 ① 필터 무시: Edge가 Wi-Fi ifIndex 8로 정상 통신.
  → R3-DEC-04를 재종결. 사유: "사용자 모드 경로 2종(WFP 연결 정책, UWP 트래픽 필터)
    모두 앱별 재지정 불가로 관측됨."
- 관측 ② 블랙홀: Edge가 어느 인터페이스에도 안 나타나고 통신 실패.
  → R3-DEC-04를 재종결. 사유: "트래픽 필터는 VPN 인터페이스에 대한 허용/차단
    기계이며 라우팅 재지정 수단이 아님이 실측으로 확인됨."

**재종결 시 기본 후속 결정**
커널 갈래로 복귀합니다. 단, 새로 확인된 **갈래 C(기존 서명 드라이버 재사용:
WinpkFilter/ndisapi, WinDivert)** 를 커널 드라이버 자체 작성 이전에 별도로 검토합니다.
WireSock Secure Connect가 우리 목표와 거의 같은 제품을 이 방식으로 이미 출시했습니다.

**본 재개로 무효화되지 않는 R3 결론**
"사용자 모드 WFP 연결 정책(`FwpmConnectionPolicyAdd0` /
`FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4`)은 앱별 트래픽을
재지정하지 못한다"는 결론은 **그대로 유효합니다.** 가설 6개 제거,
라이브 2회, 패킷 캡처 포함. 이번 재개는 그 결론을 뒤집는 것이 아니라
**다른 API 표면**을 검토하는 것입니다.
```

---

## 부록 A — AppxManifest.xml (참조 클론 원본, 이미 빌드된 바이너리와 짝이 맞습니다)

수정할 필요가 없습니다. 세 가지가 이미 다 들어 있습니다: `rescap` 네임스페이스, `vpnClient` 백그라운드 작업, 패키지 수준 활성화 클래스 등록.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="WireGuard-UWP" Publisher="CN=Publisher" Version="0.1.0.0" />
  <Properties>
    <DisplayName>WireGuard UWP VPN</DisplayName>
    <PublisherDisplayName>Publisher</PublisherDisplayName>
    <Logo>StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Universal" MinVersion="10.0.0.0" MaxVersionTested="10.0.0.0" />
  </Dependencies>
  <Resources><Resource Language="en-us" /></Resources>
  <Applications>
    <!-- 전경 앱 -->
    <Application Id="App" Executable="wireguard-uwp.exe" EntryPoint="WireGuard-UWP.App">
      <uap:VisualElements DisplayName="WireGuard UWP VPN" Description="WireGuard UWP VPN App"
        Square150x150Logo="Square150x150Logo.png" Square44x44Logo="Square44x44Logo.png"
        BackgroundColor="transparent">
        <uap:SplashScreen Image="SplashScreen.png" />
      </uap:VisualElements>
    </Application>
    <!-- 플러그인 앱: 전경 앱을 닫아도 터널이 죽지 않도록 반드시 별도 Application 이어야 합니다 -->
    <Application Id="Plugin" Executable="wireguard-uwp.exe" EntryPoint="WireGuard-UWP.App">
      <uap:VisualElements DisplayName="WireGuard UWP VPN Plugin" Description="WireGuard UWP VPN Plugin"
        Square150x150Logo="Square150x150Logo.png" Square44x44Logo="Square44x44Logo.png"
        BackgroundColor="transparent" AppListEntry="none">
        <uap:SplashScreen Image="SplashScreen.png" />
      </uap:VisualElements>
      <Extensions>
        <!-- windows.vpnPlugin 이라는 범주는 존재하지 않습니다. 이 형태가 유일하게 맞습니다. -->
        <Extension Category="windows.backgroundTasks" Executable="wireguard-uwp.exe"
                   EntryPoint="WireGuard-UWP.VpnBackgroundTask">
          <BackgroundTasks><uap:Task Type="vpnClient" /></BackgroundTasks>
        </Extension>
      </Extensions>
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClientServer" />
    <Capability Name="privateNetworkClientServer" />
    <!-- 제한 기능. 사이드로드에는 MS 승인이 필요 없습니다.
         주의: makeappx 는 이 이름을 검증하지 않습니다. 오타는 배포 때 터집니다. 눈으로 확인하십시오. -->
    <rescap:Capability Name="networkingVpnProvider" />
  </Capabilities>
  <!-- MSBuild 가 자동 생성해 주는 부분. Rust(cargo)는 안 해주므로 손으로 씁니다.
       ActivatableClassId 는 위 Extension 의 EntryPoint 와 글자 하나까지 같아야 합니다. -->
  <Extensions>
    <Extension Category="windows.activatableClass.inProcessServer">
      <InProcessServer>
        <Path>wireguard_uwp_plugin.dll</Path>
        <ActivatableClass ActivatableClassId="WireGuard-UWP.VpnBackgroundTask" ThreadingModel="both" />
      </InProcessServer>
    </Extension>
  </Extensions>
</Package>
```

---

## 부록 B — Rust 패치 (빌드 검증 완료, `git apply -p1` 대상: HEAD 328e622)

원본 파일: `C:\Users\NetMD\AppData\Local\Temp\claude\C--dev-vpn-router\f2e28a03-be97-467a-b864-d8688123e368\scratchpad\per-app-traffic-filter.patch`

```diff
diff --git a/plugin/src/config.rs b/plugin/src/config.rs
index 8e7ac1c..205027e 100644
--- a/plugin/src/config.rs
+++ b/plugin/src/config.rs
@@ -46,6 +46,24 @@ pub struct InterfaceConfig {
     #[serde(default)]
     #[serde(rename = "DNSSearch")]
     pub search_domains: Vec<String>,
+
+    /// 앱별 VPN 트래픽 필터를 걸 Win32 실행 파일의 절대 경로.
+    /// 앱마다 요소를 반복합니다. 예:
+    /// `<AppFilePath>C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe</AppFilePath>`
+    ///
+    /// 목록이 비어 있으면 필터 없음 = 기존 `VpnChannel::Start` 동작과 동일합니다.
+    #[serde(default)]
+    #[serde(rename = "AppFilePath")]
+    pub app_file_paths: Vec<String>,
+
+    /// `AppFilePath` 로 지정한 모든 앱에 적용할 라우팅 정책.
+    ///
+    /// `Force`(기본) => `VpnRoutingPolicyType::ForceAllTrafficOverVpn`
+    /// `Split`       => `VpnRoutingPolicyType::SplitRouting`
+    #[serde(default)]
+    #[serde(rename = "AppRoutingPolicy")]
+    pub app_routing_policy: Option<String>,
 }
 
 /// Remote peer specific configuration
diff --git a/plugin/src/plugin.rs b/plugin/src/plugin.rs
index 04f025a..a5170da 100644
--- a/plugin/src/plugin.rs
+++ b/plugin/src/plugin.rs
@@ -152,7 +152,13 @@ impl VpnPlugin {
         }
 
         // DNS 설정
-        let namespace_assignment = VpnNamespaceAssignment::new()?;
+        //
+        // 주의: `StartWithTrafficFilter` 는 `VpnDomainNameAssignment` 를 받습니다.
+        //       평범한 `Start` 는 `VpnNamespaceAssignment` 를 받습니다. 서로 다른 타입이라
+        //       아래 DNS 배관을 도메인 이름 타입 기준으로 다시 짭니다. 결과로 나오는
+        //       NRPT 규칙 자체는 동일합니다.
+        let namespace_assignment = VpnDomainNameAssignment::new()?;
+        let domain_name_list = namespace_assignment.DomainNameList()?;
         let dns_servers = wg_config
             .interface
             .dns_servers
@@ -164,9 +170,6 @@ impl VpnPlugin {
             .collect::<Vec<_>>();
         let search_domains = wg_config.interface.search_domains;
 
-        let namespace_count = search_domains.len() + !dns_servers.is_empty() as usize;
-        let mut namespaces = Vec::with_capacity(namespace_count);
-
         // 검색 도메인을 suffix NRPT 규칙으로 추가해서
         // 가상 인터페이스의 연결별 DNS 접미사 검색 목록에 들어가게 합니다.
@@ -174,21 +177,28 @@ impl VpnPlugin {
             // suffix 규칙으로 만들기 위해 앞에 . 을 붙입니다
             search_domain.insert(0, '.');
             let dns_servers = Vector::new(dns_servers.clone());
-            let namespace =
-                VpnNamespaceInfo::CreateVpnNamespaceInfo(search_domain, dns_servers, None)?;
-            namespaces.push(Some(namespace));
+            let domain = VpnDomainNameInfo::CreateVpnDomainNameInfo(
+                search_domain,
+                VpnDomainNameType::Suffix,
+                dns_servers,
+                None, // 프록시 서버 없음
+            )?;
+            domain_name_list.Append(domain)?;
         }
 
         if !dns_servers.is_empty() {
             // 특정 도메인 집합이 아니라 전체에 적용되도록 네임스페이스 이름을 '.' 로 둡니다 (NRPT)
             let dns_servers = Vector::new(dns_servers);
-            let namespace = VpnNamespaceInfo::CreateVpnNamespaceInfo(".", dns_servers, None)?;
-            namespaces.push(Some(namespace));
+            let domain = VpnDomainNameInfo::CreateVpnDomainNameInfo(
+                ".",
+                VpnDomainNameType::Suffix,
+                dns_servers,
+                None, // 프록시 서버 없음
+            )?;
+            domain_name_list.Append(domain)?;
         }
 
-        namespace_assignment.SetNamespaceList(Vector::new(namespaces))?;
-
         // WG 터널 객체 생성
         let tunn = Tunn::new(
             static_private,
@@ -221,8 +231,48 @@ impl VpnPlugin {
         // connect 가 실제로 멈춰 있을 일은 없습니다 (DNS 는 예외일 수 있음).
         sock.ConnectAsync(&server, port.to_string())?.get()?;
 
+        // 앱별 트래픽 필터 정책 구성.
+        //
+        // `VpnTrafficFilter` 하나가 Win32 실행 파일 하나를 절대 경로로 지목합니다
+        // (`VpnAppIdType::FilePath`). `RoutingPolicyType` 이 그 앱을 VPN 인터페이스로
+        // 강제 터널할지, 스플릿 라우팅할지를 정합니다.
+        let traffic_filters = VpnTrafficFilterAssignment::new()?;
+
+        // 열린 상태로 실패하게 둡니다. 어떤 필터에도 안 걸린 트래픽은 원래 경로를 유지합니다.
+        // 첫 라이브 실행에서 이 값을 `false` 로 두지 마십시오. 문서상 의미가
+        // "아웃바운드/인바운드 트래픽 허용 여부" 이므로, 컴퓨터 전체 아웃바운드 차단이
+        // 발생할 수 있고 그게 바로 인터넷을 날려먹는 실패 유형입니다.
+        traffic_filters.SetAllowOutbound(true)?;
+        traffic_filters.SetAllowInbound(true)?;
+
+        let routing_policy = match wg_config.interface.app_routing_policy.as_deref() {
+            None | Some("Force") => VpnRoutingPolicyType::ForceAllTrafficOverVpn,
+            Some("Split") => VpnRoutingPolicyType::SplitRouting,
+            Some(other) => {
+                channel.SetErrorMessage(format!(
+                    "AppRoutingPolicy must be 'Force' or 'Split', got: {}",
+                    other
+                ))?;
+                return Err(Error::from(E_INVALIDARG));
+            }
+        };
+
+        let filter_list = traffic_filters.TrafficFilterList()?;
+        for app_path in &wg_config.interface.app_file_paths {
+            let app_id = VpnAppId::Create(VpnAppIdType::FilePath, app_path.as_str())?;
+            let filter = VpnTrafficFilter::Create(app_id)?;
+            filter.SetRoutingPolicyType(routing_policy)?;
+            filter_list.Append(filter)?;
+            debug_log!(
+                "Traffic filter: FilePath={} RoutingPolicyType={}",
+                app_path,
+                routing_policy.0
+            );
+        }
+        debug_log!("Traffic filter count: {}", filter_list.Size()?);
+
         // VPN 설정 시작
-        channel.Start(
+        channel.StartWithTrafficFilter(
             ipv4_addrs,
             ipv6_addrs,
             None, // VPN 터널용 IPv6 주소의 인터페이스 ID 부분
@@ -230,9 +280,10 @@ impl VpnPlugin {
             namespace_assignment,
             1500,  // VPN 터널 인터페이스 MTU
             1600,  // 원격 끝점에서 들어오는 버퍼의 최대 프레임 크기
-            false, // 저비용 네트워크 모니터링 비활성
+            false, // 예약됨
             sock,  // 원격 끝점으로 가는 소켓
             None,  // 보조 소켓 미사용
+            traffic_filters,
         )?;
 
         // 연결 성공 로그
diff --git a/plugin/src/utils.rs b/plugin/src/utils.rs
index 0bce32a..caa1a72 100644
--- a/plugin/src/utils.rs
+++ b/plugin/src/utils.rs
@@ -115,6 +115,15 @@ impl<'a, T: RuntimeType + 'static> IntoParam<'a, IVector<T>> for Vector<T> {
     }
 }
 
+// `VpnDomainNameInfo::CreateVpnDomainNameInfo` 는 `IIterable<HostName>` 을 받습니다.
+// 예전 `VpnNamespaceInfo::CreateVpnNamespaceInfo` 는 `IVector<HostName>` 을 받았습니다.
+// 그래서 `Vector` 를 `IIterable` 로도 넘길 수 있어야 합니다. 인터페이스 자체는 이미 구현되어 있습니다.
+impl<'a, T: RuntimeType + 'static> IntoParam<'a, IIterable<T>> for Vector<T> {
+    fn into_param(self) -> Param<'a, IIterable<T>> {
+        Param::Owned(self.into())
+    }
+}
+
 /// `Vector` 용 `IIterator` 래퍼
 #[implement(Windows::Foundation::Collections::IIterator<T>)]
 struct VectorIterator<T: RuntimeType + 'static> {
```

**패치 적용 후 확인 사항**
- 1500/1600은 **판별 시험 동안 그대로 둡니다**(1단계와 2단계의 유일한 차이를 필터로 한정하기 위해). 제품화 시에는 1420/1500으로 낮춥니다.
- `AllowOutbound`/`AllowInbound`가 명시적으로 true인 것을 확인하십시오. 이게 U3 대비책입니다.
- `StartWithTrafficFilter` 호출이 예외를 던지면, 원인이 필터인지 DNS 타입 교체인지 먼저 분리하십시오(부록 B의 DNS 블록만 바꾸고 필터는 빈 assignment로 넘겨서 시험).

---

## 부록 C — 참조 위치 색인

```
검증된 빌드 트리 (깨끗함, 패치 적용됨)
  ...\scratchpad\wg-baseline

패치 파일
  ...\scratchpad\per-app-traffic-filter.patch

참조 클론 (★ dirty 상태, upstream 아님. 커밋 전에 반드시 정리)
  ...\scratchpad\wireguard-uwp-rs
    appx\AppxManifest.xml                    매니페스트 원본
    plugin\src\plugin.rs:225                 유일한 channel.Start() 호출 지점
    plugin\src\plugin.rs:63,69               CustomConfiguration 읽는 곳
    plugin\src\plugin.rs:215-216             서버 주소는 프로필에서, 포트만 XML에서
    plugin\src\plugin.rs:461,466,504,557,562 패킷 버퍼 누수 TODO 5곳
    plugin\src\config.rs:23-25               quick_xml 파싱 진입점
    plugin\src\background.rs:74-92           DllGetActivationFactory
    plugin\Cargo.toml:21-36                  windows = "0.28"

로컬 SDK 근거
  C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\winrt\windows.networking.vpn.idl
  C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\winrt\AppxManifestTypes.xsd:695-702, 1125-1132
  C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\{makeappx,signtool,MakePri}.exe

크레이트 근거
  C:\Users\NetMD\.cargo\registry\src\index.crates.io-1949cf8c6b5b557f\windows-0.28.0\src\Windows\Networking\Vpn\mod.rs
    :2013 VpnAppId::Create   :2078 VpnAppIdType   :2365 StartWithTrafficFilter
    :4351 CreateVpnDomainNameInfo   :6196 VpnRoutingPolicyType
    :6357 VpnTrafficFilter::Create  :6422 VpnTrafficFilterAssignment
```

---

## 마지막으로 — 이 문서가 말하고 있는 것

문서는 "된다"고 읽히고, 코드는 컴파일되고, 프로필도 만들어집니다. 하지만 **11년 동안 아무도 이 조합을 성공시킨 적이 없고, 마이크로소프트 자신의 샘플도 핵심 속성을 건드리지 않으며, 마이크로소프트가 이 앱 ID 타입을 쓰지 말라고 했고, 반박 담당 세 명이 각각 다른 이유로 안 될 거라고 했습니다.**

그래도 시험하는 이유는 단 하나, **4시간이면 확실히 알 수 있기 때문**입니다. 그 이상의 의미를 이 판정에 부여하지 마십시오.
