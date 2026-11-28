# ============================================================================
# [백업 엔진] 온라인 서버 업로드 + 오프라인 ZIP 생성 (Zero USB Write 준수)
# ============================================================================
function Test-DirectoryWritableSafe {
    param([string]$DirPath)
    if ([string]::IsNullOrWhiteSpace($DirPath)) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $DirPath)) {
            New-Item -ItemType Directory -Path $DirPath -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $DirPath ".write_probe_$PID.tmp"
        [IO.File]::WriteAllText($probe, '1')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Invoke-PrinterBackupEngine {
    param(
        [object[]]$DiagnosedPrinters,
        [object[]]$SelectedScanners,
        [string[]]$TwainFolders,
        [string]$PcIp,
        [string]$PrtBakDir,
        [switch]$OfflineZipMode,
        [string]$OriginalScriptPath = $null,
        [scriptblock]$OnProgress = $null
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Ensure-SpoolerRunning

    if ([string]::IsNullOrWhiteSpace($OriginalScriptPath)) { $OriginalScriptPath = $global:AsanCtx.OriginalScriptPath }
    if (-not (Test-Path -LiteralPath $global:AsanCtx.WorkBaseDir)) { New-Item -ItemType Directory -Path $global:AsanCtx.WorkBaseDir -Force | Out-Null }

    $folderId          = Get-BackupFolderId -PcIp $PcIp
    $safeHost          = Get-SafeFileName -Text $env:COMPUTERNAME
    $runGuid           = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $localTemp         = Join-Path $global:AsanCtx.WorkBaseDir "Work_Bak_${PID}_$runGuid"
    $backupNotes       = [System.Collections.Generic.List[object]]::new()
    $cleanTwainFolders = [string[]]@($TwainFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    try {
        if (Test-Path -LiteralPath $localTemp) { Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $localTemp -Force | Out-Null

        Write-ProgressSafe -OnProgress $OnProgress -Percent 10 -Message '[1/5] PrintBrm.exe로 원본 드라이버 패키지 및 인쇄 기본 설정 백업 중...'
        $brmFile = Join-Path $localTemp 'PrinterBackup.printerExport'
        $brmOk   = $false
        if (Test-Path -LiteralPath $global:AsanCtx.PrintBrmExe) {
            $brmRes = Invoke-NativeCommand -FilePath $global:AsanCtx.PrintBrmExe -Arguments @('-b', '-f', $brmFile)
            $brmLen = 0
            if (Test-Path -LiteralPath $brmFile) {
                try { $brmLen = (Get-Item -LiteralPath $brmFile -ErrorAction Stop).Length } catch { $brmLen = 0 }
            }
            if ($brmLen -gt 0) {
                $brmOk = $true
                if ($brmRes.ExitCode -ne 0) {
                    $brmErrShort = ([string]$brmRes.Output -replace '\s+', ' ').Trim()
                    if ($brmErrShort.Length -gt 180) { $brmErrShort = $brmErrShort.Substring(0, 180) + '...' }
                    $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = "PrintBrm 일부 경고(ExitCode=$($brmRes.ExitCode)): $brmErrShort" })
                }
            } else {
                if (Test-Path -LiteralPath $brmFile) { Remove-Item -LiteralPath $brmFile -Force -ErrorAction SilentlyContinue }
                if ($brmRes.ExitCode -ne 0) {
                    $brmErrShort = ([string]$brmRes.Output -replace '\s+', ' ').Trim()
                    if ($brmErrShort.Length -gt 180) { $brmErrShort = $brmErrShort.Substring(0, 180) + '...' }
                    $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = "PrintBrm 백업 종료코드=$($brmRes.ExitCode): $brmErrShort" })
                }
            }
        }
        if (-not $brmOk) {
            $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = 'PrintBrm.exe 패키지 생성 실패 — 개별 추출 드라이버 및 JSON 기반으로 복원됩니다.' })
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 30 -Message '[2/5] 프린터 메타데이터·포트·특수장비 세부 설정(DAT/레지스트리) 덤프 중...'
        $validPrinters     = @($DiagnosedPrinters | Where-Object { $_.StatusCode -notin @('ExcludedVirtual', 'ExcludedNoDriver') })
        $excludedCount     = (@($DiagnosedPrinters | Where-Object { $_.StatusCode -eq 'ExcludedVirtual' })).Count
        $excludedNoDrv     = @($DiagnosedPrinters | Where-Object { $_.StatusCode -eq 'ExcludedNoDriver' })
        $specialDir        = Join-Path $localTemp 'SpecialSettings'
        $activeDriverNames = [System.Collections.Generic.List[string]]::new()
        $printerRecords    = [System.Collections.Generic.List[object]]::new()
        $portRecords       = [System.Collections.Generic.List[object]]::new()
        $seenPorts         = @{}
        $defaultPrinter    = $null

        foreach ($exNd in $excludedNoDrv) {
            $backupNotes.Add([pscustomobject]@{
                Level   = 'Special'
                Target  = $exNd.PrinterName
                Message = '[백업 제외 · 무드라이버] EPSON TM-T88 등 LPT1 유선 직결 장비 — 드라이버/설정을 백업하지 않았으며, 새 PC 장치관리자에서 LPT1 포트 인식 여부만 확인 후 AMIS에서 직접 사용하세요.'
            })
        }

        foreach ($p in $validPrinters) {
            if ($p.IsDefault) { $defaultPrinter = [string]$p.PrinterName }
            # Win 10 구형 세우테크(SEWOO_TE201) 드라이버는 Win 11 유입 차단을 위해 ExportedDrivers 추출 제외
            if ($p.SpecialType -ne 'SEWOO_TE201' -and -not [string]::IsNullOrWhiteSpace($p.DriverName) -and -not $activeDriverNames.Contains([string]$p.DriverName)) {
                $activeDriverNames.Add([string]$p.DriverName)
            }

            $datRelPath = $null
            $regRelPath = $null

            if ([string]::IsNullOrWhiteSpace([string]$p.ConnectionName) -and $p.SpecialType -in @('ZD410_411', 'ZEBRA_ZT411', 'BIXOLON_TX220', 'SIP30M_IDCARD', 'OTHER_SPECIAL')) {
                if (-not (Test-Path -LiteralPath $specialDir)) { New-Item -ItemType Directory -Path $specialDir -Force | Out-Null }
                $safeKey = Get-SafeFileName -Text "$($p.SpecialType)_$($p.PrinterName)"
                $datFile = Join-Path $specialDir "$safeKey.dat"
                $regFile = Join-Path $specialDir "$safeKey.reg"

                $datRes = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Ss', '/q', '/n', $p.PrinterName, '/a', $datFile, 'd', 'g', 'u')
                $datOk  = (Test-Path -LiteralPath $datFile) -and ((Get-Item -LiteralPath $datFile -ErrorAction SilentlyContinue).Length -gt 0)
                if ($datOk) {
                    $datRelPath = "SpecialSettings\$safeKey.dat"
                } else {
                    # rundll32.exe는 실패 시에도 ExitCode=0을 반환하므로 실제 파일 생성 여부로 실패 판정
                    $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = $p.PrinterName; Message = "인쇄 기본 설정(.dat) 덤프 미생성 (ExitCode=$($datRes.ExitCode)) — 복원 후 용지/농도 설정을 직접 확인하세요." })
                }

                $regKey = "HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers\$($p.PrinterName)\PrinterDriverData"
                $rReg = Invoke-NativeCommand -FilePath 'reg.exe' -Arguments @('export', $regKey, $regFile, '/y')
                if ($rReg.ExitCode -eq 0 -and (Test-Path -LiteralPath $regFile)) { $regRelPath = "SpecialSettings\$safeKey.reg" }
            }

            if ($p.StatusCode -in @('WsdConvert', 'Ambiguous', 'SuspectedInactive', 'AuthOrSidConflict', 'OfflineUnverified')) {
                $lvl = 'Warning'
                if ($p.StatusCode -eq 'WsdConvert') { $lvl = 'Info' }
                $backupNotes.Add([pscustomobject]@{ Level = $lvl; Target = $p.PrinterName; Message = "[$($p.StatusText)] $($p.Reason)" })
            }
            if ($p.SpecialType -ne 'STANDARD') {
                $backupNotes.Add([pscustomobject]@{ Level = 'Special'; Target = $p.PrinterName; Message = "[$($p.Category)] $($p.Reason)" })
            }

            $printerRecords.Add([pscustomobject]@{
                Name             = [string]$p.PrinterName
                DriverName       = [string]$p.DriverName
                PortName         = [string]$p.PortName
                PortKind         = [string]$p.PortKind
                ConnectionName   = $p.ConnectionName
                Category         = [string]$p.Category
                SpecialType      = [string]$p.SpecialType
                BackupStatusCode = [string]$p.StatusCode
                BackupStatusText = [string]$p.StatusText
                BackupReason     = [string]$p.Reason
                WsdTargetIp      = $p.WsdTargetIp
                WsdModelName     = $p.WsdModelName
                WsdTargetMode    = $p.WsdTargetMode
                WsdTargetShare   = $p.WsdTargetShare
                SpecialDatFile   = $datRelPath
                SpecialRegFile   = $regRelPath
                Default          = [bool]$p.IsDefault
            })

            if (-not $p.ConnectionName -and -not [string]::IsNullOrWhiteSpace($p.PortName)) {
                $pKey = ([string]$p.PortName).ToLowerInvariant()
                if (-not $seenPorts.ContainsKey($pKey)) {
                    $seenPorts[$pKey] = $true
                    $portRecords.Add([pscustomobject]@{
                        Name        = [string]$p.PortName
                        Kind        = [string]$p.PortKind
                        HostAddress = $p.HostAddress
                        Protocol    = $p.Protocol
                        PortNumber  = $p.PortNumber
                        Queue       = $p.Queue
                        SNMPEnabled = $false
                        ByteCount   = [bool]$p.ByteCount
                    })
                }
            }
        }

        if ($cleanTwainFolders.Count -gt 0) {
            $backupNotes.Add([pscustomobject]@{
                Level   = 'Warning'
                Target  = 'TWAIN 스캐너'
                Message = "C:\Windows\twain_32 폴더 감지 ($($cleanTwainFolders -join ', ')) — 네트워크 스캔 IP 바인딩은 새 PC에서 별도 확인 필요"
            })
        }

        $lptDevices    = @(Get-DeviceManagerLptPorts)
        $cleanLptPorts = [string[]]@($lptDevices | ForEach-Object { [string]$_.PortName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($cleanLptPorts.Count -gt 0) {
            $lptSummary = ($lptDevices | ForEach-Object { "$($_.PortName)($($_.Status))" }) -join ', '
            $backupNotes.Add([pscustomobject]@{
                Level   = 'Info'
                Target  = '장치관리자 LPT 포트'
                Message = "구 PC 장치관리자 LPT 포트 감지 ($lptSummary) — EPSON TM-T88VI 등 LPT1 직결 장비 사용 시 드라이버·에이전트를 설치하지 말고 새 PC 장치관리자 LPT1 인식 여부만 확인하세요."
            })
        }

        if ($OfflineZipMode) {
            $backupNotes.Add([pscustomobject]@{
                Level   = 'Info'
                Target  = '오프라인 백업'
                Message = '오프라인 상태에서 전체 백업했습니다. 새 PC에서 사내망 연결 후 복원 전에 연결 상태를 자동으로 확인합니다.'
            })
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 55 -Message '[3/5] 사용 중인 서드파티 프린터 및 선택된 WIA 스캐너 드라이버 정밀 추출 중...'
        $expPrtDir  = Join-Path $localTemp 'ExportedDrivers\Printers'
        $expScanDir = Join-Path $localTemp 'ExportedDrivers\Scanners'

        $prtExpCnt = Export-PreciseThirdPartyDrivers -ActiveDriverNames $activeDriverNames.ToArray() -ExplicitPublishedNames @() -ClassGuidFilters $global:AsanCtx.PrinterClassGuids -DestinationDir $expPrtDir

        $scanPubs   = @($SelectedScanners | Where-Object { $_.Selected } | ForEach-Object { [string]$_.PublishedName })
        $scanExpCnt = 0
        if ($scanPubs.Count -gt 0) {
            $scanExpCnt = Export-PreciseThirdPartyDrivers -ActiveDriverNames @() -ExplicitPublishedNames $scanPubs -ClassGuidFilters @($global:AsanCtx.ImageClassGuid) -DestinationDir $expScanDir
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 75 -Message '[4/5] PrinterBackup.json 및 영속 Migration_Report.txt 생성 중...'
        $localSid  = Get-LocalMachineSID
        $osVerInfo = Get-OsVersionInfoSafe
        $srcOsName = [string]$osVerInfo.Caption
        $srcOsBld  = [int]$osVerInfo.Build
        $srcIsWin11 = [bool]$osVerInfo.IsWin11

        $backupJson = [pscustomobject]@{
            FormatVersion    = 6
            AppVersion       = $global:AsanCtx.AppVersion
            SourceComputer   = $env:COMPUTERNAME
            SourceIP         = $PcIp
            SourceOsName     = $srcOsName
            SourceOsBuild    = $srcOsBld
            SourceIsWin11    = [bool]$srcIsWin11
            SourceMachineSID = $localSid
            IsOfflineBackup  = [bool]$OfflineZipMode
            ExportedAt       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            DefaultPrinter   = [string]$defaultPrinter
            ExcludedVirtuals = $excludedCount
            ExportedPrtCount = $prtExpCnt
            ExportedScanCnt  = $scanExpCnt
            TwainFolders     = $cleanTwainFolders
            LptPorts         = $cleanLptPorts
            BackupNotes      = $backupNotes.ToArray()
            Printers         = $printerRecords.ToArray()
            Ports            = $portRecords.ToArray()
        }

        $jsonText = $backupJson | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText((Join-Path $localTemp 'PrinterBackup.json'), $jsonText, (New-Object Text.UTF8Encoding($true)))

        $modeStr = '온라인 사내 서버'
        if ($OfflineZipMode) { $modeStr = '오프라인 ZIP (복원 시 연결 재확인)' }
        $brmStr = '실패'
        if ($brmOk) { $brmStr = '성공' }

        $repLines = [System.Collections.Generic.List[string]]::new()
        $repLines.Add("=========================================================================")
        $repLines.Add(" 프린터·드라이버 마이그레이션 백업 리포트 (v$($global:AsanCtx.AppVersion))")
        $repLines.Add("=========================================================================")
        $repLines.Add(" 백업 일시       : $($backupJson.ExportedAt)")
        $repLines.Add(" 원본 PC (IP)    : $($env:COMPUTERNAME) ($PcIp)")
        $repLines.Add(" 원본 운영체제   : $srcOsName (Build $srcOsBld)")
        $repLines.Add(" 원본 MachineSID : $localSid")
        $repLines.Add(" 백업 모드       : $modeStr")
        $repLines.Add(" 백업 프린터 수  : $($printerRecords.Count)대 (가상 제외: ${excludedCount}대)")
        $repLines.Add(" 추출 드라이버   : 프린터 ${prtExpCnt}개 / WIA 스캐너 ${scanExpCnt}개 / PrintBrm=$brmStr")
        $repLines.Add("")
        $repLines.Add("[특이사항 및 주의 리포트]")
        if ($backupNotes.Count -eq 0) {
            $repLines.Add(" - 특이사항 없음 (모든 대상 정상)")
        } else {
            foreach ($n in $backupNotes) {
                $repLines.Add(" - [$($n.Level)] $($n.Target): $($n.Message)")
            }
        }
        [IO.File]::WriteAllText((Join-Path $localTemp 'Migration_Report.txt'), ($repLines -join "`r`n"), (New-Object Text.UTF8Encoding($true)))

        if ($OfflineZipMode) {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 88 -Message '[5/5] 오프라인 ZIP 패키지 생성 중 (C:\_AsanPrtOffline)...'
            if (-not (Test-Path -LiteralPath $global:AsanCtx.OfflineLocalRoot)) {
                New-Item -ItemType Directory -Path $global:AsanCtx.OfflineLocalRoot -Force | Out-Null
            }
            $zipName      = "${safeHost}_$(Get-Date -Format 'yyyyMMdd_HHmm').zip"
            $localZipPath = Join-Path $global:AsanCtx.OfflineLocalRoot $zipName
            if (Test-Path -LiteralPath $localZipPath) { Remove-Item -LiteralPath $localZipPath -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($localTemp, $localZipPath)

            $usbCopyPath = $null
            if (-not [string]::IsNullOrWhiteSpace($OriginalScriptPath)) {
                $origRoot = [IO.Path]::GetPathRoot($OriginalScriptPath)
                if ($origRoot -and $origRoot -notmatch '^\\\\' -and $origRoot -notmatch '(?i)^C:\\') {
                    $usbTargetDir = Join-Path $origRoot '_AsanPrtOffline'
                    if (Test-DirectoryWritableSafe -DirPath $usbTargetDir) {
                        $candUsbZip = Join-Path $usbTargetDir $zipName
                        try {
                            Copy-Item -LiteralPath $localZipPath -Destination $candUsbZip -Force -ErrorAction Stop
                            $srcLen = (Get-Item -LiteralPath $localZipPath).Length
                            $dstLen = (Get-Item -LiteralPath $candUsbZip).Length
                            if ($dstLen -gt 0 -and $dstLen -eq $srcLen) {
                                $usbCopyPath = $candUsbZip
                            } else {
                                if (Test-Path -LiteralPath $candUsbZip) { Remove-Item -LiteralPath $candUsbZip -Force -ErrorAction SilentlyContinue }
                                $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'USB 동시 복사'; Message = "USB ZIP 복사본 크기가 불일치하여 불완전 파일을 삭제했습니다 ($candUsbZip) — 로컬 C:\_AsanPrtOffline ZIP을 사용하세요." })
                            }
                        } catch {
                            if (Test-Path -LiteralPath $candUsbZip) { Remove-Item -LiteralPath $candUsbZip -Force -ErrorAction SilentlyContinue }
                            $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'USB 동시 복사'; Message = "USB 동시 복사 실패($($_.Exception.Message)) — 로컬 C:\_AsanPrtOffline ZIP을 사용하세요." })
                        }
                    }
                }
            }

            Write-ProgressSafe -OnProgress $OnProgress -Percent 100 -Message "오프라인 백업 완료: $localZipPath"
            return [pscustomobject]@{
                Success      = $true
                Mode         = 'OfflineZip'
                SavedPath    = $localZipPath
                UsbCopyPath  = $usbCopyPath
                PrinterCount = $printerRecords.Count
                ScannerCount = $scanExpCnt
                Notes        = $backupNotes.ToArray()
            }
        } else {
            if ([string]::IsNullOrWhiteSpace($PrtBakDir) -or [string]::IsNullOrWhiteSpace($folderId) -or $folderId -match '^\.+$') {
                throw "안전 가드 차단: 서버 백업 대상 경로가 유효하지 않습니다 (PrtBakDir='$PrtBakDir', FolderId='$folderId')."
            }
            $baseFull   = [IO.Path]::GetFullPath($PrtBakDir).TrimEnd('\')
            $targetDir  = Join-Path $baseFull $folderId
            $targetFull = [IO.Path]::GetFullPath($targetDir).TrimEnd('\')
            $parentFull = [IO.Path]::GetDirectoryName($targetFull).TrimEnd('\')
            if ($parentFull -ine $baseFull -or $targetFull.Length -le $baseFull.Length) {
                throw "안전 가드 차단: robocopy /MIR 대상이 _PRTBAK 직계 하위 폴더가 아닙니다 ($targetFull)."
            }

            Write-ProgressSafe -OnProgress $OnProgress -Percent 88 -Message "[5/5] 백업 서버 원자적 업로드 중: _PRTBAK\$folderId ..."
            # 원자적 스테이징 업로드(_TMP_<folderId>_<PID>): 네트워크 끊김 시 기존 정상 백업 손상 방지
            $stageDirName = "_TMP_${folderId}_$PID"
            $stageFull    = [IO.Path]::GetFullPath((Join-Path $baseFull $stageDirName)).TrimEnd('\')
            $oldFull      = [IO.Path]::GetFullPath((Join-Path $baseFull "_OLD_${folderId}_$PID")).TrimEnd('\')
            if ([IO.Path]::GetDirectoryName($stageFull).TrimEnd('\') -ine $baseFull) {
                throw "안전 가드 차단: 스테이징 경로가 _PRTBAK 직계 하위가 아닙니다 ($stageFull)."
            }
            $swapped    = $false
            $movedToOld = $false
            try {
                if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $stageFull -Force | Out-Null
                $rc = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($localTemp, $stageFull, '/E', '/R:2', '/W:1')).ExitCode
                if ($rc -ge 8) { throw "서버 스테이징 업로드 중 robocopy 오류 발생 (ExitCode=$rc)" }

                if (Test-Path -LiteralPath $targetFull) {
                    try {
                        if (Test-Path -LiteralPath $oldFull) { Remove-Item -LiteralPath $oldFull -Recurse -Force -ErrorAction SilentlyContinue }
                        [IO.Directory]::Move($targetFull, $oldFull)
                        $movedToOld = $true
                        try {
                            [IO.Directory]::Move($stageFull, $targetFull)
                            $swapped = $true
                        } catch {
                            try { if (-not (Test-Path -LiteralPath $targetFull) -and (Test-Path -LiteralPath $oldFull)) { [IO.Directory]::Move($oldFull, $targetFull); $movedToOld = $false } } catch {}
                            throw
                        }
                    } catch {
                        # 대상 폴더가 타 PC 탐색기 등에 잠겨 Move 불가 시 폴백으로 직접 /MIR 동기화
                        $rcMir = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($localTemp, $targetFull, '/MIR', '/R:2', '/W:1')).ExitCode
                        if ($rcMir -ge 8) { throw "서버 덮어쓰기 업로드 중 robocopy 오류 발생 (ExitCode=$rcMir)" }
                        $swapped = $true
                    }
                } else {
                    try {
                        [IO.Directory]::Move($stageFull, $targetFull)
                        $swapped = $true
                    } catch {
                        # 최초 백업 분기에도 Move 실패(SMB 일시 잠금 등) 시 robocopy /MIR 폴백
                        $rcMir = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($localTemp, $targetFull, '/MIR', '/R:2', '/W:1')).ExitCode
                        if ($rcMir -ge 8) { throw "서버 최초 업로드 중 robocopy 오류 발생 (ExitCode=$rcMir)" }
                        $swapped = $true
                    }
                }
                if (-not $swapped) { throw '서버 백업 폴더 원자적 전환 실패' }
            }
            finally {
                # [데이터 유실 방지] 교체 실패 + _OLD_ 보존 시 부분 생성된 target을 정리하고 _OLD_ 정상 백업 롤백
                if ((-not $swapped) -and $movedToOld -and (Test-Path -LiteralPath $oldFull)) {
                    try {
                        if (Test-Path -LiteralPath $targetFull) { Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction Stop }
                        [IO.Directory]::Move($oldFull, $targetFull)
                    } catch {}
                } elseif ((-not (Test-Path -LiteralPath $targetFull)) -and (Test-Path -LiteralPath $oldFull)) {
                    try { [IO.Directory]::Move($oldFull, $targetFull) } catch {}
                }
                if ($swapped -and (Test-Path -LiteralPath $targetFull) -and (Test-Path -LiteralPath $oldFull)) {
                    Remove-Item -LiteralPath $oldFull -Recurse -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath $stageFull) {
                    Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            Write-ProgressSafe -OnProgress $OnProgress -Percent 100 -Message "서버 백업 완료: $targetFull"
            return [pscustomobject]@{
                Success      = $true
                Mode         = 'OnlineServer'
                SavedPath    = $targetFull
                UsbCopyPath  = $null
                PrinterCount = $printerRecords.Count
                ScannerCount = $scanExpCnt
                Notes        = $backupNotes.ToArray()
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $localTemp) {
            Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# [지연 검증 엔진] PrinterBackup.json 로드 및 새 PC(온라인) 재검증
# ============================================================================
function Read-BackupSourceMetadata {
    param([string]$SourcePath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $isZip    = ($SourcePath -match '(?i)\.zip$')
    $jsonText = $null
    $hasBrm   = $false

    if ($isZip) {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($SourcePath)
        try {
            $jEntry = $zip.Entries | Where-Object { $_.FullName -ieq 'PrinterBackup.json' } | Select-Object -First 1
            $bEntry = $zip.Entries | Where-Object { $_.FullName -ieq 'PrinterBackup.printerExport' } | Select-Object -First 1
            $hasBrm = ($null -ne $bEntry)
            if ($jEntry) {
                $sr = New-Object System.IO.StreamReader($jEntry.Open(), [Text.Encoding]::UTF8)
                $jsonText = $sr.ReadToEnd()
                $sr.Close()
            }
        } finally {
            $zip.Dispose()
        }
    } else {
        $jFile  = Join-Path $SourcePath 'PrinterBackup.json'
        $hasBrm = Test-Path -LiteralPath (Join-Path $SourcePath 'PrinterBackup.printerExport')
        if (Test-Path -LiteralPath $jFile) {
            $jsonText = Get-Content -LiteralPath $jFile -Raw -Encoding UTF8
        }
    }

    if ([string]::IsNullOrWhiteSpace($jsonText)) { return $null }
    $data = $jsonText | ConvertFrom-Json
    return [pscustomobject]@{
        SourcePath = $SourcePath
        IsZip      = $isZip
        HasBrm     = $hasBrm
        Data       = $data
    }
}

function Test-BackupDataDeferred {
    param(
        $BackupData,
        [switch]$RunLiveProbe,
        [scriptblock]$OnProgress = $null
    )

    $rows            = [System.Collections.Generic.List[object]]::new()
    $authFailedHosts = [System.Collections.Generic.List[object]]::new()
    $seenAuthHost    = @{}

    $printers = @($BackupData.Printers | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
    $ports    = @($BackupData.Ports | Where-Object { $null -ne $_ })
    $total    = [math]::Max(1, $printers.Count)
    $idx      = 0

    foreach ($p in $printers) {
        $idx++
        $pName = [string]$p.Name
        $dName = [string]$p.DriverName
        $port  = [string]$p.PortName
        if (Test-IsVirtualPrinter -PrinterName $pName -PortName $port) { continue }

        $spec    = Get-SpecialPrinterProfile -PrinterName $pName -DriverName $dName -PortName $port
        $portObj = $ports | Where-Object { $_.Name -ieq $port } | Select-Object -First 1

        $pKind = 'LOCAL'
        if ($p.PortKind) { $pKind = [string]$p.PortKind }
        elseif ($portObj -and $portObj.Kind) { $pKind = [string]$portObj.Kind }
        if (-not [string]::IsNullOrWhiteSpace([string]$p.ConnectionName)) { $pKind = 'SHARED_UNC' }
        elseif ($port -match '^\\\\') { $pKind = 'LOCAL_UNC' }
        elseif ($port -match '(?i)^WSD') { $pKind = 'WSD' }

        $hostAddr = $null
        if ($portObj -and $portObj.HostAddress) { $hostAddr = [string]$portObj.HostAddress }
        else { $hostAddr = Extract-FirstUsableIPv4 -Text $port }

        $liveStatus = 'Healthy'
        if ($p.BackupStatusCode) { $liveStatus = [string]$p.BackupStatusCode }
        $liveStatusText = '정상'
        if ($p.BackupStatusText) { $liveStatusText = [string]$p.BackupStatusText }
        $liveReason = '백업 기록 유지'
        if ($p.BackupReason) { $liveReason = [string]$p.BackupReason }

        $wsdIp    = $p.WsdTargetIp
        $wsdModel = $p.WsdModelName
        $wsdMode  = $p.WsdTargetMode
        $wsdShare = $p.WsdTargetShare

        if ($RunLiveProbe) {
            $pct = [int](($idx / $total) * 100)
            Write-ProgressSafe -OnProgress $OnProgress -Percent $pct -Message "지연 검증 중 ($idx/$total): $pName"

            if ($pKind -eq 'TCPIP' -and -not [string]::IsNullOrWhiteSpace($hostAddr)) {
                $protoVal = 'RAW'
                if ($portObj -and $portObj.Protocol) { $protoVal = [string]$portObj.Protocol }
                $pNumVal = 9100
                if ($portObj -and $portObj.PortNumber) { $pNumVal = [int]$portObj.PortNumber }

                $chk = Test-TcpIpPrinterHealth -HostAddress $hostAddr -Protocol $protoVal -PortNumber $pNumVal -SkipAliveFilter:$spec.SkipAliveFilter
                $liveStatus = $chk.Status
                $liveReason = "실시간 확인 · $($chk.Reason)"
                if ($liveStatus -eq 'Healthy') { $liveStatusText = '정상' }
                elseif ($liveStatus -eq 'Ambiguous') { $liveStatusText = '응답 확인 필요' }
                else { $liveStatusText = '응답 없음' }
            } elseif ($pKind -eq 'LOCAL_UNC' -or $pKind -eq 'SHARED_UNC') {
                $targetUnc = $port
                if ($p.ConnectionName) { $targetUnc = [string]$p.ConnectionName }
                $chk = Test-UncSharePrinterAlive -UncPath $targetUnc
                $liveStatus = $chk.Status
                $liveReason = "실시간 확인 · $($chk.Reason)"
                if ($liveStatus -eq 'Healthy') {
                    $liveStatusText = '정상'
                } elseif ($liveStatus -eq 'AuthOrSidConflict') {
                    $liveStatusText = '인증 확인 필요'
                    if ($chk.HostName -and -not $seenAuthHost.ContainsKey($chk.HostName.ToLowerInvariant())) {
                        $seenAuthHost[$chk.HostName.ToLowerInvariant()] = $true
                        $authFailedHosts.Add([pscustomobject]@{ HostName = $chk.HostName; Reason = $chk.Reason })
                    }
                } elseif ($liveStatus -eq 'Ambiguous') {
                    $liveStatusText = '응답 확인 필요'
                } else {
                    $liveStatusText = '응답 없음'
                }
            } elseif ($pKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$wsdIp)) {
                if ((Test-TcpPortFast -HostIp $wsdIp -Port 9100 -TimeoutMs 1200) -or (Test-TcpPortFast -HostIp $wsdIp -Port 515 -TimeoutMs 1000)) {
                    $wsdMode = 'TCPIP'; $wsdShare = $null; $liveStatus = 'WsdConvert'; $liveStatusText = 'WSD 전환'
                    $liveReason = "실시간 확인 · WSD IP($wsdIp) 인쇄 포트 정상, TCP/IP로 자동 전환됩니다."
                } elseif (Test-TcpPortFast -HostIp $wsdIp -Port 445 -TimeoutMs 1200) {
                    $auth = Connect-SharedHostSmart -HostName $wsdIp
                    if ($auth.Success) {
                        $shs = @(Get-RemoteSharedPrinters -HostName $wsdIp)
                        if ($shs.Count -gt 0) {
                            $bestS = $shs[0]
                            $hintCombo = "$dName $wsdModel"
                            if ($hintCombo -match '(?i)Kyocera' -and ($shs -contains 'kyoceraf')) { $bestS = 'kyoceraf' }
                            elseif ($hintCombo -match '(?i)Samsung' -and ($shs -contains 'samsungm')) { $bestS = 'samsungm' }
                            $wsdMode = 'LOCAL_UNC'; $wsdShare = "\\$wsdIp\$bestS"; $liveStatus = 'WsdConvert'; $liveStatusText = 'WSD 전환'
                            $liveReason = "실시간 확인 · WSD IP($wsdIp) 공유 프린터($bestS) 확인, Local Port로 자동 전환됩니다."
                        } else {
                            $liveStatus = 'Ambiguous'; $liveStatusText = 'WSD 확인 필요'
                            $liveReason = "실시간 확인 · WSD IP($wsdIp) 접속은 되었으나 공유 프린터가 없습니다."
                        }
                    } elseif ($auth.Status -eq 'AuthOrSidConflict') {
                        $liveStatus = 'AuthOrSidConflict'; $liveStatusText = '인증 확인 필요'
                        $liveReason = "실시간 확인 · WSD 호스트($wsdIp) $($auth.Reason)"
                        if (-not $seenAuthHost.ContainsKey($wsdIp.ToLowerInvariant())) {
                            $seenAuthHost[$wsdIp.ToLowerInvariant()] = $true
                            $authFailedHosts.Add([pscustomobject]@{ HostName = $wsdIp; Reason = $liveReason })
                        }
                    } else {
                        $liveStatus = 'Ambiguous'; $liveStatusText = 'WSD 확인 필요'
                        $liveReason = "실시간 확인 · WSD IP($wsdIp) SMB 연결 실패: $($auth.Reason)"
                    }
                } else {
                    if ((Test-PingFast -HostIp $wsdIp -TimeoutMs 1000) -or (Test-TcpPortFast -HostIp $wsdIp -Port 80 -TimeoutMs 1000)) {
                        $liveStatus = 'Ambiguous'; $liveStatusText = 'WSD 확인 필요'
                        $liveReason = "실시간 확인 · WSD IP($wsdIp) 응답은 있으나 인쇄 포트가 닫혀 있습니다."
                    } else {
                        $liveStatus = 'SuspectedInactive'; $liveStatusText = '응답 없음'
                        $liveReason = "실시간 확인 · WSD IP($wsdIp) 응답 없음. 전원 꺼짐이나 IP 변경을 확인해 주세요."
                    }
                }
            }
        } elseif ($liveStatus -eq 'AuthOrSidConflict') {
            $targetUnc = $port
            if ($p.ConnectionName) { $targetUnc = [string]$p.ConnectionName }
            $hm = [regex]::Match($targetUnc, '^\\\\([^\\]+)\\')
            if ($hm.Success -and -not $seenAuthHost.ContainsKey($hm.Groups[1].Value.ToLowerInvariant())) {
                $seenAuthHost[$hm.Groups[1].Value.ToLowerInvariant()] = $true
                $authFailedHosts.Add([pscustomobject]@{ HostName = $hm.Groups[1].Value; Reason = $liveReason })
            }
        }

        $defaultCheck = $true
        if ($liveStatus -eq 'SuspectedInactive') { $defaultCheck = $false }
        if ($spec.Win11ReinstallOnly) {
            $defaultCheck   = $false
            $liveStatusText = '전용 설치 필요'
        }
        if ($spec.NoDriverBackup) {
            $defaultCheck   = $false
            $liveStatusText = 'LPT1 확인 전용'
            $liveReason     = '드라이버를 설치하지 않는 LPT1 직결 장비입니다. 장치관리자에서 LPT1 인식 여부만 확인해 주세요.'
        }

        $rows.Add([pscustomobject]@{
            Selected       = $defaultCheck
            StatusCode     = $liveStatus
            StatusText     = $liveStatusText
            Category       = $spec.Label
            SpecialType    = $spec.Type
            PrinterName    = $pName
            DriverName     = $dName
            PortName       = $port
            PortKind       = $pKind
            HostAddress    = $hostAddr
            ConnectionName = $p.ConnectionName
            WsdTargetIp    = $wsdIp
            WsdModelName   = $wsdModel
            WsdTargetMode  = $wsdMode
            WsdTargetShare = $wsdShare
            SpecialDatFile = $p.SpecialDatFile
            SpecialRegFile = $p.SpecialRegFile
            IsDefault      = [bool]$p.Default
            Reason         = $liveReason
            RawRecord      = $p
        })
    }

    return [pscustomobject]@{
        Printers        = $rows.ToArray()
        AuthFailedHosts = $authFailedHosts.ToArray()
    }
}

# ============================================================================
# [복원 엔진] WPP 사전 차단 + [H1 Fix] -SkipPrintBrm 정밀 재시도 + 원자적 정책
# ============================================================================
function Set-DefaultPrinterSafe {
    param([string]$PrinterName)
    if ([string]::IsNullOrWhiteSpace($PrinterName)) { return $false }
    try {
        New-Item -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Force | Out-Null
        Set-ItemProperty -LiteralPath 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Value 1 -Type DWord -ErrorAction SilentlyContinue
    } catch {}
    try {
        (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterName)
        return $true
    } catch {
        try {
            $rDef = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/y', '/q', '/n', $PrinterName)
            if ($rDef.ExitCode -eq 0) { return $true }
        } catch {}
        try {
            $wmi = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $PrinterName }) | Select-Object -First 1
            if ($wmi) {
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                return $true
            }
        } catch {}
    }
    return $false
}

function Remove-PrinterObjectSafe {
    param(
        $PrinterObj,
        [string]$PrinterName
    )
    $nm = $PrinterName
    if ([string]::IsNullOrWhiteSpace($nm) -and $PrinterObj) { $nm = [string]$PrinterObj.Name }
    if ($PrinterObj -and (-not $PrinterObj._NativeFallback)) {
        try {
            Remove-Printer -InputObject $PrinterObj -ErrorAction Stop
            return
        } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace($nm)) {
        if ($nm.StartsWith('\\')) {
            [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/dn', '/q', '/n', $nm))
        } else {
            [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/dl', '/q', '/n', $nm))
        }
    }
}

function Set-PrinterPropsSafe {
    param(
        $PrinterObj,
        [string]$PrinterName,
        [string]$DriverName = $null,
        [string]$PortName = $null
    )
    $nm = $PrinterName
    if ([string]::IsNullOrWhiteSpace($nm) -and $PrinterObj) { $nm = [string]$PrinterObj.Name }
    if ($PrinterObj -and (-not $PrinterObj._NativeFallback)) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($DriverName) -and -not [string]::IsNullOrWhiteSpace($PortName)) {
                Set-Printer -InputObject $PrinterObj -DriverName $DriverName -PortName $PortName -ErrorAction Stop
            } elseif (-not [string]::IsNullOrWhiteSpace($DriverName)) {
                Set-Printer -InputObject $PrinterObj -DriverName $DriverName -ErrorAction Stop
            } elseif (-not [string]::IsNullOrWhiteSpace($PortName)) {
                Set-Printer -InputObject $PrinterObj -PortName $PortName -ErrorAction Stop
            }
            return
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($nm)) { throw '프린터 이름이 비어 있어 속성을 변경할 수 없습니다.' }
    if (-not [string]::IsNullOrWhiteSpace($DriverName)) {
        $r1 = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Xs', '/n', $nm, 'DriverName', $DriverName)
        if ($r1.ExitCode -ne 0) { throw "드라이버 변경 실패 (PrintUI ExitCode=$($r1.ExitCode))" }
    }
    if (-not [string]::IsNullOrWhiteSpace($PortName)) {
        $r2 = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Xs', '/n', $nm, 'PortName', $PortName)
        if ($r2.ExitCode -ne 0) { throw "포트 변경 실패 (PrintUI ExitCode=$($r2.ExitCode))" }
    }
}

function Ensure-RestoredPortSafe {
    param(
        $PortObj,
        [string]$FallbackName,
        [string]$OverrideKind = $null,
        [string]$OverrideHostIp = $null
    )

    $pName = $FallbackName
    if ($PortObj -and $PortObj.Name) { $pName = [string]$PortObj.Name }

    $kind = 'LOCAL'
    if ($OverrideKind) { $kind = $OverrideKind }
    elseif ($PortObj -and $PortObj.Kind) { $kind = [string]$PortObj.Kind }
    elseif ($pName -match '^\\\\') { $kind = 'LOCAL_UNC' }

    $exist = @(Get-PrinterPortSafe | Where-Object { $_.Name -ieq $pName }) | Select-Object -First 1
    if ($exist) {
        if ($kind -eq 'LOCAL_UNC' -or $pName.StartsWith('\\')) {
            $hmEx = [regex]::Match($pName, '^\\\\([^\\]+)\\')
            if ($hmEx.Success) {
                $hostEx = $hmEx.Groups[1].Value
                $authEx = Connect-SharedHostSmart -HostName $hostEx
                if (-not $authEx.Success) {
                    $failHEx = $null
                    if ($authEx.Status -eq 'AuthOrSidConflict') { $failHEx = $hostEx }
                    return [pscustomobject]@{ Success = $false; PortName = [string]$exist.Name; Reason = $authEx.Reason; AuthFailedHost = $failHEx }
                }
            }
        }
        return [pscustomobject]@{ Success = $true; PortName = [string]$exist.Name; Reason = $null; AuthFailedHost = $null }
    }

    try {
        if ($kind -eq 'TCPIP') {
            $hostIp = $pName
            if ($OverrideHostIp) { $hostIp = $OverrideHostIp }
            elseif ($PortObj -and $PortObj.HostAddress) { $hostIp = [string]$PortObj.HostAddress }

            # [중요] Add-PrinterPort -SNMP 0 은 -SNMPCommunity 누락 시 0x80070057 오류 발생 -> -SNMP 생략(기본 비활성) 후 6단계에서 SNMP Enabled=0 재보장
            try {
                if ($PortObj -and [string]$PortObj.Protocol -eq 'LPR' -and -not [string]::IsNullOrWhiteSpace([string]$PortObj.Queue)) {
                    $params = @{ Name = $pName; LprHostAddress = $hostIp; LprQueueName = [string]$PortObj.Queue; ErrorAction = 'Stop' }
                    if ($PortObj.ByteCount) { $params.LprByteCounting = $true }
                    Add-PrinterPort @params
                } else {
                    $params = @{ Name = $pName; PrinterHostAddress = $hostIp; ErrorAction = 'Stop' }
                    if ($PortObj -and $PortObj.PortNumber -and [uint32]$PortObj.PortNumber -gt 0) { $params.PortNumber = [uint32]$PortObj.PortNumber }
                    Add-PrinterPort @params
                }
            } catch {
                # WMI(MSFT_PrinterPort) 클래스 손상 PC 폴백: 레지스트리 Standard TCP/IP Port 직접 생성 후 스풀러 재시작
                $tcpPortKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports\$pName"
                $isLpr = ($PortObj -and [string]$PortObj.Protocol -eq 'LPR' -and -not [string]::IsNullOrWhiteSpace([string]$PortObj.Queue))
                $pNum  = 9100
                if ($isLpr) { $pNum = 515 }
                if ($PortObj -and $PortObj.PortNumber -and [int]$PortObj.PortNumber -gt 0) { $pNum = [int]$PortObj.PortNumber }
                [void](Stop-SpoolerSafe)
                try {
                    New-Item -Path $tcpPortKey -Force -ErrorAction Stop | Out-Null
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'Protocol' -Value $(if ($isLpr) { 2 } else { 1 }) -Type DWord
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'Version' -Value 2 -Type DWord
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'HostName' -Value $hostIp -Type String
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'IPAddress' -Value '' -Type String
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'HWAddress' -Value '' -Type String
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'PortNumber' -Value $pNum -Type DWord
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'SNMP Community' -Value 'public' -Type String
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'SNMP Enabled' -Value 0 -Type DWord
                    Set-ItemProperty -LiteralPath $tcpPortKey -Name 'SNMP Index' -Value 1 -Type DWord
                    if ($isLpr) {
                        Set-ItemProperty -LiteralPath $tcpPortKey -Name 'Queue' -Value ([string]$PortObj.Queue) -Type String
                        Set-ItemProperty -LiteralPath $tcpPortKey -Name 'Double Spool' -Value 0 -Type DWord
                        Set-ItemProperty -LiteralPath $tcpPortKey -Name 'LPR Byte Counting' -Value $(if ($PortObj.ByteCount) { 1 } else { 0 }) -Type DWord
                    }
                } finally {
                    Ensure-SpoolerRunning
                }
            }
            return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null }
        }
        elseif ($kind -eq 'USB') {
            $usbPorts  = @(Get-PrinterPortSafe | Where-Object { $_.Name -match '(?i)^USB\d+' } | Sort-Object Name)
            $usedPorts = @(Get-PrinterSafe | ForEach-Object { [string]$_.PortName })
            $freeUsb   = $usbPorts | Where-Object { $usedPorts -notcontains $_.Name } | Select-Object -First 1
            if ($freeUsb) {
                return [pscustomobject]@{ Success = $true; PortName = [string]$freeUsb.Name; Reason = "USB 포트 자동 매핑 ($pName -> $($freeUsb.Name))"; AuthFailedHost = $null }
            }
            if ($usbPorts.Count -gt 0) {
                return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = "사용 가능한 미할당 USB 포트가 없음 (기존 포트 $($usbPorts.Name -join ', ') 모두 타 프린터 사용 중 — USB 재연결 후 재시도 필요)"; AuthFailedHost = $null }
            }
            return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = '새 PC에 USB 프린터 포트가 인식되지 않음 (USB 케이블 연결 후 [USB 재인식] 또는 재시도 필요)'; AuthFailedHost = $null }
        }
        elseif ($kind -eq 'LOCAL_UNC' -or $pName.StartsWith('\\')) {
            $hm = [regex]::Match($pName, '^\\\\([^\\]+)\\')
            $hostName = $null
            if ($hm.Success) { $hostName = $hm.Groups[1].Value }

            $auth = Connect-SharedHostSmart -HostName $hostName
            if (-not $auth.Success) {
                $failHost = $null
                if ($auth.Status -eq 'AuthOrSidConflict') { $failHost = $hostName }
                return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = $auth.Reason; AuthFailedHost = $failHost }
            }
            try {
                Add-PrinterPort -Name $pName -ErrorAction Stop
                return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null }
            } catch {
                [void](Stop-SpoolerSafe)
                try {
                    [Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports', $pName, '')
                } finally {
                    Ensure-SpoolerRunning
                }
                $chk = @(Get-PrinterPortSafe | Where-Object { $_.Name -ieq $pName }) | Select-Object -First 1
                if ($chk) { return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null } }
                return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = "UNC 로컬 포트 등록 실패: $($_.Exception.Message)"; AuthFailedHost = $hostName }
            }
        }
        else {
            try {
                Add-PrinterPort -Name $pName -ErrorAction Stop
            } catch {
                [void](Stop-SpoolerSafe)
                try {
                    [Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports', $pName, '')
                } finally {
                    Ensure-SpoolerRunning
                }
            }
            return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null }
        }
    }
    catch {
        return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = $_.Exception.Message; AuthFailedHost = $null }
    }
}

