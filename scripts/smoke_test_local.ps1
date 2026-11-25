#Requires -Version 5.1
<#
.SYNOPSIS
    아산병원 프린터/드라이버 통합 마이그레이션 도구 로컬 비파괴 스모크 테스트
.DESCRIPTION
    프린터·레지스트리·시스템 설정을 일절 변경하지 않는 읽기 전용 범위에서
    dist/Asan_Printer_Manager.bat의 실제 동작을 3단계로 검증합니다:
      [A] 부트스트랩 Base64 경로 인코딩/디코딩 · 읽기전용 원본(Zero-USB-Write) 추출 · RC=99 규약
      [B] 코어 엔진 읽기 전용 실환경 진단(SID/WPP/NIC/망·서버/로컬프린터/스캐너/검증조회) + 인메모리 로직 단위테스트
      [C] 실제 -STA WinForms GUI 기동 · Runspace 비동기 로드 · 4개 탭 순회 · 해상도(1040x720, 960x640) 레이아웃 감사 · 정상 종료(exit 99)
#>
param(
    [string]$BatFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\Asan_Printer_Manager.bat')
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testResults = [System.Collections.Generic.List[object]]::new()

function Add-SmokeResult {
    param([string]$Id, [string]$Title, [bool]$Passed, [string]$Detail)
    $testResults.Add([pscustomobject]@{ Id = $Id; Title = $Title; Passed = $Passed; Detail = $Detail })
    $tag = 'PASS'
    if (-not $Passed) { $tag = 'FAIL' }
    Write-Host ("[{0}] {1} - {2}" -f $tag, $Id, $Title)
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        foreach ($line in ($Detail -split "`r?`n")) {
            Write-Host ("       $line")
        }
    }
}

