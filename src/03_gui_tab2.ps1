# ============================================================================
# [Module 03] 탭 2 (복원 - Win 11 / 지연 검증 / SID·특수장비 도우미) 최종본
# - Module 02(공용 GUI 셸 + 탭 1) 하단에 무손실 결합됨
# - 3-5B 패치 반영: C1, C2, C3, C4, H1, H4, H5
# ============================================================================
$script:Tab2Ui = @{
    CmbServerBackups   = $null
    ComboBackupEntries = @()
    BtnLoadServer      = $null
    BtnOpenZip         = $null
    BtnRunDeferred     = $null
    LblSourceInfo      = $null
    TxtNotes           = $null
    BtnSelAll          = $null
    BtnSelHealthy      = $null
    BtnSelNone         = $null
    LblGridSummary     = $null
    BtnToggleHelper    = $null
    DgvRestore         = $null
    PnlHelper          = $null
    TabHelper          = $null
    TpAuth             = $null
    TpSpecial          = $null
    CmbAuthHost        = $null
    TxtAuthUser        = $null
    TxtAuthPass        = $null
    BtnAuthRetry       = $null
    BtnSidReset        = $null
    TxtAuthInfo        = $null
    CmbSpecialList     = $null
    SpecialRows        = @()
    CurrentSpecInfo    = $null
    BtnSpecInstall     = $null
    BtnSpecStep2       = $null
    BtnUsbReenum       = $null
    BtnSpecFolder      = $null
    BtnSpecProps       = $null
    TxtSpecChecklist   = $null
    BtnStartRestore    = $null
    BtnRetryFailed     = $null
    LblRestoreHint     = $null
    LoadedSourcePath   = $null
    LastFailures       = @()
    HelperExpanded     = $false
}

# ============================================================================
# 탭 2 UI 렌더링 및 도우미 패널 제어 헬퍼
# ============================================================================
function Set-Tab2HelperVisibility {
    param(
        [bool]$Expanded,
        [int]$SelectTabIndex = -1
    )
    $script:Tab2Ui.HelperExpanded = $Expanded
    if ($script:Tab2Ui.PnlHelper) {
        $script:Tab2Ui.PnlHelper.Visible = $Expanded
    }
    if ($script:Tab2Ui.BtnToggleHelper) {
        if ($Expanded) { $script:Tab2Ui.BtnToggleHelper.Text = '도우미 패널 접기 ▼' }
        else { $script:Tab2Ui.BtnToggleHelper.Text = '도우미 패널 펼치기 ▲' }
    }
    if ($Expanded -and $SelectTabIndex -ge 0 -and $script:Tab2Ui.TabHelper -and $SelectTabIndex -lt $script:Tab2Ui.TabHelper.TabPages.Count) {
        $script:Tab2Ui.TabHelper.SelectedIndex = $SelectTabIndex
    }
}

function Update-Tab2ServerDropdown {
    $cmb = $script:Tab2Ui.CmbServerBackups
    if (-not $cmb -or $cmb.IsDisposed) { return }

    $prevPath = $null
    if ($cmb.SelectedIndex -ge 0 -and $cmb.SelectedIndex -lt $script:Tab2Ui.ComboBackupEntries.Count) {
        $prevPath = $script:Tab2Ui.ComboBackupEntries[$cmb.SelectedIndex].FullPath
    }

    $sorted = @($script:AppState.ServerBackups | Sort-Object MatchRank, @{ Expression = { $_.LastWriteTime }; Descending = $true })
    $script:Tab2Ui.ComboBackupEntries = $sorted

    $cmb.BeginUpdate()
    try {
        $cmb.Items.Clear()
        $selIdx = -1
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $e      = $sorted[$i]
            $prefix = ''
            if ($e.MatchRank -eq 1) { $prefix = '[자동매칭★] ' }
            elseif ($e.IsMatched)   { $prefix = '[유사매칭] ' }

            $dtStr = $e.LastWriteTime.ToString('MM-dd HH:mm')
            $label = "$prefix$($e.Name)  ($dtStr)"
            [void]$cmb.Items.Add($label)

            if ($prevPath -and $e.FullPath -ieq $prevPath) { $selIdx = $i }
        }
        if ($selIdx -lt 0 -and $sorted.Count -gt 0) { $selIdx = 0 }
        if ($selIdx -ge 0) { $cmb.SelectedIndex = $selIdx }
    }
    finally {
        $cmb.EndUpdate()
    }

    Sync-AllUiButtonStates
}

function Render-Tab2NotesBanner {
    param(
        [object[]]$BackupNotes = @(),
        [string[]]$ExtraWarnings = @()
    )
    $txt = $script:Tab2Ui.TxtNotes
    if (-not $txt -or $txt.IsDisposed) { return }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($w in @($ExtraWarnings)) {
        if (-not [string]::IsNullOrWhiteSpace($w)) { $lines.Add($w) }
    }
    foreach ($n in @($BackupNotes)) {
        if ($null -eq $n) { continue }
        $lvl = [string]$n.Level
        $tgt = [string]$n.Target
        $msg = [string]$n.Message
        if ([string]::IsNullOrWhiteSpace($lvl) -and [string]::IsNullOrWhiteSpace($tgt) -and [string]::IsNullOrWhiteSpace($msg)) { continue }
        $lines.Add("[$lvl] $tgt`: $msg")
    }

    if ($lines.Count -eq 0) {
        $txt.BackColor = [System.Drawing.Color]::FromArgb(240, 253, 244)
        $txt.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
        $txt.Text      = '백업 시점 특이사항 없음 — 모든 프린터가 정상 상태로 기록되어 있습니다.'
    } else {
        $txt.BackColor = [System.Drawing.Color]::FromArgb(255, 251, 235)
        $txt.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
        $txt.Text      = ($lines -join "`r`n")
    }
}

function Update-Tab2GridSummary {
    $dgv = $script:Tab2Ui.DgvRestore
    if (-not $dgv -or $dgv.IsDisposed) { return }
    $total = $dgv.Rows.Count
    $sel   = 0
    foreach ($r in $dgv.Rows) {
        if ($r.Cells[0].Value -eq $true) { $sel++ }
    }
    $script:Tab2Ui.LblGridSummary.Text = "복원 대상 선택: ${sel} / ${total}대"
    Sync-AllUiButtonStates
}

function Render-Tab2RestoreGrid {
    $dgv = $script:Tab2Ui.DgvRestore
    if (-not $dgv -or $dgv.IsDisposed) { return }

    $dgv.SuspendLayout()
    try {
        $dgv.Rows.Clear()
        $rows = @($script:AppState.RestoreRows)

        foreach ($p in $rows) {
            $defMark = ''
            if ($p.IsDefault) { $defMark = '★' }

            $portDisp = [string]$p.PortName
            if ($p.PortKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$p.WsdTargetIp)) {
                $targetTxt = [string]$p.WsdTargetIp
                if ($p.WsdTargetMode -eq 'LOCAL_UNC' -and -not [string]::IsNullOrWhiteSpace([string]$p.WsdTargetShare)) {
                    $targetTxt = [string]$p.WsdTargetShare
                }
                $portDisp = "WSD -> $targetTxt"
            }

            $isLockedSpec = ($p.SpecialType -in @('SEWOO_TE201', 'EPSON_TMT88_LPT'))
            $checkInit    = [bool]$p.Selected
            if ($isLockedSpec) { $checkInit = $false }

            $rIdx = $dgv.Rows.Add(
                $checkInit,
                $defMark,
                [string]$p.StatusText,
                [string]$p.Category,
                [string]$p.PrinterName,
                $portDisp,
                [string]$p.DriverName,
                [string]$p.Reason
            )
            $gridRow     = $dgv.Rows[$rIdx]
            $gridRow.Tag = $p

            # [H4 Fix] Win 11 전용 설치(세우테크) 및 LPT1 무드라이버(EPSON TM-T88) 체크박스 셀 잠금
            if ($isLockedSpec) {
                $gridRow.Cells[0].ReadOnly          = $true
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
            } elseif ($p.SpecialType -ne 'STANDARD') {
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(243, 232, 255)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(88, 28, 135)
            } elseif ($p.StatusCode -eq 'WsdConvert') {
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
            } elseif ($p.StatusCode -eq 'AuthOrSidConflict') {
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
            } elseif ($p.StatusCode -in @('SuspectedInactive', 'Ambiguous', 'OfflineUnverified')) {
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
            } else {
                $gridRow.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
                $gridRow.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
            }
        }
    }
    finally {
        $dgv.ResumeLayout()
    }
    Update-Tab2GridSummary
}

