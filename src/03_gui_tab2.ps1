# ============================================================================
# [Module 03] 탭 2 (복원 - Win 11 / 지연 검증 / SID·특수장비 도우미) 최종본
# - Module 02(공용 GUI 셸 + 탭 1) 하단에 무손실 결합됨
# - 3-5B 패치 반영: C1, C2, C3, C4, H1, H4, H5
# ============================================================================
$script:Tab2Ui = @{
    CmbServerBackups   = $null
    ComboBackupEntries = @()
    BtnLoadServer      = $null
    BtnSearchServer    = $null
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
    SpecialInfoCache   = @{}
    LocalLptsCache     = @()
    SuppressSpecEvent  = $false
    PnlAuthTop         = $null
    PnlSpecTop         = $null
    PnlSourceOuter     = $null
    PnlNotes           = $null
    PnlNotesWrap       = $null
    PnlGridBar         = $null
    PnlAction          = $null
    PnlAuthTextWrap    = $null
    PnlSpecTextWrap    = $null
}

# ============================================================================
# 탭 2 UI 렌더링 및 도우미 패널 제어 헬퍼
# ============================================================================
function Update-Tab2HelperHeightSafe {
    if (-not $script:Tab2Ui.PnlHelper -or $script:Tab2Ui.PnlHelper.IsDisposed) { return }

    $tabH = 500
    if ($script:Ui.TabRestore -and -not $script:Ui.TabRestore.IsDisposed) {
        $tabH = [int]$script:Ui.TabRestore.ClientSize.Height
    }

    # 극소 화면(960x640 + WPP 경고 배너 동시 표시)에서만 상하 패딩을 미세 압축해 표(>=80px)·텍스트(>=40px) 동시 보장
    $isTight = ($tabH -gt 200 -and $tabH -lt 405 -and $script:Tab2Ui.HelperExpanded)
    if ($script:Tab2Ui.PnlSourceOuter) {
        if ($isTight) {
            $script:Tab2Ui.PnlSourceOuter.Height  = 52
            $script:Tab2Ui.PnlSourceOuter.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
        } else {
            $script:Tab2Ui.PnlSourceOuter.Height  = 65
            $script:Tab2Ui.PnlSourceOuter.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        }
    }
    if ($script:Tab2Ui.PnlNotes -and $script:Tab2Ui.PnlNotesWrap) {
        if ($isTight) {
            $script:Tab2Ui.PnlNotes.Height      = 50
            $script:Tab2Ui.PnlNotes.Padding     = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
            $script:Tab2Ui.PnlNotesWrap.Padding = New-Object System.Windows.Forms.Padding(10, 2, 8, 2)
        } else {
            $script:Tab2Ui.PnlNotes.Height      = 58
            $script:Tab2Ui.PnlNotes.Padding     = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
            $script:Tab2Ui.PnlNotesWrap.Padding = New-Object System.Windows.Forms.Padding(10, 5, 8, 5)
        }
    }
    if ($script:Tab2Ui.PnlGridBar) {
        if ($isTight) { $script:Tab2Ui.PnlGridBar.Height = 28 } else { $script:Tab2Ui.PnlGridBar.Height = 32 }
    }
    if ($script:Tab2Ui.PnlAction) {
        if ($isTight) { $script:Tab2Ui.PnlAction.Height = 41 } else { $script:Tab2Ui.PnlAction.Height = 46 }
    }
    foreach ($tpH in @($script:Tab2Ui.TpAuth, $script:Tab2Ui.TpSpec)) {
        if ($tpH -and -not $tpH.IsDisposed) {
            if ($isTight) { $tpH.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2) }
            else { $tpH.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5) }
        }
    }
    foreach ($tw in @($script:Tab2Ui.PnlAuthTextWrap, $script:Tab2Ui.PnlSpecTextWrap)) {
        if ($tw -and -not $tw.IsDisposed) {
            if ($isTight) { $tw.Padding = New-Object System.Windows.Forms.Padding(10, 2, 8, 2) }
            else { $tw.Padding = New-Object System.Windows.Forms.Padding(10, 6, 8, 6) }
        }
    }

    if (-not $script:Tab2Ui.HelperExpanded) { return }
    $topH = 32
    if ($script:Tab2Ui.TabHelper -and $script:Tab2Ui.TabHelper.SelectedIndex -eq 0 -and $script:Tab2Ui.PnlAuthTop) {
        $topH = [math]::Max($topH, [int]$script:Tab2Ui.PnlAuthTop.Height)
    } elseif ($script:Tab2Ui.PnlSpecTop) {
        $topH = [math]::Max($topH, [int]$script:Tab2Ui.PnlSpecTop.Height)
    }
    $extra   = [math]::Max(0, $topH - 32)
    $targetH = [math]::Min(172, (148 + $extra))

    if ($tabH -gt 200) {
        $nonGridFixed = 0
        if ($script:Tab2Ui.PnlSourceOuter) { $nonGridFixed += [int]$script:Tab2Ui.PnlSourceOuter.Height } else { $nonGridFixed += 62 }
        if ($script:Tab2Ui.PnlNotes)       { $nonGridFixed += [int]$script:Tab2Ui.PnlNotes.Height } else { $nonGridFixed += 58 }
        if ($script:Tab2Ui.PnlGridBar)     { $nonGridFixed += [int]$script:Tab2Ui.PnlGridBar.Height } else { $nonGridFixed += 32 }
        if ($script:Tab2Ui.PnlAction)      { $nonGridFixed += [int]$script:Tab2Ui.PnlAction.Height } else { $nonGridFixed += 46 }
        $nonGridFixed += 10
        $maxHelperH   = $tabH - $nonGridFixed - 84
        $minHelperH   = 118 + $extra
        if ($maxHelperH -lt $minHelperH) { $maxHelperH = $minHelperH }
        if ($targetH -gt $maxHelperH) { $targetH = $maxHelperH }
    }
    if ($script:Tab2Ui.PnlHelper.Height -ne $targetH) {
        $script:Tab2Ui.PnlHelper.Height = $targetH
    }
    if ($script:Tab2Ui.DgvRestore -and -not $script:Tab2Ui.DgvRestore.IsDisposed) {
        if ($script:Tab2Ui.DgvRestore.Height -lt 95 -and $script:Ui.LogExpanded) {
            Set-FooterLogExpanded -Expanded $false
        }
    }
}

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
        if ($Expanded) {
            $script:Tab2Ui.BtnToggleHelper.Text = '도우미 접기'
        } else {
            $pendingCnt = (@($script:AppState.AuthFailedHosts)).Count + (@($script:Tab2Ui.SpecialRows)).Count
            if ($pendingCnt -gt 0) {
                $script:Tab2Ui.BtnToggleHelper.Text = "특수·공유 도우미 ($pendingCnt)"
            } else {
                $script:Tab2Ui.BtnToggleHelper.Text = '특수·공유 도우미 열기'
            }
        }
    }
    if ($Expanded -and $SelectTabIndex -ge 0 -and $script:Tab2Ui.TabHelper -and $SelectTabIndex -lt $script:Tab2Ui.TabHelper.TabPages.Count) {
        $script:Tab2Ui.TabHelper.SelectedIndex = $SelectTabIndex
    }
    Update-Tab2HelperHeightSafe
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
            if ($e.MatchRank -eq 1) { $prefix = '자동 매칭 · ' }
            elseif ($e.IsMatched)   { $prefix = '유사 매칭 · ' }

            $dtStr = $e.LastWriteTime.ToString('MM-dd HH:mm')
            $label = "$prefix$($e.Name)  $dtStr"
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
        if ([string]::IsNullOrWhiteSpace($tgt)) {
            $lines.Add($msg)
        } else {
            $lines.Add("$tgt · $msg")
        }
    }

    if ($lines.Count -eq 0) {
        $txt.BackColor = $script:Theme.AsanMint
        $txt.ForeColor = $script:Theme.AsanDeep
        if ($script:Tab2Ui.PnlNotesWrap) { $script:Tab2Ui.PnlNotesWrap.BackColor = $script:Theme.AsanMint }
        $txt.Text      = '특이사항이 없습니다. 아래에서 복원할 프린터를 확인한 뒤 복원을 시작해 주세요.'
    } else {
        $txt.BackColor = $script:Theme.AsanOrangeTint
        $txt.ForeColor = $script:Theme.AsanOrangeText
        if ($script:Tab2Ui.PnlNotesWrap) { $script:Tab2Ui.PnlNotesWrap.BackColor = $script:Theme.AsanOrangeTint }
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
    $script:Tab2Ui.LblGridSummary.Text = "선택 ${sel} / ${total}대"
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
            if ($p.IsDefault) { $defMark = '기본' }

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
            $gridRow.Cells[5].ToolTipText = $portDisp
            $gridRow.Cells[6].ToolTipText = [string]$p.DriverName
            $gridRow.Cells[7].ToolTipText = [string]$p.Reason

            if ($p.IsDefault) {
                $gridRow.Cells[1].Style.ForeColor = $script:Theme.AsanGreen
                $gridRow.Cells[1].Style.Font      = $script:FontBold
            }

            # [H4 Fix] 전용 설치(세우테크) 및 LPT1 무드라이버(EPSON TM-T88) 체크박스 셀 잠금
            $stCell = $gridRow.Cells[2]
            $stCell.Style.Font = $script:FontBold
            if ($isLockedSpec) {
                $gridRow.Cells[0].ReadOnly          = $true
                $gridRow.DefaultCellStyle.BackColor = $script:Theme.DangerRedTint
                $gridRow.DefaultCellStyle.ForeColor = $script:Theme.DangerRedDeep
                $stCell.Style.BackColor             = $script:Theme.DangerRedTint
                $stCell.Style.ForeColor             = $script:Theme.DangerRedDeep
            } elseif ($p.SpecialType -ne 'STANDARD') {
                $stCell.Style.BackColor = $script:Theme.SpecialTint
                $stCell.Style.ForeColor = $script:Theme.SpecialPurple
            } elseif ($p.StatusCode -eq 'WsdConvert') {
                $stCell.Style.BackColor = [System.Drawing.Color]::FromArgb(226, 243, 249)
                $stCell.Style.ForeColor = $script:Theme.AsanLight
            } elseif ($p.StatusCode -eq 'AuthOrSidConflict') {
                $gridRow.DefaultCellStyle.BackColor = $script:Theme.DangerRedTint
                $stCell.Style.BackColor             = $script:Theme.DangerRedTint
                $stCell.Style.ForeColor             = $script:Theme.DangerRedDeep
            } elseif ($p.StatusCode -in @('SuspectedInactive', 'Ambiguous', 'OfflineUnverified')) {
                $stCell.Style.BackColor = $script:Theme.AsanOrangeTint
                $stCell.Style.ForeColor = $script:Theme.AsanOrangeText
            } else {
                $stCell.Style.BackColor = $script:Theme.AsanMint
                $stCell.Style.ForeColor = $script:Theme.AsanDeep
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
    $script:Tab2Ui.TpAuth.Text = " 공유 인증 · SID 해결 ($($hosts.Count)) "

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
            "인증 확인 대상: $($first.HostName) · $($first.Reason)",
            "1. 공유 메인 PC 암호가 바뀌었다면 위 칸에 아이디와 암호를 입력하고 '다시 인증'을 눌러 주세요.",
            "2. 암호가 맞는데도 연결이 거부되면 동일 SID 충돌입니다. 현재 PC SID는 $mySid 입니다.",
            "   메인 PC의 SID를 변경한 뒤 위 '스풀러 초기화 후 재연결'을 눌러 주세요."
        ) -join "`r`n"
    } else {
        $script:Tab2Ui.TxtAuthInfo.Text = '인증 오류가 감지된 공유 PC가 없습니다. 필요하면 호스트 IP를 직접 입력해 다시 인증하거나 스풀러를 초기화할 수 있습니다.'
    }
}

