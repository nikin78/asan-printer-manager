#Requires -Version 5.1
<#
.SYNOPSIS
    아산병원 프린터/드라이버 통합 마이그레이션 도구 6대 자동 정적 검증 스크립트
.DESCRIPTION
    dist/Asan_Printer_Manager.bat에 대해 다음 6개 항목을 자동 검증합니다:
      [1] 인코딩(UTF-8 No BOM), 순수 CRLF, 숨은 BOM/마크다운 변조 점검
      [2] 페이로드 마커 단일성, 부트스트랩 규약, 실제 cmd.exe 추출 테스트
      [3] Windows PowerShell 5.1 실제 AST 파서(ParseFile) 0 에러
      [4] PS 5.1 금지 구문 및 20개 절대 준수 제약사항 정적 스캔
      [5] 인라인 C# 5.0 (AsanWin32.NativeApi) 실제 Add-Type 컴파일 테스트
      [6] 전체 함수 교차참조, 비동기 $work 블록 코어 전용 검증, 실제 자식 Runspace 스냅샷 주입 테스트
#>
param(
    [string]$BatFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\Asan_Printer_Manager.bat'),
    [string]$SecretsFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'secrets.local.json'),
    [switch]$AllowPlaceholder
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$projRoot    = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $projRoot 'VERSION'
$expectedVer = '1.0.0-beta.3'
if (Test-Path -LiteralPath $versionFile) {
    $expectedVer = ([IO.File]::ReadAllText($versionFile, [Text.Encoding]::UTF8)).Trim()
}
if (-not [string]::IsNullOrWhiteSpace($env:ASAN_SECRETS_FILE) -and $SecretsFile -eq (Join-Path $projRoot 'secrets.local.json')) {
    $SecretsFile = $env:ASAN_SECRETS_FILE
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-CheckResult {
    param(
        [string]$Id,
        [string]$Title,
        [bool]$Passed,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{
        Id     = $Id
        Title  = $Title
        Passed = $Passed
        Detail = $Detail
    })
    $tag = 'PASS'
    if (-not $Passed) { $tag = 'FAIL' }
    Write-Host ("[{0}] {1} - {2}" -f $tag, $Id, $Title)
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        foreach ($dl in ($Detail -split "`r?`n")) {
            Write-Host ("       $dl")
        }
    }
}

Write-Host '===================================================================='
Write-Host (" Asan Printer Manager v{0} - 6-Point Static Verification Suite" -f $expectedVer)
Write-Host '===================================================================='
Write-Host ("Target File : $BatFile")
Write-Host ("PS Runtime  : {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
Write-Host ''

if (-not (Test-Path -LiteralPath $BatFile)) {
    throw "검증 대상 파일이 존재하지 않습니다: $BatFile"
}

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$batBytes = [IO.File]::ReadAllBytes($BatFile)
$batText  = $null
$utf8Valid = $true
try {
    $batText = $utf8Strict.GetString($batBytes)
} catch {
    $utf8Valid = $false
}

# ============================================================================
# [Check 1] UTF-8 (No BOM) + 순수 CRLF + 숨은 BOM/마크다운 변조 0건
# ============================================================================
$hasBom = ($batBytes.Length -ge 3 -and $batBytes[0] -eq 0xEF -and $batBytes[1] -eq 0xBB -and $batBytes[2] -eq 0xBF)
$loneLf = 0
$loneCr = 0
for ($i = 0; $i -lt $batBytes.Length; $i++) {
    if ($batBytes[$i] -eq 0x0A -and ($i -eq 0 -or $batBytes[$i - 1] -ne 0x0D)) { $loneLf++ }
    if ($batBytes[$i] -eq 0x0D -and ($i -eq ($batBytes.Length - 1) -or $batBytes[$i + 1] -ne 0x0A)) { $loneCr++ }
}
$embeddedBom = 0
$corruptHits = 0
if ($utf8Valid -and $null -ne $batText) {
    $embeddedBom = ([regex]::Matches($batText, "\uFEFF")).Count
    $corruptHits = ([regex]::Matches($batText, '\*\*STAGED\*\*|\*\*POWERSHELL_PAYLOAD\*\*|(?m)^```')).Count
}

$srcEncIssues = [System.Collections.Generic.List[string]]::new()
$srcDirPath   = Join-Path $projRoot 'src'
$scrDirPath   = Join-Path $projRoot 'scripts'
$expectedSrcNames = @(
    '00_bootstrap.bat',
    '01a_ctx_win32.ps1',
    '01b_net_diag.ps1',
    '01c_driver_inf.ps1',
    '01d_backup_restore.ps1',
    '01e_special_report_snapshot.ps1',
    '02_gui_shell_tab1.ps1',
    '03_gui_tab2.ps1',
    '04_gui_tab3_tab4_main.ps1'
)
foreach ($chkItem in @(
    @{ Path = (Join-Path $srcDirPath '00_bootstrap.bat');                NeedBom = $false },
    @{ Path = (Join-Path $srcDirPath '01a_ctx_win32.ps1');               NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '01b_net_diag.ps1');                NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '01c_driver_inf.ps1');              NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '01d_backup_restore.ps1');          NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '01e_special_report_snapshot.ps1'); NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '02_gui_shell_tab1.ps1');           NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '03_gui_tab2.ps1');                 NeedBom = $true },
    @{ Path = (Join-Path $srcDirPath '04_gui_tab3_tab4_main.ps1');       NeedBom = $true },
    @{ Path = (Join-Path $scrDirPath 'build_single_bat.ps1');            NeedBom = $true },
    @{ Path = (Join-Path $scrDirPath 'verify_static.ps1');               NeedBom = $true },
    @{ Path = (Join-Path $scrDirPath 'smoke_test_local.ps1');            NeedBom = $true }
)) {
    if (-not (Test-Path -LiteralPath $chkItem.Path)) {
        $srcEncIssues.Add("누락: $([IO.Path]::GetFileName($chkItem.Path))")
        continue
    }
    $fb = [IO.File]::ReadAllBytes($chkItem.Path)
    $fbBom = ($fb.Length -ge 3 -and $fb[0] -eq 0xEF -and $fb[1] -eq 0xBB -and $fb[2] -eq 0xBF)
    if ($chkItem.NeedBom -and -not $fbBom) { $srcEncIssues.Add("BOM 누락: $([IO.Path]::GetFileName($chkItem.Path))") }
    if (-not $chkItem.NeedBom -and $fbBom) { $srcEncIssues.Add("불허 BOM 존재: $([IO.Path]::GetFileName($chkItem.Path))") }
    $fLf = 0; $fCr = 0
    for ($bi = 0; $bi -lt $fb.Length; $bi++) {
        if ($fb[$bi] -eq 0x0A -and ($bi -eq 0 -or $fb[$bi - 1] -ne 0x0D)) { $fLf++ }
        if ($fb[$bi] -eq 0x0D -and ($bi -eq ($fb.Length - 1) -or $fb[$bi + 1] -ne 0x0A)) { $fCr++ }
    }
    if ($fLf -gt 0 -or $fCr -gt 0) {
        $srcEncIssues.Add("CRLF 위반($([IO.Path]::GetFileName($chkItem.Path)): LoneLF=$fLf, LoneCR=$fCr)")
    }
}
foreach ($sf in @(Get-ChildItem -LiteralPath $srcDirPath -File -ErrorAction SilentlyContinue)) {
    if ($expectedSrcNames -notcontains $sf.Name) {
        $srcEncIssues.Add("미등록 소스 파일 존재(src/): $($sf.Name)")
    }
}