function Sync-Tab2GridSelectionToState {
    $dgv = $script:Tab2Ui.DgvRestore
    if (-not $dgv -or $dgv.IsDisposed) { return }
    $dgv.EndEdit() | Out-Null
    foreach ($r in $dgv.Rows) {
        if ($r.Tag) {
            if ($r.Tag.SpecialType -in @('SEWOO_TE201', 'EPSON_TMT88_LPT')) {
                $r.Tag.Selected = $false
            } else {
                $r.Tag.Selected = ($r.Cells[0].Value -eq $true)
            }
        }
    }
}

# ============================================================================
# 인라인 공유 호스트 인증 / 동일 SID 조치 패널 갱신
# ============================================================================
function Update-Tab2AuthPanel {
    $hosts = @($script:AppState.AuthFailedHosts)
    $script:Tab2Ui.TpAuth.Text = " 공유 인증 / SID 조치 ($($hosts.Count)건) "

    $cmb = $script:Tab2Ui.CmbAuthHost
    $cmb.BeginUpdate()
    try {
        $prevText = $cmb.Text
        $cmb.Items.Clear()
        foreach ($h in $hosts) {
            [void]$cmb.Items.Add([string]$h.HostName)
        }
        if ($hosts.Count -gt 0) {
            $cmb.SelectedIndex = 0
        } elseif (-not [string]::IsNullOrWhiteSpace($prevText)) {
            $cmb.Text = $prevText
        }
    }
    finally {
        $cmb.EndUpdate()
    }

    if ($hosts.Count -gt 0) {
        $first = $hosts[0]
        $mySid = $script:AppState.LocalSid
        $script:Tab2Ui.TxtAuthInfo.Text = @(
            "[인증/SID 충돌 의심 호스트: $($first.HostName)] $($first.Reason)",
            "• 1단계: 메인 PC 로그인 암호가 변경된 경우 위 칸에 ID/암호를 입력하고 [재인증 및 검증]을 누르세요.",
            "• 2단계: 암호가 맞는데도 거부되면 골든 이미지 동일 SID 충돌입니다. (내 PC SID: $mySid)",
            "         메인 PC에서도 본 도구를 열어 상단 SID를 대조한 뒤, 메인 PC SID 변경/스풀러 초기화 후 [스풀러·자격증명 초기화 후 재연결]을 누르세요."
        ) -join "`r`n"
    } else {
        $script:Tab2Ui.TxtAuthInfo.Text = "인증 실패 또는 SID 충돌이 감지된 공유 호스트가 없습니다. (특정 호스트 IP를 직접 입력해 수동 재인증/스풀러 초기화도 가능합니다.)"
    }
}

# ============================================================================
# 특수 프린터 4종 반자동 도우미 패널 갱신
# ============================================================================
function Update-Tab2SpecialSelection {
    $cmb  = $script:Tab2Ui.CmbSpecialList
    $rows = @($script:Tab2Ui.SpecialRows)
    if (-not $cmb -or $cmb.SelectedIndex -lt 0 -or $cmb.SelectedIndex -ge $rows.Count) {
        $script:Tab2Ui.CurrentSpecInfo        = $null
        $script:Tab2Ui.TxtSpecChecklist.Text  = '감지된 특수/라벨 프린터가 없습니다.'
        $script:Tab2Ui.BtnSpecInstall.Enabled = $false
        $script:Tab2Ui.BtnSpecFolder.Enabled  = $false
        $script:Tab2Ui.BtnSpecProps.Enabled   = $false
        Sync-AllUiButtonStates
        return
    }

    $selRow = $rows[$cmb.SelectedIndex]
    $info   = Get-SpecialPrinterAssistantInfo -SpecialRow $selRow
    $script:Tab2Ui.CurrentSpecInfo = [pscustomobject]@{
        Row  = $selRow
        Info = $info
    }

    $script:Tab2Ui.TxtSpecChecklist.Text = $info.Checklist

    $hasExe    = ($info.Installer -and $info.Installer.Found -and -not [string]::IsNullOrWhiteSpace([string]$info.Installer.ExePath))
    $hasFolder = ($info.Installer -and $info.Installer.Found -and -not [string]::IsNullOrWhiteSpace([string]$info.Installer.Folder))

    $script:Tab2Ui.BtnSpecInstall.Enabled = $hasExe
    $script:Tab2Ui.BtnSpecFolder.Enabled  = $hasFolder
    $script:Tab2Ui.BtnSpecProps.Enabled   = $true

    if ($selRow.SpecialType -eq 'SEWOO_TE201') {
        $script:Tab2Ui.BtnSpecInstall.Text = '1단계: Win11 전용 설치 실행'
    } elseif ($selRow.SpecialType -eq 'SIP30M_IDCARD') {
        $script:Tab2Ui.BtnSpecInstall.Text = '1단계: sip30inst 설치 실행'
    } elseif ($selRow.SpecialType -eq 'ZEBRA_ZT411') {
        $script:Tab2Ui.BtnSpecInstall.Text = 'ZT411 드라이버 셋업 실행'
    } else {
        $script:Tab2Ui.BtnSpecInstall.Text = '전용 설치 파일 실행'
    }

    Sync-AllUiButtonStates
}

function Update-Tab2SpecialPanel {
    $specRows = @($script:AppState.RestoreRows | Where-Object { $_.SpecialType -ne 'STANDARD' })
    $script:Tab2Ui.SpecialRows    = $specRows
    $script:Tab2Ui.TpSpecial.Text = " 특수 프린터 도우미 ($($specRows.Count)건) "

    $cmb = $script:Tab2Ui.CmbSpecialList
    $cmb.BeginUpdate()
    try {
        $cmb.Items.Clear()
        foreach ($sr in $specRows) {
            [void]$cmb.Items.Add("[$($sr.Category)] $($sr.PrinterName)  ($($sr.PortName))")
        }
        if ($specRows.Count -gt 0) { $cmb.SelectedIndex = 0 }
    }
    finally {
        $cmb.EndUpdate()
    }
    Update-Tab2SpecialSelection
}

