# Test-WfpObservationFixture.ps1 — 관찰 도구의 고정값 회귀 시험
#
# 이 파일이 있는 이유
#   관찰 도구가 바깥 도구의 글자 출력을 읽어 값을 만든다. 그 해석이 틀리면 잡기가
#   정상이어도 "관찰 못 함"으로 닫힌다. 지난 차수에 그런 결함이 여러 건 나왔고,
#   자동 검사 넷이 전부 못 잡았다. 사람이 손으로 도는 예행은 회귀 가드가 아니다 —
#   한 경로만 덮고, 이 PC 에서만 돈다. 그래서 고정값 시험을 따로 만든다.
#
# 지키는 규칙 (기계 독립)
#   1. 바깥 모듈을 안 쓴다. 이 PC 에 깔린 Pester 는 3.4.0 하나뿐이고 러너 이미지의
#      판은 여기서 확인할 수 없다. 판이 다르면 같은 시험이 다른 기계에서 조용히 깨진다.
#      필요한 것이 등호 비교뿐이라 자체 실행기로 충분하다.
#   2. 이 PC 의 파일을 안 읽는다. 아래 고정값은 실제 산출물에서 "한 번 떠서" 저장소 안
#      글자로 옮겨 둔 것이다. 시험이 도는 동안 디스크에서 읽는 고정값은 0건이다.
#   3. 바깥 명령을 0회 부른다. 잡기 도구·어댑터 조회·연결 조회·경로 조회·형상 관리·
#      빌드 도구를 한 번도 안 부른다. 읽는 것은 저장소 안 .ps1 · .psm1 원문뿐이다.
#   4. 이 PC 에서만 맞는 값(인터페이스 번호 같은 것)을 기대값으로 안 쓴다.
#   5. 같은 입력에 늘 같은 답을 낸다. 시각·임의 값·기계 이름에 기대는 자리가 0건이다.
#
# 고정값 출처를 두 가지로 갈라 적는다
#   [이 기계 실물]   2026-08-17~18 에 이 PC 에서 실제로 뜬 산출물에서 옮긴 글자.
#   [코드 주석 기록] 관찰 스크립트 머리 주석에 적힌 지난 차수 실측을 옮긴 글자.
#                    이 PC 에 실물이 0건이라 실물로 확인한 것이 아니다.
#
# 부르는 방법
#   사람 · 자동 검사 : ./Test-WfpObservationFixture.ps1        (전부 통과 0 · 하나라도 실패 1)
#   같은 프로세스     : ./Test-WfpObservationFixture.ps1 -AsObject  (요약 객체 하나 · 조용)

[CmdletBinding()]
param(
    # 부르는 쪽이 결과를 값으로 받고 싶을 때 준다. 이때는 화면에 아무것도 안 내고
    # exit 도 안 부른다 — 부르는 쪽 프로세스를 끝내면 안 되기 때문이다.
    [switch]$AsObject
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------------------------------------------------------------------
# 자리 — 전부 이 파일 자기 폴더 기준이다. 부르는 쪽 폴더를 안 따라간다.
# ---------------------------------------------------------------------------
$observationRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\wfp-observation"))
$modulePath = Join-Path $observationRoot "WfpObservationText.psm1"
$interfaceScript = Join-Path $observationRoot "Get-WfpSpikeInterface.ps1"
$flowScript = Join-Path $observationRoot "New-WfpSpikeFlow.ps1"
$tunnelScript = Join-Path $observationRoot "Use-WfpSpikeTunnel.ps1"
$policyScript = Join-Path $observationRoot "Get-WfpOwnedPolicyState.ps1"

# 이름을 조각으로 이어 붙이는 이유: 이 이름이 이 폴더에 글자로 있으면 안 된다는
# 회귀 확인이 걸려 있다. 같은 방법을 이 저장소가 이미 쓴다
# (fixtures\wfp-spike\prohibited-pattern-cases.json 의 pieces).
$forbiddenConnectionCommandName = "Get-Net" + "TCPConnection"

# 사람이 고른 정리 갈래 스위치의 이름. 같은 이유로 조각을 이어 붙인다 —
# "이 스위치를 붙여 부르는 자리가 저장소 안에 0건"인지를 글자 무늬로 세는 회귀 확인이
# 걸려 있다. 그 확인은 보안 관문(무인 자동 경로 0건)을 지키는 것이라 느슨하게 두지 않는다.
# 이 시험은 그 스위치를 "부르지" 않는다. 인자 정의만 원문에서 읽는다.
$harnessStopSwitchName = "StopHarness" + "First"

$results = [Collections.Generic.List[object]]::new()

# ---------------------------------------------------------------------------
# 아주 작은 실행기 — 등호 비교와 예외 잡기만 한다.
# ---------------------------------------------------------------------------
function Invoke-FixtureTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    try {
        [void](& $Body)
        $results.Add([pscustomobject]@{ name = $Name; passed = $true; detail = "" })
    }
    catch {
        # 예외를 통과로 읽지 않는다. 시험 안에서 무엇이 터지든 그 시험은 실패다.
        $results.Add([pscustomobject]@{ name = $Name; passed = $false; detail = ($_.Exception.Message -replace "\s+", " ") })
    }
}

