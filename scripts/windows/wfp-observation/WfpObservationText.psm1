# WfpObservationText.psm1 — 바깥 도구 출력 글자를 값으로 바꾸는 순수 함수 모음
#
# 왜 따로 떼어 두나: 아래 다섯 가지는 전부 "글자(또는 JSON 글자)를 받아 값을 돌려주는"
# 순수 함수다. 그런데 관찰 스크립트 안에 있으면 시험이 부를 수 없다 — 스크립트를 점
# 소스하면 본문이 통째로 돌기 때문이다. 그래서 이 다섯을 모듈로 뽑아, 고정값 시험이
# 바깥 도구를 한 번도 안 부르고 직접 부를 수 있게 한다.
#
# 안 옮기는 것 (일부러): pktmon 되돌리기 함수 두 개는 여기 없다. 그 둘은
# Get-WfpSpikeInterface.ps1 에 그대로 남아 있고, 스크립트 범위 변수($script:*)를
# 각각 8건 · 5건 참조한다(AST 로 셈). 모듈은 변수 범위가 달라서, 옮기면 되돌리기가
# 조용히 멈춘다 — 그 증상이 정확히 이 라운드가 고치려는 사고다.
# (그 두 이름을 이 파일에 글자로 적지 않는다. 회귀 확인이 "이 파일 안에 그 이름이
#  0건"인 것을 글자 무늬로 세기 때문에, 주석에 적으면 지키고도 걸린 것처럼 보인다.)
#
# 이 파일에 있는 것 (5개)
#   ConvertFrom-PktmonFilterText    거르개 목록 글자 -> 줄 객체
#   Read-PktmonFilterRecord         되돌릴 목록 기록 파일 -> 기록 객체
#   ConvertTo-RoundTripUtcText      아무 값 -> UTC 왕복 서식 글자
#   Get-PacketComponentId           꾸러미 줄 -> 구성 요소 번호
#   ConvertFrom-PktmonComponentJson pktmon list --json 글자 -> 구성 요소/인터페이스 지도
#
# 앞의 넷은 Get-WfpSpikeInterface.ps1 에서 글자 그대로 옮겼다. 다섯 번째는 그 파일의
# 인라인 코드에서 뽑아 함수 껍데기만 새로 씌운 것이고, 고리 본문은 그대로 두었다.

# `pktmon filter list` 의 글자 출력에서 거르개 줄만 뽑는다.
#
# 이 PC 의 pktmon 은 --json 을 받지 않는다(실측). 그렇다고 "못 읽었다"로 두면
# 거르개가 원래 0개였던 흔한 경우에도 되돌리기 실패로 적히고, 되돌릴 목록 파일이
# 실행마다 쌓인다. 그래서 글자도 읽는다.
#
# 자료 줄은 번호로 시작한다 — 머리글 줄은 `#`, 구분 줄은 `-` 로 시작한다.
# 숫자로 가르므로 화면 말이 어느 나라 말이든 같게 동작한다.
# 칸 차례는 `# 이름 프로토콜 IP주소 포트` 다.
function ConvertFrom-PktmonFilterText {
    param([AllowEmptyString()][string]$Text)

    $rows = [Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*\d+\s+(?<rest>\S.*?)\s*$')
        if (-not $match.Success) { continue }
        $tokens = @($match.Groups['rest'].Value -split '\s+')
        if ($tokens.Count -lt 1 -or [string]::IsNullOrWhiteSpace($tokens[0])) { continue }
        $rows.Add([pscustomobject]@{
            name     = $tokens[0]
            protocol = if ($tokens.Count -ge 2) { $tokens[1] } else { "" }
            ip       = if ($tokens.Count -ge 3) { $tokens[2] } else { "" }
            port     = if ($tokens.Count -ge 4) { $tokens[3] } else { "" }
        })
    }
    return @($rows)
}

