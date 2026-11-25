# ============================================================================
# [특수 프린터 전용 핸들러] 원본 최우선 추출 + ZT411 PDF 규격 + SIP-30M 중복 큐 정리
# ============================================================================
function Find-LocalSpecialInstaller {
    param(
        [string]$SpecialType,
        [switch]$SkipRemoteProbe
    )

    $baseRoots = @(
        'C:\Users\admin\드라이버(win10_x64)',
        'C:\Users\admin\드라이버(win10x64)',
        'C:\Users\admin\Desktop\admin'
    )

    if ($SpecialType -eq 'ZEBRA_ZT411') {
        # [정책] 원격 드라이버 서버 접근 금지 -> 모든 골든 이미지 공통 로컬 경로 최우선 탐색 (-SkipRemoteProbe는 하위호환 유지)
        $ztSearchDirs = [System.Collections.Generic.List[string]]::new()
        foreach ($exactDir in @(
            'C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)',
            'C:\Users\admin\드라이버(win10x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)'
        )) {
            if ((Test-Path -LiteralPath $exactDir) -and -not $ztSearchDirs.Contains($exactDir)) {
                $ztSearchDirs.Add($exactDir)
            }
        }
        # 1순위: 로컬 *ZT411* 폴더 (ZD410/ZD411 오인식 엄격 차단)
        foreach ($r in $baseRoots) {
            if (-not (Test-Path -LiteralPath $r)) { continue }
            foreach ($pat in @('*ZT411*', '*AMIS*\*ZT411*', '*PRT*\*ZT411*')) {
                foreach ($md in @(Get-ChildItem -Path (Join-Path $r $pat) -Directory -ErrorAction SilentlyContinue)) {
                    if ($md.FullName -match '(?i)ZD410|ZD411') { continue }
                    if (-not $ztSearchDirs.Contains($md.FullName)) { $ztSearchDirs.Add($md.FullName) }
                }
            }
        }
        # 2순위: 기타 *Zebra* 폴더 (ZD410/ZD411 폴더 반드시 제외)
        foreach ($r in $baseRoots) {
            if (-not (Test-Path -LiteralPath $r)) { continue }
            foreach ($pat in @('*Zebra*', '*AMIS*\*Zebra*')) {
                foreach ($md in @(Get-ChildItem -Path (Join-Path $r $pat) -Directory -ErrorAction SilentlyContinue)) {
                    if ($md.FullName -match '(?i)ZD410|ZD411') { continue }
                    if (-not $ztSearchDirs.Contains($md.FullName)) { $ztSearchDirs.Add($md.FullName) }
                }
            }
        }

        $ztFolder  = $null
        $ztExePath = $null
        $ztDrxPath = $null
        $ztDrsPath = $null
        $ztInfPath = $null

        foreach ($sd in $ztSearchDirs) {
            if (-not $ztFolder) { $ztFolder = $sd }
            if (-not $ztExePath) {
                $allExes = @(Get-ChildItem -LiteralPath $sd -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '(?i)PrnInst' -and $_.FullName -notmatch '(?i)ZD410|ZD411' } |
                    Sort-Object @{ Expression = { $_.FullName.Length } }, FullName)
                $exeHit = $allExes | Where-Object { $_.Name -match '(?i)(zd86526125|zd8)' } | Select-Object -First 1
                if (-not $exeHit) {
                    $exeHit = $allExes | Where-Object { $_.Name -match '(?i)(zd51177412|zd5|certified)' } | Select-Object -First 1
                }
                if (-not $exeHit) {
                    $exeHit = $allExes | Where-Object { $_.Name -match '(?i)(zebra|setup|driver)' } | Select-Object -First 1
                }
                if ($exeHit) { $ztExePath = $exeHit.FullName }
            }
            if (-not $ztInfPath) {
                # 골든 이미지에 사전 압축 해제된 ZD8-6-5-26125\ZDesigner.inf 최우선, 구형 ZBRN.inf 차순위 (ZD410/ZD411 하위 폴더 차단)
                $infHit = @(Get-ChildItem -LiteralPath $sd -Filter 'ZDesigner.inf' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '(?i)ZD410|ZD411' } |
                    Sort-Object @{ Expression = { $_.FullName.Length } }, FullName) | Select-Object -First 1
                if (-not $infHit) {
                    $infHit = @(Get-ChildItem -LiteralPath $sd -Filter 'ZBRN.inf' -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -notmatch '(?i)ZD410|ZD411' } |
                        Sort-Object @{ Expression = { $_.FullName.Length } }, FullName) | Select-Object -First 1
                }
                if ($infHit) { $ztInfPath = $infHit.FullName }
            }
            if (-not $ztDrxPath) {
                $drxHit = @(Get-ChildItem -LiteralPath $sd -Filter '*.drx' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '(?i)ZD410|ZD411' } |
                    Sort-Object @{ Expression = { $_.FullName.Length } }, FullName) | Select-Object -First 1
                if ($drxHit) { $ztDrxPath = $drxHit.FullName }
            }
            if (-not $ztDrsPath) {
                $drsHit = @(Get-ChildItem -LiteralPath $sd -Filter '*.drs' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '(?i)ZD410|ZD411' } |
                    Sort-Object FullName) | Select-Object -First 1
                if ($drsHit) { $ztDrsPath = $drsHit.FullName }
            }
        }
        # C:\ZD8-* / C:\ZD5-* 직접 압축 해제 폴더 보조 확인 (INF 전용, PrnInst.exe 오인식 방지)
        if (-not $ztInfPath) {
            foreach ($candInf in @('C:\ZD8-6-5-26125\ZDesigner.inf', 'C:\ZD5-1-17-7412\ZBRN\ZBRN.inf')) {
                if (Test-Path -LiteralPath $candInf) { $ztInfPath = $candInf; break }
            }
        }
        if (-not $ztFolder) {
            foreach ($candDir in @('C:\ZD8-6-5-26125', 'C:\ZD5-1-17-7412')) {
                if (Test-Path -LiteralPath $candDir) { $ztFolder = $candDir; break }
            }
        }

        return [pscustomobject]@{
            Found   = ($null -ne $ztFolder -or $null -ne $ztExePath -or $null -ne $ztInfPath -or $null -ne $ztDrxPath -or $null -ne $ztDrsPath)
            Folder  = $ztFolder
            ExePath = $ztExePath
            DrxPath = $ztDrxPath
            DrsPath = $ztDrsPath
            InfPath = $ztInfPath
        }
    }

    $subPatterns = switch ($SpecialType) {
        'SIP30M_IDCARD' { @('*수납창구*\*진료카드*\*네트워크*', '*진료카드*\*네트워크*', '*SIP*30*') }
        'SEWOO_TE201'   { @('*AMIS*\*세우*\*win11*', '*세우*\*win11*', '*LK-TE*\*win11*') }
        'ZD410_411'     { @('*AMIS*\*ZD410*', '*Zebra*바코드*') }
        'BIXOLON_TX220' { @('*AMIS*\*BIXOLON*', '*AMIS*\*BX(*', '*팔찌*프린터*') }
        default         { @() }
    }

    foreach ($root in $baseRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pat in $subPatterns) {
            $matchDir = @(Get-ChildItem -Path (Join-Path $root $pat) -Directory -ErrorAction SilentlyContinue) | Select-Object -First 1
            if ($matchDir) {
                $exe = @(Get-ChildItem -LiteralPath $matchDir.FullName -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '(?i)(setup|inst|driver|install|sip30|slk|sewoo)' } |
                    Sort-Object FullName) | Select-Object -First 1
                if (-not $exe) {
                    $exe = @(Get-ChildItem -LiteralPath $matchDir.FullName -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName) | Select-Object -First 1
                }
                $exePathVal = $null
                if ($exe) { $exePathVal = $exe.FullName }

                $drxPathVal = $null
                if ($SpecialType -eq 'ZD410_411') {
                    $drx = @(Get-ChildItem -LiteralPath $matchDir.FullName -Filter '*.drx' -File -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1
                    if ($drx) { $drxPathVal = $drx.FullName }
                }

                return [pscustomobject]@{
                    Found   = $true
                    Folder  = $matchDir.FullName
                    ExePath = $exePathVal
                    DrxPath = $drxPathVal
                    DrsPath = $null
                    InfPath = $null
                }
            }
        }
    }
    return [pscustomobject]@{ Found = $false; Folder = $null; ExePath = $null; DrxPath = $null; DrsPath = $null; InfPath = $null }
}