# ============================================================================
# 특수 프린터 4종 반자동 도우미 패널 갱신
# ============================================================================
function Update-Tab2SpecialSelection {
    if ($script:Tab2Ui.SuppressSpecEvent) { return }
    $cmb  = $script:Tab2Ui.CmbSpecialList
    $rows = @($script:Tab2Ui.SpecialRows)
    if (-not $cmb -or $cmb.SelectedIndex -lt 0 -or $cmb.SelectedIndex -ge $rows.Count) {
        $script:Tab2Ui.CurrentSpecInfo        = $null
        $script:Tab2Ui.TxtSpecChecklist.Text  = '감지된 특수/라벨 프린터가 없습니다.'
        $script:Tab2Ui.BtnSpecInstall.Enabled = $false
        $script:Tab2Ui.BtnSpecFolder.Enabled  = $false
        $script:Tab2Ui.BtnSpecProps.Enabled   = $false
        if ($script:Tab2Ui.BtnSpecStep2) { $script:Tab2Ui.BtnSpecStep2.Visible = $false }
        Sync-AllUiButtonStates
        return
    }

    $selRow = $rows[$cmb.SelectedIndex]
    # 백그라운드 Runspace에서 미리 계산된 캐시 우선 사용(UI 스레드 SMB/CIM 멈춤 완전 차단)
    $cacheKey = "$($selRow.SpecialType)|$($selRow.PrinterName)"
    $info = $null
    if ($script:Tab2Ui.SpecialInfoCache -and $script:Tab2Ui.SpecialInfoCache.ContainsKey($cacheKey)) {
        $info = $script:Tab2Ui.SpecialInfoCache[$cacheKey]
    } else {
        $info = Get-SpecialPrinterAssistantInfo -SpecialRow $selRow -SkipRemoteProbe -PreloadedLpts @($script:Tab2Ui.LocalLptsCache)
        if ($script:Tab2Ui.SpecialInfoCache) { $script:Tab2Ui.SpecialInfoCache[$cacheKey] = $info }
    }
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
    if ($script:Tab2Ui.BtnSpecStep2) {
        $script:Tab2Ui.BtnSpecStep2.Visible = ([bool]$info.HasStep2)
    }

    if ($selRow.SpecialType -eq 'SEWOO_TE201') {
        $script:Tab2Ui.BtnSpecInstall.Text = '세우 전용 설치'
    } elseif ($selRow.SpecialType -eq 'SIP30M_IDCARD') {
        $script:Tab2Ui.BtnSpecInstall.Text = 'SIP-30M 설치'
    } elseif ($selRow.SpecialType -eq 'ZEBRA_ZT411') {
        $script:Tab2Ui.BtnSpecInstall.Text = 'ZT411 설치'
    } else {
        $script:Tab2Ui.BtnSpecInstall.Text = '전용 설치 실행'
    }

    Sync-AllUiButtonStates
}