Write-Host '===================================================================='
Write-Host ' Asan Printer Manager - Non-Destructive Local Smoke Test'
Write-Host '===================================================================='
Write-Host ("Target File : $BatFile")
Write-Host ("PS Runtime  : {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
Write-Host ''

if (-not (Test-Path -LiteralPath $BatFile)) {
    throw "테스트 대상 파일이 존재하지 않습니다: $BatFile"
}

$workRoot = Join-Path $env:TEMP ("AsanSmoke_{0}" -f $PID)
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

try {
    # ========================================================================
    # [Test A] Zero-USB-Write 읽기전용 소스 추출 + URL-Safe Base64 특수문자 경로 왕복
    # ========================================================================
    $roDir = Join-Path $workRoot 'SimulatedUsb_RO'
    New-Item -ItemType Directory -Path $roDir -Force | Out-Null
    $roBat = Join-Path $roDir 'Asan_Printer_Manager.bat'
    Copy-Item -LiteralPath $BatFile -Destination $roBat -Force
    $beforeFiles = @(Get-ChildItem -LiteralPath $roDir -Force | ForEach-Object { $_.Name })

    # 00_bootstrap.bat 54행과 동일한 URL-Safe Base64 인코딩 -> 01a_ctx_win32.ps1 11-19행과 동일한 디코딩 검증
    $trickyPath = 'E:\아산 병원 & 교체^작업 (100%) [beta]\Asan_Printer_Manager.bat'
    $env:ORIGINAL_SELF = $trickyPath
    $b64Out = & $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "`$ErrorActionPreference='Stop'; [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$env:ORIGINAL_SELF)).Replace('+','-').Replace('/','_').TrimEnd('=')"
    Remove-Item Env:\ORIGINAL_SELF -ErrorAction SilentlyContinue
    $b64Val = ([string]$b64Out).Trim()
    $b64SafeChars = ($b64Val -match '^[A-Za-z0-9_-]+$')

    $b64Std = $b64Val.Replace('-', '+').Replace('_', '/')
    $padLen = (4 - ($b64Std.Length % 4)) % 4
    if ($padLen -gt 0) { $b64Std = $b64Std + ('=' * $padLen) }
    $decodedPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64Std))
    $b64RoundTripOk = ($b64SafeChars -and ($decodedPath -eq $trickyPath))

    # 실제 00_bootstrap.bat 75행 추출 명령으로 %TEMP%에 임시 .ps1 추출
    $extractedPs1 = Join-Path $workRoot 'extracted_payload.ps1'
    $extractLog = Join-Path $workRoot 'extract.log'
    $env:SELF = $roBat
    $env:PSTEMP = $extractedPs1
    $extractOneLiner = '"$ErrorActionPreference=''Stop''; $raw=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $m=[regex]::Match($raw,''(?m)^##__POWERSHELL_PAYLOAD__\s*$'',[Text.RegularExpressions.RegexOptions]::RightToLeft); if(-not $m.Success){throw ''Payload marker not found.''}; $ps=$raw.Substring($m.Index+$m.Length); [IO.File]::WriteAllText($env:PSTEMP,$ps,(New-Object Text.UTF8Encoding($true)))"'
    $cmdLine = ('"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command {1} > "{2}" 2>&1' -f $ps51, $extractOneLiner, $extractLog)
    & cmd.exe /d /c $cmdLine
    $extRc = $LASTEXITCODE
    Remove-Item Env:\SELF   -ErrorAction SilentlyContinue
    Remove-Item Env:\PSTEMP -ErrorAction SilentlyContinue

    $afterFiles = @(Get-ChildItem -LiteralPath $roDir -Force | ForEach-Object { $_.Name })
    $zeroUsbWriteOk = (($beforeFiles -join '|') -eq ($afterFiles -join '|')) -and ($afterFiles.Count -eq 1)

    $aPass = ($b64RoundTripOk -and ($extRc -eq 0) -and (Test-Path -LiteralPath $extractedPs1) -and $zeroUsbWriteOk)
    Add-SmokeResult -Id 'SMK-A' -Title 'Zero-USB-Write 추출 · URL-Safe Base64 특수문자 경로 왕복' -Passed $aPass -Detail (
        "Base64Safe=$b64SafeChars, RoundTripMatch=$($decodedPath -eq $trickyPath), ExtractRC=$extRc, ZeroSourceWrite=$zeroUsbWriteOk"
    )
    if (-not $aPass) { throw 'SMK-A 실패로 후속 스모크 테스트를 중단합니다.' }

    # 추출된 페이로드에서 말미 2줄(Start-AsanPrinterManagerApp / exit 99)만 분리해 테스트 하니스용 라이브러리 준비
    $payloadRaw = [IO.File]::ReadAllText($extractedPs1, [Text.Encoding]::UTF8)
    $libCode = [regex]::Replace($payloadRaw, '(?m)^Start-AsanPrinterManagerApp\r?\nexit 99\s*$', '')
    if ($libCode.Length -eq $payloadRaw.Length) {
        throw '페이로드 말미 Start-AsanPrinterManagerApp / exit 99 패턴을 찾지 못했습니다.'
    }
    $libPs1 = Join-Path $workRoot 'payload_lib.ps1'
    [IO.File]::WriteAllText($libPs1, $libCode, (New-Object System.Text.UTF8Encoding($true)))

    # 테스트용 합성 오프라인 백업 ZIP 생성 (탭 2 지연검증/그리드/SEWOO 잠금/도우미 검증용)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $synDir = Join-Path $workRoot 'SynBackupSrc'
    $synZip = Join-Path $workRoot 'SYNTHETIC_PC_20261123_1200.zip'
    New-Item -ItemType Directory -Path $synDir -Force | Out-Null

    $synJsonObj = [pscustomobject]@{
        FormatVersion    = 6
        AppVersion       = '1.0.0-beta.3'
        SourceComputer   = 'WIN11-OLD-PC'
        SourceIP         = '172.25.99.99'
        SourceOsName     = 'Windows 11 Enterprise'
        SourceOsBuild    = 22631
        SourceIsWin11    = $true
        SourceMachineSID = 'S-1-5-21-1111111111-2222222222-3333333333'
        IsOfflineBackup  = $false
        ExportedAt       = '2026-11-25 03:55:00'
        DefaultPrinter   = '병동_교세라_5000'
        ExcludedVirtuals = 2
        ExportedPrtCount = 0
        ExportedScanCnt  = 0
        TwainFolders     = @('SampleTwain')
        BackupNotes      = @(
            [pscustomobject]@{ Level = 'Info'; Target = '병동_WSD_프린터'; Message = '[WSD전환대상] WSD -> TCP/IP(172.25.99.50) 자동 전환 대상' },
            [pscustomobject]@{ Level = 'Special'; Target = 'SLK-TE201'; Message = '[네임바코드(세우)] [Win11 전용 재설치 필수]' }
        )
        Printers         = @(
            [pscustomobject]@{
                Name = '병동_교세라_5000'; DriverName = 'Kyocera ECOSYS PA5000x KX'; PortName = '172.25.99.10'; PortKind = 'TCPIP'
                ConnectionName = $null; Category = '일반'; SpecialType = 'STANDARD'; BackupStatusCode = 'Healthy'; BackupStatusText = '정상'
                BackupReason = '인쇄 포트(172.25.99.10:9100) 정상 응답'; WsdTargetIp = $null; WsdModelName = $null; WsdTargetMode = $null
                WsdTargetShare = $null; SpecialDatFile = $null; SpecialRegFile = $null; Default = $true
            },
            [pscustomobject]@{
                Name = 'SLK-TE201'; DriverName = 'Sewoo SLK-TE201'; PortName = 'USBPOS0'; PortKind = 'LOCAL'
                ConnectionName = $null; Category = '네임바코드(세우)'; SpecialType = 'SEWOO_TE201'; BackupStatusCode = 'Healthy'; BackupStatusText = '특수(네임바코드(세우))'
                BackupReason = '[Win11 전용 재설치 필수] 로컬 직결 포트'; WsdTargetIp = $null; WsdModelName = $null; WsdTargetMode = $null
                WsdTargetShare = $null; SpecialDatFile = $null; SpecialRegFile = $null; Default = $false
            },
            [pscustomobject]@{
                Name = 'id카드'; DriverName = 'SISS HODOO SIP-30(Class)'; PortName = '172.25.99.20'; PortKind = 'TCPIP'
                ConnectionName = $null; Category = '진료카드(SIP-30M)'; SpecialType = 'SIP30M_IDCARD'; BackupStatusCode = 'Healthy'; BackupStatusText = '특수(진료카드(SIP-30M))'
                BackupReason = '특수 장비(SIP-30M) 보호 예외 적용'; WsdTargetIp = $null; WsdModelName = $null; WsdTargetMode = $null
                WsdTargetShare = $null; SpecialDatFile = $null; SpecialRegFile = $null; Default = $false
            },
            [pscustomobject]@{
                Name = '약제팀_ZT411'; DriverName = 'ZDesigner ZT411-203dpi ZPL'; PortName = '172.23.38.215'; PortKind = 'TCPIP'
                ConnectionName = $null; Category = '라벨(ZT410/411)'; SpecialType = 'ZEBRA_ZT411'; BackupStatusCode = 'Healthy'; BackupStatusText = '특수(라벨(ZT410/411))'
                BackupReason = '인쇄 포트(172.23.38.215:9100) 정상 응답'; WsdTargetIp = $null; WsdModelName = $null; WsdTargetMode = $null
                WsdTargetShare = $null; SpecialDatFile = $null; SpecialRegFile = $null; Default = $false
            },
            [pscustomobject]@{
                Name = '폐기의심_구형프린터'; DriverName = 'Samsung M382x Series'; PortName = '172.25.99.88'; PortKind = 'TCPIP'
                ConnectionName = $null; Category = '일반'; SpecialType = 'STANDARD'; BackupStatusCode = 'SuspectedInactive'; BackupStatusText = '비활성의심'
                BackupReason = 'TCP/IP(172.25.99.88) 무응답'; WsdTargetIp = $null; WsdModelName = $null; WsdTargetMode = $null
                WsdTargetShare = $null; SpecialDatFile = $null; SpecialRegFile = $null; Default = $false
            }
        )
        Ports            = @(
            [pscustomobject]@{ Name = '172.25.99.10'; Kind = 'TCPIP'; HostAddress = '172.25.99.10'; Protocol = 'RAW'; PortNumber = 9100; Queue = $null; SNMPEnabled = $false; ByteCount = $false },
            [pscustomobject]@{ Name = '172.25.99.20'; Kind = 'TCPIP'; HostAddress = '172.25.99.20'; Protocol = 'RAW'; PortNumber = 9100; Queue = $null; SNMPEnabled = $false; ByteCount = $false },
            [pscustomobject]@{ Name = '172.23.38.215'; Kind = 'TCPIP'; HostAddress = '172.23.38.215'; Protocol = 'RAW'; PortNumber = 9100; Queue = $null; SNMPEnabled = $false; ByteCount = $false }
        )
    }
    $synJson = $synJsonObj | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $synDir 'PrinterBackup.json'), $synJson, (New-Object System.Text.UTF8Encoding($true)))
    [System.IO.Compression.ZipFile]::CreateFromDirectory($synDir, $synZip)

    # ========================================================================
    # [Test B] 코어 엔진 읽기 전용 실환경 진단 + 인메모리 로직 단위 검증
    # ========================================================================
    $testBRunner = Join-Path $workRoot 'run_test_b.ps1'
    $testBCode = @"