# src/ <-> dist/ 동기화 확인 (빌드 누락된 구형 dist 방지)
$distSyncOk = $true
$distSyncDetail = 'Synced'
try {
    $modOrder = $expectedSrcNames
    $sbExp = New-Object System.Text.StringBuilder
    foreach ($mn in $modOrder) {
        $mr = [IO.File]::ReadAllText((Join-Path $srcDirPath $mn), $utf8Strict)
        if ($mr.Length -gt 0 -and $mr[0] -eq [char]0xFEFF) { $mr = $mr.Substring(1) }
        $mnorm = ([regex]::Replace($mr, "`r`n|`r|`n", "`r`n")).TrimEnd("`r", "`n")
        [void]$sbExp.Append($mnorm)
        [void]$sbExp.Append("`r`n")
    }
    $expMerged = $sbExp.ToString()
    if ((-not $AllowPlaceholder) -and (Test-Path -LiteralPath $SecretsFile)) {
        $sr = [IO.File]::ReadAllText($SecretsFile, $utf8Strict)
        if ($sr.Length -gt 0 -and $sr[0] -eq [char]0xFEFF) { $sr = $sr.Substring(1) }
        $so = $sr | ConvertFrom-Json
        $spws = @($so.DefaultPasswords | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { "'" + (([string]$_).Replace("'", "''")) + "'" })
        if ($spws.Count -gt 0) {
            $expMerged = $expMerged.Replace("@('__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__')", '@(' + ($spws -join ', ') + ')')
        }
        if ($so.PSObject.Properties.Name -contains 'DefaultUser' -and -not [string]::IsNullOrWhiteSpace([string]$so.DefaultUser)) {
            $su = ([string]$so.DefaultUser).Replace("'", "''").Replace('$', '$$')
            $expMerged = [regex]::Replace($expMerged, "(?m)^(\s*DefaultUser\s*=\s*)'[^']*'", "`$1'$su'")
        }
    }
    $expBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($expMerged)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hAct = [BitConverter]::ToString($sha.ComputeHash($batBytes))
    $hExp = [BitConverter]::ToString($sha.ComputeHash($expBytes))
    $sha.Dispose()
    if ($hAct -ne $hExp) {
        $distSyncOk = $false
        $distSyncDetail = 'OutOfSync(src 수정 후 build_single_bat.ps1 미실행)'
    }
} catch {
    $distSyncOk = $false
    $distSyncDetail = "SyncCheckErr($($_.Exception.Message))"
}

$c1Pass = ($utf8Valid -and (-not $hasBom) -and ($loneLf -eq 0) -and ($loneCr -eq 0) -and ($embeddedBom -eq 0) -and ($corruptHits -eq 0) -and ($srcEncIssues.Count -eq 0) -and $distSyncOk)
$c1Detail = "ValidUTF8=$utf8Valid, HasBOM=$hasBom, LoneLF=$loneLf, LoneCR=$loneCr, EmbeddedBOM=$embeddedBom, MarkdownCorrupt=$corruptHits, SrcEncIssues=$($srcEncIssues.Count), DistSync=$distSyncDetail, Size=$($batBytes.Length) bytes"
if ($srcEncIssues.Count -gt 0) { $c1Detail += "`r`nSrcIssues: " + ($srcEncIssues -join '; ') }
Add-CheckResult -Id 'CHK-1' -Title '인코딩(dist/src/scripts) · 순수 CRLF · src↔dist 동기화 점검' -Passed $c1Pass -Detail $c1Detail