# 실행 폴더에 남은 되돌릴 목록을 읽는다. Start 와 Stop 이 같은 함수를 쓴다.
#
# 개수와 목록이 서로 맞지 않으면 "못 읽었다"로 본다. 예전에는 개수가 비어 있으면
# [int]$null 이 0 이 되어 "원래 0개였다"로 읽혔고, 그러면 되돌리기가 성공한 것으로
# 처리되어 이 기록 파일이 지워졌다 — 사용자 거르개의 유일한 사본이 사라진다.
function Read-PktmonFilterRecord {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $savedFormat = [string]$saved.format
        if ($savedFormat -ne "JSON" -and $savedFormat -ne "TEXT") {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        # 개수 칸이 비어 있으면 0 으로 읽지 않는다. 못 읽은 것이다.
        [int]$savedCount = -1
        if (-not [int]::TryParse([string]$saved.filterCount, [ref]$savedCount) -or $savedCount -lt 0) {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        $savedFilters = @()
        if ($savedCount -gt 0) { $savedFilters = @($saved.filters) }
        # 적어 둔 개수와 실제 목록 길이가 다르면 그 기록은 믿을 수 없다.
        if ($savedFilters.Count -ne $savedCount) {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        return [pscustomobject]@{ Format = $savedFormat; Filters = $savedFilters; Raw = [string]$saved.raw }
    }
    catch {
        return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = "" }
    }
}

# 실행 폴더에 남긴 시각을 다시 읽을 때 쓴다.
#
# ConvertFrom-Json 은 ISO-8601 모양의 글자를 [datetime] 으로 바꿔 놓는다. 그 값을
# [string] 로 되돌리면 현재 문화권 서식의 "현지 시각·초 단위" 글자가 나온다
# (실측: "2026-08-17T06:35:26.2726621+00:00" -> "08/17/2026 15:35:26").
# 그대로 -PolicyAppliedAtUtc 와 견주면 같은 초에 걸린 두 시각이 "앞선다"로 뒤집혀
# UNOBSERVED ⑤ 로 닫힌다. 기록으로 남는 값도 UTC 가 아니게 된다.
# 2026-08-17 실측: 정책과 잡기 시작 간격 0.2초 -> CAPTURE_BEFORE_POLICY · 10초 -> 정상.
function ConvertTo-RoundTripUtcText {
    param($Value)

    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString("O") }
    if ($Value -is [datetime]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString("O") }
    return [string]$Value
}

# 꾸러미 줄 하나에서 구성 요소 번호를 뽑는다.
#
# pktmon etl2txt 의 칸 이름표는 창 표시 언어를 따라 번역된다. 이 PC 실측(2026-08-17):
#   영어  ... Direction Tx , Type Ethernet , Component 80, Edge 1, Filter 1, ...
#   한국어 ... 방향 Tx , 유형 Ethernet , 구성 요소 80, 에지 1, 필터 1, ...
# 그래서 "Component" 라는 이름표만 찾으면 한국어 PC 에서는 한 줄도 안 걸리고,
# 잡기가 정상이어도 꾸러미 0개(NO_PACKET_CAPTURED)로 닫힌다.
#
# 이름표가 번역돼도 칸의 자리는 같다. 쉼표로 나눈 순서는 이렇다.
#   0 PktGroupId · 1 PktNumber · 2 모양 · 3 방향 · 4 유형 · 5 구성 요소 · 6 에지 · 7 필터
#   · 8 OriginalSize · 9 LoggedSize
# 자리로 뽑은 값이 지도에 없으면 세지 않으므로, 서식이 바뀌어도 틀린 값을 만들지 않는다.
function Get-PacketComponentId {
    param([Parameter(Mandatory)][string]$Line)

    $match = [regex]::Match($Line, '(?i)\bComponent\s*[:=]?\s*(\d+)')
    if ($match.Success) { return $match.Groups[1].Value }

    $fields = $Line.Split(',')
    if ($fields.Count -lt 10) { return $null }
    $fieldMatch = [regex]::Match($fields[5], '(\d+)\s*$')
    if (-not $fieldMatch.Success) { return $null }
    return $fieldMatch.Groups[1].Value
}

