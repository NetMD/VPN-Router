# 가려진 시험 결과 템플릿

공유 전 아래 항목만 남아 있는지 확인합니다. 원본 앱 이름·경로·번들 ID·서명 식별자, 주소·도메인·포트·DNS 내용·패킷, Team ID, 인증서·프로비저닝 정보, 키와 설정 전문은 기록하지 않습니다.

## 실행 요약

- 증거 등급: `automated` / `signedMac`
- 후보: `transparentProxy`
- 판정: `notRun` / `pass` / `fail` / `inconclusive` / `stopped`
- 결과 수: 0건
- 사용자 승인 수행 여부: 예 / 아니요
- P3 WireGuard 전달 수행 여부: 아니요

## 환경 확인

- 필요한 권한 존재: `true` / `false` / 확인하지 못함
- 시스템 확장 활성화 관찰: `true` / `false` / 확인하지 못함
- 실제 TCP·UDP 흐름 수신: `true` / `false` / 확인하지 못함
- 통제 앱 일반 인터넷 보존: `true` / `false` / 확인하지 못함
- 중단 뒤 DNS·IPv4·IPv6 확인: `true` / `false` / 확인하지 못함

## 가려진 JSON 예시

```json
{
  "schemaVersion": 1,
  "runId": "00000000-0000-4000-8000-000000000001",
  "candidateKind": "transparentProxy",
  "evidenceTier": "signedMac",
  "flowKind": "udpIPv6",
  "appRole": "selectedApp",
  "flowAge": "newFlow",
  "spikeResult": "inconclusive",
  "failureCode": "wireguard-transport-unavailable",
  "observedAt": "2026-08-04T00:01:00Z",
  "durationMs": 12
}
```

## 알려진 제한

- 컴파일과 자동 검사는 실제 Network Extension 활성화를 증명하지 않습니다.
- P2는 흐름 수신과 앱 신원 판독까지만 다룹니다.
- WireGuard 출구, DNS, IPv6, QUIC, 재귀, 다른 VPN 공존은 실제 서명 증거가 없으면 `inconclusive`입니다.
- P3 전달 구조와 제품 통합은 사용자 승인 전 NO-GO입니다.