if (-not $utf8Valid) {
    throw 'UTF-8 디코딩 실패로 후속 검증을 중단합니다.'
}

# ============================================================================
# [Check 2] 마커 단일성 · 부트스트랩 규약 · 실제 cmd.exe 페이로드 추출 테스트
# ============================================================================
$markerMatches = [regex]::Matches($batText, '(?m)^##__POWERSHELL_PAYLOAD__\s*$')
$markerCount   = $markerMatches.Count

$bootPart = ''
if ($markerCount -ge 1) {
    $bootPart = $batText.Substring(0, $markerMatches[$markerCount - 1].Index)
}

$bootIssues = [System.Collections.Generic.List[string]]::new()
if ($markerCount -ne 1) { $bootIssues.Add("페이로드 마커 개수가 1개가 아님 ($markerCount)") }
if ($bootPart -notmatch 'PROCESSOR_ARCHITEW6432' -or $bootPart -notmatch 'Sysnative') { $bootIssues.Add('WOW64 Sysnative 전환 로직 누락') }
if ($bootPart -notmatch 'ToBase64String' -or $bootPart -notmatch 'ORIGINAL_SELF') { $bootIssues.Add('URL-Safe Base64 ORIGINAL_SELF 전달 로직 누락') }
if ($bootPart -notmatch '-STA') { $bootIssues.Add('부트스트랩 -STA 실행 옵션 누락') }
if ($bootPart -notmatch '"%RC%"=="99"') { $bootIssues.Add('정상 종료 코드 99 검사 누락') }
if ($bootPart -match '""%SELF%""') { $bootIssues.Add('00_bootstrap.bat 깨진 ""%SELF%"" 인용 부호 감지 ("%%SELF%%" 사용 필수)') }
if ($bootPart -match 'Start-Process\s+-FilePath\s+\$env:CMD_EXE') { $bootIssues.Add('00_bootstrap.bat WOW64 UAC 버그: 64비트 PS에서 Sysnative CMD_EXE 실행 금지(System32\cmd.exe 사용 필수)') }
if ($batText.TrimEnd("`r", "`n") -notmatch '(?m)^exit 99$') { $bootIssues.Add('페이로드 말미 exit 99 누락') }

# 부트스트랩 실제 본문에서 페이로드 추출 원라이너를 직접 파싱해 실행 검증 (사본 하드코딩 사각지대 제거)
$bootExtMatch = [regex]::Match($bootPart, '(?m)-Command\s+("\$ErrorActionPreference=''Stop'';\s*\$raw=\[IO\.File\]::ReadAllText\(\$env:SELF[^\r\n]+")')
if (-not $bootExtMatch.Success) {
    $bootIssues.Add('00_bootstrap.bat 본문에서 실제 페이로드 추출 -Command 원라이너를 찾지 못함')
}

$tmpPs1 = Join-Path $env:TEMP ("AsanVerifyStatic_{0}.ps1" -f $PID)
$tmpLog = Join-Path $env:TEMP ("AsanVerifyStatic_{0}.log" -f $PID)
$extractOk = $false
$extHasBom = $false
$payloadText = ''