function Assert-True {
    param([Parameter(Mandatory)][AllowNull()]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([AllowNull()]$Expected, [AllowNull()]$Actual, [Parameter(Mandatory)][string]$Message)
    $expectedText = if ($null -eq $Expected) { "<빈 값>" } else { [string]$Expected }
    $actualText = if ($null -eq $Actual) { "<빈 값>" } else { [string]$Actual }
    if ($expectedText -cne $actualText) {
        throw ("{0} — 기대 '{1}' · 실제 '{2}'" -f $Message, $expectedText, $actualText)
    }
}

function Assert-Null {
    param([AllowNull()]$Actual, [Parameter(Mandatory)][string]$Message)
    if ($null -ne $Actual) { throw ("{0} — 빈 값이어야 하는데 '{1}' 이(가) 나왔다" -f $Message, [string]$Actual) }
}

# ---------------------------------------------------------------------------
# 고정값 — 한 번 떠서 옮겨 둔 글자. 시험이 도는 동안 디스크에서 안 읽는다.
# ---------------------------------------------------------------------------

# [이 기계 실물] 예행 산출물 M-017 의 첫 꾸러미 줄. 쉼표 칸 10개.
# 칸 차례: 0 PktGroupId · 1 PktNumber · 2 모양 · 3 방향 · 4 유형 · 5 구성 요소
#          · 6 에지 · 7 필터 · 8 OriginalSize · 9 LoggedSize
$koreanPacketLine = '[00]49DC.4A38::2026-08-17 15:52:24.345685300 [Microsoft-Windows-PktMon] PktGroupId 556, PktNumber 1, 모양 0, 방향 Tx , 유형 Ethernet , 구성 요소 80, 에지 1, 필터 1, OriginalSize 66, LoggedSize 66 '

# [코드 주석 기록] 같은 줄의 영어 이름표 판.
# ⚠ 이 PC 에 영어 이름표 실물은 0건이다. 관찰 스크립트 머리 주석에 적힌 지난 차수
#   실측("... Direction Tx , Type Ethernet , Component 80, Edge 1, Filter 1, ...")을
#   같은 모양으로 옮긴 것이고, 영어 창에서 뜬 실물로 확인한 것이 아니다.
$englishPacketLine = '[00]49DC.4A38::2026-08-17 15:52:24.345685300 [Microsoft-Windows-PktMon] PktGroupId 556, PktNumber 1, Appearance 0, Direction Tx , Type Ethernet , Component 80, Edge 1, Filter 1, OriginalSize 66, LoggedSize 66 '

# [이 기계 실물] 같은 파일의 둘째 줄 — 꾸러미 줄이 아닌 본문 줄.
# 주소와 하드웨어 번호는 문서용 값으로 바꿨다. 이 시험이 보는 것은 "이 줄에는 꾸러미
# 표식이 없다"이지 주소가 아니고, 이 저장소는 공개 저장소라 이 PC 의 실제 주소를
# 넣을 이유가 없다. 줄의 모양(쉼표 자리·앞 탭)은 그대로 두었다.
$bodySummaryLine = "`t00-00-5E-00-53-01 > 00-00-5E-00-53-02, ethertype IPv4 (0x0800), length 66: 192.0.2.10.65375 > 192.0.2.1.443: Flags [S], seq 1612461100, win 65535, options [mss 1460,nop,wscale 8,nop,nop,sackOK], length 0"

# [이 기계 실물] 예행 산출물의 기준선 거르개 목록 — 30바이트. 줄 끝은 CRLF 그대로.
$koreanFilterListText = "패킷 필터:`r`n    없음`r`n`r`n"

# [코드 주석 기록] 거르개 목록 1건. 칸 차례는 머리 주석의 `# 이름 프로토콜 IP주소 포트`.
$englishFilterListText = "    #    Name              Protocol   IP Address   Port`r`n    1    wfp-spike-M-017   TCP        192.0.2.1    443`r`n"

# [이 기계 실물] 구성 요소 목록 JSON 의 중첩 판. 2026-08-18 실행분에서 필요한 만큼
# 줄여 옮겼다. 구성 요소 번호 60 을 일부러 두 번 넣어 "마지막 것이 이긴다"를 고정한다.
# 그 성질은 이번 차수에 안 바꾼다 — 지금 동작을 시험으로 묶어 둔다.
$nestedComponentJson = @'
[
  { "Group": "NDIS",
    "Components": [
      { "Id": 60, "Name": "Ethernet", "Properties": [ { "Name": "ifIndex", "Value": 8 } ] },
      { "Id": 62, "Name": "Wi-Fi",    "Properties": [ { "Name": "ifIndex", "Value": 15 } ] }
    ] },
  { "Group": "Filter Driver",
    "Components": [
      { "Id": 60, "Name": "QoS", "Properties": [ { "Name": "ifIndex", "Value": 99 } ] },
      { "Id": 80, "Name": "WFP", "Properties": [ { "Name": "OtherName", "Value": 1 } ] }
    ] }
]
'@

# [코드 주석 기록] 평평한 판 — Components 가 없으면 그 객체 자체를 구성 요소로 본다.
$flatComponentJson = @'
[
  { "Id": 124, "Properties": [ { "Name": "ifIndex", "Value": 8 } ] },
  { "Id": 125, "InterfaceIndex": 15 }
]
'@

# 결과 JSON 의 공통 칸. 어느 관찰 도구든 이 일곱 칸이 늘 있어야 한다.
$commonResultFields = @("schemaVersion", "tool", "startedAtUtc", "completedAtUtc", "source", "status", "failureReason")

# ---------------------------------------------------------------------------
# 원문을 AST 로 읽는 도우미 — 글자로 세면 주석이 섞인다.
# `--file-size` 는 관찰 스크립트에 세 번 나오고 그중 둘은 주석이다. AST 에는 주석이
# 없으므로 실제 인자 자리만 걸린다.
# ---------------------------------------------------------------------------
function Get-ScriptAst {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("원문을 못 찾았다: " + (Split-Path -Leaf $Path)) }
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) { throw ("원문이 안 읽힌다: " + (Split-Path -Leaf $Path)) }
    return $ast
}