# ============================================================================
# [공개 진입점] 백업 소스 로드 및 지연 검증 (탭 2 자체 및 탭 4에서 공용 호출)
# ============================================================================
function Load-Tab2BackupSourceAsync {
    param(
        [string]$SourcePath,
        [switch]$ForceLiveProbe
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show("백업 경로를 찾을 수 없습니다:`r`n$SourcePath", '로드 실패', 'OK', 'Warning') | Out-Null
        return
    }

    $net       = $script:AppState.NetworkInfo
    $isOnline  = ($null -ne $net -and $net.Status -ne 'Offline')
    $forceFlag = [bool]$ForceLiveProbe

    $work = {
        param($arg)
        Write-ProgressSafe -Percent 15 -Message "백업 메타데이터 읽는 중: $($arg.SourcePath)"
        $meta = Read-BackupSourceMetadata -SourcePath ([string]$arg.SourcePath)
        if (-not $meta -or -not $meta.Data) {
            throw '선택한 위치에서 유효한 PrinterBackup.json 파일을 찾지 못했습니다.'
        }

        $shouldProbe = ([bool]$arg.ForceProbe) -or ([bool]$arg.IsOnline -and [bool]$meta.Data.IsOfflineBackup)
        if ($shouldProbe) {
            Write-ProgressSafe -Percent 30 -Message '새 PC(온라인) 환경에서 포트·공유 3종 인증·WSD 지연 검증 수행 중...'
        } else {
            Write-ProgressSafe -Percent 60 -Message '백업 프린터 목록 및 영속 리포트 구성 중...'
        }

        $deferred  = Test-BackupDataDeferred -BackupData $meta.Data -RunLiveProbe:$shouldProbe
        $localLpts = @(Get-DeviceManagerLptPorts)
        Write-ProgressSafe -Percent 100 -Message "백업 로드 완료 (대상 $($deferred.Printers.Count)대)"

        return [pscustomobject]@{
            Meta         = $meta
            Deferred     = $deferred
            LocalLpts    = $localLpts
            DidLiveProbe = $shouldProbe
        }
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "백업 로드 실패: $err" -Level 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("백업을 불러오지 못했습니다:`r`n$err", '불러오기 오류', 'OK', 'Error') | Out-Null
            return
        }

        $meta = $data.Meta
        $bd   = $meta.Data
        $script:AppState.CurrentBackupMeta = $meta
        $script:AppState.RestoreRows       = @($data.Deferred.Printers)
        $script:AppState.AuthFailedHosts   = @($data.Deferred.AuthFailedHosts)
        $script:Tab2Ui.LoadedSourcePath    = $meta.SourcePath
        $script:Tab2Ui.LastFailures        = @()

        $brmTxt = 'PrintBrm 없음'
        if ($meta.HasBrm) { $brmTxt = 'PrintBrm 포함' }
        $modeTxt = '서버 백업'
        if ($meta.IsZip) { $modeTxt = '오프라인 ZIP' }
        $probeTxt = ''
        if ($data.DidLiveProbe) { $probeTxt = ' | 지연 검증 완료' }

        $script:Tab2Ui.LblSourceInfo.Text = "[$modeTxt] 원본: $($bd.SourceComputer) ($($bd.SourceIP)) | 일시: $($bd.ExportedAt) | $brmTxt$probeTxt"

        $extraWarns = [System.Collections.Generic.List[string]]::new()
        if ($bd.SourceMachineSID -and $script:AppState.LocalSid -and ($bd.SourceMachineSID -eq $script:AppState.LocalSid)) {
            $extraWarns.Add("[참고] 원본 PC와 현재 새 PC의 Machine SID가 동일합니다 ($($bd.SourceMachineSID)).")
        }
        $bakLpts = @()
        if ($bd.PSObject.Properties.Name -contains 'LptPorts' -and $bd.LptPorts) {
            $bakLpts = @($bd.LptPorts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        $hasTmT88 = (@($script:AppState.RestoreRows | Where-Object { $_.SpecialType -eq 'EPSON_TMT88_LPT' })).Count -gt 0
        if ($bakLpts.Count -gt 0 -or $hasTmT88) {
            $nowLpts   = @($data.LocalLpts)
            $lpt1Now   = $nowLpts | Where-Object { $_.PortName -ieq 'LPT1' } | Select-Object -First 1
            $otherLpts = @($nowLpts | Where-Object { $_.PortName -ine 'LPT1' })
            if ($lpt1Now -and $lpt1Now.IsHealthy) {
                $extraWarns.Add("[LPT1 확인 완료] 현재 새 PC 장치관리자에서 LPT1 정상 감지됨 ($($lpt1Now.Name)) — EPSON TM-T88VI 등 무드라이버 장비는 드라이버·에이전트 설치 없이 AMIS에서 직접 사용하세요.")
            } elseif ($lpt1Now) {
                $extraWarns.Add("[LPT1 주의] 현재 새 PC 장치관리자 LPT1 상태 이상 ($($lpt1Now.Name) / Status=$($lpt1Now.Status)) — 장치관리자에서 LPT1 포트 상태를 확인하세요.")
            } elseif ($otherLpts.Count -gt 0) {
                $otherDesc = ($otherLpts | ForEach-Object { "$($_.PortName)($($_.Name))" }) -join ', '
                $extraWarns.Add("[LPT1 번호 변경 필요] LPT1은 미감지이나 타 LPT 포트($otherDesc)가 감지되었습니다 — 장치관리자 포트 설정에서 LPT1으로 변경하세요.")
            } else {
                $extraWarns.Add("[LPT1 미감지 주의] 구 PC에 LPT 포트($($bakLpts -join ', '))가 있었으나 현재 새 PC 장치관리자에서 LPT1이 감지되지 않습니다 — LPT 케이블/PCIe 포트 장착 여부를 확인하세요.")
            }
        }
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            $extraWarns.Add("[주의] 공유 호스트 $($script:AppState.AuthFailedHosts.Count)곳 인증/SID 충돌 감지 — 하단 [공유 인증/SID 조치] 탭에서 확인하세요.")
        }

        Render-Tab2NotesBanner -BackupNotes @($bd.BackupNotes) -ExtraWarnings $extraWarns.ToArray()
        Render-Tab2RestoreGrid
        Update-Tab2AuthPanel
        Update-Tab2SpecialPanel

        $manualSpecs = @($script:Tab2Ui.SpecialRows | Where-Object { -not ($_.SpecialType -eq 'ZEBRA_ZT411' -and $_.PortKind -eq 'TCPIP') })
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            Set-Tab2HelperVisibility -Expanded $true -SelectTabIndex 0
        } elseif ($manualSpecs.Count -gt 0) {
            Set-Tab2HelperVisibility -Expanded $true -SelectTabIndex 1
        } else {
            Set-Tab2HelperVisibility -Expanded $false
        }
        Sync-AllUiButtonStates
    }

    $tParams = @{
        SourcePath = $SourcePath
        ForceProbe = $forceFlag
        IsOnline   = $isOnline
    }
    Invoke-AsanAsyncTask -TaskName '백업 데이터 로드 및 지연 검증' -WorkScript $work -Params $tParams -OnComplete $done
}