try {
    $env:SELF   = $BatFile
    $env:PSTEMP = $tmpPs1
    $extractOneLiner = ''
    if ($bootExtMatch.Success) { $extractOneLiner = $bootExtMatch.Groups[1].Value }
    if (-not [string]::IsNullOrWhiteSpace($extractOneLiner)) {
        $cmdLine = ('"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command {1} > "{2}" 2>&1' -f $ps51, $extractOneLiner, $tmpLog)
        & cmd.exe /d /c $cmdLine
    } else {
        $LASTEXITCODE = 1
    }
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpPs1)) {
        $extBytes  = [IO.File]::ReadAllBytes($tmpPs1)
        $extHasBom = ($extBytes.Length -ge 3 -and $extBytes[0] -eq 0xEF -and $extBytes[1] -eq 0xBB -and $extBytes[2] -eq 0xBF)
        $payloadText = [IO.File]::ReadAllText($tmpPs1, [Text.Encoding]::UTF8)
        $extractOk = $extHasBom -and ($payloadText.Length -gt 1000)
    } else {
        $logTxt = ''
        if (Test-Path -LiteralPath $tmpLog) { $logTxt = [IO.File]::ReadAllText($tmpLog, [Text.Encoding]::UTF8) }
        $bootIssues.Add("실제 추출 실패 (RC=$LASTEXITCODE): $logTxt")
    }

    $c2Pass = ($bootIssues.Count -eq 0 -and $extractOk)
    $c2Detail = "MarkerCount=$markerCount, ExtractOk=$extractOk, TempPs1Bom=$extHasBom, PayloadChars=$($payloadText.Length)"
    if ($bootIssues.Count -gt 0) { $c2Detail += "`r`nIssues: " + ($bootIssues -join '; ') }
    Add-CheckResult -Id 'CHK-2' -Title '마커 단일성 · 부트스트랩 규약 · 실제 추출 테스트' -Passed $c2Pass -Detail $c2Detail

    if (-not $extractOk) {
        throw '페이로드 추출 실패로 AST 검증을 중단합니다.'
    }

    # ============================================================================
    # [Check 3] Windows PowerShell 5.1 실제 AST 파서(ParseFile) 0 에러
    # ============================================================================
    $astTokens = $null
    $astErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($tmpPs1, [ref]$astTokens, [ref]$astErrors)
    $errCnt = 0
    if ($astErrors) { $errCnt = $astErrors.Count }
    $reqVer = 'NONE'
    if ($ast.ScriptRequirements -and $ast.ScriptRequirements.RequiredPSVersion) {
        $reqVer = $ast.ScriptRequirements.RequiredPSVersion.ToString()
    }
    $c3Pass = ($errCnt -eq 0 -and $reqVer -eq '5.1')
    $c3Detail = "ParseErrors=$errCnt, Tokens=$($astTokens.Count), #Requires=$reqVer"
    if ($errCnt -gt 0) {
        $errLines = @($astErrors | Select-Object -First 10 | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" })
        $c3Detail += "`r`n" + ($errLines -join "`r`n")
    }
    Add-CheckResult -Id 'CHK-3' -Title 'Windows PowerShell 5.1 실제 AST 파서 0 에러' -Passed $c3Pass -Detail $c3Detail

    # ============================================================================
    # [Check 4] PS 5.1 금지 구문 & 절대 준수 제약사항 정적 스캔
    # ============================================================================
    $ruleViolations = [System.Collections.Generic.List[string]]::new()

    # 4-1. 해시테이블 리터럴(@{ ... }) 내부에 직접 if 문 존재 여부 (중첩 ScriptBlock 내부 제외)
    $hashAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
    foreach ($ha in $hashAsts) {
        foreach ($kvp in $ha.KeyValuePairs) {
            $valAst = $kvp.Item2
            $ifsInVal = $valAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $false)
            if ($ifsInVal.Count -gt 0) {
                $ruleViolations.Add("Rule6 위반: Hashtable 내부 if 문 감지 (Line $($ha.Extent.StartLineNumber))")
            }
        }
    }

    # 4-2. PS 7+ ForEach-Object -Parallel 사용 여부
    $allCmdAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($ca in $allCmdAsts) {
        $cName = $ca.GetCommandName()
        if ($cName -ieq 'ForEach-Object' -or $cName -ieq '%' -or $cName -ieq 'foreach') {
            foreach ($el in $ca.CommandElements) {
                if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -match '(?i)^Parallel') {
                    $ruleViolations.Add("Rule5 위반: ForEach-Object -Parallel 감지 (Line $($ca.Extent.StartLineNumber))")
                }
            }
        }

        # 4-3. Rule 12: net.exe / cmdkey.exe 금지
        if ($cName -match '(?i)^(net(\.exe)?|cmdkey(\.exe)?)$') {
            $ruleViolations.Add("Rule12 위반: 금지 외부 명령 '$cName' 직접 호출 (Line $($ca.Extent.StartLineNumber))")
        }
        if ($cName -in @('Invoke-NativeCommand', 'Start-Process')) {
            $cmdText = $ca.Extent.Text
            if ($cmdText -match '(?i)[''"](net(\.exe)?|cmdkey(\.exe)?)[''"]') {
                $ruleViolations.Add("Rule12 위반: $cName 를 통한 net/cmdkey 실행 감지 (Line $($ca.Extent.StartLineNumber))")
            }
        }

        # 4-4. Rule 14: Remove-Printer / Set-Printer / Rename-Printer / Remove-PrinterDriver 반드시 -InputObject 사용 (-Name 금지)
        if ($cName -in @('Remove-Printer', 'Set-Printer', 'Rename-Printer', 'Remove-PrinterDriver')) {
            $paramNames = @($ca.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            if ($paramNames -contains 'Name') {
                $ruleViolations.Add("Rule14 위반: $cName 에서 -Name 사용 (Line $($ca.Extent.StartLineNumber))")
            }
            if ($paramNames -notcontains 'InputObject') {
                $ruleViolations.Add("Rule14 위반: $cName 에서 -InputObject 누락 (Line $($ca.Extent.StartLineNumber))")
            }
        }
    }

    # 4-5. Rule 13: PrintUIEntry /Ss, /Sr 호출에 /q 필수
    $printUiLines = @($payloadText -split "`r?`n" | Select-String -Pattern 'PrintUIEntry' -SimpleMatch)
    $ssSrCount = 0
    foreach ($pl in $printUiLines) {
        if ($pl.Line -match '/S[sr]\b') {
            $ssSrCount++
            if ($pl.Line -notmatch '/q\b') {
                $ruleViolations.Add("Rule13 위반: PrintUIEntry /Ss 또는 /Sr 에 /q 누락 (Line $($pl.LineNumber))")
            }
        }
    }

    # 4-6. Rule 10: 고정 상수 무결성 + 안 A(비밀 분리 주입) 점검
    foreach ($constNeedle in @(
        '172.25.152.232',
        '10.71.1.5',
        '백업 작업',
        '백업폴더',
        '_PRTBAK',
        'C:\_AsanPrtOffline',
        '$global:AsanCtx',
        '스캔유틸|ScannerFileUtility|ScanUtility'
    )) {
        if ($payloadText.IndexOf($constNeedle, [StringComparison]::Ordinal) -lt 0) {
            $ruleViolations.Add("Rule10 위반: 필수 고정 상수 누락 ('$constNeedle')")
        }
    }
    $srcCoreRaw = [IO.File]::ReadAllText((Join-Path $srcDirPath '01a_ctx_win32.ps1'), $utf8Strict)
    if ($srcCoreRaw.IndexOf("@('__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__')", [StringComparison]::Ordinal) -lt 0) {
        $ruleViolations.Add('안 A 위반: src/01a_ctx_win32.ps1에 비밀 주입 플레이스홀더가 없습니다 (하드코딩 암호 금지).')
    }
    if (-not $AllowPlaceholder -and $payloadText.IndexOf("@('__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__')", [StringComparison]::Ordinal) -ge 0) {
        $ruleViolations.Add('빌드 오류: dist/.bat에 미치환 암호 플레이스홀더가 남아 있습니다 (secrets.local.json 주입 필요).')
    }

    # 4-7. Rule 20: WinForms Anchor=Right 하드코딩 금지 + New-RightFlowStrip / Sync-AllUiButtonStates 확인
    if ($payloadText -match '(?i)\.Anchor\s*=.*Right') {
        $ruleViolations.Add('Rule20 위반: WinForms Anchor=Right 배치 감지')
    }
    if ($payloadText.IndexOf('New-RightFlowStrip', [StringComparison]::Ordinal) -lt 0) {
        $ruleViolations.Add('Rule20 위반: New-RightFlowStrip 헬퍼 누락')
    }
    if ($payloadText.IndexOf('Sync-AllUiButtonStates', [StringComparison]::Ordinal) -lt 0) {
        $ruleViolations.Add('Rule20 위반: Sync-AllUiButtonStates 누락')
    }

    # 4-8. Rule 16: 원자적 Spooler 중지 + [uint32] 0xFFFFF7FF 마스킹 확인
    if ($payloadText -notmatch '0xFFFFF7FF') {
        $ruleViolations.Add('Rule16 위반: Attributes [uint32] 비트 마스킹(0xFFFFF7FF) 누락')
    }

    # 4-9. GUI 다이얼로그 오너 누락 방지 (AST 기반): Show-AsanMessageBox 외부 직접 MessageBox::Show 호출 0건 검증
    $showMsgFnAst = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -ieq 'Show-AsanMessageBox'
    }, $true)
    $msgBoxCallAsts = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Static -and
        $n.Member.Extent.Text -ieq 'Show' -and
        $n.Expression.Extent.Text -match '(?i)^\[(System\.)?Windows\.Forms\.MessageBox\]$'
    }, $true)
    if ($null -eq $showMsgFnAst) {
        $ruleViolations.Add('UI 규칙 위반: Show-AsanMessageBox 공용 헬퍼 함수가 누락되었습니다.')
    } else {
        $mbFnStart = $showMsgFnAst.Extent.StartOffset
        $mbFnEnd   = $showMsgFnAst.Extent.EndOffset
        foreach ($mbc in $msgBoxCallAsts) {
            if ($mbc.Extent.StartOffset -lt $mbFnStart -or $mbc.Extent.EndOffset -gt $mbFnEnd) {
                $ruleViolations.Add("UI 규칙 위반: Show-AsanMessageBox 외부에서 직접 MessageBox::Show 호출 감지 (Line $($mbc.Extent.StartLineNumber))")
            }
        }
    }

    $c4Pass = ($ruleViolations.Count -eq 0)
    $c4Detail = "Checked Hashtables=$($hashAsts.Count), Commands=$($allCmdAsts.Count), PrintUI(/Ss|/Sr)=$ssSrCount, Violations=$($ruleViolations.Count)"
    if ($ruleViolations.Count -gt 0) {
        $c4Detail += "`r`n" + ($ruleViolations -join "`r`n")
    }
    Add-CheckResult -Id 'CHK-4' -Title 'PS 5.1 금지 구문 및 20개 절대 준수 제약사항 스캔' -Passed $c4Pass -Detail $c4Detail

    # ============================================================================
    # [Check 5] 인라인 C# 5.0 (AsanWin32.NativeApi) 실제 Add-Type 컴파일 테스트
    # ============================================================================
    $csMatch = [regex]::Match($payloadText, "Add-Type\s+-TypeDefinition\s+@'\r?\n([\s\S]*?)\r?\n'@")
    $c5Pass = $false
    $c5Detail = ''
    if (-not $csMatch.Success) {
        $c5Detail = 'Add-Type -TypeDefinition C# 블록을 찾지 못했습니다.'
    } else {
        $csCode = $csMatch.Groups[1].Value
        $csSyntaxIssues = [System.Collections.Generic.List[string]]::new()
        if ($csCode -match '\$"')           { $csSyntaxIssues.Add('C# 6+ 문자열 보간($") 감지') }
        if ($csCode -match '\?\.')          { $csSyntaxIssues.Add('C# 6+ null 조건 연산자(?.) 감지') }
        if ($csCode -match '\bnameof\s*\(') { $csSyntaxIssues.Add('C# 6+ nameof() 감지') }

        $tmpCsFile = Join-Path $env:TEMP ("AsanVerifyCs_{0}.cs" -f $PID)
        $tmpCsTest = Join-Path $env:TEMP ("AsanVerifyCsTest_{0}.ps1" -f $PID)
        try {
            [IO.File]::WriteAllText($tmpCsFile, $csCode, (New-Object System.Text.UTF8Encoding($true)))
            $csRunner = @"
`$ErrorActionPreference = 'Stop'
`$code = [IO.File]::ReadAllText('$($tmpCsFile -replace "'", "''")', [Text.Encoding]::UTF8)
Add-Type -TypeDefinition `$code -ErrorAction Stop
`$t = 'AsanWin32.NativeApi' -as [type]
if (-not `$t) { throw 'AsanWin32.NativeApi type not loaded' }
`$expected = @('HideConsoleWindow','HasStoredCredential','WriteDomainCredential','DeleteDomainCredential','ConnectShare','DisconnectShare','EnumPrintSharesEx','WNetAddConnection2W','WNetCancelConnection2W','GetConsoleWindow','ShowWindow')
`$methods = @(`$t.GetMethods([Reflection.BindingFlags]'Public,Static') | ForEach-Object { `$_.Name })
`$missing = @(`$expected | Where-Object { `$methods -notcontains `$_ })
if (`$missing.Count -gt 0) { throw ('Missing methods: ' + (`$missing -join ', ')) }
Write-Output ("CS_COMPILE_OK|Methods=" + `$methods.Count + "|Verified=" + `$expected.Count)
"@
            [IO.File]::WriteAllText($tmpCsTest, $csRunner, (New-Object System.Text.UTF8Encoding($true)))
            $csOut = & $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $tmpCsTest 2>&1
            $csRc  = $LASTEXITCODE
            $csText = (@($csOut) | ForEach-Object { [string]$_ }) -join ' '
            if ($csRc -eq 0 -and $csText -match 'CS_COMPILE_OK' -and $csSyntaxIssues.Count -eq 0) {
                $c5Pass = $true
                $c5Detail = "C# 5.0 Add-Type 컴파일 성공 ($csText)"
            } else {
                $c5Detail = "컴파일 실패(RC=$csRc): $csText"
                if ($csSyntaxIssues.Count -gt 0) { $c5Detail += '; ' + ($csSyntaxIssues -join '; ') }
            }
        }
        finally {
            if (Test-Path -LiteralPath $tmpCsFile) { Remove-Item -LiteralPath $tmpCsFile -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tmpCsTest) { Remove-Item -LiteralPath $tmpCsTest -Force -ErrorAction SilentlyContinue }
        }
    }
    Add-CheckResult -Id 'CHK-5' -Title '인라인 C# 5.0 (AsanWin32.NativeApi) 실제 Add-Type 컴파일' -Passed $c5Pass -Detail $c5Detail

    # ============================================================================
    # [Check 6] 전체 함수 교차참조 · 비동기 $work 코어 전용 검증 · 자식 Runspace 실주입
    # ============================================================================
    $snapMatch = [regex]::Match($payloadText, '(?m)^\$script:CoreFunctionNames\s*=')
    if (-not $snapMatch.Success) {
        throw '$script:CoreFunctionNames 스냅샷 선언을 찾을 수 없습니다.'
    }
    $snapOffset = $snapMatch.Index

    $fnDefs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $allDefinedSet  = @{}
    $coreDefinedSet = @{}
    $guiDefinedSet  = @{}
    $dupFunctions   = [System.Collections.Generic.List[string]]::new()

    foreach ($fd in $fnDefs) {
        $fnName = [string]$fd.Name
        if ($allDefinedSet.ContainsKey($fnName)) {
            $dupFunctions.Add("$fnName (Line $($fd.Extent.StartLineNumber))")
        }
        $allDefinedSet[$fnName] = $fd.Extent.StartLineNumber
        if ($fd.Extent.StartOffset -lt $snapOffset) {
            $coreDefinedSet[$fnName] = $fd.Extent.StartLineNumber
        } else {
            $guiDefinedSet[$fnName] = $fd.Extent.StartLineNumber
        }
    }

    # 시스템 기본 명령(cmdlet/function/alias) 목록 수집 (PrintManagement 포함)
    Import-Module PrintManagement -ErrorAction SilentlyContinue
    $builtinCmds = @{}
    foreach ($cmd in @(Get-Command -CommandType Cmdlet, Function, Alias -ErrorAction SilentlyContinue)) {
        $builtinCmds[$cmd.Name.ToLowerInvariant()] = $true
    }
    # Windows 기본 외부 유틸리티 허용 목록
    foreach ($ext in @('pnputil.exe','robocopy.exe','rundll32.exe','reg.exe','explorer.exe','mmc.exe','cmd.exe','powershell.exe')) {
        $builtinCmds[$ext] = $true
    }

    $undefinedCalls = [System.Collections.Generic.List[string]]::new()
    foreach ($ca in $allCmdAsts) {
        $cn = $ca.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cn)) { continue }
        # 변수/경로/표현식 기반 호출 제외
        if ($cn.StartsWith('$') -or $cn.StartsWith('&') -or $cn.StartsWith('.')) { continue }
        $cnLow = $cn.ToLowerInvariant()
        if ($allDefinedSet.ContainsKey($cn)) { continue }
        # 대소문자 무시 매칭
        $matchedLocal = $false
        foreach ($dk in $allDefinedSet.Keys) {
            if ($dk -ieq $cn) { $matchedLocal = $true; break }
        }
        if ($matchedLocal) { continue }
        if ($builtinCmds.ContainsKey($cnLow)) { continue }
        # 실제 시스템에서 확인 가능한 명령인지 최종 확인
        if (Get-Command -Name $cn -ErrorAction SilentlyContinue) { continue }
        $undefinedCalls.Add("$cn (Line $($ca.Extent.StartLineNumber))")
    }

    # 모든 비동기 $work = { ... } 및 인라인 -WorkScript { ... } 블록에서 GUI 호출 및 $script:* 참조 차단
    $guiCallsInWork    = [System.Collections.Generic.List[string]]::new()
    $scriptVarsInWork  = [System.Collections.Generic.List[string]]::new()
    $coreCallsGui      = [System.Collections.Generic.List[string]]::new()

    foreach ($fd in $fnDefs) {
        if ($fd.Extent.StartOffset -lt $snapOffset) {
            $cCmds = $fd.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($cc in $cCmds) {
                $ccn = $cc.GetCommandName()
                if (-not [string]::IsNullOrWhiteSpace($ccn) -and $guiDefinedSet.ContainsKey($ccn)) {
                    $coreCallsGui.Add("Core '$($fd.Name)' calls GUI '$ccn' (Line $($cc.Extent.StartLineNumber))")
                }
            }
        }
    }

    $workBlockAsts = [System.Collections.Generic.List[object]]::new()
    $workAssigns = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$work' -and
        $n.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
        $n.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
    }, $true)
    foreach ($wa in $workAssigns) { $workBlockAsts.Add($wa.Right.Expression.ScriptBlock) }

    foreach ($ca in $allCmdAsts) {
        if ($ca.GetCommandName() -ieq 'Invoke-AsanAsyncTask') {
            for ($ei = 0; $ei -lt ($ca.CommandElements.Count - 1); $ei++) {
                $el = $ca.CommandElements[$ei]
                if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -ieq 'WorkScript') {
                    $nxt = $ca.CommandElements[$ei + 1]
                    if ($nxt -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                        $workBlockAsts.Add($nxt.ScriptBlock)
                    }
                }
            }
        }
    }

    foreach ($sbAst in $workBlockAsts) {
        $innerCmds = $sbAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($ic in $innerCmds) {
            $icn = $ic.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($icn)) { continue }
            if ($guiDefinedSet.ContainsKey($icn)) {
                $guiCallsInWork.Add("'$icn' called inside `$work (Line $($ic.Extent.StartLineNumber))")
            }
        }
        $innerVars = $sbAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
        foreach ($iv in $innerVars) {
            if ($iv.VariablePath -and $iv.VariablePath.IsScript) {
                $scriptVarsInWork.Add("'$($iv.Extent.Text)' referenced inside `$work (Line $($iv.Extent.StartLineNumber))")
            }
        }
    }

    # 탭 4 경량 베어 Runspace($previewScript) 내부에서 코어/GUI 사용자 정의 함수 호출 금지 검사
    $barePreviewCalls = [System.Collections.Generic.List[string]]::new()
    $previewAssigns = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$previewScript' -and
        $n.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
        $n.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
    }, $true)
    foreach ($pa in $previewAssigns) {
        $psbAst = $pa.Right.Expression.ScriptBlock
        $pCmds  = $psbAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($pc in $pCmds) {
            $pcn = $pc.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($pcn)) { continue }
            $hitDefined = $false
            foreach ($dk in $allDefinedSet.Keys) {
                if ($dk -ieq $pcn) { $hitDefined = $true; break }
            }
            if ($hitDefined) {
                $barePreviewCalls.Add("'$pcn' called inside bare `$previewScript (Line $($pc.Extent.StartLineNumber))")
            }
        }
    }

    # 클린룸 PS 5.1 프로세스에서 코어 블록(~$script:CoreFunctionNames 끝)만 로드 후 실제 자식 Runspace 주입 검증
    $snapEndMatch = [regex]::Match($payloadText.Substring($snapOffset), '\r?\n\)\r?\n')
    $runspaceOk = $false
    $runspaceMsg = ''
    if ($snapEndMatch.Success) {
        $coreSlice = $payloadText.Substring(0, $snapOffset + $snapEndMatch.Index + $snapEndMatch.Length)
        $tmpCoreOnly = Join-Path $env:TEMP ("AsanVerifyCore_{0}.ps1" -f $PID)
        $tmpRsTest   = Join-Path $env:TEMP ("AsanVerifyRs_{0}.ps1" -f $PID)
        try {
            [IO.File]::WriteAllText($tmpCoreOnly, $coreSlice, (New-Object System.Text.UTF8Encoding($true)))
            $expectedCoreNames = @($coreDefinedSet.Keys | Sort-Object)
            $expectedLiteral   = ($expectedCoreNames | ForEach-Object { "'$_'" }) -join ','

            $rsScript = @"
`$ErrorActionPreference = 'Stop'
. '$($tmpCoreOnly -replace "'", "''")'
`$expected = @($expectedLiteral)
`$captured = @(`$script:CoreFunctionNames)
`$missing  = @(`$expected | Where-Object { `$captured -notcontains `$_ })
if (`$missing.Count -gt 0) {
    throw ('Snapshot missing core functions: ' + (`$missing -join ', '))
}