function Import-RewrittenPrinterRegFile {
    param(
        [string]$PrinterName,
        [string]$OriginalPrinterName,
        [string]$RegFullPath
    )
    if ([string]::IsNullOrWhiteSpace($RegFullPath) -or -not (Test-Path -LiteralPath $RegFullPath)) { return $false }

    $importTarget     = $RegFullPath
    $tempRewrittenReg = $null
    if (-not [string]::IsNullOrWhiteSpace($OriginalPrinterName) -and $OriginalPrinterName -ne $PrinterName) {
        try {
            $regContent = [IO.File]::ReadAllText($RegFullPath, [Text.Encoding]::Unicode)
            $escapedOld  = [regex]::Escape("Control\Print\Printers\$OriginalPrinterName\PrinterDriverData")
            $newPath     = "Control\Print\Printers\$PrinterName\PrinterDriverData"
            $safeNewPath = $newPath.Replace('$', '$$')
            $rewritten   = [regex]::Replace($regContent, $escapedOld, $safeNewPath, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not (Test-Path -LiteralPath $global:AsanCtx.WorkBaseDir)) { New-Item -ItemType Directory -Path $global:AsanCtx.WorkBaseDir -Force | Out-Null }
            $regGuid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
            $tempRewrittenReg = Join-Path $global:AsanCtx.WorkBaseDir "Rewritten_${PID}_$regGuid.reg"
            [IO.File]::WriteAllText($tempRewrittenReg, $rewritten, [Text.Encoding]::Unicode)
            $importTarget = $tempRewrittenReg
        } catch {
            # 이름 치환 실패 시 잘못된 원본 키로 덮어쓰지 않고 안전하게 실패 반환
            return $false
        }
    }

    $r = Invoke-NativeCommand -FilePath 'reg.exe' -Arguments @('import', $importTarget)
    if ($tempRewrittenReg -and (Test-Path -LiteralPath $tempRewrittenReg)) {
        Remove-Item -LiteralPath $tempRewrittenReg -Force -ErrorAction SilentlyContinue
    }
    return ($r.ExitCode -eq 0)
}