# ============================================================================
# 복원 실행 및 [H1 Fix] 실패 항목 전용 정밀 재시도 (-SkipPrintBrm)
# ============================================================================
function Start-Tab2RestoreExecution {
    param([switch]$RetryFailedOnly)

    if ([string]::IsNullOrWhiteSpace($script:Tab2Ui.LoadedSourcePath)) {
        [System.Windows.Forms.MessageBox]::Show('먼저 서버 백업 또는 오프라인 ZIP 파일을 불러오세요.', '백업 미선택', 'OK', 'Warning') | Out-Null
        return
    }

    # WPP 사전 차단 및 조치 안내 팝업
    $wpp = $null
    if ($script:AppState.NetworkInfo) { $wpp = $script:AppState.NetworkInfo.WppStatus }
    if ($wpp -and $wpp.IsEnabled) {
        Show-WppRemediationDialog -WppStatus $wpp
        Add-UiLog -Message 'Windows 보호 인쇄 모드(WPP) 활성화로 인해 복원이 중단되었습니다. 해제 후 F5를 누르세요.' -Level 'WARN'
        return
    }

    Sync-Tab2GridSelectionToState
    $allRows       = @($script:AppState.RestoreRows)
    $rowsToRestore = $allRows
    $skipBrmFlag   = $false

    # [H1 Fix] 실패 항목 재시도 시 실패 행만 추려 PrintBrm 전체 덮어쓰기 생략
    if ($RetryFailedOnly) {
        if ($script:Tab2Ui.LastFailures.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('재시도할 실패 항목이 없습니다.', '재시도 대상 없음', 'OK', 'Information') | Out-Null
            return
        }
        $failedNames   = @($script:Tab2Ui.LastFailures | ForEach-Object { [string]$_.PrinterName })
        $rowsToRestore = @($allRows | Where-Object { $failedNames -contains [string]$_.PrinterName })
        foreach ($r in $rowsToRestore) {
            if ($r.SpecialType -notin @('SEWOO_TE201', 'EPSON_TMT88_LPT')) { $r.Selected = $true }
        }
        $skipBrmFlag = $true
        Render-Tab2RestoreGrid
    }

    $selectedCount = (@($rowsToRestore | Where-Object { $_.Selected })).Count
    if ($selectedCount -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('복원할 프린터를 1대 이상 선택하세요.', '선택 없음', 'OK', 'Warning') | Out-Null
        return
    }

    $pcIp = 'NO_IP'
    if ($script:AppState.NetworkInfo) { $pcIp = [string]$script:AppState.NetworkInfo.IPAddress }

    # 비동기 Runspace 전달 전 스냅샷 복사(크로스 스레드 Selected 변이 차단)
    $rowSnapshots = [System.Collections.Generic.List[object]]::new()
    foreach ($origRow in @($rowsToRestore)) {
        if ($null -eq $origRow) { continue }
        $rowSnapshots.Add([pscustomobject]@{
            Selected       = [bool]$origRow.Selected
            StatusCode     = [string]$origRow.StatusCode
            StatusText     = [string]$origRow.StatusText
            Category       = [string]$origRow.Category
            SpecialType    = [string]$origRow.SpecialType
            PrinterName    = [string]$origRow.PrinterName
            DriverName     = [string]$origRow.DriverName
            PortName       = [string]$origRow.PortName
            PortKind       = [string]$origRow.PortKind
            HostAddress    = $origRow.HostAddress
            ConnectionName = $origRow.ConnectionName
            WsdTargetIp    = $origRow.WsdTargetIp
            WsdModelName   = $origRow.WsdModelName
            WsdTargetMode  = $origRow.WsdTargetMode
            WsdTargetShare = $origRow.WsdTargetShare
            SpecialDatFile = $origRow.SpecialDatFile
            SpecialRegFile = $origRow.SpecialRegFile
            IsDefault      = [bool]$origRow.IsDefault
            Reason         = [string]$origRow.Reason
        })
    }

    $tParams = @{
        SourcePath   = $script:Tab2Ui.LoadedSourcePath
        SelectedRows = $rowSnapshots.ToArray()
        PcIp         = $pcIp
        SkipPrintBrm = $skipBrmFlag
    }

    $work = {
        param($arg)
        $skipBrm = [bool]$arg.SkipPrintBrm
        return (Invoke-PrinterRestoreEngine `
            -SourcePath ([string]$arg.SourcePath) `
            -SelectedRows @($arg.SelectedRows) `
            -PcIp ([string]$arg.PcIp) `
            -SkipPrintBrm:$skipBrm)
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "복원 엔진 오류: $err" -Level 'ERROR'
            $repAns = [System.Windows.Forms.MessageBox]::Show(
                "복원 중 오류가 발생했습니다:`r`n$err`r`n`r`n이 오류 내용을 서버 리포트함(_PRTBAK\_REPORTS)으로 전송하시겠습니까?",
                '복원 오류',
                'YesNo',
                'Error'
            )
            if ($repAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                Show-BugReportDialog -DefaultCategory '복원/드라이버 오류' -ErrorSummary ([string]$err)
            }
            return
        }

        if ($data.BlockedByWpp) {
            if ($data.WppInfo) {
                if ($script:AppState.NetworkInfo) { $script:AppState.NetworkInfo.WppStatus = $data.WppInfo }
                Update-HeaderAndWppUi
                Show-WppRemediationDialog -WppStatus $data.WppInfo
            }
            return
        }

        foreach ($entry in @($data.RestoreLog)) {
            Add-UiLog -Message "[$($entry.Target)] $($entry.Message)" -Level ([string]$entry.Level).ToUpperInvariant()
        }

        $script:Tab2Ui.LastFailures      = @($data.Failures)
        $script:AppState.AuthFailedHosts = @($data.AuthFailedHosts)

        $extra   = [System.Collections.Generic.List[string]]::new()
        $samList = @($data.SamFallbackNames)
        if ($samList.Count -gt 0) {
            $extra.Add("[중요 경고] 삼성 범용 드라이버(UPD 3) 사용 프린터: $($samList -join ', ') — 테스트 페이지 오류 시 모델 전용 드라이버 교체 및 장치설정(PCL6) 필요!")
        }
        foreach ($f in @($data.Failures)) {
            $extra.Add("[복원 실패] $($f.PrinterName) ($($f.PortName)): $($f.Reason)")
        }

        if ($data.NeedsUsbReplug) {
            $extra.Add('[USB 재연결 필요] USB 바코드 소프트웨어 자동 재인식을 시도했으나 USB 포트가 미생성되었습니다 — USB 케이블을 1회 뽑았다 다시 꽂은 뒤 [실패 항목만 재시도]를 누르세요.')
        }
        $origNotes = @()
        if ($script:AppState.CurrentBackupMeta -and $script:AppState.CurrentBackupMeta.Data) {
            $origNotes = @($script:AppState.CurrentBackupMeta.Data.BackupNotes)
        }
        Render-Tab2NotesBanner -BackupNotes $origNotes -ExtraWarnings $extra.ToArray()
        Update-Tab2AuthPanel
        Update-Tab2SpecialPanel

        $manualSpecs = @($script:Tab2Ui.SpecialRows | Where-Object { -not ($_.SpecialType -eq 'ZEBRA_ZT411' -and $_.PortKind -eq 'TCPIP') })
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            Set-Tab2HelperVisibility -Expanded $true -SelectTabIndex 0
        } elseif ($manualSpecs.Count -gt 0 -or $data.NeedsUsbReplug) {
            Set-Tab2HelperVisibility -Expanded $true -SelectTabIndex 1
        }
        Sync-AllUiButtonStates

        foreach ($cb in $script:Ui.OnRestoreCompleted) {
            try { & $cb } catch {}
        }

        $succCnt = (@($data.RestoreLog | Where-Object { $_.Level -eq 'Success' })).Count
        $failCnt = (@($data.Failures)).Count
        $specCnt = (@($script:Tab2Ui.SpecialRows)).Count

        $sumLines = [System.Collections.Generic.List[string]]::new()
        $sumLines.Add("프린터 및 드라이버 복원이 완료되었습니다.")
        $sumLines.Add("")
        $sumLines.Add("• 복원 성공 항목 : ${succCnt}건 (WIA 스캐너 $($data.RestoredScanCount)개)")
        $sumLines.Add("• 복원 실패 항목 : ${failCnt}건")
        $sumLines.Add("• 감지된 특수장비: ${specCnt}대 (하단 특수 프린터 도우미 확인)")

        if ($data.NeedsUsbReplug) {
            $sumLines.Add("")
            $sumLines.Add("[USB 바코드 재연결 안내]")
            $sumLines.Add("-> 소프트웨어 자동 재인식을 시도했으나 USB 포트가 미생성되었습니다. USB 케이블을 1회 뽑았다 다시 꽂은 뒤 [실패 항목만 재시도]를 눌러주세요.")
        }
        if ($samList.Count -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("[삼성 범용 드라이버(UPD 3) 주의]")
            $sumLines.Add("대상: $($samList -join ', ')")
            $sumLines.Add("-> [3. 검증/테스트] 탭에서 테스트 페이지 출력 후 오류 발생 시 모델 전용 드라이버로 교체하세요.")
        }
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("[공유 호스트 인증 / 동일 SID 충돌 감지]")
            $sumLines.Add("-> 하단 [공유 인증/SID 조치] 탭에서 암호 재입력 또는 스풀러 초기화 후 [실패 항목만 재시도]를 누르세요.")
        }
        if ($failCnt -eq 0 -and $manualSpecs.Count -eq 0) {
            $sumLines.Add("")
            $sumLines.Add("[3. 검증/테스트] 탭으로 이동하여 일반 프린터 테스트 인쇄를 진행하세요.")
        }

        if ($failCnt -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("복원 실패 항목을 서버 리포트함(_PRTBAK\_REPORTS)으로 지금 전송하시겠습니까?")
            $repAns = [System.Windows.Forms.MessageBox]::Show(($sumLines -join "`r`n"), '복원 완료 요약 (일부 실패)', 'YesNo', 'Warning')
            if ($repAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                $firstFailPrt = [string](@($data.Failures)[0].PrinterName)
                $failSummary  = (@($data.Failures | ForEach-Object { "$($_.PrinterName) ($($_.PortName)): $($_.Reason)" }) -join "`r`n")
                Show-BugReportDialog -DefaultCategory '복원/드라이버 오류' -DefaultPrinter $firstFailPrt -ErrorSummary $failSummary
            }
        } else {
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
            if ($samList.Count -gt 0 -or $data.NeedsUsbReplug) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
            [System.Windows.Forms.MessageBox]::Show(($sumLines -join "`r`n"), '복원 완료 요약', 'OK', $icon) | Out-Null
        }
    }

    $taskTitle = '프린터/드라이버 선택 복원'
    if ($RetryFailedOnly) { $taskTitle = '실패 프린터 정밀 재시도 복원' }
    Invoke-AsanAsyncTask -TaskName $taskTitle -WorkScript $work -Params $tParams -OnComplete $done
}