`$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
`$varEntry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('AsanCtx', `$global:AsanCtx, 'Shared Asan Context')
`$iss.Variables.Add(`$varEntry)
foreach (`$fnName in `$captured) {
    `$fnItem = Get-Item -Path "Function:\`$fnName" -ErrorAction SilentlyContinue
    if (`$fnItem) {
        `$fnEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry(`$fnItem.Name, `$fnItem.Definition)
        `$iss.Commands.Add(`$fnEntry)
    }
}

`$rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace(`$iss)
`$rs.ApartmentState = [System.Threading.ApartmentState]::MTA
`$rs.Open()
try {
    `$ps = [System.Management.Automation.PowerShell]::Create()
    `$ps.Runspace = `$rs
    [void]`$ps.AddScript({
        param([string[]]`$exp)
        `$missInChild = @(`$exp | Where-Object { -not (Test-Path "Function:\`$_") })
        `$hasNative   = (`$null -ne ('AsanWin32.NativeApi' -as [type]))
        `$ver         = `$global:AsanCtx.AppVersion
        `$testIp      = Test-IsUsableIPv4 -IpText '192.168.10.20'
        `$testBadIp   = Test-IsUsableIPv4 -IpText '169.254.1.1'
        `$testSpec    = (Get-SpecialPrinterProfile -PrinterName 'id카드' -DriverName 'SISS' -PortName '10.1.1.1').Type
        [pscustomobject]@{
            MissCount = `$missInChild.Count
            HasNative = `$hasNative
            AppVer    = `$ver
            IpCheck   = (`$testIp -and (-not `$testBadIp))
            SpecType  = `$testSpec
        }
    }).AddArgument(`$expected)
    `$out = `$ps.Invoke() | Select-Object -First 1
    if (`$ps.HadErrors) { throw ('Child Runspace errors: ' + ((`$ps.Streams.Error | ForEach-Object { `$_.ToString() }) -join '; ')) }
    if (`$out.MissCount -ne 0 -or (-not `$out.HasNative) -or `$out.AppVer -ne '$expectedVer' -or (-not `$out.IpCheck) -or `$out.SpecType -ne 'SIP30M_IDCARD') {
        throw ('Child Runspace check failed: ' + (`$out | ConvertTo-Json -Compress))
    }
    Write-Output ("RUNSPACE_OK|CoreExpected=" + `$expected.Count + "|Captured=" + `$captured.Count + "|ChildMissing=0|NativeApi=True|CtxVer=" + `$out.AppVer)
}
finally {
    `$rs.Close()
    `$rs.Dispose()
}
"@
            [IO.File]::WriteAllText($tmpRsTest, $rsScript, (New-Object System.Text.UTF8Encoding($true)))
            $rsOut  = & $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $tmpRsTest 2>&1
            $rsRc   = $LASTEXITCODE
            $rsText = (@($rsOut) | ForEach-Object { [string]$_ }) -join ' '
            if ($rsRc -eq 0 -and $rsText -match 'RUNSPACE_OK') {
                $runspaceOk  = $true
                $runspaceMsg = $rsText
            } else {
                $runspaceMsg = "실패(RC=$rsRc): $rsText"
            }
        }
        finally {
            if (Test-Path -LiteralPath $tmpCoreOnly) { Remove-Item -LiteralPath $tmpCoreOnly -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $tmpRsTest)   { Remove-Item -LiteralPath $tmpRsTest   -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $runspaceMsg = '$script:CoreFunctionNames 닫는 괄호를 찾지 못했습니다.'
    }

    $c6Pass = ($dupFunctions.Count -eq 0 -and $undefinedCalls.Count -eq 0 -and $guiCallsInWork.Count -eq 0 -and $scriptVarsInWork.Count -eq 0 -and $coreCallsGui.Count -eq 0 -and $barePreviewCalls.Count -eq 0 -and $runspaceOk)
    $c6Lines = [System.Collections.Generic.List[string]]::new()
    $c6Lines.Add("DefinedFunctions=$($allDefinedSet.Count) (Core=$($coreDefinedSet.Count), GUI=$($guiDefinedSet.Count)), Duplicates=$($dupFunctions.Count), UndefinedCalls=$($undefinedCalls.Count), AsyncWorkBlocks=$($workBlockAsts.Count), GuiInWork=$($guiCallsInWork.Count), ScriptVarsInWork=$($scriptVarsInWork.Count), CoreToGui=$($coreCallsGui.Count), BarePreviewBlocks=$($previewAssigns.Count), BarePreviewCalls=$($barePreviewCalls.Count)")
    $c6Lines.Add("ChildRunspaceTest: $runspaceMsg")
    if ($dupFunctions.Count -gt 0)     { $c6Lines.Add("Duplicates: " + ($dupFunctions -join ', ')) }
    if ($undefinedCalls.Count -gt 0)   { $c6Lines.Add("Undefined: " + ($undefinedCalls -join ', ')) }
    if ($guiCallsInWork.Count -gt 0)   { $c6Lines.Add("GuiInWork: " + ($guiCallsInWork -join ', ')) }
    if ($scriptVarsInWork.Count -gt 0) { $c6Lines.Add("ScriptVarsInWork: " + ($scriptVarsInWork -join ', ')) }
    if ($coreCallsGui.Count -gt 0)     { $c6Lines.Add("CoreToGui: " + ($coreCallsGui -join ', ')) }
    if ($barePreviewCalls.Count -gt 0) { $c6Lines.Add("BarePreviewCalls: " + ($barePreviewCalls -join ', ')) }
    Add-CheckResult -Id 'CHK-6' -Title '함수 교차참조 · 비동기 $work 코어 전용 · 자식 Runspace 실주입' -Passed $c6Pass -Detail ($c6Lines -join "`r`n")
}
finally {
    Remove-Item Env:\SELF   -ErrorAction SilentlyContinue
    Remove-Item Env:\PSTEMP -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tmpPs1) { Remove-Item -LiteralPath $tmpPs1 -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $tmpLog) { Remove-Item -LiteralPath $tmpLog -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
$failedCount = (@($results | Where-Object { -not $_.Passed })).Count
Write-Host '===================================================================='
if ($failedCount -eq 0) {
    Write-Host (" STATIC VERIFICATION SUMMARY: ALL {0}/{0} CHECKS PASSED" -f $results.Count)
    Write-Host '===================================================================='
    exit 0
} else {
    Write-Host (" STATIC VERIFICATION SUMMARY: {0} FAILED / {1} TOTAL" -f $failedCount, $results.Count)
    Write-Host '===================================================================='
    exit 1
}
