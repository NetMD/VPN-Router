#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=${SPIKE_REPOSITORY_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)}
cd "$REPOSITORY_ROOT"

protected_paths="macos/VPNRouter windows docs/v0.1.0-release-plan.md docs/platform-parity-contract.md docs/platform-parity-audit.md"
generated_paths="macos/AppRoutingSpike/DerivedData macos/AppRoutingSpike/DerivedData-test macos/AppRoutingSpike/DerivedData-r3 macos/AppRoutingSpike/DerivedData-fe-host macos/AppRoutingSpike/DerivedData-fe-selected macos/AppRoutingSpike/DerivedData-fe-control"

collect_protected_changes() {
  for path in $protected_paths; do
    git diff --name-only -- "$path"
    git diff --cached --name-only -- "$path"
    git ls-files --others --exclude-standard -- "$path"
  done
}

protected_changes=$(collect_protected_changes | sort -u)

if [ -n "$protected_changes" ]; then
  echo "격리 검사 실패: 제품 또는 릴리스 보호 경로에 변경이 있습니다." >&2
  echo "$protected_changes" >&2
  exit 1
fi

for path in $generated_paths; do
  probe="$path/Build/probe"
  if ! git check-ignore -v --no-index -- "$probe" >/dev/null; then
    echo "격리 검사 실패: 생성물 Git 제외 규칙이 없습니다: $path" >&2
    exit 1
  fi
done

generated_status=$(git status --short --untracked-files=all -- $generated_paths)
if [ -n "$generated_status" ]; then
  echo "격리 검사 실패: 생성물 경로가 작업 트리에 표시됩니다." >&2
  echo "$generated_status" >&2
  exit 1
fi

echo "격리 검사 통과: 보호 경로 변경 0건, DerivedData 두 경로 Git 표시 0건"