function Get-SpecialPrinterAssistantInfo {
    param(
        $SpecialRow,
        [switch]$SkipRemoteProbe,
        [object[]]$PreloadedLpts = $null
    )

    $inst = Find-LocalSpecialInstaller -SpecialType $SpecialRow.SpecialType -SkipRemoteProbe:$SkipRemoteProbe
    switch ($SpecialRow.SpecialType) {
        'SIP30M_IDCARD' {
            $ipHint = '백업 IP'
            if ($SpecialRow.HostAddress) { $ipHint = [string]$SpecialRow.HostAddress }
            else {
                $exIp = Extract-FirstUsableIPv4 -Text ([string]$SpecialRow.PortName)
                if ($exIp) { $ipHint = $exIp }
            }

            $chk = @(
                "SIP-30M 진료카드 발급기 설치 순서",
                "1. 위 'SIP-30M 설치'를 눌러 '표준 로컬(USB) 설치'를 선택하고, 장치 미연결 창에서 '아니오' 후 '마침'을 눌러 주세요.",
                "2. 'SIP-30M 설정 마무리'를 누르면 TCP/IP 포트($ipHint, SNMP 해제), 이름 'id카드', 4개 탭 설정이 자동 적용됩니다.",
                "3. 자동으로 열리는 인쇄 기본 설정에서 리본·코팅·농도·MS쓰기를 확인한 뒤 담당자에게 AMIS 테스트를 요청해 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'SIP30M_IDCARD'; TargetIp = $ipHint; Installer = $inst; HasStep2 = $true; Checklist = $chk }
        }
        'SEWOO_TE201' {
            $pHint = 'USB(USBPOS0)'
            if ($SpecialRow.PortName -match '(?i)LPT') { $pHint = 'Parallel(LPT1)' }
            $chk = @(
                "Sewoo SLK-TE201 네임바코드 설치 순서",
                "1. 위 '세우 전용 설치'를 눌러 모델 SLK-TE201을 체크하고, 기본 프린터 설정을 해제한 뒤 포트 $pHint 를 선택해 주세요.",
                "2. AMIS 3.0에 로그인한 뒤 개인환경설정 > PC별 환경설정에서 바코드 Agent를 실행해 주세요.",
                "3. 트레이의 Barcode Print Agent를 다시 열어 자동 등록된 7.2x327.5 항목을 지우고 8.0x8.5로 수동 등록해 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'SEWOO_TE201'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'ZEBRA_ZT411' {
            $isTcpLabel = ([string]$SpecialRow.PortKind -eq 'TCPIP') -or (-not [string]::IsNullOrWhiteSpace([string]$SpecialRow.HostAddress))
            $connHint   = 'USB 직결 장비입니다. 인식되지 않으면 위 USB 다시 인식을 눌러 주세요.'
            if ($isTcpLabel) {
                $connHint = "TCP/IP 네트워크 연결 ($($SpecialRow.PortName)) · ZDesigner ZT411-203dpi ZPL 자동 복원 대상입니다."
            }
            $ztRootDefault = 'C:\Users\admin\드라이버(win10_x64)\AMIS 3.0 장비\ZT411 (약국용 신형라벨프린터)'
            $infHint = "$ztRootDefault\ZD8-6-5-26125\ZDesigner.inf"
            if ($inst.InfPath) { $infHint = $inst.InfPath }
            $cfgHint = "$ztRootDefault\약국 라벨 용지크기별 설정파일\*.drx"
            if ($inst.DrxPath) { $cfgHint = $inst.DrxPath }
            elseif ($inst.DrsPath) { $cfgHint = $inst.DrsPath }
            $exeHint = 'zd86526125-certified.exe'
            if ($inst.ExePath) { $exeHint = [IO.Path]::GetFileName($inst.ExePath) }

            $chk = @(
                "Zebra ZT410/ZT411 약제팀 라벨 프린터 안내",
                "연결 방식: $connHint",
                "1. 기존 PC에서 추출한 드라이버와 인쇄 기본 설정을 최우선으로 자동 복원합니다.",
                "2. 대체 설치가 필요한 경우 로컬 경로($ztRootDefault)의 드라이버($infHint)를 사용합니다.",
                "   설치 파일($exeHint)을 실행했다면 드라이버 폴더 생성 후 마법사에서 프린터를 추가하지 말고 반드시 '나가기'로 닫아 주세요.",
                "3. 대체 드라이버로 설치되었거나 기존 설정이 빠져 있다면 '프린터 속성' > 인쇄 기본 설정에서 용지·농도를 맞추거나 설정 파일($cfgHint)을 불러와 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'ZEBRA_ZT411'; TargetIp = $SpecialRow.HostAddress; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'ZD410_411' {
            $drxHint = 'admin\드라이버(win10_x64)\AMIS3.0장비\ZD410(Zebra바코드)\*.drx'
            if ($inst.DrxPath) { $drxHint = $inst.DrxPath }
            $chk = @(
                "Zebra ZD-410/411 검사·투약 바코드 확인 순서",
                "1. USB 연결이 지정되지 않음으로 보이면 위 'USB 다시 인식'을 눌러 주세요. 해결되지 않으면 케이블을 한 번 뺐다가 다시 꽂아 주세요.",
                "2. 프린터 속성 > 드라이버 설정에서 상태확인 사용 안 함과 용지 설정 파일($drxHint) 적용 여부를 확인해 주세요.",
                "3. 용지와 상단 여백(검사 5.5x3.0 / 2.6mm, 투약 5.5x6.0 / 1.0mm)과 AMIS Barcode Print Agent를 확인해 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'ZD410_411'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'BIXOLON_TX220' {
            $chk = @(
                "BIXOLON SLP-TX220 팔찌 바코드 확인 순서",
                "1. USB 연결이 지정되지 않음으로 보이면 위 'USB 다시 인식'을 눌러 주세요. 해결되지 않으면 케이블을 한 번 뺐다가 다시 꽂아 주세요.",
                "2. 기본 설정 > Options에서 Darkness 11~12, mm, Landscape, Rotate 180, 성인 20x250 또는 소아 20x150을 확인해 주세요.",
                "3. Advanced Setup에서 감열지/리본 구분과 Sensor Black Mark를 맞춘 뒤 AMIS Barcode Print Agent를 확인해 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'BIXOLON_TX220'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'EPSON_TMT88_LPT' {
            $lptsNow   = if ($null -ne $PreloadedLpts) { @($PreloadedLpts) } else { @(Get-DeviceManagerLptPorts) }
            $lpt1Now   = $lptsNow | Where-Object { $_.PortName -ieq 'LPT1' } | Select-Object -First 1
            $otherLpts = @($lptsNow | Where-Object { $_.PortName -ine 'LPT1' })
            $lptStatLine = '현재 PC 장치관리자에서 LPT1이 감지되지 않았습니다. 패럴렐 케이블과 LPT 포트를 확인해 주세요.'
            if ($lpt1Now) {
                $lptStatLine = "현재 PC 장치관리자에서 LPT1이 정상 감지되었습니다. ($($lpt1Now.Name))"
            } elseif ($otherLpts.Count -gt 0) {
                $otherDesc = ($otherLpts | ForEach-Object { "$($_.PortName) ($($_.Name))" }) -join ', '
                $lptStatLine = "현재 PC에서 LPT1 대신 $otherDesc 포트가 감지되었습니다. 장치관리자 포트 설정에서 LPT1으로 변경해 주세요."
            }
            $chk = @(
                "EPSON TM-T88VI LPT1 직결 장비 안내 (드라이버 설치 제외)",
                "감지 상태: $lptStatLine",
                "1. Windows 프린터 드라이버, 포트 설정, 바코드 에이전트를 설치하지 마세요.",
                "2. LPT 패럴렐 케이블을 연결한 뒤 장치관리자(devmgmt.msc)의 포트(COM & LPT)에 LPT1이 보이는지 확인해 주세요.",
                "3. LPT1이 정상 인식되면 AMIS 3.0에서 별도 설정 없이 바로 출력 테스트를 진행해 주세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'EPSON_TMT88_LPT'; TargetIp = $null; Installer = [pscustomobject]@{ Found = $false; Folder = $null; ExePath = $null; DrxPath = $null; DrsPath = $null; InfPath = $null }; HasStep2 = $false; Checklist = $chk }
        }
        default {
            return [pscustomobject]@{ Type = $SpecialRow.SpecialType; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = "특수 프린터 $($SpecialRow.PrinterName)의 드라이버와 용지 기본 설정을 확인한 뒤 AMIS에서 테스트해 주세요." }
        }
    }
}

function Resolve-SpecialSettingFileOnDemand {
    param(
        [string]$RelPath,
        [string]$BackupSourcePath
    )
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return $null }

    $fileName      = [IO.Path]::GetFileName($RelPath)
    $persistedDir  = Join-Path $global:AsanCtx.WorkBaseDir 'LastSpecialSettings'
    $persistedPath = Join-Path $persistedDir $fileName

    if (-not [string]::IsNullOrWhiteSpace($BackupSourcePath) -and (Test-Path -LiteralPath $BackupSourcePath)) {
        if (-not (Test-Path -LiteralPath $persistedDir)) { New-Item -ItemType Directory -Path $persistedDir -Force | Out-Null }
        if ($BackupSourcePath -match '(?i)\.zip$') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($BackupSourcePath)
            try {
                $normRel = $RelPath.Replace('\', '/')
                $entry   = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -ieq $normRel } | Select-Object -First 1
                if ($entry) {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $persistedPath, $true)
                    return $persistedPath
                }
            } finally {
                $zip.Dispose()
            }
        } else {
            $srcFull = Join-Path $BackupSourcePath $RelPath
            if (Test-Path -LiteralPath $srcFull) {
                Copy-Item -LiteralPath $srcFull -Destination $persistedPath -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $persistedPath) { return $persistedPath }
            }
        }
    }

    if (Test-Path -LiteralPath $persistedPath) { return $persistedPath }
    return $null
}

function Complete-Sip30mPostInstall {
    param(
        [string]$TargetIp,
        [string]$DesiredPrinterName = 'id카드',
        [string]$OriginalPrinterName = 'id카드',
        [string]$DatRelPath = $null,
        [string]$RegRelPath = $null,
        [string]$BackupSourcePath = $null
    )

    Ensure-SpoolerRunning
    $allPrts = @(Get-Printer -ErrorAction SilentlyContinue)
    $sipPrt  = $allPrts | Where-Object { $_.Name -match '(?i)SISS\s+HODOO\s+SIP-30|SIP-30\(Class\)' } | Select-Object -First 1
    if (-not $sipPrt) {
        $sipPrt = $allPrts | Where-Object { $_.Name -eq $DesiredPrinterName -or $_.Name -match '(?i)SIP-30|HODOO|SISS' -or $_.DriverName -match '(?i)SIP-30|HODOO|SISS' } | Select-Object -First 1
    }

    if (-not $sipPrt) {
        return [pscustomobject]@{ Success = $false; Message = 'SISS HODOO SIP-30(Class) 프린터가 감지되지 않습니다. 1단계 설치 프로그램(sip30inst)을 먼저 완료하세요.' }
    }

    if ([string]::IsNullOrWhiteSpace($TargetIp) -or $TargetIp -eq '백업 IP' -or (-not (Test-IsUsableIPv4 -IpText $TargetIp))) {
        return [pscustomobject]@{ Success = $false; Message = "유효한 SIP-30M 대상 TCP/IPv4 주소가 아닙니다: '$TargetIp'" }
    }

    $pRes = Ensure-RestoredPortSafe -PortObj $null -FallbackName $TargetIp -OverrideKind 'TCPIP' -OverrideHostIp $TargetIp
    if (-not $pRes.Success) {
        return [pscustomobject]@{ Success = $false; Message = "TCP/IP 포트($TargetIp) 생성 실패: $($pRes.Reason)" }
    }

    $curName = [string]$sipPrt.Name
    Set-Printer -InputObject $sipPrt -PortName $pRes.PortName -ErrorAction Stop

    if ($curName -ne $DesiredPrinterName) {
        $dup = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $DesiredPrinterName }) | Select-Object -First 1
        if ($dup) {
            Remove-Printer -InputObject $dup -ErrorAction SilentlyContinue
        }
        $refreshed = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $curName }) | Select-Object -First 1
        if ($refreshed) {
            Rename-Printer -InputObject $refreshed -NewName $DesiredPrinterName -ErrorAction Stop
            $curName = $DesiredPrinterName
        }
    }

    $datFile = Resolve-SpecialSettingFileOnDemand -RelPath $DatRelPath -BackupSourcePath $BackupSourcePath
    $regFile = Resolve-SpecialSettingFileOnDemand -RelPath $RegRelPath -BackupSourcePath $BackupSourcePath

    $datApplied = $false
    if ($datFile -and (Test-Path -LiteralPath $datFile)) {
        $srSip = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $curName, '/a', $datFile, 'd', 'g', 'u', 'r')
        if ($srSip.ExitCode -eq 0) { $datApplied = $true }
    }

    $pendingRegs = @()
    $regQueued   = $false
    if ($regFile -and (Test-Path -LiteralPath $regFile)) {
        $pendingRegs = @([pscustomobject]@{ PrinterName = $curName; OriginalPrinterName = $OriginalPrinterName; RegFullPath = $regFile })
        $regQueued   = $true
    }

    $policyRes  = Invoke-AsanStandardPolicyAtomic -PendingRegImports $pendingRegs
    $regFailed  = ($policyRes -and (@($policyRes.FailedRegImports) -contains $curName))
    $regApplied = ($regQueued -and (-not $regFailed))

    $safeCurName = ($curName -replace '"', '\"')
    Start-Process -FilePath 'rundll32.exe' -ArgumentList ('printui.dll,PrintUIEntry /e /n "' + $safeCurName + '"')

    $detail = '백업된 설정 파일이 없어 기본 설정 창에서 값을 직접 확인하세요.'
    if ($regFailed) {
        $detail = '레지스트리(.reg) 설정 주입에 실패했습니다 — 열린 기본 설정 창에서 4개 탭(리본/코팅/농도/MS쓰기)을 직접 확인하세요.'
    } elseif ($datApplied -or $regApplied) {
        $detail = '백업된 4개 탭 인쇄 기본 설정(리본/코팅/농도/MS쓰기)이 자동 주입되었습니다.'
    }
    return [pscustomobject]@{
        Success = $true
        Message = "SIP-30M 마무리 완료: 이름='$curName', 포트='$($pRes.PortName)' (SNMP/양방향 OFF). $detail"
    }
}

