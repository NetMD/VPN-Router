# VPN Router

선택한 사이트만 기존 VPN 연결로 보내고, 나머지 인터넷은 평소 네트워크에
그대로 두는 데스크톱 앱입니다. VPN 서비스를 제공하는 제품이 아니라 사용자가
가져온 WireGuard 프로필을 안전하게 관리하고 사이트별 경로를 만드는 도구입니다.

## 한눈에 보기

```text
선택 사이트
    │
    ├─ DNS 응답 관찰 · 주소별 경로 계획
    │
    ▼
기존 WireGuard VPN ───── 선택 사이트만 VPN
일반 네트워크 ────────── 그 밖의 트래픽
```

VPN Router는 다음 원칙을 중심으로 동작합니다.

- 프로필과 사이트를 사용자가 직접 선택합니다.
- 개인 키는 플랫폼의 보호된 저장소에만 보관합니다.
- 다른 VPN, 광고 차단기, 보안 DNS, 백신을 자동으로 끄거나 바꾸지 않습니다.
- DNS 응답 경로와 VPN Router가 소유한 상태를 계속 확인합니다.
- 안전하게 유지할 수 없으면 VPN Router가 만든 DNS·경로·터널만 정리합니다.
- 진단 파일에는 상태, 개수, 시각과 오류 코드만 넣고 원문 설정·키·주소를
  넣지 않습니다.

## 플랫폼

| 플랫폼 | 앱 | 네트워크 계층 | 배포 상태 |
|---|---|---|---|
| Windows 11 x64 | WinUI 3 / .NET 10 | Windows 서비스, WireGuard, DNS, 경로, IPC | portable EXE 검증 및 GitHub Actions 준비 |
| macOS 15+ Apple Silicon | SwiftUI | Packet Tunnel + DNS Proxy System Extension, Keychain | unsigned 패키지 검증 완료; 서명·공증·실제 연결 검증 진행 중 |

두 플랫폼은 홈, VPN 프로필, VPN 사이트, 문제 해결, 설정의 다섯 영역과
사용자에게 보이는 작업 의미를 공유합니다. 저수준 VPN·DNS·경로·권한·저장소
구현은 운영체제별로 분리합니다.

## 빠른 시작

### Windows 개발 실행

필요한 것:

- Windows 11 x64
- .NET 10 SDK와 WinUI 개발 도구
- 공식 WireGuard for Windows 설치
- 관리자 권한이 필요한 개발 연결 테스트 환경

저장소 루트에서 실행합니다.

```powershell
dotnet build .\windows\VpnRouter.slnx -nr:false
dotnet build .\windows\VpnRouterVs.sln -nr:false
dotnet run --project .\windows\VpnRouter.Tests\VpnRouter.Tests.csproj --no-build
```

개발 실행 스크립트와 복구 절차는 다음 문서에 있습니다.

- [Windows 다음 작업](docs/windows-next-session.md)
- [Windows MVP 진행 기록](docs/windows-mvp-progress.md)
- [Windows 서비스 개발 안내](docs/windows-service-dev.md)
- [Windows 릴리스 보강](docs/windows-release-hardening.md)

### macOS 개발 실행

필요한 것:

- macOS 15 이상을 권장하는 Apple Silicon Mac
- Xcode와 Swift
- WireGuardKit Go bridge를 빌드할 Go 도구
- Network Extension을 실행할 Apple 서명·프로비저닝 환경

순수 로직 테스트는 다음과 같이 실행합니다.

```bash
cd macos/VPNRouter
swift test
```

Xcode에서 실행한 앱은 System Extension 활성화를 위해 `/Applications`에
설치된 앱이어야 합니다. DerivedData에서 바로 실행하면 운영체제가 부모 앱
위치를 거부합니다. 실제 Packet Tunnel·DNS Proxy 동작은 서명된 앱을 실제 Mac에
설치한 뒤 확인해야 하며, 컴파일 성공만으로 동작을 주장하지 않습니다.

- [macOS 다음 작업](docs/macos-next-session.md)
- [macOS MVP 진행 기록](docs/macos-mvp-progress.md)
- [macOS 릴리스 보강](docs/macos-phase4-release-hardening.md)

## 빌드와 릴리스

`.github/workflows/release.yml`은 다음 두 방식으로 실행됩니다.