function Invoke-AsanStandardPolicyAtomic {
    param(
        [hashtable]$PreExistingPrinters = $null,
        [switch]$CleanMigratedVirtuals,
        [object[]]$PendingRegImports = @()
    )

    Ensure-SpoolerRunning

    if ($CleanMigratedVirtuals) {
        foreach ($p in @(Get-PrinterSafe)) {
            $pName = [string]$p.Name
            if ($pName -eq 'Microsoft Print to PDF') { continue }
            if ($PreExistingPrinters -and $PreExistingPrinters.ContainsKey($pName.ToLowerInvariant())) { continue }
            if (Test-IsVirtualPrinter -PrinterName $pName -PortName $p.PortName) {
                Remove-PrinterObjectSafe -PrinterObj $p -PrinterName $pName
            }
        }
    }

    $prtMap = @{}
    foreach ($p in @(Get-LocalPrintersSafe)) {
        $prtMap[[string]$p.Name] = $p
    }

    $spoolerStopped = Stop-SpoolerSafe
    if (-not $spoolerStopped) {
        Start-Sleep -Milliseconds 700
        $spoolerStopped = Stop-SpoolerSafe
    }
    $failedRegImports = [System.Collections.Generic.List[string]]::new()

    try {
        $tcpRegRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports'
        if (Test-Path -LiteralPath $tcpRegRoot) {
            Get-ChildItem -LiteralPath $tcpRegRoot -ErrorAction SilentlyContinue | ForEach-Object {
                Set-ItemProperty -LiteralPath $_.PSPath -Name 'SNMP Enabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
            }
        }

        $prtRegRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'
        if (Test-Path -LiteralPath $prtRegRoot) {
            Get-ChildItem -LiteralPath $prtRegRoot -ErrorAction SilentlyContinue | ForEach-Object {
                $pName = $_.PSChildName
                $regProps = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                $drvForSpec  = ''
                $portForSpec = ''
                $pInfo = $prtMap[$pName]
                if ($pInfo) {
                    $drvForSpec  = [string]$pInfo.DriverName
                    $portForSpec = [string]$pInfo.PortName
                }
                if ($regProps) {
                    if ([string]::IsNullOrWhiteSpace($drvForSpec) -and $regProps.PSObject.Properties.Name -contains 'Printer Driver') {
                        $drvForSpec = [string]$regProps.'Printer Driver'
                    }
                    if ([string]::IsNullOrWhiteSpace($portForSpec) -and $regProps.PSObject.Properties.Name -contains 'Port') {
                        $portForSpec = [string]$regProps.Port
                    }
                }
                $spec = Get-SpecialPrinterProfile -PrinterName $pName -DriverName $drvForSpec -PortName $portForSpec
                if ($spec.IsSpecial -and ($portForSpec -match '(?i)^USB')) { return }

                $attr = $null
                if ($regProps -and $regProps.PSObject.Properties.Name -contains 'Attributes') {
                    $attr = $regProps.Attributes
                }
                if ($null -ne $attr) {
                    $rawInt64 = [int64]$attr
                    $curUInt  = [uint32]($rawInt64 -band [int64]0xFFFFFFFF)
                    $newUInt  = [uint32]($curUInt -band [uint32]0xFFFFF7FF)
                    $regDword = [BitConverter]::ToInt32([BitConverter]::GetBytes($newUInt), 0)
                    Set-ItemProperty -LiteralPath $_.PSPath -Name 'Attributes' -Value $regDword -Type DWord -ErrorAction SilentlyContinue
                }
            }
        }

        foreach ($regItem in @($PendingRegImports)) {
            $regOk = Import-RewrittenPrinterRegFile -PrinterName $regItem.PrinterName -OriginalPrinterName $regItem.OriginalPrinterName -RegFullPath $regItem.RegFullPath
            if (-not $regOk) {
                $failedRegImports.Add([string]$regItem.PrinterName)
                Write-ProgressSafe -Percent 88 -Message "[경고] 특수장비 레지스트리 설정(.reg) 주입 실패: $($regItem.PrinterName)"
            }
        }
    }
    finally {
        Ensure-SpoolerRunning
    }
    return [pscustomobject]@{
        SpoolerStopped   = $spoolerStopped
        FailedRegImports = $failedRegImports.ToArray()
    }
}