# ============================================================================
# [동일 SID 충돌 클라이언트 복구] 스풀러 대기열·자격증명 초기화 및 호스트 재인증
# ============================================================================
function Reset-ClientSpoolerAndHostCred {
    param(
        [string]$HostName = $null,
        [string]$CustomUser = $null,
        [string]$CustomPass = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($HostName)) {
        Disconnect-AllHostSessions -HostName $HostName
        [AsanWin32.NativeApi]::DeleteDomainCredential($HostName)
        $ck = $HostName.ToLowerInvariant()
        if ($global:AsanCtx.HostCredCache.ContainsKey($ck)) { $global:AsanCtx.HostCredCache.Remove($ck) }
    }

    [void](Stop-SpoolerSafe)
    try {
        $spoolQueueDir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        if (Test-Path -LiteralPath $spoolQueueDir) {
            Get-ChildItem -LiteralPath $spoolQueueDir -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Ensure-SpoolerRunning
    }

    if (-not [string]::IsNullOrWhiteSpace($HostName)) {
        return (Connect-SharedHostSmart -HostName $HostName -CustomUser $CustomUser -CustomPass $CustomPass -ForceResetSession)
    }
    return [pscustomobject]@{ Success = $true; Status = 'ResetDone'; Win32Error = 0; Reason = '클라이언트 Print Spooler 및 대기열 잔여물 초기화 완료' }
}

# ============================================================================
# [서버 관리 헬퍼] 백업 목록 조회 및 PrinterBackup.* 실제 수정시각 기반 5일 정리
# ============================================================================
function Get-BackupEffectiveWriteTime {
    param([IO.DirectoryInfo]$DirInfo)
    $bestTime = $DirInfo.LastWriteTime
    foreach ($mf in @('PrinterBackup.json', 'PrinterBackup.printerExport')) {
        $mp = Join-Path $DirInfo.FullName $mf
        if (Test-Path -LiteralPath $mp) {
            try {
                $fi = Get-Item -LiteralPath $mp -Force -ErrorAction Stop
                if ($fi.LastWriteTime -gt $bestTime) { $bestTime = $fi.LastWriteTime }
            } catch {
                # SMB 일시 잠금/재백업 진행 중 Get-Item 실패 시 Fail-Closed(최신 시각 반환)로 오삭제 차단
                return (Get-Date)
            }
        }
    }
    return $bestTime
}

function Get-ServerBackupEntries {
    param([string]$PrtBakDir, [string]$PcIp)
    if ([string]::IsNullOrWhiteSpace($PrtBakDir) -or -not (Test-Path -LiteralPath $PrtBakDir)) { return @() }

    $expectedId = Get-BackupFolderId -PcIp $PcIp
    $safeHost   = $expectedId -replace '\([^()]*\)$', ''
    $safeIp     = Get-SafeFileName -Text $PcIp

    $list = [System.Collections.Generic.List[object]]::new()
    $now  = Get-Date
    foreach ($d in @(Get-ChildItem -LiteralPath $PrtBakDir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith('_')) { continue }
        $hasJson = Test-Path -LiteralPath (Join-Path $d.FullName 'PrinterBackup.json')
        $hasBrm  = Test-Path -LiteralPath (Join-Path $d.FullName 'PrinterBackup.printerExport')
        if (-not ($hasJson -or $hasBrm)) { continue }

        # robocopy /MIR 덮어쓰기 시 NTFS 폴더 타임스탬프 미갱신 함정 방지: 내부 마커 파일 최신 시각 기준
        $effTime   = Get-BackupEffectiveWriteTime -DirInfo $d
        $exactDays = ($now - $effTime).TotalDays
        $ageDays   = [math]::Round($exactDays, 1)

        $isExact = ($d.Name -ieq $expectedId)
        $isIp    = ($PcIp -ne 'NO_IP' -and $d.Name -like "*($safeIp)*")
        $isName  = ($d.Name -like "$safeHost(*")

        $rank = 9
        if ($isExact) { $rank = 1 }
        elseif ($isIp) { $rank = 2 }
        elseif ($isName) { $rank = 3 }

        $list.Add([pscustomobject]@{
            Name          = $d.Name
            FullPath      = $d.FullName
            LastWriteTime = $effTime
            AgeDays       = $ageDays
            IsOld5Days    = ($exactDays -ge 5.0)
            IsMatched     = ($isExact -or $isIp -or $isName)
            MatchRank     = $rank
            HasBrm        = $hasBrm
        })
    }
    return @($list.ToArray() | Sort-Object LastWriteTime -Descending)
}

function Remove-OldServerBackups {
    param([string]$PrtBakDir, [int]$DaysThreshold = 5)
    $now     = Get-Date
    $removed = [System.Collections.Generic.List[string]]::new()
    if ($DaysThreshold -lt 1) { return @() }
    if ([string]::IsNullOrWhiteSpace($PrtBakDir) -or -not (Test-Path -LiteralPath $PrtBakDir)) { return @() }
    $baseFull = [IO.Path]::GetFullPath($PrtBakDir).TrimEnd('\')

    foreach ($d in @(Get-ChildItem -LiteralPath $PrtBakDir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith('_')) { continue }
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $dFull = [IO.Path]::GetFullPath($d.FullName).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($dFull).TrimEnd('\') -ine $baseFull) { continue }
        $hasMarker = (Test-Path -LiteralPath (Join-Path $dFull 'PrinterBackup.json')) -or (Test-Path -LiteralPath (Join-Path $dFull 'PrinterBackup.printerExport'))
        if (-not $hasMarker) { continue }
        $effTime = Get-BackupEffectiveWriteTime -DirInfo $d
        if (($now - $effTime).TotalDays -lt [double]$DaysThreshold) { continue }
        Remove-Item -LiteralPath $dFull -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $dFull)) { $removed.Add($d.Name) }
    }
    return @($removed.ToArray())
}

# ============================================================================
# [버그/오류 리포트 엔진] 민감정보 자동 마스킹 + _PRTBAK\_REPORTS 전송(오프라인 폴백)
# ============================================================================
function Protect-ReportSensitiveText {
    param(
        [string]$Text,
        [string[]]$ExtraSecrets = @()
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $masked  = $Text
    $secrets = [System.Collections.Generic.List[string]]::new()
    foreach ($pw in @(Get-ConfiguredDefaultPasswords)) {
        if ($pw.Length -ge 3) { $secrets.Add($pw) }
    }
    try {
        foreach ($cv in @($global:AsanCtx.HostCredCache.Values)) {
            if ($cv -and -not [string]::IsNullOrWhiteSpace([string]$cv.Pass)) {
                $cp = [string]$cv.Pass
                if ($cp.Length -ge 3) { $secrets.Add($cp) }
            }
        }
    } catch {}
    foreach ($ex in @($ExtraSecrets)) {
        $es = [string]$ex
        if (-not [string]::IsNullOrWhiteSpace($es) -and $es.Length -ge 3) { $secrets.Add($es) }
    }
    $expandedSecrets = [System.Collections.Generic.List[string]]::new()
    foreach ($s in ($secrets | Select-Object -Unique)) {
        $expandedSecrets.Add($s)
        # ConvertTo-Json이 &, ', <, >, \, " 등을 이스케이프한 변형 문자열도 함께 마스킹
        $jEsc = $s.Replace('\', '\\').Replace('"', '\"').Replace('&', '\u0026').Replace("'", '\u0027').Replace('<', '\u003c').Replace('>', '\u003e')
        if ($jEsc -cne $s -and $jEsc.Length -ge 3) { $expandedSecrets.Add($jEsc) }
    }
    foreach ($s in ($expandedSecrets | Sort-Object { $_.Length } -Descending | Select-Object -Unique)) {
        $masked = [regex]::Replace($masked, [regex]::Escape($s), '[REDACTED]')
    }
    return $masked
}

function Send-AsanBugReport {
    param(
        [string]$Category = '일반 오류/버그',
        [string]$UserDescription = '',
        [string]$TargetPrinter = '(전체/미지정)',
        [string]$UiLogText = '',
        [string]$ErrorSummary = '',
        [string]$PrtBakDir = $null,
        [string]$PcIp = 'NO_IP',
        [string]$OsCaption = '',
        [string]$LocalSid = '',
        [string]$NetStatus = 'Unknown',
        [bool]$WppEnabled = $false,
        [string]$LoadedBackupSource = '',
        [string[]]$ExtraSecrets = @()
    )

    $now       = Get-Date
    $stamp     = $now.ToString('yyyyMMdd_HHmmss')
    $safeHost  = Get-SafeFileName -Text $env:COMPUTERNAME
    $safeIp    = Get-SafeFileName -Text $PcIp
    $reportId  = "${stamp}_${safeHost}_${safeIp}"

    # 현장 환경 스냅샷 수집 (읽기 전용)
    $instPrts = @()
    try {
        $instPrts = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name          = [string]$_.Name
                DriverName    = [string]$_.DriverName
                PortName      = [string]$_.PortName
                Default       = [bool]$_.Default
                WorkOffline   = [bool]$_.WorkOffline
                PrinterStatus = [int]$_.PrinterStatus
            }
        })
    } catch {}

    $tcpPorts = @()
    try {
        $tcpPorts = @(Get-CimInstance -ClassName Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name        = [string]$_.Name
                HostAddress = [string]$_.HostAddress
                Protocol    = [int]$_.Protocol
                PortNumber  = [int]$_.PortNumber
                SNMPEnabled = [bool]$_.SNMPEnabled
            }
        })
    } catch {}

    $lptPorts = @(Get-DeviceManagerLptPorts)
    $usbPrintDevs = @()
    try {
        $usbPrintDevs = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.DeviceID) -match '^(?i)(USBPRINT\\|USB\\VID_(0A5F|1504|0525|154F))' -or
            (([string]$_.DeviceID) -match '^(?i)USB\\' -and $null -ne $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0)
        } | ForEach-Object {
            [pscustomobject]@{
                DeviceID  = [string]$_.DeviceID
                Name      = [string]$_.Name
                PNPClass  = [string]$_.PNPClass
                Status    = [string]$_.Status
                ErrorCode = [int]$_.ConfigManagerErrorCode
            }
        })
    } catch {}

    $cleanTarget = Protect-ReportSensitiveText -Text $TargetPrinter      -ExtraSecrets $ExtraSecrets
    $cleanLoaded = Protect-ReportSensitiveText -Text $LoadedBackupSource -ExtraSecrets $ExtraSecrets
    $cleanDesc   = Protect-ReportSensitiveText -Text $UserDescription    -ExtraSecrets $ExtraSecrets
    $cleanErr    = Protect-ReportSensitiveText -Text $ErrorSummary       -ExtraSecrets $ExtraSecrets
    $cleanLog    = Protect-ReportSensitiveText -Text $UiLogText          -ExtraSecrets $ExtraSecrets

    $detailObj = [pscustomobject]@{
        ReportVersion      = 1
        ReportId           = $reportId
        CreatedAt          = $now.ToString('yyyy-MM-dd HH:mm:ss')
        AppVersion         = $global:AsanCtx.AppVersion
        Category           = $Category
        TargetPrinter      = $cleanTarget
        UserDescription    = $cleanDesc
        ErrorSummary       = $cleanErr
        Environment        = [pscustomobject]@{
            ComputerName       = $env:COMPUTERNAME
            UserName           = $env:USERNAME
            OsCaption          = $OsCaption
            IPAddress          = $PcIp
            MachineSID         = $LocalSid
            NetworkStatus      = $NetStatus
            WppEnabled         = $WppEnabled
            LoadedBackupSource = $cleanLoaded
        }
        InstalledPrinters  = $instPrts
        TcpIpPorts         = $tcpPorts
        DeviceManagerLpts  = $lptPorts
        UsbPrintDevices    = $usbPrintDevs
        UiLog              = $cleanLog
    }

    $sumLines = [System.Collections.Generic.List[string]]::new()
    $sumLines.Add("=========================================================================")
    $sumLines.Add(" 아산병원 프린터 마이그레이션 도구 오류/버그 리포트 (v$($global:AsanCtx.AppVersion))")
    $sumLines.Add("=========================================================================")
    $sumLines.Add(" 리포트 ID     : $reportId")
    $sumLines.Add(" 접수 일시     : $($detailObj.CreatedAt)")
    $sumLines.Add(" 증상 분류     : $Category")
    $sumLines.Add(" 대상 프린터   : $cleanTarget")
    $sumLines.Add(" PC / IP       : $($env:COMPUTERNAME) ($PcIp)")
    $sumLines.Add(" OS / SID      : $OsCaption | $LocalSid")
    $sumLines.Add(" 망상태 / WPP  : $NetStatus | WPP=$WppEnabled")
    $sumLines.Add(" 로드된 백업   : $cleanLoaded")
    $sumLines.Add("")
    $sumLines.Add("[현장 담당자 메모]")
    if ([string]::IsNullOrWhiteSpace($cleanDesc)) { $sumLines.Add(" (입력 없음)") } else { $sumLines.Add($cleanDesc) }
    $sumLines.Add("")
    $sumLines.Add("[직전 오류/실패 요약]")
    if ([string]::IsNullOrWhiteSpace($cleanErr)) { $sumLines.Add(" (없음)") } else { $sumLines.Add($cleanErr) }
    $sumLines.Add("")
    $sumLines.Add("[설치 프린터 현황 ($($instPrts.Count)대)]")
    foreach ($ip in $instPrts) {
        $sumLines.Add(" - $($ip.Name) | Port=$($ip.PortName) | Drv=$($ip.DriverName) | Offline=$($ip.WorkOffline)")
    }
    $sumLines.Add("")
    $sumLines.Add("[장치관리자 LPT ($($lptPorts.Count)개) / USB 바코드·이상장치 ($($usbPrintDevs.Count)개)]")
    foreach ($lp in $lptPorts) {
        $sumLines.Add(" - [LPT] $($lp.PortName): $($lp.Name) ($($lp.Status))")
    }
    foreach ($ud in $usbPrintDevs) {
        $sumLines.Add(" - [USB] $($ud.Name) | Class=$($ud.PNPClass) | Status=$($ud.Status) | Err=$($ud.ErrorCode) | ID=$($ud.DeviceID)")
    }
    $sumLines.Add("")
    $sumLines.Add("[실시간 로그 전문 (민감정보 마스킹됨)]")
    $sumLines.Add($cleanLog)

    $summaryText = Protect-ReportSensitiveText -Text ($sumLines -join "`r`n") -ExtraSecrets $ExtraSecrets
    $jsonText    = Protect-ReportSensitiveText -Text ($detailObj | ConvertTo-Json -Depth 8) -ExtraSecrets $ExtraSecrets
    $utf8Bom     = New-Object System.Text.UTF8Encoding($true)

    $savedToServer = $false
    $targetDir     = $null
    $fallbackNote  = $null

    if (-not [string]::IsNullOrWhiteSpace($PrtBakDir) -and (Test-Path -LiteralPath $PrtBakDir)) {
        try {
            $baseFull   = [IO.Path]::GetFullPath($PrtBakDir).TrimEnd('\')
            $repRoot    = Join-Path $baseFull '_REPORTS'
            $repRootFul = [IO.Path]::GetFullPath($repRoot).TrimEnd('\')
            if ([IO.Path]::GetDirectoryName($repRootFul).TrimEnd('\') -ieq $baseFull) {
                if (-not (Test-Path -LiteralPath $repRootFul)) {
                    New-Item -ItemType Directory -Path $repRootFul -Force -ErrorAction Stop | Out-Null
                }
                $candDir = Join-Path $repRootFul $reportId
                New-Item -ItemType Directory -Path $candDir -Force -ErrorAction Stop | Out-Null
                [IO.File]::WriteAllText((Join-Path $candDir 'BugReport_Summary.txt'), $summaryText, $utf8Bom)
                [IO.File]::WriteAllText((Join-Path $candDir 'BugReport_Detail.json'), $jsonText, $utf8Bom)
                $targetDir     = $candDir
                $savedToServer = $true
            }
        } catch {
            $fallbackNote = $_.Exception.Message
        }
    }

    if (-not $savedToServer) {
        $localRoot = Join-Path $global:AsanCtx.OfflineLocalRoot '_Reports'
        if (-not (Test-Path -LiteralPath $localRoot)) {
            New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
        }
        $candLocal = Join-Path $localRoot $reportId
        New-Item -ItemType Directory -Path $candLocal -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $candLocal 'BugReport_Summary.txt'), $summaryText, $utf8Bom)
        [IO.File]::WriteAllText((Join-Path $candLocal 'BugReport_Detail.json'), $jsonText, $utf8Bom)
        $targetDir = $candLocal
    }

    return [pscustomobject]@{
        Success       = $true
        ReportId      = $reportId
        SavedPath     = $targetDir
        SavedToServer = $savedToServer
        FallbackNote  = $fallbackNote
    }
}

