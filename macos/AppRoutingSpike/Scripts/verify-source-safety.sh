#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPIKE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if rg -n 'NWConnection[[:space:]]*\(' \
  "$SPIKE_ROOT/Networking" "$SPIKE_ROOT/TransparentProxyExtension"; then
  echo "안전 검사 실패: P2에서 외부 NWConnection 생성은 허용되지 않습니다." >&2
  exit 1
fi

if rg -n '(^|[[:space:]])(route|networksetup)([[:space:]]|$)' \
  "$SPIKE_ROOT/Networking" "$SPIKE_ROOT/TransparentProxyExtension" "$SPIKE_ROOT/Scripts" \
  --glob '*.swift' --glob '*.sh'; then
  echo "안전 검사 실패: 수동 경로 또는 DNS 변경 명령을 찾았습니다." >&2
  exit 1
fi

duplicate_contracts=$(rg -l \
  'enum (CandidateKind|EvidenceTier|SpikeResult|FlowKind|AppRole|FlowAge)' \
  "$SPIKE_ROOT" --glob '*.swift' | wc -l | tr -d ' ')
if [ "$duplicate_contracts" -ne 1 ]; then
  echo "안전 검사 실패: enum 계약은 SpikeContracts.swift 한 곳에만 있어야 합니다." >&2
  exit 1
fi

inline_limits=$(rg -n '262144|5242880|65535|65536|2000' \
  "$SPIKE_ROOT/Networking" "$SPIKE_ROOT/TransparentProxyExtension" \
  --glob '*.swift' --glob '!SpikeLimits.swift' || true)
if [ -n "$inline_limits" ]; then
  echo "안전 검사 실패: SpikeLimits 밖에 경계값 리터럴이 있습니다." >&2
  echo "$inline_limits" >&2
  exit 1
fi

echo "소스 안전 검사 통과: P2 직접 연결·수동 네트워크 변경·계약 중복·경계값 중복 0건"
