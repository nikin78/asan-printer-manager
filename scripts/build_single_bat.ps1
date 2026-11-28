#Requires -Version 5.1
<#
.SYNOPSIS
    아산병원 프린터/드라이버 통합 마이그레이션 도구 단일 .bat 무손실 빌드 스크립트
.DESCRIPTION
    src/ 하위 9개 모듈을 번호 순서대로 순수 Windows CRLF(\r\n)로 결합하고
    로컬 secrets.local.json의 공용 암호를 빌드 시점에만 주입하여
    UTF-8 (No BOM) 인코딩으로 dist/Asan_Printer_Manager.bat을 생성합니다.
#>
param(
    [string]$SrcDir      = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src'),
    [string]$OutFile     = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\Asan_Printer_Manager.bat'),
    [string]$SecretsFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'secrets.local.json'),
    [switch]$AllowPlaceholderBuild
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$projRoot    = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $projRoot 'VERSION'
$appVer      = 'unknown'
if (Test-Path -LiteralPath $versionFile) {
    $appVer = ([IO.File]::ReadAllText($versionFile, [Text.Encoding]::UTF8)).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($env:ASAN_SECRETS_FILE) -and $SecretsFile -eq (Join-Path $projRoot 'secrets.local.json')) {
    $SecretsFile = $env:ASAN_SECRETS_FILE
}