# ============================================================================
# [H2 Fix] 설치 프린터 SNMP/양방향 검증 조회 (Runspace 실행을 위해 코어 편입)
# ============================================================================
function Get-InstalledPrintersVerifyInfo {
    Ensure-SpoolerRunning
    $cimPrinters = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue)
    $tcpRegRoot  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports'
    $prtRegRoot  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $cimPrinters) {
        $pName        = [string]$p.Name
        $dName        = [string]$p.DriverName
        $port         = [string]$p.PortName
        $isVirt       = Test-IsVirtualPrinter -PrinterName $pName -PortName $port
        $spec         = Get-SpecialPrinterProfile -PrinterName $pName -DriverName $dName -PortName $port
        $isUsbSpecial = ($spec.IsSpecial -and ($port -match '(?i)^USB'))

        $snmpState = '-'
        $snmpWarn  = $false
        if (-not [string]::IsNullOrWhiteSpace($port)) {
            $tcpKey = Join-Path $tcpRegRoot $port
            if (Test-Path -LiteralPath $tcpKey) {
                $sv = (Get-ItemProperty -LiteralPath $tcpKey -Name 'SNMP Enabled' -ErrorAction SilentlyContinue).'SNMP Enabled'
                if ($null -ne $sv -and [int]$sv -ne 0) {
                    $snmpState = 'ON'
                    $snmpWarn  = $true
                } else {
                    $snmpState = 'OFF'
                }
            }
        }

        $bidiState = '-'
        $bidiWarn  = $false
        if (-not $pName.StartsWith('\\')) {
            $pKey = Join-Path $prtRegRoot $pName
            if (Test-Path -LiteralPath $pKey) {
                $attr = (Get-ItemProperty -LiteralPath $pKey -Name 'Attributes' -ErrorAction SilentlyContinue).Attributes
                if ($null -ne $attr) {
                    $uVal   = [uint32]([int64]$attr -band [int64]0xFFFFFFFF)
                    $bidiOn = (($uVal -band [uint32]0x00000800) -ne 0)
                    if ($bidiOn) {
                        if ($isUsbSpecial) {
                            $bidiState = 'ON(유지)'
                            $bidiWarn  = $false
                        } else {
                            $bidiState = 'ON'
                            $bidiWarn  = (-not $isVirt)
                        }
                    } else {
                        $bidiState = 'OFF'
                    }
                }
            }
        }

        $stateTxt = '정상'
        if ($p.WorkOffline) { $stateTxt = '오프라인' }
        elseif ([int]$p.PrinterStatus -eq 7) { $stateTxt = '오프라인' }
        elseif ([int]$p.PrinterStatus -eq 1 -or [int]$p.PrinterStatus -eq 2) { $stateTxt = '확인필요' }

        $catLabel = $spec.Label
        if ($isVirt) { $catLabel = '가상' }

        $list.Add([pscustomobject]@{
            IsDefault       = [bool]$p.Default
            IsVirtual       = $isVirt
            IsSpecial       = [bool]$spec.IsSpecial
            ExcludeBulkTest = ([bool]$spec.ExcludeBulkTest -or $isVirt)
            Category        = $catLabel
            SpecialType     = [string]$spec.Type
            PrinterName     = $pName
            PortName        = $port
            SnmpState       = $snmpState
            SnmpWarn        = $snmpWarn
            BidiState       = $bidiState
            BidiWarn        = $bidiWarn
            DriverName      = $dName
            StatusText      = $stateTxt
        })
    }

    return @($list.ToArray())
}

# ============================================================================
# [H2 Fix] 순수 코어 함수 이름 스냅샷 (GUI 정의 전 1회 캡처 -> 자식 Runspace 전용)
# ============================================================================
$script:CoreFunctionNames = @(
    Get-ChildItem -Path 'Function:\' -ErrorAction SilentlyContinue |
    Where-Object {
        [string]::IsNullOrEmpty($_.ModuleName) -and
        $_.Name -match '^[A-Za-z]+-[A-Za-z0-9]+$' -and
        @('Clear-Host', 'Get-Verb', 'ImportSystemModules', 'TabExpansion2') -notcontains $_.Name
    } |
    ForEach-Object { $_.Name }
)