function Invoke-PrinterRestoreEngine {
    param(
        [string]$SourcePath,
        [object[]]$SelectedRows,
        [string]$PcIp,
        [switch]$IgnoreWppWarning,
        [switch]$SkipPrintBrm,
        [scriptblock]$OnProgress = $null
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Ensure-SpoolerRunning

    $wppCheck = Test-WindowsProtectedPrintMode
    if ($wppCheck.IsEnabled -and -not $IgnoreWppWarning) {
        return [pscustomobject]@{
            Success           = $false
            BlockedByWpp      = $true
            WppInfo           = $wppCheck
            RestoreLog        = @([pscustomobject]@{ Level = 'Warning'; Target = 'WPP 차단'; Message = $wppCheck.BannerTitle })
            Failures          = @()
            AuthFailedHosts   = @()
            DetectedSpecials   = @()
            SamFallbackNames   = @()
            ZtManualPrefsNames = @()
            RestoredScanCount  = 0
        }
    }

    if (-not (Test-Path -LiteralPath $global:AsanCtx.WorkBaseDir)) { New-Item -ItemType Directory -Path $global:AsanCtx.WorkBaseDir -Force | Out-Null }

    $resGuid            = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $localTemp          = Join-Path $global:AsanCtx.WorkBaseDir "Work_Res_${PID}_$resGuid"
    $isZip              = ($SourcePath -match '(?i)\.zip$')
    $restoreLog         = [System.Collections.Generic.List[object]]::new()
    $failures           = [System.Collections.Generic.List[object]]::new()
    $authHosts          = [System.Collections.Generic.List[object]]::new()
    $seenAuth           = @{}
    $offlineUncHosts    = @{}
    $detectedSpecials   = [System.Collections.Generic.List[object]]::new()
    $samFallbackList    = [System.Collections.Generic.List[string]]::new()
    $ztManualPrefsList  = [System.Collections.Generic.List[string]]::new()
    $pendingRegImports  = [System.Collections.Generic.List[object]]::new()
    $needsUsbReplug     = $false
    $brmRestoredOk      = $false

    try {
        if (Test-Path -LiteralPath $localTemp) { Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $localTemp -Force | Out-Null

        $preExistingPrinters = @{}
        foreach ($ep in @(Get-PrinterSafe)) {
            $preExistingPrinters[([string]$ep.Name).ToLowerInvariant()] = $true
        }
        $preExistingDrivers = @{}
        foreach ($ed in @(Get-PrinterDriverSafe)) {
            $preExistingDrivers[([string]$ed.Name).ToLowerInvariant()] = $true
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 10 -Message '[1/6] 백업 데이터 로컬 스테이징 준비 중...'
        if ($isZip) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($SourcePath, $localTemp)
        } else {
            $cleanSrcDir = $SourcePath.TrimEnd('\')
            $rc = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($cleanSrcDir, $localTemp, '/E', '/R:2', '/W:1')).ExitCode
            if ($rc -ge 8) { throw "백업 서버 다운로드 실패 (robocopy ExitCode=$rc)" }
        }

        $jsonFile   = Join-Path $localTemp 'PrinterBackup.json'
        $brmFile    = Join-Path $localTemp 'PrinterBackup.printerExport'
        $expPrtDir  = Join-Path $localTemp 'ExportedDrivers\Printers'
        $expScanDir = Join-Path $localTemp 'ExportedDrivers\Scanners'

        $backupData = $null
        if (Test-Path -LiteralPath $jsonFile) {
            $backupData = Get-Content -LiteralPath $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        $selectedNames = @($SelectedRows | Where-Object { $_.Selected } | ForEach-Object { [string]$_.PrinterName })

        # [2/6] UNC 로컬 포트 선등록 및 3종 비밀번호 무인 인증
        Write-ProgressSafe -OnProgress $OnProgress -Percent 22 -Message '[2/6] 공유 포트(\\IP\공유명) 자격 증명(3종 자동 시도) 및 포트 선등록 중...'
        $uncPortsToRegister = [System.Collections.Generic.List[string]]::new()
        foreach ($row in @($SelectedRows | Where-Object { $_.Selected })) {
            $targetUnc = $null
            if ($row.PortKind -eq 'LOCAL_UNC' -or $row.PortName -match '^\\\\') { $targetUnc = [string]$row.PortName }
            elseif ($row.PortKind -eq 'WSD' -and $row.WsdTargetMode -eq 'LOCAL_UNC' -and $row.WsdTargetShare) { $targetUnc = [string]$row.WsdTargetShare }

            if ($targetUnc) {
                $hm = [regex]::Match($targetUnc, '^\\\\([^\\]+)\\')
                if ($hm.Success) {
                    $h    = $hm.Groups[1].Value
                    $auth = Connect-SharedHostSmart -HostName $h
                    if ($auth.Success) {
                        if (-not $uncPortsToRegister.Contains($targetUnc)) { $uncPortsToRegister.Add($targetUnc) }
                    } elseif ($auth.Status -eq 'AuthOrSidConflict') {
                        if (-not $seenAuth.ContainsKey($h.ToLowerInvariant())) {
                            $seenAuth[$h.ToLowerInvariant()] = $true
                            $authHosts.Add([pscustomobject]@{ HostName = $h; Reason = $auth.Reason })
                        }
                    } else {
                        $offlineUncHosts[$h.ToLowerInvariant()] = [string]$auth.Reason
                    }
                }
            }
        }
        if ($uncPortsToRegister.Count -gt 0) {
            [void](Stop-SpoolerSafe)
            try {
                foreach ($up in $uncPortsToRegister) {
                    [Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports', $up, '')
                }
            } finally {
                Ensure-SpoolerRunning
            }
        }

        # [3/6] PrintBrm 선복원 ([H1 Fix] 실패 항목 재시도 시 건너뛰어 기존 수동 설치/정상 큐 보호)
        if ($SkipPrintBrm) {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 36 -Message '[3/6] 실패 항목 정밀 재시도 모드 — PrintBrm 전체 덮어쓰기 생략'
        } elseif (Test-Path -LiteralPath $brmFile) {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 36 -Message '[3/6] PrintBrm 원본 드라이버 및 인쇄 기본 설정 복원 중...'
            $brmRestoreRes = Invoke-NativeCommand -FilePath $global:AsanCtx.PrintBrmExe -Arguments @('-r', '-f', $brmFile, '-o', 'force')
            if ($brmRestoreRes.ExitCode -eq 0) {
                $brmRestoredOk = $true
            } else {
                $brmShort = ([string]$brmRestoreRes.Output -replace '\s+', ' ').Trim()
                if ($brmShort.Length -gt 200) { $brmShort = $brmShort.Substring(0, 200) + '...' }
                $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = "PrintBrm 일부 경고/오류 (ExitCode=$($brmRestoreRes.ExitCode)) — 누락 항목은 5단계 정밀 복원으로 자동 보완됩니다. [$brmShort]" })
            }
        } else {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 36 -Message '[3/6] PrintBrm 없음 — 개별 드라이버 및 JSON 기반으로 복원 진행...'
        }

        # [4/6] 사후 정제 ([H1 Fix] -SkipPrintBrm 시 생략)
        if (-not $SkipPrintBrm) {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 48 -Message '[4/6] 미선택·가상 프린터 및 전용 설치 대상 정리 중...'
            $allBackupRowsByName = @{}
            foreach ($r in @($SelectedRows)) { $allBackupRowsByName[[string]$r.PrinterName] = $r }
            $sewooDriversToClean = [System.Collections.Generic.List[string]]::new()

            foreach ($curPrt in @(Get-PrinterSafe)) {
                $cName = [string]$curPrt.Name
                if ($cName -eq 'Microsoft Print to PDF') { continue }

                $wasPreExisting = $preExistingPrinters.ContainsKey($cName.ToLowerInvariant())
                if (-not $wasPreExisting -and (Test-IsVirtualPrinter -PrinterName $cName -PortName $curPrt.PortName)) {
                    Remove-PrinterObjectSafe -PrinterObj $curPrt -PrinterName $cName
                    continue
                }

                $specNow = Get-SpecialPrinterProfile -PrinterName $cName -DriverName $curPrt.DriverName -PortName $curPrt.PortName
                # 이미 새 PC에 선설치된 정상 세우테크 큐는 보호($wasPreExisting 확인)
                if ((-not $wasPreExisting) -and ($specNow.Win11ReinstallOnly -or $specNow.NoDriverBackup)) {
                    $isoDrv = [string]$curPrt.DriverName
                    Remove-PrinterObjectSafe -PrinterObj $curPrt -PrinterName $cName
                    if (-not [string]::IsNullOrWhiteSpace($isoDrv) -and -not $sewooDriversToClean.Contains($isoDrv)) {
                        $sewooDriversToClean.Add($isoDrv)
                    }
                    if ($specNow.NoDriverBackup) {
                        $restoreLog.Add([pscustomobject]@{ Level = 'Special'; Target = $cName; Message = 'EPSON TM-T88 유입 큐와 드라이버를 자동 격리 삭제했습니다. 드라이버를 설치하지 말고 장치관리자 LPT1 인식만 확인해 주세요.' })
                    } else {
                        $restoreLog.Add([pscustomobject]@{ Level = 'Special'; Target = $cName; Message = '세우테크 유입 큐와 드라이버를 자동 격리 삭제했습니다. 새 PC 전용 설치 도우미로 직접 설치해 주세요.' })
                    }
                    continue
                }

                if ($allBackupRowsByName.ContainsKey($cName)) {
                    $rowRef = $allBackupRowsByName[$cName]
                    if (-not $rowRef.Selected -and -not $wasPreExisting) {
                        Remove-PrinterObjectSafe -PrinterObj $curPrt -PrinterName $cName
                        $restoreLog.Add([pscustomobject]@{ Level = 'Info'; Target = $cName; Message = '사용자가 복원 제외(체크 해제)하여 사후 정제 삭제됨' })
                        continue
                    }
                    if ($rowRef.Selected -and $rowRef.PortKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$rowRef.WsdTargetIp)) {
                        Remove-PrinterObjectSafe -PrinterObj $curPrt -PrinterName $cName
                        continue
                    }
                }
            }

            # PrintBrm으로 큐 없이 드라이버만 유입된 Win 10 구형 세우테크 / 무드라이버 TM-T88 고아 드라이버도 함께 격리
            $hasSelectedUsbTm88 = (@($SelectedRows | Where-Object {
                $_.Selected -and ($_.PrinterName -match '(?i)TM-?T88|TMT88' -or $_.DriverName -match '(?i)TM-?T88|TMT88') -and ($_.SpecialType -ne 'EPSON_TMT88_LPT')
            })).Count -gt 0
            $remainingDrvs = @(Get-PrinterSafe | ForEach-Object { [string]$_.DriverName })
            foreach ($dCheck in @(Get-PrinterDriverSafe)) {
                $dn = [string]$dCheck.Name
                if ([string]::IsNullOrWhiteSpace($dn)) { continue }
                if ($preExistingDrivers.ContainsKey($dn.ToLowerInvariant())) { continue }
                if ($remainingDrvs -contains $dn) { continue }
                if ($dn -match '(?i)SLK-TE|LK-TE|Sewoo|POS\s*PRINTER') {
                    if (-not $sewooDriversToClean.Contains($dn)) { $sewooDriversToClean.Add($dn) }
                } elseif ((-not $hasSelectedUsbTm88) -and ($dn -match '(?i)TM-?T88|TMT88')) {
                    if (-not $sewooDriversToClean.Contains($dn)) { $sewooDriversToClean.Add($dn) }
                }
            }

            if ($sewooDriversToClean.Count -gt 0) {
                foreach ($sdName in $sewooDriversToClean) {
                    if ($remainingDrvs -notcontains $sdName) {
                        foreach ($dObj in @(Get-PrinterDriverSafe | Where-Object { $_.Name -eq $sdName })) {
                            if (-not $dObj._NativeFallback) {
                                try { Remove-PrinterDriver -InputObject $dObj -ErrorAction SilentlyContinue } catch {}
                            } else {
                                [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/dd', '/q', '/m', $sdName))
                            }
                        }
                    }
                }
            }
        } else {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 48 -Message '[4/6] 정밀 재시도 모드 — 기존 설치 큐 유지'
        }

        # [5/6] 복원 작업당 1회 INF 인덱스 구축 + USB 바코드 자동 재인식 + 정밀 복원
        Write-ProgressSafe -OnProgress $OnProgress -Percent 58 -Message '[5/6] 드라이버 인덱스 구축 및 누락/WSD 전환/특수장비 복원 중...'
        $expInfs = @()
        if (Test-Path -LiteralPath $expPrtDir) {
            $expInfs = @(Get-ChildItem -LiteralPath $expPrtDir -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
        }

        # USB 직결 특수/바코드 프린터가 선택된 경우: 해당 제조사 INF만 선별 선등록 후 미인식 바코드만 PnP 재인식
        $usbSpecialVendors = [System.Collections.Generic.List[string]]::new()
        $hasSelectedZt411Usb = $false
        foreach ($chkRow in @($SelectedRows | Where-Object { $_.Selected })) {
            $chkSpec = Get-SpecialPrinterProfile -PrinterName ([string]$chkRow.PrinterName) -DriverName ([string]$chkRow.DriverName) -PortName ([string]$chkRow.PortName)
            if ($chkSpec.IsSpecial -and (-not $chkSpec.Win11ReinstallOnly) -and (-not $chkSpec.NoDriverBackup) -and ([string]$chkRow.PortKind -eq 'USB' -or [string]$chkRow.PortName -match '(?i)^USB')) {
                if ($chkSpec.Type -eq 'ZEBRA_ZT411') { $hasSelectedZt411Usb = $true }
                foreach ($v in @(Get-DetectedVendors -Text "$($chkRow.DriverName) $($chkRow.PrinterName)")) {
                    if ($v -in @('ZEBRA', 'BIXOLON') -and -not $usbSpecialVendors.Contains($v)) {
                        $usbSpecialVendors.Add($v)
                    }
                }
            }
        }
        # ExportedDrivers 인덱스만 선구축, DriverStore/LocalPrt는 드라이버 미발견 시 지연(Lazy) 구축
        $exportedIndex          = @(Build-InfIndexCache -InfFiles $expInfs)
        $usedZtLocalUsbFallback = $false
        if ($usbSpecialVendors.Count -gt 0) {
            $registeredZebraBackup = $false
            foreach ($idxEntry in $exportedIndex) {
                if ($idxEntry.Vendors -contains 'SEWOO') { continue }
                $matchUsbVendor = $false
                foreach ($uv in $usbSpecialVendors) {
                    if ($idxEntry.Vendors -contains $uv) { $matchUsbVendor = $true; break }
                }
                if ($matchUsbVendor) {
                    $rcUsbAdd = (Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $idxEntry.Path, '/install')).ExitCode
                    if (($idxEntry.Vendors -contains 'ZEBRA') -and ($rcUsbAdd -eq 0 -or $rcUsbAdd -eq 259 -or $rcUsbAdd -eq 3010)) {
                        $registeredZebraBackup = $true
                    }
                }
            }
            # ZT411 USB: 기존 PC 백업(PrintBrm/ExportedDrivers) 최우선 — 모두 없는 부득이한 경우에만 골든 이미지 로컬 INF 폴백 등록
            $brmAddedZtDrv = (@(Get-PrinterDriverSafe | Where-Object {
                $_.Name -match '(?i)ZT41[01]' -and ($SkipPrintBrm -or (-not $preExistingDrivers.ContainsKey(([string]$_.Name).ToLowerInvariant())))
            })).Count -gt 0
            if ($hasSelectedZt411Usb -and (-not $registeredZebraBackup) -and (-not $brmAddedZtDrv)) {
                $ztLocalFallback = Find-LocalSpecialInstaller -SpecialType 'ZEBRA_ZT411' -SkipRemoteProbe
                if ($ztLocalFallback -and $ztLocalFallback.InfPath -and (Test-Path -LiteralPath $ztLocalFallback.InfPath)) {
                    $rcZtLoc = (Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $ztLocalFallback.InfPath, '/install')).ExitCode
                    if ($rcZtLoc -eq 0 -or $rcZtLoc -eq 259 -or $rcZtLoc -eq 3010) {
                        $usedZtLocalUsbFallback = $true
                    }
                }
            }
            $usbReRes = Invoke-UsbBarcodeAutoReenumerate -WaitSeconds 8 -OnProgress $OnProgress
            if ($usbReRes.AttemptedCount -gt 0) {
                $uLvl = 'Info'
                if ($usbReRes.NeedsManualReplug) {
                    $uLvl = 'Warning'
                    $needsUsbReplug = $true
                }
                $restoreLog.Add([pscustomobject]@{ Level = $uLvl; Target = 'USB 바코드 자동 재인식'; Message = $usbReRes.Summary })
            }
        }
        $driverIndexCache = @{
            Exported    = $exportedIndex
            DriverStore = $null
            LocalPrt    = $null
        }

        foreach ($row in @($SelectedRows)) {
            $pName = [string]$row.PrinterName
            $spec  = Get-SpecialPrinterProfile -PrinterName $pName -DriverName $row.DriverName -PortName $row.PortName

            if ($spec.IsSpecial) {
                $detectedSpecials.Add($row)
                if ($spec.Win11ReinstallOnly -or $spec.NoDriverBackup) { continue }
            }
            if (-not $row.Selected) { continue }

            $existing = @(Get-PrinterSafe | Where-Object { $_.Name -eq $pName }) | Select-Object -First 1

            # Case A: PrintBrm으로 이미 생성된 큐 검증 및 보강
            if ($existing) {
                $finalDrvName       = [string]$existing.DriverName
                $isSharedConnection = (-not [string]::IsNullOrWhiteSpace([string]$row.ConnectionName)) -or $pName.StartsWith('\\') -or ($row.PortKind -eq 'SHARED_UNC')
                if ((-not $isSharedConnection) -and (-not $spec.IsSpecial) -and $finalDrvName -match $global:AsanCtx.MicrosoftInboxGenericRegex) {
                    $drvRes = Resolve-BestDriverForPrinter -PrinterName $pName -WantedDriverName $row.DriverName -ModelHint $row.WsdModelName -DriverIndexCache $driverIndexCache -ExcludeFromPcl6:$spec.ExcludeFromPcl6 -PreExistingDrivers $preExistingDrivers -ForceUpgradeGeneric
                    if ($drvRes.Success -and $drvRes.DriverName -ne $finalDrvName) {
                        try {
                            Set-PrinterPropsSafe -PrinterObj $existing -PrinterName $pName -DriverName $drvRes.DriverName
                            $oldDrvName   = $finalDrvName
                            $finalDrvName = $drvRes.DriverName
                            $restoreLog.Add([pscustomobject]@{ Level = 'Info'; Target = $pName; Message = "MS 범용 드라이버 교체: $oldDrvName -> $finalDrvName ($($drvRes.Source))" })
                            if ($drvRes.ProtocolNotice) { $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $drvRes.ProtocolNotice }) }
                        } catch {
                            $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = "MS 범용 드라이버 교체 실패 ($($_.Exception.Message)) — 기존 '$finalDrvName' 유지됨" })
                        }
                    }
                }
                if ($finalDrvName -match '(?i)Samsung Universal Print Driver 3') {
                    if (-not $samFallbackList.Contains($pName)) { $samFallbackList.Add($pName) }
                }
                $existingPort = [string]$existing.PortName
                if ((-not $isSharedConnection) -and ($row.PortKind -eq 'USB' -or $existingPort -match '(?i)^USB\d+')) {
                    $curPortExists = @(Get-PrinterPortSafe | Where-Object { $_.Name -ieq $existingPort }) | Select-Object -First 1
                    if (-not $curPortExists) {
                        $uRes = Ensure-RestoredPortSafe -PortObj $null -FallbackName $row.PortName -OverrideKind 'USB'
                        if ($uRes.Success) {
                            try {
                                Set-PrinterPropsSafe -PrinterObj $existing -PrinterName $pName -PortName $uRes.PortName
                                $existingPort = [string]$uRes.PortName
                                $restoreLog.Add([pscustomobject]@{ Level = 'Info'; Target = $pName; Message = $uRes.Reason })
                            } catch {
                                $usbSetErr = "USB 포트($($uRes.PortName)) 변경 적용 실패: $($_.Exception.Message)"
                                $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $usbSetErr })
                                $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $existingPort; DriverName = $finalDrvName; Reason = $usbSetErr; HostName = $null })
                                continue
                            }
                        } else {
                            $usbFailMsg = "USB 포트 미감지로 실제 출력 불가 ($($uRes.Reason))"
                            $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $usbFailMsg })
                            $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $existingPort; DriverName = $finalDrvName; Reason = $usbFailMsg; HostName = $null })
                            continue
                        }
                    }
                }
                $appliedDatA = $false
                $appliedRegA = $false
                if ($spec.IsSpecial) {
                    if ($row.SpecialDatFile) {
                        $dFull = Join-Path $localTemp $row.SpecialDatFile
                        if (Test-Path -LiteralPath $dFull) {
                            $srRes = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $pName, '/a', $dFull, 'd', 'g', 'u', 'r')
                            if ($srRes.ExitCode -eq 0) { $appliedDatA = $true }
                        }
                    }
                    if ($row.SpecialRegFile) {
                        $rFull = Join-Path $localTemp $row.SpecialRegFile
                        if (Test-Path -LiteralPath $rFull) {
                            $pendingRegImports.Add([pscustomobject]@{ PrinterName = $pName; OriginalPrinterName = $pName; RegFullPath = $rFull })
                            $appliedRegA = $true
                        }
                    }
                    if ($spec.Type -eq 'ZEBRA_ZT411') {
                        $isUsbZtA = ($row.PortKind -eq 'USB' -or $existingPort -match '(?i)^USB\d+')
                        if (($usedZtLocalUsbFallback -and $isUsbZtA) -or ((-not $brmRestoredOk) -and (-not $appliedDatA) -and (-not $appliedRegA))) {
                            if (-not $ztManualPrefsList.Contains($pName)) { $ztManualPrefsList.Add($pName) }
                            $ztWarnA = 'ZT411 백업 설정(.dat/.reg) 미확인 — 프린터 속성 > 인쇄 기본 설정(용지/농도 또는 .drx/.drs 가져오기)을 직접 마무리하세요.'
                            if ($usedZtLocalUsbFallback -and $isUsbZtA) {
                                $ztWarnA = '기존 PC USB ZT411 드라이버 미추출로 골든 이미지 로컬 드라이버가 폴백 등록됨 — 프린터 속성 > 인쇄 기본 설정(용지/농도 또는 .drx/.drs 가져오기)을 직접 마무리하세요.'
                            }
                            $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $ztWarnA })
                        }
                    }
                }

                $blockedAuthHost   = $null
                $offlineUncReason  = $null
                $offlineUncHost    = $null
                if ($existingPort -match '^\\\\([^\\]+)\\') {
                    $candH = $matches[1]
                    $candKey = $candH.ToLowerInvariant()
                    if ($seenAuth.ContainsKey($candKey)) { $blockedAuthHost = $candH }
                    elseif ($offlineUncHosts.ContainsKey($candKey)) {
                        $offlineUncHost   = $candH
                        $offlineUncReason = [string]$offlineUncHosts[$candKey]
                    }
                }

                if ($blockedAuthHost) {
                    $warnMsg = "큐는 등록되었으나 공유 호스트($blockedAuthHost) 인증/SID 충돌로 실제 인쇄 불가 — 하단 인증/SID 패널에서 조치 필요"
                    $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $warnMsg })
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $existingPort; DriverName = $finalDrvName; Reason = $warnMsg; HostName = $blockedAuthHost })
                } elseif ($offlineUncHost) {
                    $warnMsg = "큐는 등록되었으나 공유 메인 PC($offlineUncHost) 미응답/연결 실패로 인쇄 불가 ($offlineUncReason)"
                    $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $warnMsg })
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $existingPort; DriverName = $finalDrvName; Reason = $warnMsg; HostName = $offlineUncHost })
                } elseif ($existingPort -match '(?i)^WSD') {
                    $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = "WSD 포트($existingPort)가 유지됨 — IP 미추출로 수동 TCP/IP 포트 전환 필요" })
                } else {
                    $restoreLog.Add([pscustomobject]@{ Level = 'Success'; Target = $pName; Message = "원본 복원 완료 ($finalDrvName / $existingPort)" })
                }
                continue
            }

            # Case B: 공유 프린터(Point-and-Print)
            if (-not [string]::IsNullOrWhiteSpace([string]$row.ConnectionName)) {
                $conn     = [string]$row.ConnectionName
                $connHost = $null
                $hm       = [regex]::Match($conn, '^\\\\([^\\]+)\\')
                if ($hm.Success) {
                    $connHost = $hm.Groups[1].Value
                    $auth     = Connect-SharedHostSmart -HostName $connHost
                    if (-not $auth.Success) {
                        $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $conn; DriverName = $row.DriverName; Reason = $auth.Reason; HostName = $connHost })
                        if ($auth.Status -eq 'AuthOrSidConflict' -and -not $seenAuth.ContainsKey($connHost.ToLowerInvariant())) {
                            $seenAuth[$connHost.ToLowerInvariant()] = $true
                            $authHosts.Add([pscustomobject]@{ HostName = $connHost; Reason = $auth.Reason })
                        }
                        continue
                    }
                }
                try {
                    try {
                        Add-Printer -ConnectionName $conn -ErrorAction Stop
                    } catch {
                        $inConn = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/in', '/q', '/n', $conn)
                        if ($inConn.ExitCode -ne 0) { throw $_.Exception }
                    }
                    $restoreLog.Add([pscustomobject]@{ Level = 'Success'; Target = $pName; Message = "공유 프린터 연결 완료 ($conn)" })
                } catch {
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $conn; DriverName = $row.DriverName; Reason = "공유 연결 실패: $($_.Exception.Message)"; HostName = $connHost })
                }
                continue
            }

            # Case C: 신규 등록 또는 WSD -> TCP/IP / Local Port 전환
            $targetPortName = [string]$row.PortName
            $overrideKind   = $null
            $overrideHostIp = $null

            if ($row.PortKind -eq 'WSD') {
                if ([string]::IsNullOrWhiteSpace([string]$row.WsdTargetIp)) {
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $row.PortName; DriverName = $row.DriverName; Reason = 'WSD IP 미추출 — 수동 포트 지정 필요'; HostName = $null })
                    continue
                }
                if ($row.WsdTargetMode -eq 'LOCAL_UNC' -and -not [string]::IsNullOrWhiteSpace([string]$row.WsdTargetShare)) {
                    $targetPortName = [string]$row.WsdTargetShare
                    $overrideKind   = 'LOCAL_UNC'
                } else {
                    $targetPortName = [string]$row.WsdTargetIp
                    $overrideKind   = 'TCPIP'
                    $overrideHostIp = [string]$row.WsdTargetIp
                }
            }

            $preferExpFirst = ($spec.Type -eq 'ZEBRA_ZT411')
            $drvRes = Resolve-BestDriverForPrinter -PrinterName $pName -WantedDriverName $row.DriverName -ModelHint $row.WsdModelName -DriverIndexCache $driverIndexCache -ExcludeFromPcl6:$spec.ExcludeFromPcl6 -PreExistingDrivers $preExistingDrivers -PreferExportedFirst:$preferExpFirst
            if (-not $drvRes.Success) {
                $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $targetPortName; DriverName = $row.DriverName; Reason = $drvRes.ProtocolNotice; HostName = $null })
                continue
            }

            $portObj = $null
            if ($backupData -and $backupData.Ports) {
                $portObj = @($backupData.Ports | Where-Object { $_.Name -ieq $targetPortName }) | Select-Object -First 1
            }

            $pRes = Ensure-RestoredPortSafe -PortObj $portObj -FallbackName $targetPortName -OverrideKind $overrideKind -OverrideHostIp $overrideHostIp
            if (-not $pRes.Success) {
                $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $targetPortName; DriverName = $drvRes.DriverName; Reason = $pRes.Reason; HostName = $pRes.AuthFailedHost })
                if ($pRes.AuthFailedHost -and -not $seenAuth.ContainsKey($pRes.AuthFailedHost.ToLowerInvariant())) {
                    $seenAuth[$pRes.AuthFailedHost.ToLowerInvariant()] = $true
                    $authHosts.Add([pscustomobject]@{ HostName = $pRes.AuthFailedHost; Reason = $pRes.Reason })
                }
                continue
            }

            if ($pRes.PortName -match '^\\\\([^\\]+)\\') {
                $candHC   = $matches[1]
                $candKeyC = $candHC.ToLowerInvariant()
                if ($seenAuth.ContainsKey($candKeyC)) {
                    $warnMsgC = "공유 호스트($candHC) 인증/SID 충돌로 복원 중단 — 하단 인증/SID 패널에서 조치 필요"
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $pRes.PortName; DriverName = $drvRes.DriverName; Reason = $warnMsgC; HostName = $candHC })
                    continue
                } elseif ($offlineUncHosts.ContainsKey($candKeyC)) {
                    $warnMsgC = "공유 메인 PC($candHC) 미응답/연결 실패로 복원 중단 ($($offlineUncHosts[$candKeyC]))"
                    $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $pRes.PortName; DriverName = $drvRes.DriverName; Reason = $warnMsgC; HostName = $candHC })
                    continue
                }
            }

            try {
                try {
                    Add-Printer -Name $pName -DriverName $drvRes.DriverName -PortName $pRes.PortName -ErrorAction Stop
                } catch {
                    $ifAdd = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/if', '/q', '/b', $pName, '/r', $pRes.PortName, '/m', $drvRes.DriverName)
                    if ($ifAdd.ExitCode -ne 0) { throw $_.Exception }
                }
                $appliedDatC = $false
                $appliedRegC = $false
                if ($spec.IsSpecial) {
                    if ($row.SpecialDatFile) {
                        $dFull = Join-Path $localTemp $row.SpecialDatFile
                        if (Test-Path -LiteralPath $dFull) {
                            $srResC = Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $pName, '/a', $dFull, 'd', 'g', 'u', 'r')
                            if ($srResC.ExitCode -eq 0) { $appliedDatC = $true }
                        }
                    }
                    if ($row.SpecialRegFile) {
                        $rFull = Join-Path $localTemp $row.SpecialRegFile
                        if (Test-Path -LiteralPath $rFull) {
                            $pendingRegImports.Add([pscustomobject]@{ PrinterName = $pName; OriginalPrinterName = $pName; RegFullPath = $rFull })
                            $appliedRegC = $true
                        }
                    }
                }
                $msg = "복원 완료 (드라이버: $($drvRes.DriverName) [$($drvRes.Source)] / 포트: $($pRes.PortName))"
                if ($row.PortKind -eq 'WSD') { $msg = "[WSD 전환 성공] $msg" }
                $restoreLog.Add([pscustomobject]@{ Level = 'Success'; Target = $pName; Message = $msg })

                if ($spec.Type -eq 'ZEBRA_ZT411') {
                    $isUsbZtC          = ($row.PortKind -eq 'USB' -or [string]$pRes.PortName -match '(?i)^USB\d+')
                    $usedZtFallbackDrv = ($drvRes.Source -notin @('OriginalRestored', 'ExportedBackupDriver')) -or ($usedZtLocalUsbFallback -and $isUsbZtC)
                    if ($usedZtFallbackDrv -or (-not $appliedDatC -and -not $appliedRegC)) {
                        if (-not $ztManualPrefsList.Contains($pName)) { $ztManualPrefsList.Add($pName) }
                        $ztWarnMsg = "백업된 ZT411 인쇄 기본 설정(.dat/.reg)이 없어 기본값으로 복원됨 — 프린터 속성 > 인쇄 기본 설정(용지/농도 또는 .drx/.drs 가져오기)을 반드시 마무리하세요."
                        if ($usedZtFallbackDrv) {
                            $ztWarnMsg = "기존 PC 드라이버 복원 불가로 로컬 골든 이미지 드라이버($($drvRes.DriverName) [$($drvRes.Source)])로 대체 복원됨 — 프린터 속성 > 인쇄 기본 설정(용지/농도 또는 .drx/.drs 가져오기)을 반드시 마무리하세요."
                        }
                        $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $ztWarnMsg })
                    }
                }

                if ($drvRes.UsedSamFallback -or $drvRes.DriverName -match '(?i)Samsung Universal Print Driver 3') {
                    if (-not $samFallbackList.Contains($pName)) { $samFallbackList.Add($pName) }
                }
                if ($drvRes.ProtocolNotice) {
                    $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $pName; Message = $drvRes.ProtocolNotice })
                }
            } catch {
                $failures.Add([pscustomobject]@{ PrinterName = $pName; PortName = $pRes.PortName; DriverName = $drvRes.DriverName; Reason = "큐 등록 실패: $($_.Exception.Message)"; HostName = $null })
            }
        }

        # [6/6] 원자적 아산 표준 정책 + WIA 스캐너 복원 + 기본 프린터 복원
        Write-ProgressSafe -OnProgress $OnProgress -Percent 86 -Message '[6/6] Spooler 안전 중지 후 아산 표준(SNMP/양방향/.reg) 적용 및 WIA 스캐너 복원 중...'
        $policyRes = $null
        if ($SkipPrintBrm) {
            $policyRes = Invoke-AsanStandardPolicyAtomic -PendingRegImports $pendingRegImports.ToArray()
        } else {
            $policyRes = Invoke-AsanStandardPolicyAtomic -PreExistingPrinters $preExistingPrinters -CleanMigratedVirtuals -PendingRegImports $pendingRegImports.ToArray()
        }
        if ($policyRes) {
            if (-not $policyRes.SpoolerStopped) {
                $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = '표준 정책'; Message = 'Spooler 중지 대기 시간 초과 — [3. 출력 확인] 탭에서 SNMP/양방향 상태를 한 번 확인하세요.' })
            }
            foreach ($failRegPrt in @($policyRes.FailedRegImports)) {
                $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = $failRegPrt; Message = '특수장비 세부 설정(.reg) 주입 실패 — 프린터 속성 > 인쇄 기본 설정을 직접 확인하세요.' })
                $isZtFail = (@($SelectedRows | Where-Object { $_.PrinterName -eq $failRegPrt -and $_.SpecialType -eq 'ZEBRA_ZT411' })).Count -gt 0
                if ($isZtFail -and -not $ztManualPrefsList.Contains($failRegPrt)) { $ztManualPrefsList.Add($failRegPrt) }
            }
        }

        $restoredScanCnt = 0
        if (-not $SkipPrintBrm -and (Test-Path -LiteralPath $expScanDir)) {
            foreach ($sInf in @(Get-ChildItem -LiteralPath $expScanDir -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)) {
                $rcS = (Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $sInf.FullName, '/install')).ExitCode
                if ($rcS -eq 0 -or $rcS -eq 259 -or $rcS -eq 3010) { $restoredScanCnt++ }
            }
            if ($restoredScanCnt -gt 0) {
                $restoreLog.Add([pscustomobject]@{ Level = 'Success'; Target = 'WIA 스캐너'; Message = "백업된 제조사 공식 스캐너 드라이버 ${restoredScanCnt}개 설치 완료" })
            }
        }

        if ($backupData -and -not [string]::IsNullOrWhiteSpace([string]$backupData.DefaultPrinter)) {
            $defTarget = [string]$backupData.DefaultPrinter
            if ($selectedNames -contains $defTarget) {
                [void](Set-DefaultPrinterSafe -PrinterName $defTarget)
            }
        }

        $persistedSpecialDir = Join-Path $global:AsanCtx.WorkBaseDir 'LastSpecialSettings'
        $srcSpecDir = Join-Path $localTemp 'SpecialSettings'
        if (Test-Path -LiteralPath $srcSpecDir) {
            if (Test-Path -LiteralPath $persistedSpecialDir) { Remove-Item -LiteralPath $persistedSpecialDir -Recurse -Force -ErrorAction SilentlyContinue }
            if (-not (Test-Path -LiteralPath $persistedSpecialDir)) { New-Item -ItemType Directory -Path $persistedSpecialDir -Force -ErrorAction SilentlyContinue | Out-Null }
            foreach ($sfItem in @(Get-ChildItem -LiteralPath $srcSpecDir -Force -ErrorAction SilentlyContinue)) {
                Copy-Item -LiteralPath $sfItem.FullName -Destination $persistedSpecialDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 100 -Message '복원 파이프라인 완료!'
        return [pscustomobject]@{
            Success            = $true
            BlockedByWpp       = $false
            WppInfo            = $wppCheck
            RestoreLog         = $restoreLog.ToArray()
            Failures           = $failures.ToArray()
            AuthFailedHosts    = $authHosts.ToArray()
            DetectedSpecials   = $detectedSpecials.ToArray()
            SamFallbackNames   = $samFallbackList.ToArray()
            ZtManualPrefsNames = $ztManualPrefsList.ToArray()
            RestoredScanCount  = $restoredScanCnt
            NeedsUsbReplug     = $needsUsbReplug
        }
    }
    finally {
        if (Test-Path -LiteralPath $localTemp) {
            Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