$moduleOrder = @(
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

Write-Host '===================================================================='
Write-Host (" Asan Printer Manager v{0} - Single BAT Lossless Build" -f $appVer)
Write-Host '===================================================================='
Write-Host "Source Dir  : $SrcDir"
Write-Host "Output File : $OutFile"
Write-Host "Secrets File: $SecretsFile"

if (-not (Test-Path -LiteralPath $SrcDir)) {
    throw "소스 폴더를 찾을 수 없습니다: $SrcDir"
}

$utf8StrictReader = New-Object System.Text.UTF8Encoding($false, $true)
$utf8NoBomWriter  = New-Object System.Text.UTF8Encoding($false)

# 기본 공용 암호는 src/01a_ctx_win32.ps1에 내장되어 별도 파일 없이 즉시 동작하며,
# 로컬 secrets.local.json이 존재하고 소스에 플레이스홀더가 있을 때만 선택적 오버라이드를 수행합니다.
$pwLiteral       = $null
$userOverride    = $null
$placeholderExpr = "@('__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__')"

if ((-not $AllowPlaceholderBuild) -and (Test-Path -LiteralPath $SecretsFile)) {
    $secRaw = [IO.File]::ReadAllText($SecretsFile, $utf8StrictReader)
    if ($secRaw.Length -gt 0 -and $secRaw[0] -eq [char]0xFEFF) { $secRaw = $secRaw.Substring(1) }
    $secObj = $secRaw | ConvertFrom-Json
    $pws = @($secObj.DefaultPasswords | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    if ($pws.Count -gt 0) {
        $validPws = @($pws | Where-Object { $_ -notmatch '(?i)CHANGE_ME_|__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__' })
        if ($validPws.Count -gt 0) {
            $escapedItems = @($validPws | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" })
            $pwLiteral    = '@(' + ($escapedItems -join ', ') + ')'
        }
    }
    if ($secObj.PSObject.Properties.Name -contains 'DefaultUser' -and -not [string]::IsNullOrWhiteSpace([string]$secObj.DefaultUser)) {
        $userOverride = [string]$secObj.DefaultUser
    }
}

$sb = New-Object System.Text.StringBuilder
$totalLines = 0
$moduleStats = [System.Collections.Generic.List[object]]::new()

foreach ($modName in $moduleOrder) {
    $modPath = Join-Path $SrcDir $modName
    if (-not (Test-Path -LiteralPath $modPath)) {
        throw "필수 소스 모듈이 누락되었습니다: $modPath"
    }

    # 엄격한 UTF-8 읽기 (BOM 자동 제거 + 깨진 바이트 즉시 오류)
    $raw = [IO.File]::ReadAllText($modPath, $utf8StrictReader)
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
        $raw = $raw.Substring(1)
    }
    if ($raw.IndexOf([char]0xFEFF) -ge 0) {
        throw "모듈 내부에 숨은 BOM(U+FEFF) 문자가 포함되어 있습니다: $modName"
    }

    # 모든 줄바꿈을 순수 Windows CRLF(\r\n)로 정규화하고 말미 단일 CRLF 보장
    $normalized = [regex]::Replace($raw, "`r`n|`r|`n", "`r`n")
    $trimmedEnd = $normalized.TrimEnd("`r", "`n")
    $lineCount  = ($trimmedEnd -split "`r`n").Count

    [void]$sb.Append($trimmedEnd)
    [void]$sb.Append("`r`n")

    $totalLines += $lineCount
    $moduleStats.Add([pscustomobject]@{
        Module = $modName
        Lines  = $lineCount
        Bytes  = ([IO.FileInfo]$modPath).Length
    })
}

$mergedText = $sb.ToString()

if ($null -ne $pwLiteral -and $mergedText.IndexOf($placeholderExpr, [StringComparison]::Ordinal) -ge 0) {
    $mergedText = $mergedText.Replace($placeholderExpr, $pwLiteral)
    if ($userOverride) {
        $safeUser = $userOverride.Replace("'", "''").Replace('$', '$$')
        $mergedText = [regex]::Replace($mergedText, "(?m)^(\s*DefaultUser\s*=\s*)'[^']*'", "`$1'$safeUser'")
    }
}

# 출력 디렉터리 생성 및 UTF-8 (No BOM) + 순수 CRLF 저장
$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
[IO.File]::WriteAllText($OutFile, $mergedText, $utf8NoBomWriter)

# 빌드 직후 기본 무결성 자가 점검
$outBytes = [IO.File]::ReadAllBytes($OutFile)
$hasBom   = ($outBytes.Length -ge 3 -and $outBytes[0] -eq 0xEF -and $outBytes[1] -eq 0xBB -and $outBytes[2] -eq 0xBF)
if ($hasBom) {
    throw '빌드 실패: 출력 .bat 파일에 UTF-8 BOM이 포함되었습니다.'
}

$loneLf = 0
$loneCr = 0
for ($i = 0; $i -lt $outBytes.Length; $i++) {
    if ($outBytes[$i] -eq 0x0A -and ($i -eq 0 -or $outBytes[$i - 1] -ne 0x0D)) { $loneLf++ }
    if ($outBytes[$i] -eq 0x0D -and ($i -eq ($outBytes.Length - 1) -or $outBytes[$i + 1] -ne 0x0A)) { $loneCr++ }
}
if ($loneLf -gt 0 -or $loneCr -gt 0) {
    throw "빌드 실패: 순수 CRLF 위반 (LoneLF=$loneLf, LoneCR=$loneCr)"
}

$verifyText = [IO.File]::ReadAllText($OutFile, $utf8StrictReader)
if ($verifyText.IndexOf([char]0xFEFF) -ge 0) {
    throw '빌드 실패: 출력 파일 내부에 BOM(U+FEFF) 문자가 남아 있습니다.'
}

$markerMatches = [regex]::Matches($verifyText, '(?m)^##__POWERSHELL_PAYLOAD__\s*$')
if ($markerMatches.Count -ne 1) {
    throw "빌드 실패: ##__POWERSHELL_PAYLOAD__ 마커 개수가 1개가 아닙니다 (감지: $($markerMatches.Count)개)."
}

$sha = [System.Security.Cryptography.SHA256]::Create()
$shaHex = ([BitConverter]::ToString($sha.ComputeHash($outBytes)) -replace '-', '')
$sha.Dispose()

Write-Host ''
Write-Host '[모듈 병합 내역]'
foreach ($st in $moduleStats) {
    Write-Host ("  - {0,-28} : {1,5} lines ({2,8:N0} bytes)" -f $st.Module, $st.Lines, $st.Bytes)
}
Write-Host ''
Write-Host '[최종 산출물 검증 결과]'
Write-Host ("  - 총 줄 수      : {0:N0} lines" -f $totalLines)
Write-Host ("  - 파일 크기     : {0:N0} bytes" -f $outBytes.Length)
Write-Host ("  - 인코딩        : UTF-8 (No BOM) [PASS]")
Write-Host ("  - 개행 규칙     : 순수 CRLF (LoneLF=0, LoneCR=0) [PASS]")
Write-Host ("  - 페이로드 마커 : 1개 확인 [PASS]")
if ($mergedText.IndexOf($placeholderExpr, [StringComparison]::Ordinal) -lt 0) {
    Write-Host ("  - 기본 계정 설정: 단일 실행 파일 내장 완료 (별도 설정 파일 불필요) [PASS]")
} else {
    Write-Host ("  - 기본 계정 설정: 플레이스홀더 모드 (-AllowPlaceholderBuild)")
}
Write-Host ("  - SHA-256       : $shaHex")
Write-Host ''
Write-Host 'BUILD SUCCEEDED.'