`$ErrorActionPreference = 'Stop'
. '$($libPs1 -replace "'", "''")'

`$sid = Get-LocalMachineSID
`$wpp = Test-WindowsProtectedPrintMode
`$nic = Get-ActiveNetworkInfo
`$net = Test-AsanNetworkAndServer
`$locPrts = @(Get-LocalPrinterDiagnostics -OfflineMode)
`$scanInv = Get-ScannerDriverInventory
`$verPrts = @(Get-InstalledPrintersVerifyInfo)

# 1. 실환경 읽기 전용 진단 결과 검증
if (`$sid -notmatch '^S-1-5-21-\d+-\d+-\d+$') { throw "SID 형식 오류: `$sid" }
if (`$null -eq `$wpp -or `$null -eq `$wpp.IsEnabled) { throw 'WPP 결과 null' }
if (`$net.Status -notin @('Online','IntranetOnly','Offline')) { throw "알 수 없는 망 상태: `$(`$net.Status)" }

# 2. 특수장비(ZT411 PDF 규격 + EPSON TM-T88 LPT/USB 포트 분기) + 가상 프린터 필터 인메모리 검증
`$pSip    = Get-SpecialPrinterProfile -PrinterName 'id카드' -DriverName 'SISS HODOO SIP-30' -PortName '10.1.1.1'
`$pSew    = Get-SpecialPrinterProfile -PrinterName 'Sewoo' -DriverName 'SLK-TE201' -PortName 'USBPOS0'
`$pZeb    = Get-SpecialPrinterProfile -PrinterName '투약바코드' -DriverName 'ZDesigner ZD410-203dpi ZPL' -PortName 'USB001'
`$pZt4    = Get-SpecialPrinterProfile -PrinterName '약제팀 라벨' -DriverName 'ZDesigner ZT411-203dpi ZPL' -PortName '172.23.38.215'
`$pBix    = Get-SpecialPrinterProfile -PrinterName '팔찌' -DriverName 'BIXOLON SLP-TX220' -PortName 'USB002'
`$pT88Lpt = Get-SpecialPrinterProfile -PrinterName 'EPSON TM-T88VI' -DriverName 'EPSON TM-T88VI Receipt' -PortName 'LPT1:'
`$pT88Usb = Get-SpecialPrinterProfile -PrinterName 'EPSON TM-T88VI' -DriverName 'EPSON TM-T88VI Receipt' -PortName 'USB003'
`$pStd    = Get-SpecialPrinterProfile -PrinterName '병동레이저' -DriverName 'Kyocera ECOSYS PA5000x KX' -PortName '10.1.1.2'
`$lptDevs = @(Get-DeviceManagerLptPorts)
if (`$pSip.Type -ne 'SIP30M_IDCARD' -or (-not `$pSip.SkipAliveFilter)) { throw 'SIP30M 분류 오류' }
if (`$pSew.Type -ne 'SEWOO_TE201' -or (-not `$pSew.Win11ReinstallOnly)) { throw 'SEWOO 분류 오류' }
if (`$pZeb.Type -ne 'ZD410_411') { throw 'ZD410 분류 오류' }
if (`$pZt4.Type -ne 'ZEBRA_ZT411' -or (-not `$pZt4.ExcludeFromPcl6) -or (-not `$pZt4.ExcludeBulkTest)) { throw 'ZT411 분류 오류' }
if ((@(Get-DetectedVendors -Text 'ZT411 ZBRN')) -notcontains 'ZEBRA') { throw 'ZT411 벤더 감지 오류' }
if (`$pBix.Type -ne 'BIXOLON_TX220') { throw 'TX220 분류 오류' }
if (`$pT88Lpt.Type -ne 'EPSON_TMT88_LPT' -or (-not `$pT88Lpt.NoDriverBackup)) { throw 'EPSON TM-T88VI LPT1 무드라이버 분류 오류' }
if (`$pT88Usb.NoDriverBackup) { throw 'EPSON TM-T88VI USB 포트가 무드라이버 삭제 대상으로 오분류됨' }
if (`$pStd.IsSpecial) { throw '일반 프린터 오분류' }
if (-not (Test-IsVirtualPrinter -PrinterName 'Microsoft Print to PDF' -PortName 'PORTPROMPT:')) { throw '가상 프린터 필터 오류' }

# 2-A. ZT411 도우미 체크리스트 골든 이미지 로컬 정책 검증 (원격 172.23.2.130 미참조 / ZDesigner.inf / 나가기 / .drx)
`$ztRow  = [pscustomobject]@{ SpecialType = 'ZEBRA_ZT411'; PortKind = 'TCPIP'; PortName = '172.23.38.215'; HostAddress = '172.23.38.215'; PrinterName = '약제팀_ZT411' }
`$ztInfo = Get-SpecialPrinterAssistantInfo -SpecialRow `$ztRow
if (`$ztInfo.Checklist -match '172\.23\.2\.130') {
    throw 'ZT411 체크리스트에 금지된 원격 드라이버 서버(172.23.2.130) 잔존'
}
if (`$ztInfo.Checklist -notmatch 'ZT411 \(약국용 신형라벨프린터\)' -or `$ztInfo.Checklist -notmatch '(ZDesigner|ZBRN)\.inf' -or `$ztInfo.Checklist -notmatch '나가기' -or `$ztInfo.Checklist -notmatch '인쇄 기본 설정') {
    throw 'ZT411 골든 이미지 로컬 정책 안내 문구 누락'
}

# 2-B. 버그 리포트 민감정보 마스킹(동적 공용암호 + HostCredCache + 2글자 미만 미훼손) + 5일 정리 NTFS 타임스탬프 검증
`$cfgPws = @(Get-ConfiguredDefaultPasswords)
`$origDefPws = `$global:AsanCtx.DefaultPasswords
`$sampleDefPw = 'DummySecretPw99!'
if (`$cfgPws.Count -gt 0) {
    `$sampleDefPw = `$cfgPws[0]
} else {
    `$global:AsanCtx.DefaultPasswords = @(`$sampleDefPw)
}
try {
    `$global:AsanCtx.HostCredCache['10.0.0.99'] = [pscustomobject]@{ User = 'admin'; Pass = 'CachedHostPw77!' }
    `$masked = Protect-ReportSensitiveText -Text "pw=`$sampleDefPw cache=CachedHostPw77! custom=MySecret! ip=172.25.1.1" -ExtraSecrets @('MySecret!', '1')
    `$global:AsanCtx.HostCredCache.Remove('10.0.0.99')
    if (`$masked.Contains(`$sampleDefPw) -or `$masked -match 'CachedHostPw77|MySecret' -or `$masked -notmatch '172\.25\.1\.1') {
        throw "민감정보 마스킹 검증 실패: `$masked"
    }

    `$fakePrtBak = Join-Path '$($workRoot -replace "'", "''")' 'FakePrtBak'
    New-Item -ItemType Directory -Path `$fakePrtBak -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path `$fakePrtBak '_REPORTS') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path `$fakePrtBak '_DB') -Force | Out-Null

    # 폴더 타임스탬프는 7일 전이지만 PrinterBackup.json은 오늘 갱신된 재백업(삭제되면 안 됨!)
    `$refreshedDir = Join-Path `$fakePrtBak 'TESTPC(172.25.1.1)'
    New-Item -ItemType Directory -Path `$refreshedDir -Force | Out-Null
    `$refJson = Join-Path `$refreshedDir 'PrinterBackup.json'
    [IO.File]::WriteAllText(`$refJson, '{}', (New-Object System.Text.UTF8Encoding(`$true)))
    (Get-Item -LiteralPath `$refreshedDir).LastWriteTime = (Get-Date).AddDays(-7)

    # 폴더와 json 모두 6일 전인 실제 만료 백업(삭제되어야 함!)
    `$expiredDir = Join-Path `$fakePrtBak 'OLDPC(172.25.1.2)'
    New-Item -ItemType Directory -Path `$expiredDir -Force | Out-Null
    `$expJson = Join-Path `$expiredDir 'PrinterBackup.json'
    [IO.File]::WriteAllText(`$expJson, '{}', (New-Object System.Text.UTF8Encoding(`$true)))
    (Get-Item -LiteralPath `$expJson).LastWriteTime    = (Get-Date).AddDays(-6)
    (Get-Item -LiteralPath `$expiredDir).LastWriteTime = (Get-Date).AddDays(-6)

    `$repRes = Send-AsanBugReport -Category '테스트' -UserDescription "pw=`$sampleDefPw sp=My&Sec'ret!" -TargetPrinter "약제팀 `$sampleDefPw" -UiLogText "log `$sampleDefPw" -PrtBakDir `$fakePrtBak -PcIp '172.25.1.1' -ExtraSecrets @("My&Sec'ret!")
    if (-not `$repRes.Success -or (-not `$repRes.SavedToServer) -or (-not (Test-Path -LiteralPath (Join-Path `$repRes.SavedPath 'BugReport_Summary.txt')))) {
        throw '버그 리포트 저장 검증 실패'
    }
    `$repSumTxt = [IO.File]::ReadAllText((Join-Path `$repRes.SavedPath 'BugReport_Summary.txt'), [Text.Encoding]::UTF8)
    `$repJsnTxt = [IO.File]::ReadAllText((Join-Path `$repRes.SavedPath 'BugReport_Detail.json'), [Text.Encoding]::UTF8)
    if (`$repSumTxt.Contains(`$sampleDefPw) -or `$repJsnTxt.Contains(`$sampleDefPw) -or `$repJsnTxt -match 'My\\u0026Sec|My&Sec') {
        throw '저장된 버그 리포트(Summary/JSON)에 비밀번호 평문 또는 JSON 이스케이프 평문 잔존!'
    }
} finally {
    `$global:AsanCtx.DefaultPasswords = `$origDefPws
}

`$srvEntries = @(Get-ServerBackupEntries -PrtBakDir `$fakePrtBak -PcIp '172.25.1.1')
if (`$srvEntries.Count -ne 2) { throw ("_REPORTS/_DB 시스템 폴더 격리 실패: count=" + `$srvEntries.Count) }
`$entFresh = `$srvEntries | Where-Object { `$_.Name -eq 'TESTPC(172.25.1.1)' } | Select-Object -First 1
`$entOld   = `$srvEntries | Where-Object { `$_.Name -eq 'OLDPC(172.25.1.2)' } | Select-Object -First 1
if (`$entFresh.IsOld5Days -or (-not `$entOld.IsOld5Days)) {
    throw "NTFS 재백업 타임스탬프 판정 오류 (FreshOld=`$(`$entFresh.IsOld5Days), OldOld=`$(`$entOld.IsOld5Days))"
}
`$removedOld = @(Remove-OldServerBackups -PrtBakDir `$fakePrtBak -DaysThreshold 5)
if (`$removedOld.Count -ne 1 -or `$removedOld[0] -ne 'OLDPC(172.25.1.2)' -or (-not (Test-Path -LiteralPath `$refreshedDir))) {
    throw ("5일 경과 정리 보호 실패: removed=" + (`$removedOld -join ','))
}

# 2-C. 다국어 INF [Strings.xxxx] 영문/한글 우선순위 + 인라인 주석 + 따옴표 "%Token%" + 비모델 섹션 제외 검증
`$multiInf = @(
    '[Version]',
    'Signature="`$Windows NT`$"',
    '[SourceDisksNames]',
    '1 = "Driver Install Disk"',
    '[Kyocera.NTamd64] ; model section',
    '%MODEL_PA5000% = PA5000_INST, USBPRINT\Kyocera',
    '"%MODEL_QUOTED%" = PA5000_INST2, USBPRINT\Kyocera2',
    '[Strings] ; default english',
    'MODEL_PA5000 = "Kyocera ECOSYS PA5000x KX"',
    'MODEL_QUOTED = "Sindoh D410 Series PCL6"',
    '[Strings.0804]',
    'MODEL_PA5000 = "京瓷 ECOSYS PA5000x KX"'
) -join [Environment]::NewLine
`$parsedInfNames = @(Get-InfDisplayNames -InfText `$multiInf)
if (`$parsedInfNames -notcontains 'Kyocera ECOSYS PA5000x KX' -or `$parsedInfNames -notcontains 'Sindoh D410 Series PCL6' -or `$parsedInfNames -contains 'Driver Install Disk') {
    throw ("다국어/인라인주석/따옴표토큰 INF 파싱 오류: " + (`$parsedInfNames -join ' | '))
}

# 2-C2. 신도리코!=RICOH, Zebra 203dpi 이기종(ZD410!=ZT411) 차단, 한글 병동명(52병동) 비줄기 검증
`$sindohVends = @(Get-DetectedVendors -Text '신도리코 D410')
if ((`$sindohVends -contains 'RICOH') -or (`$sindohVends -notcontains 'SINDOH')) {
    throw ("신도리코 벤더 오분류: " + (`$sindohVends -join ','))
}
`$ztTokens = @(Get-SignificantTokens 'ZDesigner ZT411-203dpi ZPL')
`$ztStems  = @(Get-ModelStems -Tokens `$ztTokens)
`$zdScore  = Score-DriverDisplayName -DisplayName 'ZDesigner ZD410-203dpi ZPL' -SearchTarget 'ZDesigner ZT411-203dpi ZPL' -WantedNorm (Normalize-Text 'ZDesigner ZT411-203dpi ZPL') -WantedVendor 'ZEBRA' -Tokens `$ztTokens -ModelStems `$ztStems -WantedHasDigits (`$ztStems.Count -gt 0) -PreferPcl6 `$false -AllowVendorUniversal `$false
if (`$zdScore -ge 160) {
    throw "Zebra 203dpi 이기종 오매칭(ZT411->ZD410 Score=`$zdScore)"
}
`$korWardStems = @(Get-ModelStems -Tokens (Get-SignificantTokens '52병동 프린터'))
if (`$korWardStems.Count -ne 0) {
    throw ("한글 병동명 모델 줄기 오인: " + (`$korWardStems -join ','))
}

# 2-D. @(`$null) 고스트 행 차단 + '_' 접두어 호스트명 방어 + ZT411 PrnInst 제외 검증
`$nullPrtDef = Test-BackupDataDeferred -BackupData ([pscustomobject]@{ Printers = `$null; Ports = `$null })
if (`$nullPrtDef.Printers.Count -ne 0) { throw "Printers=`$null 고스트 행 생성 오류: `$(`$nullPrtDef.Printers.Count)" }
`$oldComp = `$env:COMPUTERNAME
try {
    `$env:COMPUTERNAME = '_TESTPC'
    `$fidTest = Get-BackupFolderId -PcIp '172.25.1.9'
    if (`$fidTest.StartsWith('_')) { throw "호스트명 '_' 접두어 미방어: `$fidTest" }
} finally {
    `$env:COMPUTERNAME = `$oldComp
}
`$ztLocalInst = Find-LocalSpecialInstaller -SpecialType 'ZEBRA_ZT411' -SkipRemoteProbe
if (`$ztLocalInst.ExePath -and `$ztLocalInst.ExePath -match '(?i)PrnInst') {
    throw "ZT411 설치기에서 금지된 PrnInst.exe 오인식: `$(`$ztLocalInst.ExePath)"
}
foreach (`$ztField in @(`$ztLocalInst.Folder, `$ztLocalInst.ExePath, `$ztLocalInst.InfPath, `$ztLocalInst.DrxPath, `$ztLocalInst.DrsPath)) {
    if (`$ztField -and `$ztField -match '(?i)ZD410|ZD411|172\.23\.2\.130') {
        throw "ZT411 탐색 결과 오인식(ZD410/원격서버): `$ztField"
    }
}

# 2-D2. Build-InfIndexCache Provider=%Token% 간접 참조 해석 검증 (ZDesigner.inf 패턴)
`$tmpInfPath = Join-Path '$($workRoot -replace "'", "''")' 'fake_indirect.inf'
`$tmpInfBody = @(
    '[Version]',
    'Signature="`$Windows NT`$"',
    'Provider=%EP% ; indirect provider token',
    '[Models.NTamd64]',
    '"Generic Label 203dpi" = INST_SEC, USBPRINT\LABEL203',
    '[Strings]',
    'EP="Zebra Technologies Corporation"'
) -join "`r`n"
[IO.File]::WriteAllText(`$tmpInfPath, `$tmpInfBody, (New-Object System.Text.UTF8Encoding(`$false)))
`$infIdxRes = @(Build-InfIndexCache -InfFiles @((Get-Item -LiteralPath `$tmpInfPath)))
if (`$infIdxRes.Count -ne 1 -or (`$infIdxRes[0].Vendors -notcontains 'ZEBRA')) {
    throw "Provider=%Token% 간접 참조 벤더 해석 실패: `$(`$infIdxRes[0].Vendors -join ',')"
}

# 2-E. USB 바코드 장치 판별 읽기 전용 단위 검증 (100% 비파괴 — pnputil 미호출)
`$brokenUsbDevs = @(Get-BrokenBarcodeUsbDevices)
if (`$null -eq `$brokenUsbDevs) { throw 'Get-BrokenBarcodeUsbDevices 반환값 오류' }
`$bixVend = @(Get-DetectedVendors -Text 'TX220')
if (`$bixVend -notcontains 'BIXOLON') { throw 'TX220 벤더 매핑 누락' }
`$zbrVend = @(Get-DetectedVendors -Text 'ZDesigner ZT411-203dpi ZPL')
`$zbrPkg  = @(Get-DetectedVendors -Text 'Zebra Technologies zbrn.inf')
if ((`$zbrVend -notcontains 'ZEBRA') -or (`$zbrPkg -notcontains 'ZEBRA')) { throw 'ZT411 정규 벤더 매칭 오류' }

# 3. 모델 줄기/와일드카드 & 2패스 드라이버 스코어링 검증
`$stemsSam = Get-ModelStems -Tokens (Get-SignificantTokens 'Samsung SL-M3820ND PCL6')
`$wcSam    = Test-WildcardModelMatch -CandidateDisplayName 'Samsung M332x 382x 402x Series' -WantedStems `$stemsSam
`$stemsKyo = Get-ModelStems -Tokens (Get-SignificantTokens 'Kyocera ECOSYS PA5000dn')
`$wcKyo    = Test-WildcardModelMatch -CandidateDisplayName 'Kyocera ECOSYS PA5000x KX' -WantedStems `$stemsKyo
if (-not `$wcSam -or -not `$wcKyo) { throw "와일드카드 매칭 실패 (Sam=`$wcSam, Kyo=`$wcKyo)" }

`$toks = @(Get-SignificantTokens 'Kyocera ECOSYS PA5000dn')
`$sMs  = Score-DriverDisplayName -DisplayName 'Microsoft IPP Class Driver' -SearchTarget 'Kyocera ECOSYS PA5000dn' -WantedNorm (Normalize-Text 'Kyocera ECOSYS PA5000dn') -WantedVendor 'KYOCERA' -Tokens `$toks -ModelStems `$stemsKyo -WantedHasDigits `$true -PreferPcl6 `$true -AllowVendorUniversal `$true
`$sKx1 = Score-DriverDisplayName -DisplayName 'Kyocera KX DRIVER for Universal Printing' -SearchTarget 'Kyocera ECOSYS PA5000dn' -WantedNorm (Normalize-Text 'Kyocera ECOSYS PA5000dn') -WantedVendor 'KYOCERA' -Tokens `$toks -ModelStems `$stemsKyo -WantedHasDigits `$true -PreferPcl6 `$true -AllowVendorUniversal `$false
`$sKx2 = Score-DriverDisplayName -DisplayName 'Kyocera KX DRIVER for Universal Printing' -SearchTarget 'Kyocera ECOSYS PA5000dn' -WantedNorm (Normalize-Text 'Kyocera ECOSYS PA5000dn') -WantedVendor 'KYOCERA' -Tokens `$toks -ModelStems `$stemsKyo -WantedHasDigits `$true -PreferPcl6 `$true -AllowVendorUniversal `$true
`$sUpd = Score-DriverDisplayName -DisplayName 'Samsung Universal Print Driver 3' -SearchTarget 'Samsung SL-M3820ND' -WantedNorm (Normalize-Text 'Samsung SL-M3820ND') -WantedVendor 'SAMSUNG' -Tokens @(Get-SignificantTokens 'Samsung SL-M3820ND') -ModelStems `$stemsSam -WantedHasDigits `$true -PreferPcl6 `$true -AllowVendorUniversal `$true
if (`$sMs -ne -1 -or `$sKx1 -ne -1 -or `$sKx2 -lt 200 -or `$sUpd -ne -1) {
    throw "2패스 스코어링 오류 (MS=`$sMs, KX_P1=`$sKx1, KX_P2=`$sKx2, SamUPD3=`$sUpd)"
}

# 4. 합성 ZIP 메타데이터 로드 & 지연 검증(비실시간) 확인
`$meta = Read-BackupSourceMetadata -SourcePath '$($synZip -replace "'", "''")'
if (-not `$meta -or -not `$meta.IsZip -or `$meta.Data.FormatVersion -ne 6) { throw '합성 ZIP 메타데이터 로드 실패' }
`$def  = Test-BackupDataDeferred -BackupData `$meta.Data
`$rowSew  = `$def.Printers | Where-Object { `$_.SpecialType -eq 'SEWOO_TE201' } | Select-Object -First 1
`$rowInac = `$def.Printers | Where-Object { `$_.StatusCode -eq 'SuspectedInactive' } | Select-Object -First 1
`$rowNorm = `$def.Printers | Where-Object { `$_.PrinterName -eq '병동_교세라_5000' } | Select-Object -First 1
if (`$rowSew.Selected -or `$rowSew.StatusText -ne '전용 설치 필요') { throw "SEWOO 기본 체크해제 규칙 실패: Status=`$(`$rowSew.StatusText)" }
if (`$rowInac.Selected) { throw '비활성의심 기본 체크해제 규칙 실패' }
if (-not `$rowNorm.Selected) { throw '정상 프린터 기본 체크 규칙 실패' }

Write-Output ("TEST_B_OK|SID=`$sid|WPP=`$(`$wpp.IsEnabled)|NetStatus=`$(`$net.Status)|IP=`$(`$net.IPAddress)|LocalPrinters=`$(`$locPrts.Count)|VerifyPrinters=`$(`$verPrts.Count)|AutoScan=`$(`$scanInv.AutoScanners.Count)|UnclassScan=`$(`$scanInv.UnclassifiedScanners.Count)")
"@
    [IO.File]::WriteAllText($testBRunner, $testBCode, (New-Object System.Text.UTF8Encoding($true)))
    $bOut = & $ps51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $testBRunner 2>&1
    $bRc = $LASTEXITCODE
    $bTxt = (@($bOut) | ForEach-Object { [string]$_ }) -join "`r`n"
    $bPass = ($bRc -eq 0 -and $bTxt -match 'TEST_B_OK')
    Add-SmokeResult -Id 'SMK-B' -Title '코어 엔진 읽기 전용 실환경 진단 및 인메모리 로직 단위 검증' -Passed $bPass -Detail $bTxt

    # ========================================================================
    # [Test C] 실제 -STA WinForms GUI 기동 · Runspace 비동기 · 4탭 순회 · 레이아웃 감사 · exit 99
    # ========================================================================
    $testCRunner = Join-Path $workRoot 'run_test_c_gui.ps1'
    $guiReportFile = Join-Path $workRoot 'gui_smoke_report.json'
    $testCCode = @"
`$ErrorActionPreference = 'Stop'
. '$($libPs1 -replace "'", "''")'

`$script:SmokeErrors = [System.Collections.Generic.List[string]]::new()
`$script:SmokeStage  = 0
`$script:SmokeTicks  = 0
`$script:LayoutIssues = [System.Collections.Generic.List[string]]::new()
`$script:SmokeMeta   = @{}

function Test-ContainerLayout {
    param([System.Windows.Forms.Control]`$Container, [string]`$ContextLabel)
    if (-not `$Container -or -not `$Container.Visible) { return }
    `$cWidth  = `$Container.ClientSize.Width
    `$cHeight = `$Container.ClientSize.Height
    `$visButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    foreach (`$ch in `$Container.Controls) {
        if (-not `$ch.Visible) { continue }
        if (`$ch -is [System.Windows.Forms.Button]) {
            `$visButtons.Add(`$ch)
            if (`$ch.Right -gt (`$cWidth + 3)) {
                `$script:LayoutIssues.Add("`$ContextLabel > Button '`$(`$ch.Text)' Right=`$(`$ch.Right) > ParentWidth=`$cWidth")
            }
            if (`$ch.Left -lt -2) {
                `$script:LayoutIssues.Add("`$ContextLabel > Button '`$(`$ch.Text)' Left=`$(`$ch.Left) < 0")
            }
            if (`$ch.Bottom -gt (`$cHeight + 3)) {
                `$script:LayoutIssues.Add("`$ContextLabel > Button '`$(`$ch.Text)' Bottom=`$(`$ch.Bottom) > ParentHeight=`$cHeight")
            }
        }
        if (`$ch -is [System.Windows.Forms.DataGridView]) {
            if (`$ch.Height -lt 80) {
                `$script:LayoutIssues.Add("`$ContextLabel > DataGridView crushed: Height=`$(`$ch.Height) (< 80)")
            }
        }
        if (`$ch -is [System.Windows.Forms.TextBox] -and `$ch.Multiline) {
            if (`$ch.Height -lt 40) {
                `$script:LayoutIssues.Add("`$ContextLabel > Multiline TextBox crushed: Height=`$(`$ch.Height) (< 40)")
            }
        }
        if (`$ch.Controls.Count -gt 0) {
            Test-ContainerLayout -Container `$ch -ContextLabel "`$ContextLabel/`$(`$ch.GetType().Name)"
        }
    }
    for (`$i = 0; `$i -lt `$visButtons.Count; `$i++) {
        for (`$j = `$i + 1; `$j -lt `$visButtons.Count; `$j++) {
            `$b1 = `$visButtons[`$i]
            `$b2 = `$visButtons[`$j]
            `$inter = [System.Drawing.Rectangle]::Intersect(`$b1.Bounds, `$b2.Bounds)
            if (`$inter.Width -gt 2 -and `$inter.Height -gt 2) {
                `$script:LayoutIssues.Add("`$ContextLabel > Overlap '`$(`$b1.Text)' & '`$(`$b2.Text)' (`$(`$inter.Width)x`$(`$inter.Height))")
            }
        }
    }
}