# pktmon list --json 글자에서 "구성 요소 번호 -> 인터페이스 번호" 지도를 만든다.
#
# 이 함수는 Get-WfpSpikeInterface.ps1 의 인라인 코드에서 뽑았다. 뽑기 전에는 이 논리를
# 시험할 방법이 아예 없었다 — 함수가 아니었기 때문이다. 껍데기(함수 선언·빈 값 검사·
# return)만 새로 쓰고 고리 본문은 원래 글자를 그대로 두었다. 결함이 있던 자리가 정확히
# 그 고리 본문이라 보존하는 것이 값이다.
#
# 아래 주석은 원본에 있던 실측 기록이다.
#   pktmon 의 구성 요소 번호는 인터페이스 번호와 다르다. pktmon list 로 지도를 만든다.
#   지도를 못 만들면 UNOBSERVED 3 이다. 다른 도구로 임의로 대신하지 않는다.
#   pktmon list --json 은 평평한 목록이 아니다. 실측 구조(2026-08-17)는 이렇다.
#     [ { "Group": "...", "Components": [ { "Id": 124, "Properties": [ { "Name": "ifIndex", "Value": 8 } ] } ] } ]
#   인터페이스 번호는 구성 요소의 직접 속성이 아니라 Properties 목록 안 이름/값 쌍이다.
#   옛 코드는 맨 바깥 객체에서 Id 와 ifIndex 를 직접 찾아, 지도가 늘 빈 채로 끝났다
#   (꾸러미를 세어도 COMPONENT_INDEX_UNREADABLE 로 닫혔다).
#   평평한 목록으로 오는 판도 대비해 Components 가 없으면 그 객체 자체를 구성 요소로 본다.
#
# 알려진 성질 (이번에 안 바꿈): 같은 구성 요소 번호가 여러 번 나오면 마지막 것이 이긴다.
# 2026-08-18 이 PC 실측 — 구성 요소 137개 가운데 번호가 겹치는 값이 17개다. 그런데
# ifIndex 를 가진 50개의 번호는 서로 안 겹쳐서 오늘은 해가 없다. 동작을 안 바꾸고
# 지금 동작을 시험으로 고정한다. 겹침 위험은 다음 차수로 넘긴다.
#
# 못 만들면 빈 지도다. 예외를 던지지 않는다 — 부르는 쪽이 그 뒤에 UNOBSERVED 로 닫는다.
function ConvertFrom-PktmonComponentJson {
    param([AllowEmptyString()][AllowNull()][string]$Json)

    $componentToInterface = @{}
    if ([string]::IsNullOrWhiteSpace($Json)) { return $componentToInterface }
    try {
        $listJson = $Json | ConvertFrom-Json
        foreach ($group in @($listJson)) {
            if ($null -eq $group) { continue }
            $groupComponents = if ($group.PSObject.Properties.Name -contains "Components") { @($group.Components) } else { @($group) }
            foreach ($component in $groupComponents) {
                if ($null -eq $component) { continue }

                $componentId = $null
                foreach ($name in @("Id", "ComponentId", "id")) {
                    if ($component.PSObject.Properties.Name -contains $name) { $componentId = [string]$component.$name; break }
                }
                if ([string]::IsNullOrWhiteSpace($componentId)) { continue }

                $interfaceIndex = $null
                # 먼저 직접 속성으로 있는지 본다.
                foreach ($name in @("InterfaceIndex", "IfIndex", "NetworkInterfaceIndex", "ifIndex")) {
                    if ($component.PSObject.Properties.Name -contains $name) { $interfaceIndex = [string]$component.$name; break }
                }
                # 없으면 Properties 목록에서 이름으로 찾는다.
                if ([string]::IsNullOrWhiteSpace($interfaceIndex)) {
                    foreach ($property in @($component.Properties)) {
                        if ($null -eq $property) { continue }
                        if ([string]$property.Name -in @("ifIndex", "IfIndex", "InterfaceIndex", "NetworkInterfaceIndex")) {
                            $interfaceIndex = [string]$property.Value
                            break
                        }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($interfaceIndex)) { continue }

                $componentToInterface[$componentId] = [int]$interfaceIndex
            }
        }
    }
    catch { $componentToInterface = @{} }
    return $componentToInterface
}

# 앱을 띄우기 "전"에는 없던 로컬 포트만 새 연결로 본다.
#
# 이 함수도 New-WfpSpikeFlow.ps1 의 인라인 한 줄에서 뽑았다. 판정식 모양은 그대로 두고
# 이름만 인자 이름으로 바꿨다. 뽑기 전에는 이 차집합을 시험할 방법이 없었다.
#
# 왜 프로세스 번호로 안 거르나 (원본 주석의 실측 기록): 브라우저가 이미 떠 있으면
# 우리가 띄운 실행기는 일을 넘기고 곧 끝나고, 소켓을 여는 것은 브라우저의 network
# service 자식이다. 그래서 "우리가 띄운 번호"로 거르면 어느 브라우저에서도 안 맞는다.
# 대신 대상 주소·포트로 가는 연결 가운데 앱을 띄우기 전에는 없던 로컬 포트를 쓴다.
function Select-NewLocalPort {
    param(
        # 앱을 띄우기 "전"에 이미 있던 로컬 포트.
        [AllowEmptyCollection()][int[]]$PreexistingPort = @(),
        # 지금 보이는 로컬 포트.
        [AllowEmptyCollection()][int[]]$ObservedPort = @()
    )

    return @($ObservedPort | Where-Object { -not ($PreexistingPort -contains [int]$_) })
}

# 내보내는 이름을 하나씩 적는다. 여기 안 적은 것은 밖에서 안 보인다 —
# 시험 하나가 이 집합을 정확히 대조한다.
Export-ModuleMember -Function @(
    'ConvertFrom-PktmonFilterText',
    'Read-PktmonFilterRecord',
    'ConvertTo-RoundTripUtcText',
    'Get-PacketComponentId',
    'ConvertFrom-PktmonComponentJson',
    'Select-NewLocalPort'
)