# ============================================================================
# [H5 Fix] 인라인 인증 재시도 / SID 스풀러 초기화 (HostName 명시 반환)
# ============================================================================
function Invoke-Tab2HostAuthActionAsync {
    param([switch]$WithSpoolerReset)

    $hostName = $script:Tab2Ui.CmbAuthHost.Text.Trim()
    $userVal  = $script:Tab2Ui.TxtAuthUser.Text.Trim()
    $passVal  = $script:Tab2Ui.TxtAuthPass.Text

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        [System.Windows.Forms.MessageBox]::Show('조치할 공유 메인 PC의 IP 주소를 선택하거나 입력하세요.', '호스트 미입력', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $WithSpoolerReset -and [string]::IsNullOrWhiteSpace($userVal)) {
        [System.Windows.Forms.MessageBox]::Show('사용자 계정(예: admin)을 입력하세요.', '계정 미입력', 'OK', 'Warning') | Out-Null
        return
    }

    $tParams = @{
        HostName = $hostName
        UserName = $userVal
        Password = $passVal
        DoReset  = [bool]$WithSpoolerReset
    }

    $work = {
        param($arg)
        $h = [string]$arg.HostName
        $u = [string]$arg.UserName
        $p = [string]$arg.Password
        if ([bool]$arg.DoReset) {
            Write-ProgressSafe -Percent 30 -Message "호스트($h) 자격 증명·세션 삭제 및 클라이언트 Print Spooler 초기화 중..."
            $useU = $null
            $useP = $null
            if (-not [string]::IsNullOrWhiteSpace($p)) { $useU = $u; $useP = $p }
            $res = Reset-ClientSpoolerAndHostCred -HostName $h -CustomUser $useU -CustomPass $useP
            Write-ProgressSafe -Percent 100 -Message "초기화 및 재연결 시도 완료: $($res.Reason)"
            return [pscustomobject]@{ HostName = $h; AuthResult = $res }
        } else {
            Write-ProgressSafe -Percent 40 -Message "호스트($h) 계정($u)으로 재인증 시도 중..."
            $res = Connect-SharedHostSmart -HostName $h -CustomUser $u -CustomPass $p -ForceResetSession
            Write-ProgressSafe -Percent 100 -Message "재인증 결과: $($res.Reason)"
            return [pscustomobject]@{ HostName = $h; AuthResult = $res }
        }
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data -or -not $data.AuthResult) {
            Add-UiLog -Message "호스트 인증/초기화 오류: $err" -Level 'ERROR'
            return
        }

        $targetHost = [string]$data.HostName
        $authRes    = $data.AuthResult

        if ($authRes.Success) {
            $remaining = @($script:AppState.AuthFailedHosts | Where-Object { $_.HostName -ine $targetHost })
            $script:AppState.AuthFailedHosts = $remaining

            foreach ($r in @($script:AppState.RestoreRows)) {
                $pStr = [string]$r.PortName
                $cStr = [string]$r.ConnectionName
                $wStr = [string]$r.WsdTargetShare
                if (($pStr -like "\\$targetHost\*") -or ($cStr -like "\\$targetHost\*") -or ($wStr -like "\\$targetHost\*")) {
                    if ($r.StatusCode -eq 'AuthOrSidConflict') {
                        $r.StatusCode = 'Healthy'
                        $r.StatusText = '재인증성공'
                        if ($r.SpecialType -notin @('SEWOO_TE201', 'EPSON_TMT88_LPT')) { $r.Selected = $true }
                        $r.Reason     = "사용자 재인증 성공 ($($authRes.UsedUser)) — 복원 가능"
                    }
                }
            }
            Render-Tab2RestoreGrid
            Update-Tab2AuthPanel

            [System.Windows.Forms.MessageBox]::Show(
                "호스트($targetHost) 인증에 성공했습니다! ($($authRes.Reason))`r`n`r`n이제 [실패 항목만 재시도] 또는 [선택 항목 복원 시작] 버튼을 눌러 복원을 완료하세요.",
                '공유 호스트 인증 성공',
                'OK',
                'Information'
            ) | Out-Null
        } else {
            $mySid = $script:AppState.LocalSid
            $script:Tab2Ui.TxtAuthInfo.Text = @(
                "[재시도 실패 — 동일 Windows SID 충돌 강력 의심] $($authRes.Reason)",
                "• 현재 작업 중인 PC의 Machine SID: $mySid",
                "• 조치 절차: 1) 메인 PC($targetHost)에서 SID 변경 및 스풀러 초기화 진행",
                "             2) 완료 후 이 화면의 [스풀러·자격증명 초기화 후 재연결] 버튼 클릭"
            ) -join "`r`n"
            [System.Windows.Forms.MessageBox]::Show(
                "호스트($targetHost) 연결이 여전히 거부되었습니다.`r`n$($authRes.Reason)`r`n`r`n비밀번호가 확실히 맞다면 메인 PC와 동일 Windows SID 충돌 상태입니다.`r`n메인 PC SID 작업 후 [스풀러·자격증명 초기화 후 재연결]을 실행하세요.",
                '인증 실패 / SID 충돌 의심',
                'OK',
                'Warning'
            ) | Out-Null
        }
    }

    $title = "공유 호스트($hostName) 재인증"
    if ($WithSpoolerReset) { $title = "클라이언트 스풀러 초기화 및 호스트($hostName) 재연결" }
    Invoke-AsanAsyncTask -TaskName $title -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
}

# [C1 Fix] DialogResult + AcceptButton/CancelButton 사용 (로컬 $dlg 클로저 소실 제거)
function Show-SimpleIpPromptDialog {
    param([string]$DefaultIp = '')
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'SIP-30M 대상 IP 입력'
    $dlg.Size            = New-Object System.Drawing.Size(370, 160)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.Font            = $script:FontBase
    $dlg.Padding         = New-Object System.Windows.Forms.Padding(14)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text   = '진료카드 발급기(SIP-30M)의 TCP/IP 주소를 입력하세요:'
    $lbl.Dock   = [System.Windows.Forms.DockStyle]::Top
    $lbl.Height = 24

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text   = $DefaultIp
    $tb.Dock   = [System.Windows.Forms.DockStyle]::Top
    $tb.Height = 26

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 38
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $flpRight = New-RightFlowStrip -TopPadding 0 -RightPadding 0

    $btnCan = New-StyledButton -Text '취소' -Width 84 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(100, 116, 139))
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCan.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnOk = New-StyledButton -Text '확인' -Width 84 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235))
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $flpRight.Controls.Add($btnCan)
    $flpRight.Controls.Add($btnOk)
    $pnlBot.Controls.Add($flpRight)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCan
    $dlg.Controls.Add($pnlBot)
    $dlg.Controls.Add($tb)
    $dlg.Controls.Add($lbl)

    $outIp = $null
    if ($dlg.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $outIp = $tb.Text.Trim()
    }
    $dlg.Dispose()
    return $outIp
}

function Invoke-Tab2Sip30mStep2Async {
    $cur = $script:Tab2Ui.CurrentSpecInfo
    if (-not $cur -or $cur.Row.SpecialType -ne 'SIP30M_IDCARD') { return }

    $targetIp = [string]$cur.Info.TargetIp
    if ([string]::IsNullOrWhiteSpace($targetIp) -or $targetIp -eq '백업 IP') {
        $targetIp = Show-SimpleIpPromptDialog
        if ([string]::IsNullOrWhiteSpace($targetIp)) { return }
    }

    $tParams = @{
        TargetIp            = $targetIp
        OriginalPrinterName = [string]$cur.Row.PrinterName
        DatRelPath          = $cur.Row.SpecialDatFile
        RegRelPath          = $cur.Row.SpecialRegFile
        BackupSourcePath    = $script:Tab2Ui.LoadedSourcePath
    }

    $work = {
        param($arg)
        Write-ProgressSafe -Percent 30 -Message "SIP-30M TCP/IP 포트($($arg.TargetIp)), 이름(id카드) 및 4개 탭 설정 적용 중..."
        $res = Complete-Sip30mPostInstall `
            -TargetIp ([string]$arg.TargetIp) `
            -DesiredPrinterName 'id카드' `
            -OriginalPrinterName ([string]$arg.OriginalPrinterName) `
            -DatRelPath $arg.DatRelPath `
            -RegRelPath $arg.RegRelPath `
            -BackupSourcePath ([string]$arg.BackupSourcePath)
        Write-ProgressSafe -Percent 100 -Message $res.Message
        return $res
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "SIP-30M 2단계 마무리 오류: $err" -Level 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("SIP-30M 마무리 중 오류가 발생했습니다:`r`n$err", 'SIP-30M 오류', 'OK', 'Error') | Out-Null
            return
        }
        $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        if ($data.Success) {
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
            foreach ($cb in $script:Ui.OnRestoreCompleted) { try { & $cb } catch {} }
        }
        [System.Windows.Forms.MessageBox]::Show($data.Message, 'SIP-30M 2단계 마무리', 'OK', $icon) | Out-Null
    }

    Invoke-AsanAsyncTask -TaskName 'SIP-30M(id카드) 2단계 자동 마무리' -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
}