# Start-AsanPrinterManagerApp와 완전히 동일한 GUI 조립 (단, ShowDialog 직전 자동 스모크 타이머 부착)
Initialize-MainGuiShell
Initialize-Tab1BackupUi
Initialize-Tab2RestoreUi
Initialize-Tab3VerifyUi
Initialize-Tab4ServerUi
Register-DisabledTooltipTree -Root `$script:Ui.Form
Sync-AllUiButtonStates

`$script:Ui.TabMain.Add_SelectedIndexChanged({
    `$idx = `$script:Ui.TabMain.SelectedIndex
    if (`$idx -ne 3) {
        Stop-Tab4PreviewAsync
    }
    if (`$idx -eq 2 -and (-not `$script:AsyncState.IsBusy)) {
        if (-not `$script:Tab3Ui.HasLoadedOnce -or `$script:Tab3Ui.NeedsRefresh) {
            Invoke-Tab3RefreshAsync
        }
    } elseif (`$idx -eq 3) {
        Update-Tab4PreviewBox
        Sync-AllUiButtonStates
    }
})

`$script:Ui.Form.Add_Shown({
    Add-UiLog -Message "프린터·드라이버 마이그레이션 도구 v`$(`$global:AsanCtx.AppVersion) 기동됨 (Smoke Test)" -Level 'INFO'
    Invoke-EnvironmentRefreshAsync -AfterRefresh {
        `$bestMatch = @(`$script:AppState.ServerBackups | Where-Object { `$_.MatchRank -le 2 } | Sort-Object MatchRank, @{ Expression = { `$_.LastWriteTime }; Descending = `$true }) | Select-Object -First 1
        if (`$script:AppState.IsWin11 -and `$bestMatch) {
            `$script:Ui.TabMain.SelectedIndex = 1
        } else {
            `$script:Ui.TabMain.SelectedIndex = 0
        }
    }
})