# 배열 리터럴 안에서 어떤 인자 이름 바로 다음에 오는 값들을 모은다.
function Get-ArgumentValueAfter {
    param(
        [Parameter(Mandatory)]$Ast,
        [Parameter(Mandatory)][string]$ArgumentName
    )

    $values = [Collections.Generic.List[string]]::new()
    foreach ($array in $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true)) {
        $elements = @($array.Elements)
        for ($index = 0; $index -lt $elements.Count - 1; $index++) {
            $element = $elements[$index]
            if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $element.Value -ceq $ArgumentName) {
                $values.Add([string]$elements[$index + 1].Extent.Text.Trim('"', "'"))
            }
        }
    }
    return @($values)
}

# 어떤 명령의 어떤 인자에 붙은 값들을 모은다.
function Get-CommandParameterValue {
    param(
        [Parameter(Mandatory)]$Ast,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][string]$ParameterName
    )

    $values = [Collections.Generic.List[string]]::new()
    foreach ($command in $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        if ([string]$command.GetCommandName() -cne $CommandName) { continue }
        $elements = @($command.CommandElements)
        for ($index = 0; $index -lt $elements.Count - 1; $index++) {
            $element = $elements[$index]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                $element.ParameterName -ceq $ParameterName) {
                $values.Add([string]$elements[$index + 1].Extent.Text)
            }
        }
    }
    return @($values)
}

function Get-FunctionSourceText {
    param([Parameter(Mandatory)]$Ast, [Parameter(Mandatory)][string]$FunctionName)
    $found = @($Ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $FunctionName }, $true))
    if ($found.Count -ne 1) { throw ("함수를 딱 하나 못 찾았다: " + $FunctionName + " (찾은 수 " + $found.Count + ")") }
    return [string]$found[0].Extent.Text
}

# 관찰 도구를 부르는 방법을 부르는 쪽과 글자 그대로 같게 맞춘다
# (test-wfp-app-routing-spike.ps1 의 Invoke-ObservationScript 와 같은 모양).
function Invoke-ObservationScriptForTest {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    $output = & $ScriptPath @Arguments
    $lines = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    return [pscustomobject]@{ LineCount = $lines.Count; LastLine = if ($lines.Count -gt 0) { [string]$lines[-1] } else { "" } }
}

function Assert-ObservationResult {
    param(
        [Parameter(Mandatory)]$Invocation,
        [Parameter(Mandatory)][string]$ExpectedFailureReason,
        [Parameter(Mandatory)][string]$Label
    )

    Assert-Equal -Expected 1 -Actual $Invocation.LineCount -Message ($Label + " — 결과 줄이 한 줄이어야 한다")
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($Invocation.LastLine)) -Message ($Label + " — 결과 줄이 비었다")
    $parsed = $Invocation.LastLine | ConvertFrom-Json
    foreach ($field in $commonResultFields) {
        Assert-True -Condition ($parsed.PSObject.Properties.Name -contains $field) -Message ($Label + " — 공통 칸이 빠졌다: " + $field)
    }
    Assert-Equal -Expected $ExpectedFailureReason -Actual ([string]$parsed.failureReason) -Message ($Label + " — 실패 사유")
}