function Invoke-Tab2UsbReenumAsync {
    $work = {
        param($arg)
        Write-ProgressSafe -Percent 25 -Message 'USB 바코드 프린터 장치 검색 및 PnP 소프트웨어 재인식 실행 중...'
        $res = Invoke-UsbBarcodeAutoReenumerate -WaitSeconds 8 -ForceAllBarcodeUsb
        Write-ProgressSafe -Percent 100 -Message $res.Summary
        return $res
    }
    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "USB 바코드 재인식 오류: $err" -Level 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("USB 재인식 중 오류가 발생했습니다:`r`n$err", 'USB 재인식 오류', 'OK', 'Error') | Out-Null
            return
        }
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        if ($data.NeedsManualReplug) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
        foreach ($cb in $script:Ui.OnRestoreCompleted) { try { & $cb } catch {} }
        [System.Windows.Forms.MessageBox]::Show($data.Summary, 'USB 바코드 소프트웨어 재인식', 'OK', $icon) | Out-Null
    }
    Invoke-AsanAsyncTask -TaskName 'USB 바코드 소프트웨어 재인식' -WorkScript $work -OnComplete $done -Indeterminate
}

# ============================================================================
# [C2 + C4 + H4 Fix] 탭 2 컨트롤 배치 초기화 (Dock + RightFlowStrip 구조화)
# ============================================================================
function Initialize-Tab2RestoreUi {
    $parent = $script:Ui.TabRestore

    # ---------------- [1] 상단 백업 소스 선택 바 ----------------
    $pnlSource = New-Object System.Windows.Forms.Panel
    $pnlSource.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlSource.Height    = 64
    $pnlSource.BackColor = [System.Drawing.Color]::Transparent

    $lblSrc = New-Object System.Windows.Forms.Label
    $lblSrc.Text     = '서버 백업:'
    $lblSrc.Font     = $script:FontBold
    $lblSrc.AutoSize = $true
    $lblSrc.Location = New-Object System.Drawing.Point(2, 9)

    $cmbBackups = New-Object System.Windows.Forms.ComboBox
    $cmbBackups.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbBackups.Location      = New-Object System.Drawing.Point(72, 5)
    $cmbBackups.Size          = New-Object System.Drawing.Size(320, 24)
    $cmbBackups.Font          = $script:FontBase
    $script:Ui.BusyControls.Add($cmbBackups)

    $btnLoadSrv = New-StyledButton -Text '불러오기' -Width 80 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235)) -RegisterBusy
    $btnLoadSrv.Location = New-Object System.Drawing.Point(398, 4)
    $btnLoadSrv.Add_Click({
        $idx = $script:Tab2Ui.CmbServerBackups.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:Tab2Ui.ComboBackupEntries.Count) {
            Load-Tab2BackupSourceAsync -SourcePath $script:Tab2Ui.ComboBackupEntries[$idx].FullPath
        }
    })

    $btnOpenZip = New-StyledButton -Text '오프라인 ZIP 불러오기' -Width 160 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(15, 118, 110)) -RegisterBusy
    $btnOpenZip.Location = New-Object System.Drawing.Point(484, 4)
    $btnOpenZip.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title  = '오프라인 백업 ZIP 파일 선택 (로컬 또는 외장 SSD)'
        $ofd.Filter = 'ZIP 백업 파일 (*.zip)|*.zip|모든 파일 (*.*)|*.*'
        if (Test-Path -LiteralPath $global:AsanCtx.OfflineLocalRoot) {
            $ofd.InitialDirectory = $global:AsanCtx.OfflineLocalRoot
        }
        if ($ofd.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            Load-Tab2BackupSourceAsync -SourcePath $ofd.FileName
        }
        $ofd.Dispose()
    })

    $btnDeferred = New-StyledButton -Text '지연 검증 실행' -Width 116 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85)) -RegisterBusy
    $btnDeferred.Location = New-Object System.Drawing.Point(650, 4)
    $btnDeferred.Enabled  = $false
    $btnDeferred.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:Tab2Ui.LoadedSourcePath)) {
            Load-Tab2BackupSourceAsync -SourcePath $script:Tab2Ui.LoadedSourcePath -ForceLiveProbe
        }
    })

    $lblSourceInfo = New-Object System.Windows.Forms.Label
    $lblSourceInfo.Text      = '서버 백업을 선택하거나 [오프라인 ZIP 불러오기]로 복원 대상을 로드하세요.'
    $lblSourceInfo.Font      = $script:FontSmall
    $lblSourceInfo.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $lblSourceInfo.AutoSize  = $true
    $lblSourceInfo.Location  = New-Object System.Drawing.Point(2, 40)

    $pnlSource.Controls.AddRange(@($lblSrc, $cmbBackups, $btnLoadSrv, $btnOpenZip, $btnDeferred, $lblSourceInfo))

    # ---------------- [2] 영속 리포트(BackupNotes + 복원 경고) 배너 ----------------
    $pnlNotes = New-Object System.Windows.Forms.Panel
    $pnlNotes.Dock    = [System.Windows.Forms.DockStyle]::Top
    $pnlNotes.Height  = 66
    $pnlNotes.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

    $txtNotes = New-Object System.Windows.Forms.TextBox
    $txtNotes.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtNotes.Multiline   = $true
    $txtNotes.ReadOnly    = $true
    $txtNotes.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtNotes.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtNotes.BackColor   = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $txtNotes.ForeColor   = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $txtNotes.Font        = $script:FontSmall
    $txtNotes.Text        = '백업을 불러오면 백업 시점 특이사항(WSD·비활성의심·특수장비·TWAIN 등)이 여기에 고정 표시됩니다.'
    $pnlNotes.Controls.Add($txtNotes)

    # ---------------- [3] 그리드 선택 툴바 ([C2] RightFlowStrip 적용) ----------------
    $pnlGridBar = New-Object System.Windows.Forms.Panel
    $pnlGridBar.Dock   = [System.Windows.Forms.DockStyle]::Top
    $pnlGridBar.Height = 32

    $pnlGridLeft = New-Object System.Windows.Forms.Panel
    $pnlGridLeft.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlGridLeft.BackColor = [System.Drawing.Color]::Transparent

    $btnSelAll = New-StyledButton -Text '전체 선택' -Width 74 -Height 24 -BackColor ([System.Drawing.Color]::FromArgb(100, 116, 139)) -RegisterBusy
    $btnSelAll.Font     = $script:FontSmall
    $btnSelAll.Location = New-Object System.Drawing.Point(0, 2)
    $btnSelAll.Add_Click({
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) {
            if ($r.Tag -and $r.Tag.SpecialType -notin @('SEWOO_TE201', 'EPSON_TMT88_LPT')) { $r.Cells[0].Value = $true }
        }
        Sync-Tab2GridSelectionToState
        Update-Tab2GridSummary
    })

    $btnSelHealthy = New-StyledButton -Text '정상만 선택' -Width 88 -Height 24 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105)) -RegisterBusy
    $btnSelHealthy.Font     = $script:FontSmall
    $btnSelHealthy.Location = New-Object System.Drawing.Point(78, 2)
    $btnSelHealthy.Add_Click({
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) {
            if ($r.Tag) {
                $chkVal = ($r.Tag.StatusCode -ne 'SuspectedInactive' -and $r.Tag.SpecialType -notin @('SEWOO_TE201', 'EPSON_TMT88_LPT'))
                $r.Cells[0].Value = $chkVal
            }
        }
        Sync-Tab2GridSelectionToState
        Update-Tab2GridSummary
    })

    $btnSelNone = New-StyledButton -Text '선택 해제' -Width 74 -Height 24 -BackColor ([System.Drawing.Color]::FromArgb(148, 163, 184)) -RegisterBusy
    $btnSelNone.Font     = $script:FontSmall
    $btnSelNone.Location = New-Object System.Drawing.Point(170, 2)
    $btnSelNone.Add_Click({
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) { $r.Cells[0].Value = $false }
        Sync-Tab2GridSelectionToState
        Update-Tab2GridSummary
    })

    $lblGridSum = New-Object System.Windows.Forms.Label
    $lblGridSum.Text      = '복원 대상 선택: 0 / 0대'
    $lblGridSum.Font      = $script:FontBold
    $lblGridSum.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblGridSum.AutoSize  = $true
    $lblGridSum.Location  = New-Object System.Drawing.Point(258, 6)

    $pnlGridLeft.Controls.AddRange(@($btnSelAll, $btnSelHealthy, $btnSelNone, $lblGridSum))

    $flpGridRight = New-RightFlowStrip -TopPadding 2 -RightPadding 0
    $btnToggleHelper = New-StyledButton -Text '도우미 패널 펼치기 ▲' -Width 154 -Height 24 -BackColor ([System.Drawing.Color]::FromArgb(124, 58, 237))
    $btnToggleHelper.Font = $script:FontSmall
    $btnToggleHelper.Add_Click({
        Set-Tab2HelperVisibility -Expanded (-not $script:Tab2Ui.HelperExpanded)
    })
    $flpGridRight.Controls.Add($btnToggleHelper)

    $pnlGridBar.Controls.Add($pnlGridLeft)
    $pnlGridBar.Controls.Add($flpGridRight)

    # ---------------- [4] 중앙 선택 복원 그리드 ----------------
    $dgv = New-StyledGrid -AllowCheckEdit
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    $colChk = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colChk.Name       = 'Selected'
    $colChk.HeaderText = '복원'
    $colChk.Width      = 42
    [void]$dgv.Columns.Add($colChk)

    foreach ($cDef in @(
        @{ Name = 'Default';  Header = '기본';               Width = 40 },
        @{ Name = 'Status';   Header = '검증 상태';           Width = 108 },
        @{ Name = 'Category'; Header = '구분';               Width = 105 },
        @{ Name = 'Printer';  Header = '프린터 이름';         Width = 175 },
        @{ Name = 'Port';     Header = '포트 / 전환 대상';    Width = 165 },
        @{ Name = 'Driver';   Header = '백업 드라이버';       Width = 175 },
        @{ Name = 'Reason';   Header = '검증 및 상세 사유';   Width = 260 }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $cDef.Name
        $c.HeaderText = $cDef.Header
        $c.Width      = $cDef.Width
        $c.ReadOnly   = $true
        [void]$dgv.Columns.Add($c)
    }

    $dgv.Add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty) {
            [void]$sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })
    $dgv.Add_CellValueChanged({
        param($sender, $e)
        if ($e.ColumnIndex -eq 0 -and $e.RowIndex -ge 0) {
            Sync-Tab2GridSelectionToState
            Update-Tab2GridSummary
        }
    })

    # ---------------- [5] 하단 접이식 2탭 도우미 패널 ([C2] TopBar + Fill 구조) ----------------
    $pnlHelper = New-Object System.Windows.Forms.Panel
    $pnlHelper.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlHelper.Height  = 152
    $pnlHelper.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $pnlHelper.Visible = $false

    $tabHelper = New-Object System.Windows.Forms.TabControl
    $tabHelper.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabHelper.Font = $script:FontBold

    # -- [5-A] 공유 인증 / 동일 SID 조치 탭 --
    $tpAuth = New-Object System.Windows.Forms.TabPage(' 공유 인증 / SID 조치 (0건) ')
    $tpAuth.BackColor = [System.Drawing.Color]::FromArgb(254, 242, 242)
    $tpAuth.Font      = $script:FontBase
    $tpAuth.Padding   = New-Object System.Windows.Forms.Padding(6)

    $pnlAuthTop = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlAuthTop.Dock          = [System.Windows.Forms.DockStyle]::Top
    $pnlAuthTop.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlAuthTop.WrapContents  = $true
    $pnlAuthTop.AutoSize      = $true
    $pnlAuthTop.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $pnlAuthTop.BackColor     = [System.Drawing.Color]::Transparent
    $pnlAuthTop.Padding       = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text     = '호스트 IP:'
    $lblH.AutoSize = $true
    $lblH.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $cmbAuthHost = New-Object System.Windows.Forms.ComboBox
    $cmbAuthHost.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cmbAuthHost.Size          = New-Object System.Drawing.Size(130, 24)
    $cmbAuthHost.Margin        = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $lblU = New-Object System.Windows.Forms.Label
    $lblU.Text     = 'ID:'
    $lblU.AutoSize = $true
    $lblU.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $txtAuthUser = New-Object System.Windows.Forms.TextBox
    $txtAuthUser.Text   = $global:AsanCtx.DefaultUser
    $txtAuthUser.Size   = New-Object System.Drawing.Size(80, 24)
    $txtAuthUser.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text     = '암호:'
    $lblP.AutoSize = $true
    $lblP.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $txtAuthPass = New-Object System.Windows.Forms.TextBox
    $txtAuthPass.UseSystemPasswordChar = $true
    $txtAuthPass.Size                  = New-Object System.Drawing.Size(116, 24)
    $txtAuthPass.Margin                = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $btnAuthRetry = New-StyledButton -Text '재인증 및 검증' -Width 116 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235)) -RegisterBusy
    $btnAuthRetry.Font   = $script:FontSmall
    $btnAuthRetry.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnAuthRetry.Add_Click({ Invoke-Tab2HostAuthActionAsync })

    $btnSidReset = New-StyledButton -Text '스풀러·자격증명 초기화 후 재연결' -Width 214 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(185, 28, 28)) -RegisterBusy
    $btnSidReset.Font   = $script:FontSmall
    $btnSidReset.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
    $btnSidReset.Add_Click({ Invoke-Tab2HostAuthActionAsync -WithSpoolerReset })

    $pnlAuthTop.Controls.AddRange(@($lblH, $cmbAuthHost, $lblU, $txtAuthUser, $lblP, $txtAuthPass, $btnAuthRetry, $btnSidReset))

    $txtAuthInfo = New-Object System.Windows.Forms.TextBox
    $txtAuthInfo.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtAuthInfo.Multiline   = $true
    $txtAuthInfo.ReadOnly    = $true
    $txtAuthInfo.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtAuthInfo.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtAuthInfo.BackColor   = [System.Drawing.Color]::White
    $txtAuthInfo.ForeColor   = [System.Drawing.Color]::FromArgb(127, 29, 29)
    $txtAuthInfo.Font        = $script:FontSmall

    $tpAuth.Controls.Add($txtAuthInfo)
    $tpAuth.Controls.Add($pnlAuthTop)
    $txtAuthInfo.BringToFront()

    # -- [5-B] 특수 프린터 반자동 도우미 탭 (DPI 125~150% 대응 FlowLayoutPanel) --
    $tpSpec = New-Object System.Windows.Forms.TabPage(' 특수 프린터 도우미 (0건) ')
    $tpSpec.BackColor = [System.Drawing.Color]::FromArgb(250, 245, 255)
    $tpSpec.Font      = $script:FontBase
    $tpSpec.Padding   = New-Object System.Windows.Forms.Padding(6)

    $pnlSpecTop = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlSpecTop.Dock          = [System.Windows.Forms.DockStyle]::Top
    $pnlSpecTop.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlSpecTop.WrapContents  = $true
    $pnlSpecTop.AutoSize      = $true
    $pnlSpecTop.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $pnlSpecTop.BackColor     = [System.Drawing.Color]::Transparent
    $pnlSpecTop.Padding       = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)

    $lblSp = New-Object System.Windows.Forms.Label
    $lblSp.Text     = '특수 장비:'
    $lblSp.AutoSize = $true
    $lblSp.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $cmbSpec = New-Object System.Windows.Forms.ComboBox
    $cmbSpec.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbSpec.Size          = New-Object System.Drawing.Size(195, 24)
    $cmbSpec.Margin        = New-Object System.Windows.Forms.Padding(0, 2, 6, 2)
    $cmbSpec.Add_SelectedIndexChanged({ Update-Tab2SpecialSelection })

    $btnSpecInst = New-StyledButton -Text '1단계: 전용 설치 실행' -Width 146 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(124, 58, 237))
    $btnSpecInst.Font    = $script:FontSmall
    $btnSpecInst.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecInst.Enabled = $false
    $btnSpecInst.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if ($cur -and $cur.Info.Installer -and $cur.Info.Installer.ExePath) {
            try {
                Start-Process -FilePath $cur.Info.Installer.ExePath -WorkingDirectory $cur.Info.Installer.Folder
                Add-UiLog -Message "특수 장비 설치 프로그램 실행: $($cur.Info.Installer.ExePath)" -Level 'INFO'
            } catch {
                [System.Windows.Forms.MessageBox]::Show($script:Ui.Form, "설치 파일 실행 실패: $($_.Exception.Message)", '실행 오류', 'OK', 'Error') | Out-Null
            }
        }
    })

    $btnSpecStep2 = New-StyledButton -Text '2단계: SIP-30M 마무리' -Width 186 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(15, 118, 110)) -RegisterBusy
    $btnSpecStep2.Font    = $script:FontSmall
    $btnSpecStep2.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecStep2.Enabled = $false
    $btnSpecStep2.Add_Click({ Invoke-Tab2Sip30mStep2Async })

    $btnUsbReenum = New-StyledButton -Text 'USB 재인식' -Width 86 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(2, 132, 199)) -RegisterBusy
    $btnUsbReenum.Font   = $script:FontSmall
    $btnUsbReenum.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnUsbReenum.Add_Click({ Invoke-Tab2UsbReenumAsync })

    $btnSpecDir = New-StyledButton -Text '폴더 열기' -Width 72 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnSpecDir.Font    = $script:FontSmall
    $btnSpecDir.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecDir.Enabled = $false
    $btnSpecDir.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if ($cur -and $cur.Info.Installer -and $cur.Info.Installer.Folder) {
            Open-FolderInExplorerSafe -FolderPath $cur.Info.Installer.Folder
        }
    })

    # [H4 Fix] 프린터 미설치 시 오류 팝업 대신 친절한 안내 표시
    $btnSpecProps = New-StyledButton -Text '속성 열기' -Width 72 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85))
    $btnSpecProps.Font    = $script:FontSmall
    $btnSpecProps.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
    $btnSpecProps.Enabled = $false
    $btnSpecProps.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if (-not $cur) { return }
        $pName        = [string]$cur.Row.PrinterName
        $installedPrt = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $pName }) | Select-Object -First 1
        if (-not $installedPrt) {
            [System.Windows.Forms.MessageBox]::Show(
                "'$pName' 프린터가 아직 이 PC에 설치되어 있지 않습니다.`r`n복원 또는 1단계 전용 설치를 먼저 완료한 뒤 속성을 열어주세요.",
                '프린터 미설치',
                'OK',
                'Information'
            ) | Out-Null
            return
        }
        $safeArg = 'printui.dll,PrintUIEntry /p /n "' + ($pName -replace '"', '\"') + '"'
        try { Start-Process -FilePath 'rundll32.exe' -ArgumentList $safeArg } catch {}
    })

    $pnlSpecTop.Controls.AddRange(@($lblSp, $cmbSpec, $btnSpecInst, $btnSpecStep2, $btnUsbReenum, $btnSpecDir, $btnSpecProps))

    $txtSpecChk = New-Object System.Windows.Forms.TextBox
    $txtSpecChk.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtSpecChk.Multiline   = $true
    $txtSpecChk.ReadOnly    = $true
    $txtSpecChk.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtSpecChk.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtSpecChk.BackColor   = [System.Drawing.Color]::White
    $txtSpecChk.ForeColor   = [System.Drawing.Color]::FromArgb(88, 28, 135)
    $txtSpecChk.Font        = $script:FontSmall

    $tpSpec.Controls.Add($txtSpecChk)
    $tpSpec.Controls.Add($pnlSpecTop)
    $txtSpecChk.BringToFront()

    $tabHelper.TabPages.Add($tpAuth)
    $tabHelper.TabPages.Add($tpSpec)
    $pnlHelper.Controls.Add($tabHelper)

    # ---------------- [6] 최하단 복원 실행 액션 바 ----------------
    $pnlAction = New-Object System.Windows.Forms.Panel
    $pnlAction.Dock   = [System.Windows.Forms.DockStyle]::Bottom
    $pnlAction.Height = 46

    $btnStart = New-StyledButton -Text '선택 항목 복원 시작' -Width 195 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(22, 163, 74)) -RegisterBusy
    $btnStart.Location = New-Object System.Drawing.Point(0, 8)
    $btnStart.Enabled  = $false
    $btnStart.Add_Click({ Start-Tab2RestoreExecution })

    $btnRetry = New-StyledButton -Text '실패 항목만 재시도' -Width 165 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(217, 119, 6)) -RegisterBusy
    $btnRetry.Location = New-Object System.Drawing.Point(206, 8)
    $btnRetry.Enabled  = $false
    $btnRetry.Add_Click({ Start-Tab2RestoreExecution -RetryFailedOnly })

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text      = '※ 비활성의심 및 Win 11 전용 설치 기종(세우테크)은 기본 체크 해제됩니다.'
    $lblHint.Font      = $script:FontSmall
    $lblHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $lblHint.AutoSize  = $true
    $lblHint.Location  = New-Object System.Drawing.Point(385, 16)

    $pnlAction.Controls.AddRange(@($btnStart, $btnRetry, $lblHint))

    # Dock Z-Order: Fill(0) -> Bottom(Inner) -> Bottom(Outer) -> Top(Inner) -> Top(Mid) -> Top(Outer)
    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlHelper)
    $parent.Controls.Add($pnlAction)
    $parent.Controls.Add($pnlGridBar)
    $parent.Controls.Add($pnlNotes)
    $parent.Controls.Add($pnlSource)
    $dgv.BringToFront()

    $script:Tab2Ui.CmbServerBackups = $cmbBackups
    $script:Tab2Ui.BtnLoadServer    = $btnLoadSrv
    $script:Tab2Ui.BtnOpenZip       = $btnOpenZip
    $script:Tab2Ui.BtnRunDeferred   = $btnDeferred
    $script:Tab2Ui.LblSourceInfo    = $lblSourceInfo
    $script:Tab2Ui.TxtNotes         = $txtNotes
    $script:Tab2Ui.BtnSelAll        = $btnSelAll
    $script:Tab2Ui.BtnSelHealthy    = $btnSelHealthy
    $script:Tab2Ui.BtnSelNone       = $btnSelNone
    $script:Tab2Ui.LblGridSummary   = $lblGridSum
    $script:Tab2Ui.BtnToggleHelper  = $btnToggleHelper
    $script:Tab2Ui.DgvRestore       = $dgv
    $script:Tab2Ui.PnlHelper        = $pnlHelper
    $script:Tab2Ui.TabHelper        = $tabHelper
    $script:Tab2Ui.TpAuth           = $tpAuth
    $script:Tab2Ui.TpSpecial        = $tpSpec
    $script:Tab2Ui.CmbAuthHost      = $cmbAuthHost
    $script:Tab2Ui.TxtAuthUser      = $txtAuthUser
    $script:Tab2Ui.TxtAuthPass      = $txtAuthPass
    $script:Tab2Ui.BtnAuthRetry     = $btnAuthRetry
    $script:Tab2Ui.BtnSidReset      = $btnSidReset
    $script:Tab2Ui.TxtAuthInfo      = $txtAuthInfo
    $script:Tab2Ui.CmbSpecialList   = $cmbSpec
    $script:Tab2Ui.BtnSpecInstall   = $btnSpecInst
    $script:Tab2Ui.BtnSpecStep2     = $btnSpecStep2
    $script:Tab2Ui.BtnUsbReenum     = $btnUsbReenum
    $script:Tab2Ui.BtnSpecFolder    = $btnSpecDir
    $script:Tab2Ui.BtnSpecProps     = $btnSpecProps
    $script:Tab2Ui.TxtSpecChecklist = $txtSpecChk
    $script:Tab2Ui.BtnStartRestore  = $btnStart
    $script:Tab2Ui.BtnRetryFailed   = $btnRetry
    $script:Tab2Ui.LblRestoreHint   = $lblHint

    $script:Ui.OnEnvRefreshed.Add({ Update-Tab2ServerDropdown })
}