`$smokeTimer = New-Object System.Windows.Forms.Timer
`$smokeTimer.Interval = 350
`$smokeTimer.Add_Tick({
    `$script:SmokeTicks++
    try {
        # 최대 35초 타임아웃 안전장치 (무한 대기 원천 차단)
        if (`$script:SmokeTicks -gt 100) {
            `$script:SmokeErrors.Add("Smoke test timeout at stage `$(`$script:SmokeStage)")
            `$smokeTimer.Stop()
            `$script:Ui.Form.Close()
            return
        }

        if (`$script:AsyncState.IsBusy) { return }

        switch (`$script:SmokeStage) {
            0 {
                # 초기 환경 진단(Runspace) 완료 확인 + 스마트 시작 탭 검증 (일치 백업 없으면 Win 11 구 PC도 탭 1)
                if (`$null -eq `$script:AppState.NetworkInfo) { return }
                `$bestMatchNow = @(`$script:AppState.ServerBackups | Where-Object { `$_.MatchRank -le 2 }) | Select-Object -First 1
                `$expectTab = 0
                if (`$script:AppState.IsWin11 -and `$bestMatchNow) { `$expectTab = 1 }
                `$script:SmokeMeta['InitSelectedTab'] = `$script:Ui.TabMain.SelectedIndex
                `$script:SmokeMeta['IsWin11']         = `$script:AppState.IsWin11
                `$script:SmokeMeta['NetStatus']       = `$script:AppState.NetworkInfo.Status
                `$script:SmokeMeta['HeaderSid']       = `$script:Ui.LblSid.Text
                `$script:SmokeMeta['HeaderOs']        = `$script:Ui.LblOs.Text
                if (`$script:Ui.TabMain.SelectedIndex -ne `$expectTab) {
                    `$script:SmokeErrors.Add("초기 탭 불일치: 기대=`$expectTab, 실제=`$(`$script:Ui.TabMain.SelectedIndex)")
                }
                # 탭 1로 이동 후 오프라인 읽기 전용 사전 스캔 실행
                `$script:Ui.TabMain.SelectedIndex = 0
                `$script:SmokeStage = 1
                Invoke-Tab1ScanAsync -ForceOfflineProbe
            }
            1 {
                # 탭 1 스캔 완료 확인
                if (-not `$script:Tab1Ui.HasScannedOnce) { return }
                `$script:SmokeMeta['Tab1Rows'] = `$script:Tab1Ui.DgvPrinters.Rows.Count
                # 탭 2로 이동 후 합성 ZIP 로드 테스트
                `$script:Ui.TabMain.SelectedIndex = 1
                `$script:SmokeStage = 2
                Load-Tab2BackupSourceAsync -SourcePath '$($synZip -replace "'", "''")'
            }
            2 {
                # 탭 2 합성 백업 로드 및 SEWOO 잠금 / 도우미 자동 펼침 검증
                if ([string]::IsNullOrWhiteSpace([string]`$script:Tab2Ui.LoadedSourcePath)) { return }
                `$dgv2 = `$script:Tab2Ui.DgvRestore
                `$script:SmokeMeta['Tab2Rows']        = `$dgv2.Rows.Count
                `$script:SmokeMeta['HelperExpanded']  = `$script:Tab2Ui.HelperExpanded
                `$script:SmokeMeta['BtnRestoreOn']    = `$script:Tab2Ui.BtnStartRestore.Enabled
                `$sewooLocked = `$false
                foreach (`$r in `$dgv2.Rows) {
                    if (`$r.Tag -and `$r.Tag.SpecialType -eq 'SEWOO_TE201') {
                        `$sewooLocked = (`$r.Cells[0].ReadOnly -eq `$true -and `$r.Cells[0].Value -eq `$false)
                    }
                }
                `$script:SmokeMeta['SewooLocked'] = `$sewooLocked
                if (`$dgv2.Rows.Count -ne 5) { `$script:SmokeErrors.Add("Tab2 그리드 행 수 불일치: `$(`$dgv2.Rows.Count)") }
                if (-not `$sewooLocked)      { `$script:SmokeErrors.Add('SEWOO_TE201 체크박스 잠금(ReadOnly+False) 미작동') }
                if (-not `$script:Tab2Ui.HelperExpanded) { `$script:SmokeErrors.Add('특수장비 감지 시 도우미 패널 자동 펼침 미작동') }
                if (-not `$script:Tab2Ui.BtnStartRestore.Enabled) { `$script:SmokeErrors.Add('선택 항목 있음에도 복원 시작 버튼 비활성') }
                if (`$script:Tab2Ui.BtnRetryFailed.Enabled -or (-not `$script:Ui.DisabledReasons.ContainsKey(`$script:Tab2Ui.BtnRetryFailed))) {
                    `$script:SmokeErrors.Add('비활성 버튼 사유 툴팁(BtnRetryFailed) 미등록')
                }

                # 탭 3으로 이동 (자동 Invoke-Tab3RefreshAsync 트리거)
                `$script:SmokeStage = 3
                `$script:Ui.TabMain.SelectedIndex = 2
            }
            3 {
                if (-not `$script:Tab3Ui.HasLoadedOnce) { return }
                `$script:SmokeMeta['Tab3Rows'] = `$script:Tab3Ui.DgvVerify.Rows.Count

                # 탭 4 이동 확인 + 표준 크기(1040x720) & 최소 크기(960x640) 전 탭 레이아웃 검사
                `$script:Ui.TabMain.SelectedIndex = 3
                `$script:SmokeStage = 4
            }
            4 {
                `$f = `$script:Ui.Form
                foreach (`$szPair in @(
                    @{ Label = '1040x720'; W = 1040; H = 720 },
                    @{ Label = '960x640';  W = 960;  H = 640 }
                )) {
                    `$f.Size = New-Object System.Drawing.Size(`$szPair.W, `$szPair.H)
                    [System.Windows.Forms.Application]::DoEvents()
                    Test-ContainerLayout -Container `$script:Ui.PnlHeader -ContextLabel "`$(`$szPair.Label)/Header"
                    Test-ContainerLayout -Container `$script:Ui.PnlFooter -ContextLabel "`$(`$szPair.Label)/Footer"

                    # WPP 배너 임시 표시 상태에서 배너 + 탭 2 도우미 동시 표시 레이아웃 검사 후 원복
                    `$origWppVis = `$script:Ui.PnlWppBanner.Visible
                    `$script:Ui.PnlWppBanner.Visible = `$true
                    [System.Windows.Forms.Application]::DoEvents()
                    Test-ContainerLayout -Container `$script:Ui.PnlWppBanner -ContextLabel "`$(`$szPair.Label)/WppBanner"
                    `$script:Ui.TabMain.SelectedIndex = 1
                    [System.Windows.Forms.Application]::DoEvents()
                    Test-ContainerLayout -Container `$script:Ui.TabMain.TabPages[1] -ContextLabel "`$(`$szPair.Label)/Tab2WithWpp"
                    `$script:Ui.PnlWppBanner.Visible = `$origWppVis

                    for (`$ti = 0; `$ti -lt 4; `$ti++) {
                        `$script:Ui.TabMain.SelectedIndex = `$ti
                        [System.Windows.Forms.Application]::DoEvents()
                        Test-ContainerLayout -Container `$script:Ui.TabMain.TabPages[`$ti] -ContextLabel "`$(`$szPair.Label)/Tab`$(`$ti+1)"
                    }
                }
                `$script:SmokeMeta['LogLineCount'] = (`$script:Ui.TxtLog.Lines).Count
                `$script:SmokeMeta['LayoutIssues'] = `$script:LayoutIssues.ToArray()

                `$smokeTimer.Stop()
                `$script:Ui.Form.Close()
            }
        }
    }
    catch {
        `$script:SmokeErrors.Add("Tick 예외(Stage `$(`$script:SmokeStage)): `$(`$_.Exception.Message)")
        `$smokeTimer.Stop()
        try { `$script:Ui.Form.Close() } catch {}
    }
})
`$smokeTimer.Start()

[void]`$script:Ui.Form.ShowDialog()
`$smokeTimer.Dispose()
`$script:Ui.Form.Dispose()

`$report = [pscustomobject]@{
    Errors       = `$script:SmokeErrors.ToArray()
    LayoutIssues = `$script:LayoutIssues.ToArray()
    Meta         = `$script:SmokeMeta
}
[IO.File]::WriteAllText('$($guiReportFile -replace "'", "''")', (`$report | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding(`$true)))

if (`$script:SmokeErrors.Count -gt 0) { exit 2 }
exit 99
"@
    [IO.File]::WriteAllText($testCRunner, $testCCode, (New-Object System.Text.UTF8Encoding($true)))

    $cOut = & $ps51 -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $testCRunner 2>&1
    $cRc = $LASTEXITCODE

    $cPass = $false
    $cLines = [System.Collections.Generic.List[string]]::new()
    $cLines.Add("GUI Process ExitCode=$cRc (expect 99)")

    if (Test-Path -LiteralPath $guiReportFile) {
        $rep = Get-Content -LiteralPath $guiReportFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $errList = @($rep.Errors)
        $layList = @($rep.LayoutIssues)
        $m = $rep.Meta
        $cLines.Add("InitTab=$($m.InitSelectedTab) (IsWin11=$($m.IsWin11)), NetStatus=$($m.NetStatus), Tab1Rows=$($m.Tab1Rows), Tab2Rows=$($m.Tab2Rows), Tab3Rows=$($m.Tab3Rows)")
        $cLines.Add("SewooLocked=$($m.SewooLocked), HelperAutoExpanded=$($m.HelperExpanded), BtnRestoreOn=$($m.BtnRestoreOn), LogLines=$($m.LogLineCount)")
        $cLines.Add("RuntimeErrors=$($errList.Count), LayoutIssues(1040x720 & 960x640)=$($layList.Count)")
        foreach ($e in $errList) { $cLines.Add("  [ERR] $e") }
        foreach ($l in $layList) { $cLines.Add("  [LAYOUT] $l") }
        $cPass = ($cRc -eq 99 -and $errList.Count -eq 0 -and $layList.Count -eq 0)
    }
    else {
        $cLines.Add('GUI 리포트 파일 미생성: ' + ((@($cOut) | ForEach-Object { [string]$_ }) -join ' '))
    }

    Add-SmokeResult -Id 'SMK-C' -Title '실제 -STA WinForms GUI 기동 · 4탭 비동기 순회 · 레이아웃 감사 · exit 99' -Passed $cPass -Detail ($cLines -join "`r`n")
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
$failedCnt = (@($testResults | Where-Object { -not $_.Passed })).Count
Write-Host '===================================================================='
if ($failedCnt -eq 0) {
    Write-Host (" LOCAL SMOKE TEST SUMMARY: ALL {0}/{0} TESTS PASSED" -f $testResults.Count)
    Write-Host '===================================================================='
    exit 0
}
else {
    Write-Host (" LOCAL SMOKE TEST SUMMARY: {0} FAILED / {1} TOTAL" -f $failedCnt, $testResults.Count)
    Write-Host '===================================================================='
    exit 1
}