# ---------------------------------------------------------------------------
# 임시 자리 — F-09~F-11 만 쓴다. 매번 새로 만들고 끝에 반드시 지운다.
# 이 PC 의 개인 폴더 이름을 이 파일에 안 적는다.
# ---------------------------------------------------------------------------
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("wfp-observation-fixture-" + [guid]::NewGuid().ToString("N"))
$missingRunDirectory = Join-Path ([IO.Path]::GetTempPath()) ("wfp-observation-absent-" + [guid]::NewGuid().ToString("N"))

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot -Force)

    Import-Module -Name $modulePath -Force -ErrorAction Stop

    # =======================================================================
    # F-01 ~ F-03 : 꾸러미 줄에서 구성 요소 번호 뽑기
    # =======================================================================
    Invoke-FixtureTest -Name "F-01 꾸러미 줄에서 구성 요소 번호 뽑기 — 한국어 이름표" -Body {
        Assert-Equal -Expected "80" -Actual (Get-PacketComponentId -Line $koreanPacketLine) `
            -Message "한국어 이름표 줄에서 구성 요소 번호를 못 뽑았다"
        # 칸 수 경계 — 11칸이면 여섯째 칸이 그대로라 같은 답이어야 한다.
        Assert-Equal -Expected "80" -Actual (Get-PacketComponentId -Line ($koreanPacketLine + ", Extra 1")) `
            -Message "칸이 하나 늘어도 여섯째 칸을 봐야 한다"
    }

    Invoke-FixtureTest -Name "F-02 꾸러미 줄에서 구성 요소 번호 뽑기 — 영어 이름표" -Body {
        Assert-Equal -Expected "80" -Actual (Get-PacketComponentId -Line $englishPacketLine) `
            -Message "영어 이름표 줄에서 구성 요소 번호를 못 뽑았다"
    }

    Invoke-FixtureTest -Name "F-03 꾸러미 줄이 아닌 줄은 세지 않는다" -Body {
        # 세는 쪽이 꾸러미 줄을 가리는 표식은 PktGroupId 다. 본문 줄에는 그 표식이 없다.
        # 그래서 본문 줄은 이 함수에 아예 안 들어간다 — 그것이 이 시험이 지키는 사실이다.
        Assert-True -Condition ($bodySummaryLine.IndexOf("PktGroupId", [StringComparison]::Ordinal) -lt 0) `
            -Message "본문 줄에 꾸러미 표식이 있으면 안 된다"
        Assert-True -Condition ($koreanPacketLine.IndexOf("PktGroupId", [StringComparison]::Ordinal) -ge 0) `
            -Message "꾸러미 줄에는 표식이 있어야 한다"
        # 칸이 모자란 줄은 빈 값이다 (아홉 칸 경계).
        $nineFieldLine = $koreanPacketLine.Substring(0, $koreanPacketLine.LastIndexOf(','))
        Assert-Equal -Expected 9 -Actual ($nineFieldLine.Split(',').Count) -Message "아홉 칸짜리 줄을 못 만들었다"
        Assert-Null -Actual (Get-PacketComponentId -Line $nineFieldLine) -Message "칸이 모자라면 빈 값이어야 한다"
    }

    # =======================================================================
    # F-04 ~ F-06 : 구성 요소 지도 만들기
    # =======================================================================
    Invoke-FixtureTest -Name "F-04 구성 요소 지도 만들기 — 중첩 판" -Body {
        $map = ConvertFrom-PktmonComponentJson -Json $nestedComponentJson
        # 인터페이스 번호는 구성 요소의 직접 속성이 아니라 Properties 목록 안 이름/값 쌍이다.
        Assert-Equal -Expected 15 -Actual $map["62"] -Message "중첩 판에서 짝을 못 얻었다"
        # 같은 번호가 두 번 나오면 마지막 것이 이긴다 — 지금 동작을 그대로 고정한다.
        Assert-Equal -Expected 99 -Actual $map["60"] -Message "번호가 겹치면 마지막 것이 이겨야 한다"
        # ifIndex 가 없는 구성 요소는 지도에 안 들어간다.
        Assert-True -Condition (-not $map.ContainsKey("80")) -Message "인터페이스 번호가 없는 구성 요소는 지도에 없어야 한다"
        Assert-Equal -Expected 2 -Actual $map.Count -Message "지도 크기"
    }

    Invoke-FixtureTest -Name "F-05 구성 요소 지도 만들기 — 평평한 판" -Body {
        $map = ConvertFrom-PktmonComponentJson -Json $flatComponentJson
        Assert-Equal -Expected 8 -Actual $map["124"] -Message "평평한 판에서 Properties 를 못 탔다"
        Assert-Equal -Expected 15 -Actual $map["125"] -Message "평평한 판에서 직접 속성을 못 봤다"
        Assert-Equal -Expected 2 -Actual $map.Count -Message "지도 크기"
    }

    Invoke-FixtureTest -Name "F-06 지도를 못 만들면 빈 지도" -Body {
        Assert-Equal -Expected 0 -Actual (ConvertFrom-PktmonComponentJson -Json "").Count -Message "빈 글자"
        Assert-Equal -Expected 0 -Actual (ConvertFrom-PktmonComponentJson -Json "   ").Count -Message "공백뿐인 글자"
        Assert-Equal -Expected 0 -Actual (ConvertFrom-PktmonComponentJson -Json $null).Count -Message "빈 값"
        Assert-Equal -Expected 0 -Actual (ConvertFrom-PktmonComponentJson -Json "이것은 JSON 이 아니다").Count -Message "JSON 이 아닌 글자"
        Assert-Equal -Expected 0 -Actual (ConvertFrom-PktmonComponentJson -Json "[]").Count -Message "항목 0개"
    }

    # =======================================================================
    # F-07 ~ F-08 : 거르개 목록 글자 읽기
    # =======================================================================
    Invoke-FixtureTest -Name "F-07 거르개 목록 글자 — 한국어 '없음'" -Body {
        $rows = @(ConvertFrom-PktmonFilterText -Text $koreanFilterListText)
        # 자료 줄은 번호로 시작한다. '없음' 줄에는 번호가 없으므로 0줄이다.
        Assert-Equal -Expected 0 -Actual $rows.Count -Message "거르개가 없을 때는 0줄이어야 한다"
        Assert-Equal -Expected 0 -Actual @(ConvertFrom-PktmonFilterText -Text "").Count -Message "빈 글자"
    }

    Invoke-FixtureTest -Name "F-08 거르개 목록 글자 — 1건" -Body {
        $rows = @(ConvertFrom-PktmonFilterText -Text $englishFilterListText)
        Assert-Equal -Expected 1 -Actual $rows.Count -Message "자료 줄이 하나여야 한다"
        Assert-Equal -Expected "wfp-spike-M-017" -Actual $rows[0].name -Message "이름 칸"
        Assert-Equal -Expected "TCP" -Actual $rows[0].protocol -Message "프로토콜 칸"
        Assert-Equal -Expected "192.0.2.1" -Actual $rows[0].ip -Message "IP 칸"
        Assert-Equal -Expected "443" -Actual $rows[0].port -Message "포트 칸"
    }

    # =======================================================================
    # F-09 ~ F-11 : 되돌릴 목록 기록 읽기
    # =======================================================================
    Invoke-FixtureTest -Name "F-09 기록의 개수 칸이 비면 0 이 아니다" -Body {
        # 예전에는 개수가 비어 있으면 [int]$null 이 0 이 되어 "원래 0개였다"로 읽혔고,
        # 그러면 되돌리기가 성공한 것으로 처리되어 기록 파일이 지워졌다.
        foreach ($countLiteral in @('null', '""', '"abc"', '-1')) {
            $path = Join-Path $temporaryRoot ("record-empty-" + [Math]::Abs($countLiteral.GetHashCode()) + ".json")
            Set-Content -LiteralPath $path -Encoding utf8NoBOM -Value ('{"format":"TEXT","filterCount":' + $countLiteral + ',"filters":[],"raw":"x"}')
            $record = Read-PktmonFilterRecord -Path $path
            Assert-Equal -Expected "UNAVAILABLE" -Actual $record.Format -Message ("개수 칸이 " + $countLiteral + " 일 때")
            Assert-Null -Actual $record.Filters -Message ("개수 칸이 " + $countLiteral + " 일 때 목록")
        }
    }

    Invoke-FixtureTest -Name "F-10 개수와 목록 길이가 어긋나면 못 읽음" -Body {
        $mismatchPath = Join-Path $temporaryRoot "record-mismatch.json"
        Set-Content -LiteralPath $mismatchPath -Encoding utf8NoBOM -Value '{"format":"TEXT","filterCount":2,"filters":[{"name":"a"}],"raw":"x"}'
        $mismatch = Read-PktmonFilterRecord -Path $mismatchPath
        Assert-Equal -Expected "UNAVAILABLE" -Actual $mismatch.Format -Message "개수 2 · 목록 1"
        Assert-Null -Actual $mismatch.Filters -Message "개수 2 · 목록 1 의 목록"

        # 개수와 길이가 맞으면 읽힌다 — 0건과 1건 양쪽을 본다.
        $zeroPath = Join-Path $temporaryRoot "record-zero.json"
        Set-Content -LiteralPath $zeroPath -Encoding utf8NoBOM -Value '{"format":"TEXT","filterCount":0,"filters":[],"raw":"x"}'
        $zero = Read-PktmonFilterRecord -Path $zeroPath
        Assert-Equal -Expected "TEXT" -Actual $zero.Format -Message "개수 0 · 목록 0"
        Assert-Equal -Expected 0 -Actual @($zero.Filters).Count -Message "개수 0 일 때 목록 길이"

        $onePath = Join-Path $temporaryRoot "record-one.json"
        Set-Content -LiteralPath $onePath -Encoding utf8NoBOM -Value '{"format":"TEXT","filterCount":1,"filters":[{"name":"a"}],"raw":"x"}'
        $one = Read-PktmonFilterRecord -Path $onePath
        Assert-Equal -Expected "TEXT" -Actual $one.Format -Message "개수 1 · 목록 1"
        Assert-Equal -Expected 1 -Actual @($one.Filters).Count -Message "개수 1 일 때 목록 길이"
    }

    Invoke-FixtureTest -Name "F-11 없는 기록 파일은 빈 값" -Body {
        $absentPath = Join-Path $temporaryRoot "record-absent.json"
        Assert-Null -Actual (Read-PktmonFilterRecord -Path $absentPath) -Message "없는 파일"
        # 모르는 형식은 "못 읽음"이지 빈 값이 아니다. 둘은 다른 사실이다.
        $unknownPath = Join-Path $temporaryRoot "record-unknown-format.json"
        Set-Content -LiteralPath $unknownPath -Encoding utf8NoBOM -Value '{"format":"XML","filterCount":0,"filters":[],"raw":"x"}'
        Assert-Equal -Expected "UNAVAILABLE" -Actual (Read-PktmonFilterRecord -Path $unknownPath).Format -Message "모르는 형식"
    }

    # =======================================================================
    # F-12 : 시각을 UTC 왕복 서식으로 되돌리기
    # =======================================================================
    Invoke-FixtureTest -Name "F-12 시각을 UTC 왕복 서식으로 되돌리기" -Body {
        # ConvertFrom-Json 은 ISO-8601 글자를 [datetime] 으로 바꿔 놓는다. 그대로
        # [string] 로 되돌리면 현재 문화권의 "현지 시각·초 단위" 글자가 나오고,
        # 같은 초에 걸린 두 시각이 "앞선다"로 뒤집힌다.
        $roundTripped = ('{"t":"2026-08-17T06:35:26.2726621+00:00"}' | ConvertFrom-Json).t
        Assert-True -Condition ($roundTripped -is [datetime]) -Message "이 갈래가 성립하려면 [datetime] 이어야 한다"
        Assert-Equal -Expected "2026-08-17T06:35:26.2726621+00:00" -Actual (ConvertTo-RoundTripUtcText $roundTripped) `
            -Message "[datetime] 갈래"
        Assert-Equal -Expected "2026-08-17T06:35:26.2726621+00:00" `
            -Actual (ConvertTo-RoundTripUtcText ([datetimeoffset]::Parse("2026-08-17T06:35:26.2726621+00:00"))) `
            -Message "[datetimeoffset] 갈래"
        # 시각이 아닌 값은 그대로 글자로 나온다.
        Assert-Equal -Expected "" -Actual (ConvertTo-RoundTripUtcText "") -Message "빈 글자 갈래"
    }

    # =======================================================================
    # F-13 : 앱 띄우기 전에 없던 로컬 포트만 새 연결로 보기
    # =======================================================================
    Invoke-FixtureTest -Name "F-13 앱 띄우기 전에 없던 로컬 포트만 새 연결로 보기" -Body {
        Assert-Equal -Expected "1,2" -Actual (@(Select-NewLocalPort -PreexistingPort @() -ObservedPort @(1, 2)) -join ",") `
            -Message "전 목록이 비면 전부 새 연결이다"
        Assert-Equal -Expected 0 -Actual @(Select-NewLocalPort -PreexistingPort @(1, 2) -ObservedPort @(1, 2)).Count `
            -Message "전후가 같으면 새 연결이 없다"
        Assert-Equal -Expected "3" -Actual (@(Select-NewLocalPort -PreexistingPort @(1) -ObservedPort @(1, 3)) -join ",") `
            -Message "겹치는 것을 뺀 나머지만 새 연결이다"
        Assert-Equal -Expected 0 -Actual @(Select-NewLocalPort -PreexistingPort @(1) -ObservedPort @()).Count `
            -Message "지금 보이는 것이 없으면 새 연결도 없다"
    }

    # =======================================================================
    # F-14 ~ F-17 : 저장소 원문을 AST 로 읽어 값이 안 흘러내리는지 본다
    # =======================================================================
    Invoke-FixtureTest -Name "F-14 잡기 파일 크기 하한" -Body {
        # @() 로 감싼다. 원소가 하나면 PowerShell 이 배열을 풀어 글자 하나로 만들고,
        # 그러면 $values[0] 이 배열의 첫 원소가 아니라 글자의 첫 자가 된다("512" -> "5").
        $values = @(Get-ArgumentValueAfter -Ast (Get-ScriptAst -Path $interfaceScript) -ArgumentName "--file-size")
        Assert-Equal -Expected 1 -Actual $values.Count -Message "실제 인자 자리가 딱 하나여야 한다"
        $fileSize = 0
        Assert-True -Condition ([int]::TryParse($values[0], [ref]$fileSize)) -Message "인자 값이 숫자가 아니다"
        Assert-True -Condition ($fileSize -ge 512) `
            -Message "--file-size 가 512 미만입니다. 이 하한은 그 기계의 CPU 수에 묶여 있습니다(하나마다 16MB 버퍼). 기계가 바뀌면 값도 바뀝니다. 낮추기 전에 그 기계에서 다시 재십시오."
    }

    Invoke-FixtureTest -Name "F-15 표본 간격 25ms 하나뿐" -Body {
        # @() 로 감싸는 이유는 F-14 와 같다.
        $values = @(Get-CommandParameterValue -Ast (Get-ScriptAst -Path $flowScript) -CommandName "Start-Sleep" -ParameterName "Milliseconds")
        Assert-Equal -Expected 1 -Actual $values.Count `
            -Message "표본 간격 또는 연결 열거 방식이 바뀌었습니다. 250ms 로 물으면 짧게 살다 죽는 연결을 놓칩니다(실측 3회 중 2회)."
        # 25 보다 크거나 작으면 둘 다 실패여야 값이 고정된다.
        Assert-Equal -Expected "25" -Actual $values[0] `
            -Message "표본 간격 또는 연결 열거 방식이 바뀌었습니다. 250ms 로 물으면 짧게 살다 죽는 연결을 놓칩니다(실측 3회 중 2회)."
    }

    Invoke-FixtureTest -Name "F-16 연결 열거 방식 고정" -Body {
        $body = Get-FunctionSourceText -Ast (Get-ScriptAst -Path $flowScript) -FunctionName "Get-TargetTcpLocalPort"
        Assert-True -Condition ($body.IndexOf("GetActiveTcpConnections", [StringComparison]::Ordinal) -ge 0) `
            -Message "표본 간격 또는 연결 열거 방식이 바뀌었습니다. 250ms 로 물으면 짧게 살다 죽는 연결을 놓칩니다(실측 3회 중 2회)."
        Assert-True -Condition ($body.IndexOf($forbiddenConnectionCommandName, [StringComparison]::Ordinal) -lt 0) `
            -Message "표본 간격 또는 연결 열거 방식이 바뀌었습니다. 250ms 로 물으면 짧게 살다 죽는 연결을 놓칩니다(실측 3회 중 2회)."
    }

    Invoke-FixtureTest -Name "F-17 모듈이 내보내는 함수 집합" -Body {
        $moduleAst = Get-ScriptAst -Path $modulePath
        $declared = @($moduleAst.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object)
        $expected = @(
            "ConvertFrom-PktmonComponentJson", "ConvertFrom-PktmonFilterText", "ConvertTo-RoundTripUtcText",
            "Get-PacketComponentId", "Read-PktmonFilterRecord", "Select-NewLocalPort"
        ) | Sort-Object
        Assert-Equal -Expected ($expected -join ",") -Actual ($declared -join ",") -Message "모듈이 담은 함수 집합"

        # 되돌리기 함수 두 개는 여기 있으면 안 된다. 그 둘은 스크립트 범위 변수를
        # 참조하므로, 모듈로 옮기면 되돌리기가 조용히 멈춘다.
        foreach ($mustNotMove in @("Restore-PktmonFilterState", "Undo-PktmonState")) {
            Assert-True -Condition ($declared -notcontains $mustNotMove) -Message ("모듈로 옮기면 안 되는 함수가 있다: " + $mustNotMove)
        }

        # 담은 함수가 곧 내보내는 함수여야 한다.
        $exported = @((Get-Module -Name ([IO.Path]::GetFileNameWithoutExtension($modulePath))).ExportedFunctions.Keys | Sort-Object)
        Assert-Equal -Expected ($expected -join ",") -Actual ($exported -join ",") -Message "모듈이 내보내는 함수 집합"
    }

    # =======================================================================
    # F-18 ~ F-21 : 경계면 왕복 — 부르는 쪽 방식 그대로 부르고 결과를 되읽는다
    #
    # 상태를 안 바꾸는 인자로 실패 갈래를 유도한다. 네 스크립트 모두 실행 폴더(또는
    # 시각) 검사가 바깥 도구 확인보다 앞이라, 바깥 명령이 한 번도 안 불린다.
    # 시각 값 자체는 안 본다 — 있는지만 본다. 그래야 같은 입력에 같은 답이 선다.
    # =======================================================================
    Invoke-FixtureTest -Name "F-18 경계면 왕복 — 소유 정책 열거기" -Body {
        Assert-ObservationResult -Label "소유 정책 열거기" -ExpectedFailureReason "RUN_DIRECTORY_MISSING" `
            -Invocation (Invoke-ObservationScriptForTest -ScriptPath $policyScript -Arguments @{
                RunDirectory = $missingRunDirectory
                Label        = "fixture-test"
            })
        Assert-True -Condition (-not (Test-Path -LiteralPath $missingRunDirectory)) -Message "없는 폴더가 새로 생기면 안 된다"
    }

    Invoke-FixtureTest -Name "F-19 경계면 왕복 — 인터페이스 관찰기" -Body {
        Assert-ObservationResult -Label "인터페이스 관찰기" -ExpectedFailureReason "RUN_DIRECTORY_MISSING" `
            -Invocation (Invoke-ObservationScriptForTest -ScriptPath $interfaceScript -Arguments @{
                Mode                   = "Stop"
                VpnInterfaceIndex      = 1
                BaselineInterfaceIndex = 2
                Transport              = "TCP"
                RunDirectory           = $missingRunDirectory
                CaseId                 = "M-001"
            })
        Assert-True -Condition (-not (Test-Path -LiteralPath $missingRunDirectory)) -Message "없는 폴더가 새로 생기면 안 된다"
    }

    Invoke-FixtureTest -Name "F-20 경계면 왕복 — 흐름 발생기" -Body {
        # -AppPath 는 지금 도는 실행 파일을 쓴다. 어느 기계에나 있고, 시각 검사가
        # 그 앞에 있어 절대 실행되지 않는다.
        Assert-ObservationResult -Label "흐름 발생기" -ExpectedFailureReason "POLICY_TIMESTAMP_UNSET" `
            -Invocation (Invoke-ObservationScriptForTest -ScriptPath $flowScript -Arguments @{
                AppPath            = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                Transport          = "TCP"
                IpVersion          = "IPv4"
                PolicyAppliedAtUtc = ""
                RunDirectory       = $missingRunDirectory
            })
    }

    Invoke-FixtureTest -Name "F-21 경계면 왕복 — 터널 도구" -Body {
        Assert-ObservationResult -Label "터널 도구" -ExpectedFailureReason "RUN_DIRECTORY_MISSING" `
            -Invocation (Invoke-ObservationScriptForTest -ScriptPath $tunnelScript -Arguments @{
                Mode              = "Verify"
                RunDirectory      = $missingRunDirectory
                TunnelServiceName = "fixture-test"
            })

        # 사람이 고른 정리 갈래의 기다림 값에 상한이 있어야 한다. 상한이 없으면
        # 사고 복구 경로가 사람 손 없이 오래 멈춘다. 인자 정의를 원문에서 읽는다.
        $tunnelAst = Get-ScriptAst -Path $tunnelScript
        $waitParameter = @($tunnelAst.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.ParameterAst] -and
            $node.Name.VariablePath.UserPath -ceq "HarnessStopWaitMs" }, $true))
        Assert-Equal -Expected 1 -Actual $waitParameter.Count -Message "기다림 인자가 딱 하나여야 한다"
        $waitText = [string]$waitParameter[0].Extent.Text
        Assert-True -Condition ($waitText.IndexOf("ValidateRange(0, 60000)", [StringComparison]::Ordinal) -ge 0) `
            -Message "기다림 인자에 0~60000 상한이 없다"
        Assert-True -Condition ($waitText.IndexOf("= 2000", [StringComparison]::Ordinal) -ge 0) `
            -Message "기다림 인자의 기본값이 2000 이 아니다"

        # 사람이 안 고르면 안 도는 갈래여야 한다 — 스위치에 기본값을 적으면 안 된다.
        $stopSwitch = @($tunnelAst.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.ParameterAst] -and
            $node.Name.VariablePath.UserPath -ceq $harnessStopSwitchName }, $true))
        Assert-Equal -Expected 1 -Actual $stopSwitch.Count -Message "정리 갈래 스위치가 딱 하나여야 한다"
        Assert-True -Condition ($null -eq $stopSwitch[0].DefaultValue) -Message "정리 갈래 스위치에 기본값이 붙으면 안 된다"
    }
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 요약
# ---------------------------------------------------------------------------
$passedCount = @($results | Where-Object { $_.passed }).Count
$failedCount = @($results | Where-Object { -not $_.passed }).Count
$summary = [pscustomobject]@{
    total   = $results.Count
    passed  = $passedCount
    failed  = $failedCount
    results = @($results)
}

if ($AsObject) {
    # 부르는 쪽이 값으로 받는다. 화면에 아무것도 안 내고 exit 도 안 부른다.
    Write-Output $summary
    return
}

foreach ($result in $results) {
    if ($result.passed) { Write-Host ("  통과  " + $result.name) }
    else { Write-Host ("  실패  " + $result.name + " — " + $result.detail) }
}

if ($results.Count -lt 1) {
    # 빈 상태를 "전부 통과"로 읽지 않는다.
    Write-Host "시험이 0건입니다. 시험 파일을 찾지 못했습니다."
    exit 1
}

Write-Host ("고정값 시험 {0}/{1} 통과." -f $passedCount, $results.Count)
if ($failedCount -ne 0) { exit 1 }
exit 0