function Update-Tab2SpecialPanel {
    $specRows = @($script:AppState.RestoreRows | Where-Object { $_.SpecialType -ne 'STANDARD' })
    $script:Tab2Ui.SpecialRows    = $specRows
    $script:Tab2Ui.TpSpecial.Text = " 특수 프린터 설치 도우미 ($($specRows.Count)) "

    $cmb = $script:Tab2Ui.CmbSpecialList
    $script:Tab2Ui.SuppressSpecEvent = $true
    $cmb.BeginUpdate()
    try {
        $cmb.Items.Clear()
        foreach ($sr in $specRows) {
            [void]$cmb.Items.Add("$($sr.Category) · $($sr.PrinterName)  $($sr.PortName)")
        }
        if ($specRows.Count -gt 0) { $cmb.SelectedIndex = 0 }
    }
    finally {
        $cmb.EndUpdate()
        $script:Tab2Ui.SuppressSpecEvent = $false
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

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        [void](Show-AsanMessageBox -Text '불러올 백업 경로가 비어 있습니다.' -Caption '로드 실패' -Buttons 'OK' -Icon 'Warning')
        return
    }

    $net       = $script:AppState.NetworkInfo
    $isOnline  = ($null -ne $net -and $net.Status -ne 'Offline')
    $forceFlag = [bool]$ForceLiveProbe

    $work = {
        param($arg)
        $srcPath = [string]$arg.SourcePath
        if (-not (Test-Path -LiteralPath $srcPath)) {
            throw "백업 경로를 찾을 수 없습니다: $srcPath"
        }
        Write-ProgressSafe -Percent 15 -Message "백업 메타데이터 읽는 중: $srcPath"
        $meta = Read-BackupSourceMetadata -SourcePath $srcPath
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

        # 특수장비 설치파일/로컬(.drx/.drs)/LPT 정보를 백그라운드에서 선계산하여 UI 스레드 멈춤 원천 차단
        $specInfoMap = @{}
        foreach ($sr in @($deferred.Printers | Where-Object { $_.SpecialType -ne 'STANDARD' })) {
            $ck = "$($sr.SpecialType)|$($sr.PrinterName)"
            if (-not $specInfoMap.ContainsKey($ck)) {
                $specInfoMap[$ck] = Get-SpecialPrinterAssistantInfo -SpecialRow $sr -PreloadedLpts $localLpts
            }
        }

        Write-ProgressSafe -Percent 100 -Message "백업 로드 완료 (대상 $($deferred.Printers.Count)대)"

        return [pscustomobject]@{
            Meta         = $meta
            Deferred     = $deferred
            LocalLpts    = $localLpts
            SpecInfoMap  = $specInfoMap
            DidLiveProbe = $shouldProbe
        }
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "백업 로드 실패: $err" -Level 'ERROR'
            Invoke-ErrorWithAutoReportPrompt -Caption '백업 불러오기 오류' -Message "백업을 불러오지 못했습니다:`r`n$err" -Category '복원/드라이버 오류' -ErrorDetail ([string]$err)
            return
        }

        $meta = $data.Meta
        $bd   = $meta.Data
        $script:AppState.CurrentBackupMeta = $meta
        $script:AppState.RestoreRows       = @($data.Deferred.Printers)
        $script:AppState.AuthFailedHosts   = @($data.Deferred.AuthFailedHosts)
        $script:Tab2Ui.LoadedSourcePath    = $meta.SourcePath
        $script:Tab2Ui.LastFailures        = @()
        $script:Tab2Ui.LocalLptsCache      = @($data.LocalLpts)
        $script:Tab2Ui.SpecialInfoCache    = @{}
        if ($data.SpecInfoMap) {
            foreach ($k in $data.SpecInfoMap.Keys) { $script:Tab2Ui.SpecialInfoCache[$k] = $data.SpecInfoMap[$k] }
        }

        $brmTxt = 'PrintBrm 없음'
        if ($meta.HasBrm) { $brmTxt = 'PrintBrm 포함' }
        $modeTxt = '서버 백업'
        if ($meta.IsZip) { $modeTxt = '로컬 ZIP 파일' }
        $osPart = ''
        if ($bd.PSObject.Properties.Name -contains 'SourceOsName' -and -not [string]::IsNullOrWhiteSpace([string]$bd.SourceOsName)) {
            $osPart = " · $($bd.SourceOsName)"
        }
        $probeTxt = ''
        if ($data.DidLiveProbe) { $probeTxt = ' · 실시간 확인 완료' }

        $script:Tab2Ui.LblSourceInfo.Text = "$modeTxt · 원본 $($bd.SourceComputer) ($($bd.SourceIP))$osPart · $($bd.ExportedAt) · $brmTxt$probeTxt"

        $extraWarns = [System.Collections.Generic.List[string]]::new()
        if ($bd.SourceMachineSID -and $script:AppState.LocalSid -and ($bd.SourceMachineSID -eq $script:AppState.LocalSid)) {
            $extraWarns.Add("참고 · 원본 PC와 현재 PC의 Machine SID가 같습니다. ($($bd.SourceMachineSID))")
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
                $extraWarns.Add("LPT1 정상 감지 · $($lpt1Now.Name). EPSON TM-T88VI 등 무드라이버 장비는 드라이버 설치 없이 AMIS에서 바로 사용해 주세요.")
            } elseif ($lpt1Now) {
                $extraWarns.Add("LPT1 상태 확인 필요 · $($lpt1Now.Name) ($($lpt1Now.Status)). 장치관리자에서 LPT1 포트 상태를 확인해 주세요.")
            } elseif ($otherLpts.Count -gt 0) {
                $otherDesc = ($otherLpts | ForEach-Object { "$($_.PortName) ($($_.Name))" }) -join ', '
                $extraWarns.Add("LPT1 번호 변경 필요 · 대신 $otherDesc 포트가 감지되었습니다. 장치관리자에서 LPT1으로 변경해 주세요.")
            } else {
                $extraWarns.Add("LPT1 미감지 · 기존 PC에 있던 LPT 포트($($bakLpts -join ', '))가 현재 PC에서 보이지 않습니다. 케이블과 포트 장착을 확인해 주세요.")
            }
        }
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            $extraWarns.Add("공유 인증 확인 필요 · 공유 PC $($script:AppState.AuthFailedHosts.Count)곳에서 연결이 거부되었습니다. 아래 공유 인증 탭에서 해결해 주세요.")
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
        [void](Show-AsanMessageBox -Text '먼저 서버 백업 또는 오프라인 ZIP 파일을 불러오세요.' -Caption '백업 미선택' -Buttons 'OK' -Icon 'Warning')
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
            [void](Show-AsanMessageBox -Text '재시도할 실패 항목이 없습니다.' -Caption '재시도 대상 없음' -Buttons 'OK' -Icon 'Information')
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
        [void](Show-AsanMessageBox -Text '복원할 프린터를 1대 이상 선택하세요.' -Caption '선택 없음' -Buttons 'OK' -Icon 'Warning')
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
            Invoke-ErrorWithAutoReportPrompt -Caption '복원 오류' -Message "복원 작업 중 오류가 발생했습니다:`r`n$err" -Category '복원/드라이버 오류' -ErrorDetail ([string]$err)
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
        $ztPrefsList = @()
        if ($data.PSObject.Properties.Name -contains 'ZtManualPrefsNames' -and $data.ZtManualPrefsNames) {
            $ztPrefsList = @($data.ZtManualPrefsNames)
        }
        if ($samList.Count -gt 0) {
            $extra.Add("[중요 경고] 삼성 범용 드라이버(UPD 3) 사용 프린터: $($samList -join ', ') — 테스트 페이지 오류 시 모델 전용 드라이버 교체 및 장치설정(PCL6) 필요!")
        }
        if ($ztPrefsList.Count -gt 0) {
            $extra.Add("[ZT411 인쇄 기본 설정 마무리 필요] 대상: $($ztPrefsList -join ', ') — 골든 이미지 드라이버로 대체 복원되었거나 백업된 인쇄 기본 설정(.dat/.reg)이 미확인되었습니다. 프린터 속성 > 인쇄 기본 설정(또는 폴더 내 용지별 .drx/.drs 가져오기)을 직접 마무리하세요.")
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
        } elseif ($manualSpecs.Count -gt 0 -or $data.NeedsUsbReplug -or $ztPrefsList.Count -gt 0) {
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
        $sumLines.Add("프린터와 드라이버 복원을 마쳤습니다.")
        $sumLines.Add("")
        $sumLines.Add("복원 성공: ${succCnt}건 (스캐너 드라이버 $($data.RestoredScanCount)개)")
        $sumLines.Add("복원 실패: ${failCnt}건")
        $sumLines.Add("특수 장비: ${specCnt}대")

        if ($ztPrefsList.Count -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("ZT411 인쇄 기본 설정 확인 필요: $($ztPrefsList -join ', ')")
            $sumLines.Add("대체 드라이버로 설치되었거나 기존 설정이 빠져 있습니다. 아래 특수 프린터 도우미에서 프린터 속성을 열어 용지·농도를 확인하거나 설정 파일(.drx/.drs)을 불러와 주세요.")
        }
        if ($data.NeedsUsbReplug) {
            $sumLines.Add("")
            $sumLines.Add("USB 바코드 재연결 필요")
            $sumLines.Add("자동 재인식으로 USB 포트가 생기지 않았습니다. USB 케이블을 한 번 뺐다가 다시 꽂은 뒤 '실패 항목 다시 시도'를 눌러 주세요.")
        }
        if ($samList.Count -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("삼성 범용 드라이버(UPD 3) 확인: $($samList -join ', ')")
            $sumLines.Add("출력 확인 탭에서 테스트 인쇄 후 문제가 있으면 모델 전용 드라이버로 교체해 주세요.")
        }
        if ($script:AppState.AuthFailedHosts.Count -gt 0) {
            $sumLines.Add("")
            $sumLines.Add("공유 PC 인증 또는 SID 충돌 감지")
            $sumLines.Add("아래 공유 인증 탭에서 암호를 다시 입력하거나 스풀러 초기화 후 '실패 항목 다시 시도'를 눌러 주세요.")
        }
        $canJumpTab3 = ($failCnt -eq 0 -and $manualSpecs.Count -eq 0 -and $ztPrefsList.Count -eq 0 -and $samList.Count -eq 0 -and (-not $data.NeedsUsbReplug))
        if ($canJumpTab3) {
            $sumLines.Add("")
            $sumLines.Add("지금 바로 '3. 출력 확인' 탭으로 이동해 테스트 인쇄를 진행할까요?")
        }

        if ($failCnt -gt 0) {
            $netNow   = $script:AppState.NetworkInfo
            $srvReady = ($null -ne $netNow -and $netNow.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$netNow.PrtBakDir))
            $sumLines.Add("")
            if ($srvReady) {
                $sumLines.Add("실패한 항목의 진단 리포트를 자동으로 구성해 사내 리포트함으로 보낼까요?")
            } else {
                $sumLines.Add("현재 사내 서버에 연결되어 있지 않습니다. 실패 항목의 진단 리포트를 이 PC의 로컬 폴더(C:\_AsanPrtOffline\_Reports)에 저장할까요?")
            }
            $repAns = Show-AsanMessageBox -Text ($sumLines -join "`r`n") -Caption '복원 결과 요약' -Buttons 'YesNo' -Icon 'Warning'
            if ($repAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                $firstFailPrt = [string](@($data.Failures)[0].PrinterName)
                $failSummary  = (@($data.Failures | ForEach-Object { "$($_.PrinterName) ($($_.PortName)): $($_.Reason)" }) -join "`r`n")
                Show-BugReportDialog -DefaultCategory '복원/드라이버 오류' -DefaultPrinter $firstFailPrt -ErrorSummary $failSummary
            }
        } elseif ($canJumpTab3) {
            $goVerify = Show-AsanMessageBox -Text ($sumLines -join "`r`n") -Caption '복원 완료' -Buttons 'YesNo' -Icon 'Information'
            if ($goVerify -eq [System.Windows.Forms.DialogResult]::Yes -and $script:Ui.TabMain) {
                $script:Ui.TabMain.SelectedIndex = 2
            }
        } else {
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
            if ($samList.Count -gt 0 -or $data.NeedsUsbReplug -or $ztPrefsList.Count -gt 0) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
            [void](Show-AsanMessageBox -Text ($sumLines -join "`r`n") -Caption '복원 완료' -Buttons 'OK' -Icon $icon)
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
        [void](Show-AsanMessageBox -Text '조치할 공유 메인 PC의 IP 주소를 선택하거나 입력하세요.' -Caption '호스트 미입력' -Buttons 'OK' -Icon 'Warning')
        return
    }
    if (-not $WithSpoolerReset -and [string]::IsNullOrWhiteSpace($userVal)) {
        [void](Show-AsanMessageBox -Text '사용자 계정(예: admin)을 입력하세요.' -Caption '계정 미입력' -Buttons 'OK' -Icon 'Warning')
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
            Invoke-ErrorWithAutoReportPrompt -Caption '공유 인증 오류' -Message "공유 PC 인증 또는 스풀러 초기화 중 오류가 발생했습니다:`r`n$err" -Category '공유 인증/SID 충돌' -ErrorDetail ([string]$err)
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

            [void](Show-AsanMessageBox -Text "호스트($targetHost) 인증에 성공했습니다! ($($authRes.Reason))`r`n`r`n이제 [실패 항목만 재시도] 또는 [선택 항목 복원 시작] 버튼을 눌러 복원을 완료하세요." -Caption '공유 호스트 인증 성공' -Buttons 'OK' -Icon 'Information')
        } else {
            $mySid = $script:AppState.LocalSid
            $script:Tab2Ui.TxtAuthInfo.Text = @(
                "[재시도 실패 — 동일 Windows SID 충돌 강력 의심] $($authRes.Reason)",
                "• 현재 작업 중인 PC의 Machine SID: $mySid",
                "• 조치 절차: 1) 메인 PC($targetHost)에서 SID 변경 및 스풀러 초기화 진행",
                "             2) 완료 후 이 화면의 [스풀러·자격증명 초기화 후 재연결] 버튼 클릭"
            ) -join "`r`n"
            [void](Show-AsanMessageBox -Text "호스트($targetHost) 연결이 여전히 거부되었습니다.`r`n$($authRes.Reason)`r`n`r`n비밀번호가 확실히 맞다면 메인 PC와 동일 Windows SID 충돌 상태입니다.`r`n메인 PC SID 작업 후 [스풀러·자격증명 초기화 후 재연결]을 실행하세요." -Caption '인증 실패 / SID 충돌 의심' -Buttons 'OK' -Icon 'Warning')
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

    $btnCan = New-StyledButton -Text '취소' -Width 84 -Height 28 -Variant 'Secondary'
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCan.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnOk = New-StyledButton -Text '확인' -Width 84 -Height 28 -Variant 'Primary'
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
            Invoke-ErrorWithAutoReportPrompt -Caption 'SIP-30M 설정 오류' -Message "SIP-30M 설정 마무리 중 오류가 발생했습니다:`r`n$err" -Category '특수/바코드 프린터' -TargetPrinter 'id카드' -ErrorDetail ([string]$err)
            return
        }
        $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        if ($data.Success) {
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
            foreach ($cb in $script:Ui.OnRestoreCompleted) { try { & $cb } catch {} }
        }
        [void](Show-AsanMessageBox -Text $data.Message -Caption 'SIP-30M 2단계 마무리' -Buttons 'OK' -Icon $icon)
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
            Invoke-ErrorWithAutoReportPrompt -Caption 'USB 재인식 오류' -Message "USB 바코드 다시 인식 중 오류가 발생했습니다:`r`n$err" -Category '특수/바코드 프린터' -ErrorDetail ([string]$err)
            return
        }
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        if ($data.NeedsManualReplug) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
        foreach ($cb in $script:Ui.OnRestoreCompleted) { try { & $cb } catch {} }
        [void](Show-AsanMessageBox -Text $data.Summary -Caption 'USB 바코드 소프트웨어 재인식' -Buttons 'OK' -Icon $icon)
    }
    Invoke-AsanAsyncTask -TaskName 'USB 바코드 소프트웨어 재인식' -WorkScript $work -OnComplete $done -Indeterminate
}