1. `v0.1.0`과 같은 태그를 push합니다.
2. GitHub Actions에서 수동 실행하고 버전을 입력합니다.

Windows 작업은 두 솔루션과 focused test를 실행한 뒤 portable EXE와 SHA-256을
만듭니다. macOS 작업은 Apple Silicon arm64 앱과 내장 확장을 검증한 뒤 unsigned
ZIP, DMG와 체크섬을 만듭니다. 두 작업이 성공하면 태그 실행은 GitHub Release를
자동으로 만들고 산출물을 올립니다.

현재 macOS Actions 산출물은 unsigned compile/package evidence입니다. 실제
System Extension 배포에는 Developer ID 서명, 공증, stapling, Gatekeeper와
실제 Mac 설치 검증이 추가로 필요합니다. GitHub Actions에 인증서나 개인 키를
커밋하지 말고, 서명 단계를 추가할 때는 GitHub Secrets와 최소 권한을 사용합니다.

## 구조

```text
vpn_router/
├── windows/
│   ├── VpnRouter.App/          # WinUI 3 화면
│   ├── VpnRouter.Service/      # 권한이 필요한 네트워크 백엔드
│   ├── VpnRouter.Launcher/     # portable 단일 실행 파일
│   ├── VpnRouter.Core/         # 공통 규칙과 모델
│   ├── VpnRouter.Ipc/          # 앱-백엔드 계약
│   ├── VpnRouter.Networking/   # DNS와 Windows 경로
│   └── VpnRouter.Vpn/          # WireGuard 어댑터
├── macos/VPNRouter/
│   ├── VPNRouter/              # SwiftUI 호스트 앱과 공유 로직
│   ├── PacketTunnel/           # Packet Tunnel 확장
│   ├── DNSProxyExtension/      # DNS Proxy 확장
│   └── Tests/                  # Swift 테스트
├── scripts/
│   ├── windows/                # portable 빌드·검증·복구 스크립트
│   └── macos/                  # 앱·서명 구조 검증 스크립트
└── docs/                       # 제품 계약, 플랫폼 인수인계, 릴리스 기록
```

## 제품 범위와 현재 한계

현재 범위:

- WireGuard 프로필 가져오기, 정리, 이름 변경, 선택과 삭제
- 루트 도메인과 하위 도메인 사이트 규칙
- YouTube·Netflix 미디어/CDN 확장 규칙
- IPv4 사이트 경로와 대상 도메인 AAAA 보호
- DNS 소유권 확인, 연결 해제 정리와 다음 실행 복구
- 제한된 진단 파일과 수동 네트워크 복구

아직 릴리스 범위 밖인 항목:

- OpenVPN, L2TP, 모바일 앱
- 앱별 라우팅과 전체 IPv6 분할 라우팅
- VPN 제공업체 계정 자동화
- 자동 업데이트와 일반 설치 프로그램
- Windows x86/ARM64, Intel Mac
- captive portal 자동 로그인·복구
- 계정이 필요한 Netflix 재생 자동화

## 보안과 개인정보

실제 WireGuard 설정 파일, 개인 키, 토큰, 진단 원문을 저장소에 추가하지
마십시오. 테스트에는 가짜 키를 사용하고, 문제를 공유할 때도 상태·개수·시각과
오류 코드만 남기십시오. VPN Router는 다른 VPN이나 보안 제품을 자동으로
중지하거나 재설정하지 않습니다.

플랫폼별 안전 경계와 공통 동작은 다음 문서에서 관리합니다.

- [플랫폼 공통 계약](docs/platform-parity-contract.md)
- [UI/UX 원칙](docs/ui-design-principles.md)
- [Windows UI/UX 전달 사항](docs/windows-ui-ux-handoff.md)
- [v0.1.0 릴리스 계획](docs/v0.1.0-release-plan.md)
- [변경 기록](CHANGELOG.md)
- [macOS와 Windows 릴리스 준비 상태](docs/platform-parity-audit.md)

## 라이선스

VPN Router 프로젝트는 [MIT License](LICENSE.md)로 배포됩니다. 저장소에
포함된 WireGuardKit과 기타 외부 구성 요소는 각자의 라이선스와 고지를
따릅니다. 배포할 때 upstream 고지를 제거하지 마십시오.