# ============================================================================
# [C2 + C4 + H4 Fix] 탭 2 컨트롤 배치 초기화 — 1→2→3단계 서울아산병원 복원 UX
# ============================================================================
function Initialize-Tab2RestoreUi {
    $parent = $script:Ui.TabRestore

    # ---------------- [1] 1단계 백업 소스 선택 카드 (화이트 카드 + 좌측 아산 그린 포인트 + 넉넉한 여백) ----------------
    $pnlSourceOuter = New-Object System.Windows.Forms.Panel
    $pnlSourceOuter.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlSourceOuter.Height    = 65
    $pnlSourceOuter.Padding   = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $pnlSourceOuter.BackColor = [System.Drawing.Color]::Transparent

    $pnlSource = New-Object System.Windows.Forms.Panel
    $pnlSource.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $pnlSource.BackColor   = $script:Theme.CardBg
    $pnlSource.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $pnlSrcAccent = New-Object System.Windows.Forms.Panel
    $pnlSrcAccent.Dock      = [System.Windows.Forms.DockStyle]::Left
    $pnlSrcAccent.Width     = 4
    $pnlSrcAccent.BackColor = $script:Theme.AsanGreen

    $pnlSrcInner = New-Object System.Windows.Forms.Panel
    $pnlSrcInner.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlSrcInner.Padding   = New-Object System.Windows.Forms.Padding(12, 6, 10, 5)
    $pnlSrcInner.BackColor = [System.Drawing.Color]::Transparent

    $flpSrcRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpSrcRow.Dock          = [System.Windows.Forms.DockStyle]::Top
    $flpSrcRow.Height        = 28
    $flpSrcRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpSrcRow.WrapContents  = $false
    $flpSrcRow.BackColor     = [System.Drawing.Color]::Transparent
    $flpSrcRow.Padding       = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)

    $lblSrc = New-Object System.Windows.Forms.Label
    $lblSrc.Text      = ' 1단계 '
    $lblSrc.Font      = $script:FontSmallB
    $lblSrc.BackColor = $script:Theme.AsanGreen
    $lblSrc.ForeColor = [System.Drawing.Color]::White
    $lblSrc.AutoSize  = $true
    $lblSrc.Padding   = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
    $lblSrc.Margin    = New-Object System.Windows.Forms.Padding(0, 3, 8, 0)

    $cmbBackups = New-Object System.Windows.Forms.ComboBox
    $cmbBackups.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbBackups.Size          = New-Object System.Drawing.Size(320, 24)
    $cmbBackups.DropDownWidth = 500
    $cmbBackups.Font          = $script:FontBase
    $cmbBackups.Margin        = New-Object System.Windows.Forms.Padding(0, 2, 6, 0)
    $cmbBackups.Add_SelectionChangeCommitted({
        if ($script:AsyncState.IsBusy) { return }
        $idx = $script:Tab2Ui.CmbServerBackups.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:Tab2Ui.ComboBackupEntries.Count) {
            $pickedPath = [string]$script:Tab2Ui.ComboBackupEntries[$idx].FullPath
            if ($pickedPath -ine [string]$script:Tab2Ui.LoadedSourcePath) {
                Load-Tab2BackupSourceAsync -SourcePath $pickedPath
            }
        }
    })
    $script:Ui.BusyControls.Add($cmbBackups)

    $btnLoadSrv = New-StyledButton -Text '불러오기' -Width 82 -Height 26 -Variant 'SoftTeal' -RegisterBusy
    $btnLoadSrv.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 0)
    $btnLoadSrv.Add_Click({
        $idx = $script:Tab2Ui.CmbServerBackups.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:Tab2Ui.ComboBackupEntries.Count) {
            Load-Tab2BackupSourceAsync -SourcePath $script:Tab2Ui.ComboBackupEntries[$idx].FullPath
        }
    })

    $btnSearchSrv = New-StyledButton -Text '서버 검색' -Width 82 -Height 26 -Variant 'Secondary' -RegisterBusy
    $btnSearchSrv.Font   = $script:FontSmallB
    $btnSearchSrv.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 0)
    $btnSearchSrv.Add_Click({
        if ($script:Ui.TabMain) {
            $script:Ui.TabMain.SelectedIndex = 3
            if ($script:Tab4Ui -and $script:Tab4Ui.TxtSearch -and (-not $script:Tab4Ui.TxtSearch.IsDisposed)) {
                $script:Tab4Ui.TxtSearch.Focus()
            }
        }
    })
    if ($script:Ui.ToolTip) {
        $script:Ui.ToolTip.SetToolTip($btnSearchSrv, '서버 백업이 많을 때 컴퓨터 이름이나 IP로 빠르게 검색해 불러옵니다')
    }

    $btnOpenZip = New-StyledButton -Text 'ZIP 파일 열기' -Width 112 -Height 26 -Variant 'Secondary' -RegisterBusy
    $btnOpenZip.Font   = $script:FontSmallB
    $btnOpenZip.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 0)
    $btnOpenZip.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title  = '오프라인 백업 ZIP 파일 선택'
        $ofd.Filter = 'ZIP 백업 파일 (*.zip)|*.zip|모든 파일 (*.*)|*.*'
        if (Test-Path -LiteralPath $global:AsanCtx.OfflineLocalRoot) {
            $ofd.InitialDirectory = $global:AsanCtx.OfflineLocalRoot
        }
        if ($ofd.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            Load-Tab2BackupSourceAsync -SourcePath $ofd.FileName
        }
        $ofd.Dispose()
    })

    $btnDeferred = New-StyledButton -Text '연결 다시 확인' -Width 110 -Height 26 -Variant 'Secondary' -RegisterBusy
    $btnDeferred.Font    = $script:FontSmallB
    $btnDeferred.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)
    $btnDeferred.Enabled = $false
    $btnDeferred.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:Tab2Ui.LoadedSourcePath)) {
            Load-Tab2BackupSourceAsync -SourcePath $script:Tab2Ui.LoadedSourcePath -ForceLiveProbe
        }
    })

    $flpSrcRow.Controls.AddRange(@($lblSrc, $cmbBackups, $btnLoadSrv, $btnSearchSrv, $btnOpenZip, $btnDeferred))

    $lblSourceInfo = New-Object System.Windows.Forms.Label
    $lblSourceInfo.Text      = '서버 백업을 선택하거나 ZIP 파일 열기로 복원 대상을 불러와 주세요.'
    $lblSourceInfo.Font      = $script:FontSmall
    $lblSourceInfo.ForeColor = $script:Theme.InkSecondary
    $lblSourceInfo.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblSourceInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $pnlSrcInner.Controls.Add($lblSourceInfo)
    $pnlSrcInner.Controls.Add($flpSrcRow)
    $pnlSource.Controls.Add($pnlSrcInner)
    $pnlSource.Controls.Add($pnlSrcAccent)
    $pnlSourceOuter.Controls.Add($pnlSource)

    # ---------------- [2] 영속 리포트(BackupNotes + 복원 경고) 패딩 카드 배너 ----------------
    $pnlNotes = New-Object System.Windows.Forms.Panel
    $pnlNotes.Dock    = [System.Windows.Forms.DockStyle]::Top
    $pnlNotes.Height  = 58
    $pnlNotes.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

    $notesBox     = New-PaddedTextBoxPanel -BackColor $script:Theme.AsanMint -ForeColor $script:Theme.AsanDeep -Font $script:FontSmall -PadX 10 -PadY 5 -ReadOnly $true -InitialText '백업을 불러오면 복원 전에 확인할 주의 사항이 여기에 표시됩니다.'
    $pnlNotesWrap = $notesBox.Panel
    $txtNotes     = $notesBox.TextBox
    $pnlNotes.Controls.Add($pnlNotesWrap)

    # ---------------- [3] 2단계 프린터 선택 툴바 (FlowLayoutPanel + RightFlowStrip — DPI 안전) ----------------
    $pnlGridBar = New-Object System.Windows.Forms.Panel
    $pnlGridBar.Dock   = [System.Windows.Forms.DockStyle]::Top
    $pnlGridBar.Height = 32

    $flpGridLeft = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpGridLeft.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $flpGridLeft.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpGridLeft.WrapContents  = $false
    $flpGridLeft.BackColor     = [System.Drawing.Color]::Transparent
    $flpGridLeft.Padding       = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

    $lblStep2 = New-Object System.Windows.Forms.Label
    $lblStep2.Text      = ' 2단계 '
    $lblStep2.Font      = $script:FontSmallB
    $lblStep2.BackColor = $script:Theme.AsanGreen
    $lblStep2.ForeColor = [System.Drawing.Color]::White
    $lblStep2.AutoSize  = $true
    $lblStep2.Padding   = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
    $lblStep2.Margin    = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)

    $btnSelAll = New-StyledButton -Text '전체 선택' -Width 76 -Height 24 -Variant 'Secondary' -RegisterBusy
    $btnSelAll.Font   = $script:FontSmallB
    $btnSelAll.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
    $btnSelAll.Add_Click({
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) {
            if ($r.Tag -and $r.Tag.SpecialType -notin @('SEWOO_TE201', 'EPSON_TMT88_LPT')) { $r.Cells[0].Value = $true }
        }
        Sync-Tab2GridSelectionToState
        Update-Tab2GridSummary
    })

    $btnSelHealthy = New-StyledButton -Text '정상만 선택' -Width 88 -Height 24 -Variant 'Secondary' -RegisterBusy
    $btnSelHealthy.Font   = $script:FontSmallB
    $btnSelHealthy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
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

    $btnSelNone = New-StyledButton -Text '모두 해제' -Width 76 -Height 24 -Variant 'Secondary' -RegisterBusy
    $btnSelNone.Font   = $script:FontSmallB
    $btnSelNone.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $btnSelNone.Add_Click({
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) { $r.Cells[0].Value = $false }
        Sync-Tab2GridSelectionToState
        Update-Tab2GridSummary
    })

    $lblGridSum = New-Object System.Windows.Forms.Label
    $lblGridSum.Text      = '선택 0 / 0대'
    $lblGridSum.Font      = $script:FontBold
    $lblGridSum.ForeColor = $script:Theme.InkPrimary
    $lblGridSum.AutoSize  = $true
    $lblGridSum.Margin    = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

    $flpGridLeft.Controls.AddRange(@($lblStep2, $btnSelAll, $btnSelHealthy, $btnSelNone, $lblGridSum))

    $flpGridRight = New-RightFlowStrip -TopPadding 3 -RightPadding 0
    $btnToggleHelper = New-StyledButton -Text '특수·공유 도우미 열기' -Width 160 -Height 24 -Variant 'SoftTeal'
    $btnToggleHelper.Font = $script:FontSmallB
    $btnToggleHelper.Add_Click({
        Set-Tab2HelperVisibility -Expanded (-not $script:Tab2Ui.HelperExpanded)
    })
    $flpGridRight.Controls.Add($btnToggleHelper)

    $pnlGridBar.Controls.Add($flpGridLeft)
    $pnlGridBar.Controls.Add($flpGridRight)

    # ---------------- [4] 중앙 선택 복원 그리드 (마지막 컬럼 Fill) ----------------
    $dgv = New-StyledGrid -AllowCheckEdit
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    $colChk = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colChk.Name       = 'Selected'
    $colChk.HeaderText = '복원'
    $colChk.Width      = 54
    [void]$dgv.Columns.Add($colChk)

    foreach ($cDef in @(
        @{ Name = 'Default';  Header = '기본';           Width = 54;  Fill = $false },
        @{ Name = 'Status';   Header = '상태';           Width = 112; Fill = $false },
        @{ Name = 'Category'; Header = '구분';           Width = 118; Fill = $false },
        @{ Name = 'Printer';  Header = '프린터 이름';     Width = 146; Fill = $false },
        @{ Name = 'Port';     Header = '포트 / 전환 대상'; Width = 132; Fill = $false },
        @{ Name = 'Driver';   Header = '드라이버';       Width = 152; Fill = $false },
        @{ Name = 'Reason';   Header = '상세 내용';      Width = 180; Fill = $true }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $cDef.Name
        $c.HeaderText = $cDef.Header
        $c.Width      = $cDef.Width
        $c.ReadOnly   = $true
        if ($cDef.Fill) {
            $c.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
            $c.MinimumWidth = 150
        }
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
    $pnlHelper.Height  = 138
    $pnlHelper.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $pnlHelper.Visible = $false

    $tabHelper = New-Object System.Windows.Forms.TabControl
    $tabHelper.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabHelper.Font = $script:FontSmallB
    $tabHelper.Add_SelectedIndexChanged({ Update-Tab2HelperHeightSafe })

    # -- [5-A] 공유 인증 / 동일 SID 조치 탭 --
    $tpAuth = New-Object System.Windows.Forms.TabPage(' 공유 인증 · SID 해결 (0) ')
    $tpAuth.BackColor = [System.Drawing.Color]::FromArgb(254, 248, 247)
    $tpAuth.Font      = $script:FontBase
    $tpAuth.Padding   = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)

    $pnlAuthTop = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlAuthTop.Dock          = [System.Windows.Forms.DockStyle]::Top
    $pnlAuthTop.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlAuthTop.WrapContents  = $true
    $pnlAuthTop.AutoSize      = $true
    $pnlAuthTop.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $pnlAuthTop.BackColor     = [System.Drawing.Color]::Transparent
    $pnlAuthTop.Padding       = New-Object System.Windows.Forms.Padding(0, 1, 0, 5)

    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text     = '호스트 IP'
    $lblH.Font     = $script:FontSmallB
    $lblH.AutoSize = $true
    $lblH.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $cmbAuthHost = New-Object System.Windows.Forms.ComboBox
    $cmbAuthHost.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cmbAuthHost.Size          = New-Object System.Drawing.Size(130, 24)
    $cmbAuthHost.Margin        = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $lblU = New-Object System.Windows.Forms.Label
    $lblU.Text     = '아이디'
    $lblU.Font     = $script:FontSmallB
    $lblU.AutoSize = $true
    $lblU.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $txtAuthUser = New-Object System.Windows.Forms.TextBox
    $txtAuthUser.Text   = $global:AsanCtx.DefaultUser
    $txtAuthUser.Size   = New-Object System.Drawing.Size(78, 24)
    $txtAuthUser.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text     = '암호'
    $lblP.Font     = $script:FontSmallB
    $lblP.AutoSize = $true
    $lblP.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $txtAuthPass = New-Object System.Windows.Forms.TextBox
    $txtAuthPass.UseSystemPasswordChar = $true
    $txtAuthPass.Size                  = New-Object System.Drawing.Size(112, 24)
    $txtAuthPass.Margin                = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)

    $btnAuthRetry = New-StyledButton -Text '다시 인증' -Width 92 -Height 26 -Variant 'Primary' -RegisterBusy
    $btnAuthRetry.Font   = $script:FontSmallB
    $btnAuthRetry.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnAuthRetry.Add_Click({ Invoke-Tab2HostAuthActionAsync })

    $btnSidReset = New-StyledButton -Text '스풀러 초기화 후 재연결' -Width 176 -Height 26 -Variant 'DangerOutline' -RegisterBusy
    $btnSidReset.Font   = $script:FontSmallB
    $btnSidReset.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
    $btnSidReset.Add_Click({ Invoke-Tab2HostAuthActionAsync -WithSpoolerReset })

    $pnlAuthTop.Controls.AddRange(@($lblH, $cmbAuthHost, $lblU, $txtAuthUser, $lblP, $txtAuthPass, $btnAuthRetry, $btnSidReset))

    $authBox         = New-PaddedTextBoxPanel -BackColor $script:Theme.CardBg -ForeColor $script:Theme.DangerRedDeep -Font $script:FontSmall -PadX 10 -PadY 6 -ReadOnly $true
    $pnlAuthTextWrap = $authBox.Panel
    $txtAuthInfo     = $authBox.TextBox

    $tpAuth.Controls.Add($pnlAuthTextWrap)
    $tpAuth.Controls.Add($pnlAuthTop)
    $pnlAuthTextWrap.BringToFront()

    # -- [5-B] 특수 프린터 반자동 도우미 탭 (DPI 125~150% 대응 FlowLayoutPanel) --
    $tpSpec = New-Object System.Windows.Forms.TabPage(' 특수 프린터 설치 도우미 (0) ')
    $tpSpec.BackColor = [System.Drawing.Color]::FromArgb(245, 249, 249)
    $tpSpec.Font      = $script:FontBase
    $tpSpec.Padding   = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)

    $pnlSpecTop = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlSpecTop.Dock          = [System.Windows.Forms.DockStyle]::Top
    $pnlSpecTop.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlSpecTop.WrapContents  = $true
    $pnlSpecTop.AutoSize      = $true
    $pnlSpecTop.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $pnlSpecTop.BackColor     = [System.Drawing.Color]::Transparent
    $pnlSpecTop.Padding       = New-Object System.Windows.Forms.Padding(0, 1, 0, 5)

    $lblSp = New-Object System.Windows.Forms.Label
    $lblSp.Text     = '장비'
    $lblSp.Font     = $script:FontSmallB
    $lblSp.AutoSize = $true
    $lblSp.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 4, 2)

    $cmbSpec = New-Object System.Windows.Forms.ComboBox
    $cmbSpec.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbSpec.Size          = New-Object System.Drawing.Size(216, 24)
    $cmbSpec.DropDownWidth = 380
    $cmbSpec.Margin        = New-Object System.Windows.Forms.Padding(0, 2, 6, 2)
    $cmbSpec.Add_SelectedIndexChanged({ Update-Tab2SpecialSelection })

    $btnSpecInst = New-StyledButton -Text '전용 설치 실행' -Width 120 -Height 26 -Variant 'Primary' -RegisterBusy
    $btnSpecInst.Font    = $script:FontSmallB
    $btnSpecInst.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecInst.Enabled = $false
    $btnSpecInst.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if ($cur -and $cur.Info.Installer -and $cur.Info.Installer.ExePath) {
            try {
                Start-Process -FilePath $cur.Info.Installer.ExePath -WorkingDirectory $cur.Info.Installer.Folder
                Add-UiLog -Message "특수 장비 설치 프로그램 실행: $($cur.Info.Installer.ExePath)" -Level 'INFO'
            } catch {
                [void](Show-AsanMessageBox -Text "설치 파일 실행 실패: $($_.Exception.Message)" -Caption '실행 오류' -Buttons 'OK' -Icon 'Error')
            }
        }
    })

    $btnSpecStep2 = New-StyledButton -Text 'SIP-30M 설정 마무리' -Width 148 -Height 26 -Variant 'SoftTeal' -RegisterBusy
    $btnSpecStep2.Font    = $script:FontSmallB
    $btnSpecStep2.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecStep2.Enabled = $false
    $btnSpecStep2.Visible = $false
    $btnSpecStep2.Add_Click({ Invoke-Tab2Sip30mStep2Async })

    $btnUsbReenum = New-StyledButton -Text 'USB 다시 인식' -Width 104 -Height 26 -Variant 'SoftOrange' -RegisterBusy
    $btnUsbReenum.Font   = $script:FontSmallB
    $btnUsbReenum.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnUsbReenum.Add_Click({ Invoke-Tab2UsbReenumAsync })

    $btnSpecDir = New-StyledButton -Text '폴더 열기' -Width 76 -Height 26 -Variant 'Secondary'
    $btnSpecDir.Font    = $script:FontSmallB
    $btnSpecDir.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 6, 2)
    $btnSpecDir.Enabled = $false
    $btnSpecDir.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if ($cur -and $cur.Info.Installer -and $cur.Info.Installer.Folder) {
            Open-FolderInExplorerSafe -FolderPath $cur.Info.Installer.Folder
        }
    })

    # [H4 Fix] 프린터 미설치 시 오류 팝업 대신 친절한 안내 표시
    $btnSpecProps = New-StyledButton -Text '프린터 속성' -Width 86 -Height 26 -Variant 'Secondary' -RegisterBusy
    $btnSpecProps.Font    = $script:FontSmallB
    $btnSpecProps.Margin  = New-Object System.Windows.Forms.Padding(0, 1, 0, 2)
    $btnSpecProps.Enabled = $false
    $btnSpecProps.Add_Click({
        $cur = $script:Tab2Ui.CurrentSpecInfo
        if (-not $cur) { return }
        $pName        = [string]$cur.Row.PrinterName
        $installedPrt = @(Get-PrinterSafe | Where-Object { $_.Name -eq $pName }) | Select-Object -First 1
        if (-not $installedPrt) {
            [void](Show-AsanMessageBox -Text "'$pName' 프린터가 아직 이 PC에 설치되어 있지 않습니다.`r`n복원 또는 전용 설치를 먼저 완료한 뒤 속성을 열어 주세요." -Caption '프린터 미설치' -Buttons 'OK' -Icon 'Information')
            return
        }
        $safeArg = 'printui.dll,PrintUIEntry /p /n "' + ($pName -replace '"', '\"') + '"'
        try { Start-Process -FilePath 'rundll32.exe' -ArgumentList $safeArg } catch {}
    })

    $pnlSpecTop.Controls.AddRange(@($lblSp, $cmbSpec, $btnSpecInst, $btnSpecStep2, $btnUsbReenum, $btnSpecDir, $btnSpecProps))

    $specBox         = New-PaddedTextBoxPanel -BackColor $script:Theme.CardBg -ForeColor $script:Theme.InkPrimary -Font $script:FontSmall -PadX 10 -PadY 6 -ReadOnly $true
    $pnlSpecTextWrap = $specBox.Panel
    $txtSpecChk      = $specBox.TextBox

    $tpSpec.Controls.Add($pnlSpecTextWrap)
    $tpSpec.Controls.Add($pnlSpecTop)
    $pnlSpecTextWrap.BringToFront()

    $tabHelper.TabPages.Add($tpAuth)
    $tabHelper.TabPages.Add($tpSpec)
    $pnlHelper.Controls.Add($tabHelper)

    # ---------------- [6] 3단계 복원 실행 액션 바 (FlowLayoutPanel — DPI 안전) ----------------
    $pnlAction = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlAction.Dock          = [System.Windows.Forms.DockStyle]::Bottom
    $pnlAction.Height        = 44
    $pnlAction.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlAction.WrapContents  = $false
    $pnlAction.BackColor     = [System.Drawing.Color]::Transparent
    $pnlAction.Padding       = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $lblStep3 = New-Object System.Windows.Forms.Label
    $lblStep3.Text      = ' 3단계 '
    $lblStep3.Font      = $script:FontSmallB
    $lblStep3.BackColor = $script:Theme.AsanGreen
    $lblStep3.ForeColor = [System.Drawing.Color]::White
    $lblStep3.AutoSize  = $true
    $lblStep3.Padding   = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
    $lblStep3.Margin    = New-Object System.Windows.Forms.Padding(0, 7, 8, 0)

    $btnStart = New-StyledButton -Text '선택 항목 복원하기' -Width 166 -Height 34 -Variant 'Primary' -RegisterBusy
    $btnStart.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $btnStart.Enabled = $false
    $btnStart.Add_Click({ Start-Tab2RestoreExecution })

    $btnRetry = New-StyledButton -Text '실패 항목 다시 시도' -Width 148 -Height 34 -Variant 'Orange' -RegisterBusy
    $btnRetry.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $btnRetry.Enabled = $false
    $btnRetry.Add_Click({ Start-Tab2RestoreExecution -RetryFailedOnly })

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text      = '응답 없는 프린터와 전용 설치 기종은 안전을 위해 자동 해제됩니다.'
    $lblHint.Font      = $script:FontSmall
    $lblHint.ForeColor = $script:Theme.InkSecondary
    $lblHint.AutoSize  = $true
    $lblHint.Margin    = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $pnlAction.Controls.AddRange(@($lblStep3, $btnStart, $btnRetry, $lblHint))

    # Dock Z-Order: Fill(0) -> Bottom(Inner) -> Bottom(Outer) -> Top(Inner) -> Top(Mid) -> Top(Outer)
    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlHelper)
    $parent.Controls.Add($pnlAction)
    $parent.Controls.Add($pnlGridBar)
    $parent.Controls.Add($pnlNotes)
    $parent.Controls.Add($pnlSourceOuter)
    $dgv.BringToFront()

    $script:Tab2Ui.CmbServerBackups = $cmbBackups
    $script:Tab2Ui.BtnLoadServer    = $btnLoadSrv
    $script:Tab2Ui.BtnSearchServer  = $btnSearchSrv
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
    $script:Tab2Ui.PnlAuthTop       = $pnlAuthTop
    $script:Tab2Ui.PnlSpecTop       = $pnlSpecTop
    $script:Tab2Ui.PnlSourceOuter   = $pnlSourceOuter
    $script:Tab2Ui.PnlNotes         = $pnlNotes
    $script:Tab2Ui.PnlNotesWrap     = $pnlNotesWrap
    $script:Tab2Ui.PnlGridBar       = $pnlGridBar
    $script:Tab2Ui.PnlAction        = $pnlAction
    $script:Tab2Ui.PnlAuthTextWrap  = $pnlAuthTextWrap
    $script:Tab2Ui.PnlSpecTextWrap  = $pnlSpecTextWrap
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

    $pnlAuthTop.Add_SizeChanged({ Update-Tab2HelperHeightSafe })
    $pnlSpecTop.Add_SizeChanged({ Update-Tab2HelperHeightSafe })
    $parent.Add_SizeChanged({ Update-Tab2HelperHeightSafe })

    $script:Ui.OnEnvRefreshed.Add({ Update-Tab2ServerDropdown })
}
