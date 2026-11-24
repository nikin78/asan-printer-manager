# ============================================================================
# [Module 02] 공용 WinForms GUI 셸(3-1) + 탭 1 백업(3-2) 최종본
# - Module 01(Rev.5 최종 코어) 하단에 무손실 결합됨
# - 3-5B 패치 반영: C1, C2, C3, C4, C5, H2
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# UI 컨트롤 참조, 앱 런타임 상태, 비동기 스레드 제어 상태
$script:Ui = @{
    Form               = $null
    PnlHeader          = $null
    PnlWppBanner       = $null
    PnlFooter          = $null
    TabMain            = $null
    TabBackup          = $null
    TabRestore         = $null
    TabVerify          = $null
    TabServer          = $null
    LblTitle           = $null
    LblOs              = $null
    LblPcIp            = $null
    LblSid             = $null
    BtnCopySid         = $null
    BtnBugReport       = $null
    LblNetBadge        = $null
    LblServerPath      = $null
    BtnRefresh         = $null
    LblWppTitle        = $null
    BtnWppGuide        = $null
    BtnWppAction       = $null
    PrgBar             = $null
    LblProgressText    = $null
    TxtLog             = $null
    BtnToggleLog       = $null
    BtnClearLog        = $null
    LogExpanded        = $true
    BusyControls       = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    OnEnvRefreshed     = [System.Collections.Generic.List[scriptblock]]::new()
    OnRestoreCompleted = [System.Collections.Generic.List[scriptblock]]::new()
}

$script:AppState = @{
    OsCaption         = ''
    IsWin11           = $false
    LocalSid          = ''
    NetworkInfo       = $null
    DiagnosedPrinters = @()
    ScannerInventory  = $null
    ServerBackups     = @()
    CurrentBackupMeta = $null
    RestoreRows       = @()
    AuthFailedHosts   = @()
}

$script:AsyncState = @{
    IsBusy        = $false
    TaskName      = ''
    Runspace      = $null
    PowerShell    = $null
    AsyncResult   = $null
    OnComplete    = $null
    CallbackState = $null
    PollTimer     = $null
}

# ============================================================================
# 공용 UI 스타일 팩토리, [C2] 우측 정렬 스트립, [C4] 공백 경로 탐색기 헬퍼
# ============================================================================
$script:FontBase  = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Regular)
$script:FontBold  = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
$script:FontTitle = New-Object System.Drawing.Font('맑은 고딕', 11.5, [System.Drawing.FontStyle]::Bold)
$script:FontSmall = New-Object System.Drawing.Font('맑은 고딕', 8.5, [System.Drawing.FontStyle]::Regular)
$script:FontMono  = New-Object System.Drawing.Font('Consolas', 8.5, [System.Drawing.FontStyle]::Regular)

function Open-FolderInExplorerSafe {
    param([string]$FolderPath)
    if ([string]::IsNullOrWhiteSpace($FolderPath)) { return }
    if (-not (Test-Path -LiteralPath $FolderPath)) { return }
    $clean = $FolderPath.Trim()
    if ($clean.Length -gt 3 -and $clean.EndsWith('\')) { $clean = $clean.TrimEnd('\') }
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $clean + '"')
    } catch {}
}

function New-RightFlowStrip {
    param(
        [int]$TopPadding = 4,
        [int]$RightPadding = 4
    )
    $flp = New-Object System.Windows.Forms.FlowLayoutPanel
    $flp.Dock          = [System.Windows.Forms.DockStyle]::Right
    $flp.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $flp.WrapContents  = $false
    $flp.AutoSize      = $true
    $flp.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flp.BackColor     = [System.Drawing.Color]::Transparent
    $flp.Padding       = New-Object System.Windows.Forms.Padding(0, $TopPadding, $RightPadding, 0)
    $flp.Margin        = New-Object System.Windows.Forms.Padding(0)
    return $flp
}

function New-StyledButton {
    param(
        [string]$Text,
        [int]$Width = 120,
        [int]$Height = 30,
        [System.Drawing.Color]$BackColor = ([System.Drawing.Color]::FromArgb(37, 99, 235)),
        [System.Drawing.Color]$ForeColor = ([System.Drawing.Color]::White),
        [switch]$RegisterBusy
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = $Text
    $btn.Size      = New-Object System.Drawing.Size($Width, $Height)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.Font      = $script:FontBold
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    if ($RegisterBusy) { $script:Ui.BusyControls.Add($btn) }
    return $btn
}

function New-StyledGrid {
    param([switch]$AllowCheckEdit)
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.AllowUserToAddRows          = $false
    $dgv.AllowUserToDeleteRows       = $false
    $dgv.AllowUserToResizeRows       = $false
    $dgv.RowHeadersVisible           = $false
    $dgv.MultiSelect                 = $false
    $dgv.SelectionMode               = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $dgv.BackgroundColor             = [System.Drawing.Color]::White
    $dgv.BorderStyle                 = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgv.GridColor                   = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $dgv.EnableHeadersVisualStyles   = $false
    $dgv.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $dgv.ColumnHeadersHeight         = 30
    $dgv.RowTemplate.Height          = 26
    $dgv.Font                        = $script:FontBase
    $dgv.AutoSizeColumnsMode         = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None

    $dgv.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $dgv.ColumnHeadersDefaultCellStyle.Font      = $script:FontBold
    $dgv.DefaultCellStyle.SelectionBackColor     = [System.Drawing.Color]::FromArgb(219, 234, 254)
    $dgv.DefaultCellStyle.SelectionForeColor     = [System.Drawing.Color]::FromArgb(15, 23, 42)

    if (-not $AllowCheckEdit) {
        $dgv.ReadOnly = $true
    } else {
        $dgv.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    }

    try {
        $prop = [System.Windows.Forms.DataGridView].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($prop) { $prop.SetValue($dgv, $true, $null) }
    } catch {}

    return $dgv
}

function Add-UiLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    if (-not $script:Ui.TxtLog -or $script:Ui.TxtLog.IsDisposed) { return }
    $ts   = (Get-Date).ToString('HH:mm:ss')
    $line = "[$ts][$Level] $Message`r`n"
    if ($script:Ui.TxtLog.TextLength -gt 60000) {
        $script:Ui.TxtLog.Text = $script:Ui.TxtLog.Text.Substring(30000)
    }
    $script:Ui.TxtLog.AppendText($line)
    $script:Ui.TxtLog.SelectionStart = $script:Ui.TxtLog.TextLength
    $script:Ui.TxtLog.ScrollToCaret()
}

# ============================================================================
# [C3 Fix] 전 탭 조건부 버튼 활성 상태 중앙 동기화
# ============================================================================
function Sync-AllUiButtonStates {
    $busy     = [bool]$script:AsyncState.IsBusy
    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir))

    # 탭 1: 서버 백업 버튼은 온라인일 때만 활성
    if ($script:Tab1Ui -and $script:Tab1Ui.BtnBackupServer -and -not $script:Tab1Ui.BtnBackupServer.IsDisposed) {
        $script:Tab1Ui.BtnBackupServer.Enabled = ((-not $busy) -and $isOnline)
        if ($isOnline) {
            $script:Tab1Ui.BtnBackupServer.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
        } else {
            $script:Tab1Ui.BtnBackupServer.BackColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
        }
    }

    # 탭 2: 백업 로드 여부, 선택 개수, 실패 건수, SIP-30M 2단계 조건 정확 반영
    if ($script:Tab2Ui -and $script:Tab2Ui.DgvRestore -and -not $script:Tab2Ui.DgvRestore.IsDisposed) {
        $hasServer = ((@($script:Tab2Ui.ComboBackupEntries)).Count -gt 0)
        $hasLoaded = (-not [string]::IsNullOrWhiteSpace([string]$script:Tab2Ui.LoadedSourcePath))
        $hasFail   = ((@($script:Tab2Ui.LastFailures)).Count -gt 0)
        $selCnt    = 0
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) {
            if ($r.Cells[0].Value -eq $true) { $selCnt++ }
        }
        $hasSip2 = ($null -ne $script:Tab2Ui.CurrentSpecInfo -and [bool]$script:Tab2Ui.CurrentSpecInfo.Info.HasStep2)

        if ($script:Tab2Ui.BtnLoadServer)   { $script:Tab2Ui.BtnLoadServer.Enabled   = ((-not $busy) -and $hasServer) }
        if ($script:Tab2Ui.BtnRunDeferred)  { $script:Tab2Ui.BtnRunDeferred.Enabled  = ((-not $busy) -and $hasLoaded) }
        if ($script:Tab2Ui.BtnStartRestore) { $script:Tab2Ui.BtnStartRestore.Enabled = ((-not $busy) -and $hasLoaded -and ($selCnt -gt 0)) }
        if ($script:Tab2Ui.BtnRetryFailed)  { $script:Tab2Ui.BtnRetryFailed.Enabled  = ((-not $busy) -and $hasLoaded -and $hasFail) }
        if ($script:Tab2Ui.BtnSpecStep2)    { $script:Tab2Ui.BtnSpecStep2.Enabled    = ((-not $busy) -and $hasSip2) }
    }

    # 탭 4: 5일 경과 수 및 행 선택 상태 반영
    if ($script:Tab4Ui -and $script:Tab4Ui.DgvServer -and -not $script:Tab4Ui.DgvServer.IsDisposed) {
        $old5   = (@($script:AppState.ServerBackups | Where-Object { $_.IsOld5Days })).Count
        $hasSel = ($script:Tab4Ui.DgvServer.SelectedRows.Count -gt 0)
        if ($script:Tab4Ui.BtnCleanOld5)  { $script:Tab4Ui.BtnCleanOld5.Enabled  = ((-not $busy) -and $isOnline -and ($old5 -gt 0)) }
        if ($script:Tab4Ui.BtnLoadToTab2) { $script:Tab4Ui.BtnLoadToTab2.Enabled = ((-not $busy) -and $hasSel) }
        if ($script:Tab4Ui.BtnDeleteOne)  { $script:Tab4Ui.BtnDeleteOne.Enabled  = ((-not $busy) -and $isOnline -and $hasSel) }
    }
}

function Set-UiBusyState {
    param(
        [bool]$IsBusy,
        [string]$StatusText = '',
        [switch]$Indeterminate
    )
    $script:AsyncState.IsBusy = $IsBusy
    foreach ($ctrl in $script:Ui.BusyControls) {
        if ($ctrl -and -not $ctrl.IsDisposed) {
            $ctrl.Enabled = (-not $IsBusy)
        }
    }
    if (-not $IsBusy) {
        Sync-AllUiButtonStates
    }
    if ($script:Ui.Form -and -not $script:Ui.Form.IsDisposed) {
        if ($IsBusy) { $script:Ui.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor }
        else { $script:Ui.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    if ($script:Ui.PrgBar -and -not $script:Ui.PrgBar.IsDisposed) {
        if ($IsBusy) {
            if ($Indeterminate) {
                $script:Ui.PrgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            } else {
                $script:Ui.PrgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                $script:Ui.PrgBar.Value = 5
            }
        } else {
            $script:Ui.PrgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $script:Ui.PrgBar.Value = 0
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($StatusText) -and $script:Ui.LblProgressText) {
        $script:Ui.LblProgressText.Text = $StatusText
    }
}

# ============================================================================
# Runspace 비동기 작업 실행기 ([H2] 코어 스냅샷 전용 주입 + [C1] CallbackState)
# ============================================================================
function New-AsanChildInitialSessionState {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    $varEntry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('AsanCtx', $global:AsanCtx, 'Shared Asan Context')
    $iss.Variables.Add($varEntry)

    foreach ($fnName in @($script:CoreFunctionNames)) {
        $fnItem = Get-Item -Path "Function:\$fnName" -ErrorAction SilentlyContinue
        if ($fnItem) {
            $fnEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fnItem.Name, $fnItem.Definition)
            $iss.Commands.Add($fnEntry)
        }
    }

    return $iss
}

function Stop-ActiveAsyncRunspace {
    if ($script:AsyncState.PollTimer) {
        try { $script:AsyncState.PollTimer.Stop() } catch {}
    }
    if ($script:AsyncState.PowerShell) {
        try { $script:AsyncState.PowerShell.Stop() } catch {}
        try { $script:AsyncState.PowerShell.Dispose() } catch {}
        $script:AsyncState.PowerShell = $null
    }
    if ($script:AsyncState.Runspace) {
        try { $script:AsyncState.Runspace.Close() } catch {}
        try { $script:AsyncState.Runspace.Dispose() } catch {}
        $script:AsyncState.Runspace = $null
    }
    $script:AsyncState.AsyncResult   = $null
    $script:AsyncState.OnComplete    = $null
    $script:AsyncState.CallbackState = $null
    $script:AsyncState.IsBusy        = $false
}

function Drain-AsyncLogQueue {
    $item = $null
    while ($global:AsanCtx.LogQueue.TryDequeue([ref]$item)) {
        if ($null -eq $item) { continue }
        if ($script:Ui.PrgBar -and -not $script:Ui.PrgBar.IsDisposed) {
            $pct = [int]$item.Percent
            if ($pct -ge 0 -and $pct -le 100) {
                if ($script:Ui.PrgBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Continuous) {
                    $script:Ui.PrgBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                }
                $script:Ui.PrgBar.Value = $pct
            }
        }
        if ($script:Ui.LblProgressText -and -not [string]::IsNullOrWhiteSpace($item.Message)) {
            $script:Ui.LblProgressText.Text = $item.Message
        }
        if (-not [string]::IsNullOrWhiteSpace($item.Message)) {
            Add-UiLog -Message $item.Message -Level 'WORK'
        }
    }
}

function Invoke-AsanAsyncTask {
    param(
        [string]$TaskName,
        [scriptblock]$WorkScript,
        [hashtable]$Params = @{},
        [scriptblock]$OnComplete = $null,
        [object]$CallbackState = $null,
        [switch]$Indeterminate
    )

    if ($script:AsyncState.IsBusy) {
        [System.Windows.Forms.MessageBox]::Show(
            "현재 '$($script:AsyncState.TaskName)' 작업이 진행 중입니다. 완료 후 다시 시도하세요.",
            '작업 진행 중',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $dummy = $null
    while ($global:AsanCtx.LogQueue.TryDequeue([ref]$dummy)) {}

    Set-UiBusyState -IsBusy $true -StatusText "$TaskName 시작 중..." -Indeterminate:$Indeterminate
    Add-UiLog -Message "=== [$TaskName] 시작 ===" -Level 'INFO'

    try {
        $iss = New-AsanChildInitialSessionState
        $rs  = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs

        $wrapperCode = {
            param([string]$BodyText, [hashtable]$ArgMap)
            $ErrorActionPreference = 'Stop'
            Import-Module PrintManagement -ErrorAction SilentlyContinue
            try {
                $sb  = [scriptblock]::Create($BodyText)
                $res = & $sb $ArgMap
                return [pscustomobject]@{
                    Ok    = $true
                    Data  = $res
                    Error = $null
                }
            }
            catch {
                $errDetail = $_.Exception.Message
                if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
                    $errDetail = "$errDetail (Line $($_.InvocationInfo.ScriptLineNumber))"
                }
                return [pscustomobject]@{
                    Ok    = $false
                    Data  = $null
                    Error = $errDetail
                }
            }
        }

        [void]$ps.AddScript($wrapperCode).AddArgument($WorkScript.ToString()).AddArgument($Params)
        $asyncRes = $ps.BeginInvoke()

        $script:AsyncState.TaskName      = $TaskName
        $script:AsyncState.Runspace      = $rs
        $script:AsyncState.PowerShell    = $ps
        $script:AsyncState.AsyncResult   = $asyncRes
        $script:AsyncState.OnComplete    = $OnComplete
        $script:AsyncState.CallbackState = $CallbackState

        $script:AsyncState.PollTimer.Start()
    }
    catch {
        Stop-ActiveAsyncRunspace
        Set-UiBusyState -IsBusy $false -StatusText '작업 시작 실패'
        Add-UiLog -Message "비동기 작업 기동 오류: $($_.Exception.Message)" -Level 'ERROR'
        [System.Windows.Forms.MessageBox]::Show(
            "작업을 시작할 수 없습니다:`r`n$($_.Exception.Message)",
            '실행 오류',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# ============================================================================
# [C1 Fix] WPP 조치 안내 대화상자 (클로저 소실 제거: Tag + DialogResult)
# ============================================================================
function Show-WppRemediationDialog {
    param($WppStatus)
    if (-not $WppStatus -or -not $WppStatus.IsEnabled) { return }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Windows 보호 인쇄 모드(WPP) 해제 안내'
    $dlg.Size            = New-Object System.Drawing.Size(620, 395)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [System.Drawing.Color]::White
    $dlg.Font            = $script:FontBase

    $lblHead = New-Object System.Windows.Forms.Label
    $lblHead.Text      = $WppStatus.BannerTitle
    $lblHead.Dock      = [System.Windows.Forms.DockStyle]::Top
    $lblHead.Height    = 46
    $lblHead.BackColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $lblHead.ForeColor = [System.Drawing.Color]::White
    $lblHead.Font      = $script:FontBold
    $lblHead.Padding   = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $lblHead.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 52
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)

    $btnOpen = New-StyledButton -Text 'Windows 프린터 설정 열기' -Width 218 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(185, 28, 28))
    if ($WppStatus.IsPolicyEnforced) { $btnOpen.Text = '로컬 그룹 정책(gpedit.msc) 열기' }
    $btnOpen.Dock = [System.Windows.Forms.DockStyle]::Left
    $btnOpen.Tag  = $WppStatus
    $btnOpen.Add_Click({
        param($sender, $e)
        $w = $sender.Tag
        if (-not $w) { return }
        try {
            if ($w.IsPolicyEnforced) {
                Start-Process -FilePath 'mmc.exe' -ArgumentList 'gpedit.msc'
            } else {
                Start-Process -FilePath $w.SettingsUri
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("설정 창을 열지 못했습니다: $($_.Exception.Message)", '열기 실패', 'OK', 'Warning') | Out-Null
        }
    })

    $btnClose = New-StyledButton -Text '닫기 (해제 후 F5 새로고침)' -Width 208 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnClose.Dock         = [System.Windows.Forms.DockStyle]::Right
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $pnlBot.Controls.Add($btnOpen)
    $pnlBot.Controls.Add($btnClose)

    $pnlBody = New-Object System.Windows.Forms.Panel
    $pnlBody.Dock    = [System.Windows.Forms.DockStyle]::Fill
    $pnlBody.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 6)

    $txtGuide = New-Object System.Windows.Forms.TextBox
    $txtGuide.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtGuide.Multiline   = $true
    $txtGuide.ReadOnly    = $true
    $txtGuide.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtGuide.BackColor   = [System.Drawing.Color]::FromArgb(254, 242, 242)
    $txtGuide.ForeColor   = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $txtGuide.Font        = $script:FontBase
    $txtGuide.Text        = $WppStatus.RemediationGuide
    $pnlBody.Controls.Add($txtGuide)

    $dlg.CancelButton = $btnClose
    $dlg.Controls.Add($pnlBody)
    $dlg.Controls.Add($pnlBot)
    $dlg.Controls.Add($lblHead)
    $pnlBody.BringToFront()

    [void]$dlg.ShowDialog($script:Ui.Form)
    $dlg.Dispose()
}

# ============================================================================
# [버그/오류 리포트 팝업] DialogResult 기반 클로저 안전 + _PRTBAK\_REPORTS 전송
# ============================================================================
function Show-BugReportDialog {
    param(
        [string]$DefaultCategory = '복원/드라이버 오류',
        [string]$DefaultPrinter = '',
        [string]$ErrorSummary = ''
    )

    if ($script:AsyncState.IsBusy) {
        [System.Windows.Forms.MessageBox]::Show('현재 진행 중인 작업이 완료된 뒤 리포트를 전송해 주세요.', '작업 진행 중', 'OK', 'Information') | Out-Null
        return
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = '오류 / 버그 리포트 전송 (_PRTBAK\_REPORTS)'
    $dlg.Size            = New-Object System.Drawing.Size(560, 420)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [System.Drawing.Color]::White
    $dlg.Font            = $script:FontBase
    $dlg.Padding         = New-Object System.Windows.Forms.Padding(14)

    $lblGuide = New-Object System.Windows.Forms.Label
    $lblGuide.Text      = '현장 오류 상황·PC 환경·프린터/포트/LPT/USB 상태·실시간 로그를 서버 리포트함(_PRTBAK\_REPORTS)으로 자동 수집·전송합니다. (비밀번호 자동 마스킹 / 오프라인 시 로컬 저장)'
    $lblGuide.Dock      = [System.Windows.Forms.DockStyle]::Top
    $lblGuide.Height    = 40
    $lblGuide.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $lblGuide.Font      = $script:FontSmall

    $pnlFields = New-Object System.Windows.Forms.Panel
    $pnlFields.Dock   = [System.Windows.Forms.DockStyle]::Top
    $pnlFields.Height = 76

    $lblCat = New-Object System.Windows.Forms.Label
    $lblCat.Text     = '증상 분류:'
    $lblCat.Font     = $script:FontBold
    $lblCat.AutoSize = $true
    $lblCat.Location = New-Object System.Drawing.Point(0, 10)

    $cmbCat = New-Object System.Windows.Forms.ComboBox
    $cmbCat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbCat.Location      = New-Object System.Drawing.Point(84, 6)
    $cmbCat.Size          = New-Object System.Drawing.Size(220, 24)
    foreach ($cat in @('복원/드라이버 오류', '백업 오류', 'WSD/포트 전환', '공유 인증/SID 충돌', '특수/바코드 프린터', 'UI/프로그램 버그', '기타')) {
        [void]$cmbCat.Items.Add($cat)
    }
    $catIdx = $cmbCat.Items.IndexOf($DefaultCategory)
    if ($catIdx -lt 0) { $catIdx = 0 }
    $cmbCat.SelectedIndex = $catIdx

    $lblPrt = New-Object System.Windows.Forms.Label
    $lblPrt.Text     = '대상 프린터:'
    $lblPrt.Font     = $script:FontBold
    $lblPrt.AutoSize = $true
    $lblPrt.Location = New-Object System.Drawing.Point(0, 44)

    $cmbPrt = New-Object System.Windows.Forms.ComboBox
    $cmbPrt.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cmbPrt.Location      = New-Object System.Drawing.Point(84, 40)
    $cmbPrt.Size          = New-Object System.Drawing.Size(426, 24)
    $prtSeen = @{}
    [void]$cmbPrt.Items.Add('(전체/미지정)')
    $prtSeen['(전체/미지정)'] = $true
    foreach ($srcList in @($script:AppState.RestoreRows, $script:AppState.DiagnosedPrinters)) {
        foreach ($item in @($srcList)) {
            $pn = [string]$item.PrinterName
            if (-not [string]::IsNullOrWhiteSpace($pn) -and -not $prtSeen.ContainsKey($pn)) {
                $prtSeen[$pn] = $true
                [void]$cmbPrt.Items.Add($pn)
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($DefaultPrinter)) {
        $cmbPrt.Text = $DefaultPrinter
    } else {
        $cmbPrt.SelectedIndex = 0
    }

    $pnlFields.Controls.AddRange(@($lblCat, $cmbCat, $lblPrt, $cmbPrt))

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 46
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $flpRight = New-RightFlowStrip -TopPadding 0 -RightPadding 0
    $btnCan = New-StyledButton -Text '취소' -Width 92 -Height 32 -BackColor ([System.Drawing.Color]::FromArgb(100, 116, 139))
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCan.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnSend = New-StyledButton -Text '리포트 전송' -Width 126 -Height 32 -BackColor ([System.Drawing.Color]::FromArgb(234, 88, 12))
    $btnSend.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $flpRight.Controls.Add($btnCan)
    $flpRight.Controls.Add($btnSend)
    $pnlBot.Controls.Add($flpRight)

    $pnlMemo = New-Object System.Windows.Forms.Panel
    $pnlMemo.Dock    = [System.Windows.Forms.DockStyle]::Fill
    $pnlMemo.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $lblMemo = New-Object System.Windows.Forms.Label
    $lblMemo.Text   = '현장 상황 메모 (예: 어떤 프린터/단계에서 무슨 오류가 났는지 간단히 기입):'
    $lblMemo.Font   = $script:FontBold
    $lblMemo.Dock   = [System.Windows.Forms.DockStyle]::Top
    $lblMemo.Height = 22

    $txtMemo = New-Object System.Windows.Forms.TextBox
    $txtMemo.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtMemo.Multiline   = $true
    $txtMemo.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtMemo.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtMemo.Font        = $script:FontBase
    if (-not [string]::IsNullOrWhiteSpace($ErrorSummary)) {
        $txtMemo.Text = "[자동 첨부 오류 요약]`r`n$ErrorSummary`r`n`r`n[현장 추가 메모]`r`n"
        $txtMemo.SelectionStart = $txtMemo.TextLength
    }

    $pnlMemo.Controls.Add($txtMemo)
    $pnlMemo.Controls.Add($lblMemo)
    $txtMemo.BringToFront()

    $dlg.AcceptButton = $btnSend
    $dlg.CancelButton = $btnCan
    $dlg.Controls.Add($pnlMemo)
    $dlg.Controls.Add($pnlBot)
    $dlg.Controls.Add($pnlFields)
    $dlg.Controls.Add($lblGuide)
    $pnlMemo.BringToFront()

    $dr = $dlg.ShowDialog($script:Ui.Form)
    $selCat  = [string]$cmbCat.SelectedItem
    $selPrt  = $cmbPrt.Text.Trim()
    $memoVal = $txtMemo.Text.Trim()
    $dlg.Dispose()

    if ($dr -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $net     = $script:AppState.NetworkInfo
    $prtBak  = $null
    $pcIp    = 'NO_IP'
    $netStat = 'Unknown'
    $wppOn   = $false
    if ($net) {
        $prtBak  = $net.PrtBakDir
        $pcIp    = [string]$net.IPAddress
        $netStat = [string]$net.Status
        if ($net.WppStatus) { $wppOn = [bool]$net.WppStatus.IsEnabled }
    }
    $uiLog = ''
    if ($script:Ui.TxtLog -and -not $script:Ui.TxtLog.IsDisposed) { $uiLog = [string]$script:Ui.TxtLog.Text }
    $loadedSrc = ''
    if ($script:Tab2Ui -and $script:Tab2Ui.LoadedSourcePath) { $loadedSrc = [string]$script:Tab2Ui.LoadedSourcePath }
    $extraSec = @()
    if ($script:Tab2Ui -and $script:Tab2Ui.TxtAuthPass -and -not [string]::IsNullOrWhiteSpace($script:Tab2Ui.TxtAuthPass.Text)) {
        $extraSec = @($script:Tab2Ui.TxtAuthPass.Text)
    }

    $tParams = @{
        Category           = $selCat
        UserDescription    = $memoVal
        TargetPrinter      = $selPrt
        UiLogText          = $uiLog
        ErrorSummary       = $ErrorSummary
        PrtBakDir          = $prtBak
        PcIp               = $pcIp
        OsCaption          = [string]$script:AppState.OsCaption
        LocalSid           = [string]$script:AppState.LocalSid
        NetStatus          = $netStat
        WppEnabled         = $wppOn
        LoadedBackupSource = $loadedSrc
        ExtraSecrets       = $extraSec
    }

    $work = {
        param($arg)
        Write-ProgressSafe -Percent 40 -Message '환경·프린터·포트·LPT/USB 상태 수집 및 민감정보 마스킹 중...'
        $res = Send-AsanBugReport `
            -Category ([string]$arg.Category) `
            -UserDescription ([string]$arg.UserDescription) `
            -TargetPrinter ([string]$arg.TargetPrinter) `
            -UiLogText ([string]$arg.UiLogText) `
            -ErrorSummary ([string]$arg.ErrorSummary) `
            -PrtBakDir $arg.PrtBakDir `
            -PcIp ([string]$arg.PcIp) `
            -OsCaption ([string]$arg.OsCaption) `
            -LocalSid ([string]$arg.LocalSid) `
            -NetStatus ([string]$arg.NetStatus) `
            -WppEnabled ([bool]$arg.WppEnabled) `
            -LoadedBackupSource ([string]$arg.LoadedBackupSource) `
            -ExtraSecrets @($arg.ExtraSecrets)
        Write-ProgressSafe -Percent 100 -Message "버그 리포트 저장 완료: $($res.SavedPath)"
        return $res
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "버그 리포트 전송 실패: $err" -Level 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("버그 리포트 전송 중 오류가 발생했습니다:`r`n$err", '전송 오류', 'OK', 'Error') | Out-Null
            return
        }
        if ($data.SavedToServer) {
            Add-UiLog -Message "서버 리포트함 전송 완료: $($data.SavedPath)" -Level 'INFO'
            [System.Windows.Forms.MessageBox]::Show(
                "오류/버그 리포트가 사내 서버 리포트함으로 전송되었습니다.`r`n`r`n• 리포트 ID: $($data.ReportId)`r`n• 저장 경로: $($data.SavedPath)",
                '리포트 전송 완료',
                'OK',
                'Information'
            ) | Out-Null
        } else {
            Add-UiLog -Message "오프라인/로컬 리포트 저장 완료: $($data.SavedPath)" -Level 'WARN'
            [System.Windows.Forms.MessageBox]::Show(
                "서버 연결이 불가하여 로컬 오프라인 리포트 폴더에 저장했습니다.`r`n`r`n• 저장 경로: $($data.SavedPath)`r`n• 추후 파일만 개발 담당자에게 전달해 주세요.",
                '로컬 리포트 저장 완료',
                'OK',
                'Information'
            ) | Out-Null
        }
    }

    Invoke-AsanAsyncTask -TaskName '오류/버그 리포트 수집 및 전송' -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
}

function Update-HeaderAndWppUi {
    $net = $script:AppState.NetworkInfo
    $script:Ui.LblOs.Text  = "OS: $($script:AppState.OsCaption)"
    $script:Ui.LblSid.Text = "Machine SID: $($script:AppState.LocalSid)"

    $ipText = '확인 중...'
    if ($net) { $ipText = $net.IPAddress }
    $script:Ui.LblPcIp.Text = "PC: $($env:COMPUTERNAME) ($ipText)"

    if (-not $net) {
        $script:Ui.LblNetBadge.Text      = ' ● 연결 확인 중... '
        $script:Ui.LblNetBadge.BackColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        $script:Ui.LblServerPath.Text    = '백업 서버 연결 상태 확인 중...'
        $script:Ui.PnlWppBanner.Visible  = $false
        return
    }

    if ($net.Status -eq 'Online') {
        $script:Ui.LblNetBadge.Text      = ' ● 사내망 / 서버 온라인 '
        $script:Ui.LblNetBadge.BackColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
        $script:Ui.LblServerPath.Text    = "백업 경로: $($net.PrtBakDir)"
    } elseif ($net.Status -eq 'IntranetOnly') {
        $script:Ui.LblNetBadge.Text      = ' ▲ 사내망 연결 / 서버 미응답 '
        $script:Ui.LblNetBadge.BackColor = [System.Drawing.Color]::FromArgb(217, 119, 6)
        $script:Ui.LblServerPath.Text    = $net.Message
    } else {
        $script:Ui.LblNetBadge.Text      = ' ■ 오프라인 (네트워크 설정 필요) '
        $script:Ui.LblNetBadge.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
        $script:Ui.LblServerPath.Text    = $net.Message
    }

    $wpp = $net.WppStatus
    if ($wpp -and $wpp.IsEnabled) {
        $script:Ui.LblWppTitle.Text = $wpp.BannerTitle
        if ($wpp.IsPolicyEnforced) { $script:Ui.BtnWppAction.Text = '그룹 정책 열기' }
        else { $script:Ui.BtnWppAction.Text = '프린터 설정 열기' }
        $script:Ui.PnlWppBanner.Visible = $true
        Add-UiLog -Message $wpp.BannerTitle -Level 'WARN'
    } else {
        $script:Ui.PnlWppBanner.Visible = $false
    }
}

function Invoke-EnvironmentRefreshAsync {
    param([scriptblock]$AfterRefresh = $null)

    $work = {
        param($arg)
        Write-ProgressSafe -Percent 20 -Message '운영체제·Machine SID 및 WPP 정책 점검 중...'
        $osObj = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $osCap = 'Windows'
        $build = 0
        if ($osObj) {
            $osCap = [string]$osObj.Caption
            [void][int]::TryParse([string]$osObj.BuildNumber, [ref]$build)
        }
        $sid = Get-LocalMachineSID

        Write-ProgressSafe -Percent 55 -Message "아산병원 사내망(DNS $($global:AsanCtx.InternalDnsIP)) 및 백업 서버($($global:AsanCtx.ServerIP)) 연결 확인 중..."
        $net = Test-AsanNetworkAndServer

        $backups = @()
        if ($net.PrtBakDir) {
            Write-ProgressSafe -Percent 85 -Message '서버 백업 목록 조회 중...'
            $backups = @(Get-ServerBackupEntries -PrtBakDir $net.PrtBakDir -PcIp $net.IPAddress)
        }

        Write-ProgressSafe -Percent 100 -Message '환경 진단 완료'
        return [pscustomobject]@{
            OsCaption     = $osCap
            IsWin11       = ($build -ge 22000 -or $osCap -match 'Windows 11')
            LocalSid      = $sid
            NetworkInfo   = $net
            ServerBackups = $backups
        }
    }

    # [C1 Fix] $cbState로 $AfterRefresh 전달받아 PS 5.1 동적 스코프 소실 차단
    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "환경 진단 실패: $err" -Level 'ERROR'
            return
        }
        $script:AppState.OsCaption     = $data.OsCaption
        $script:AppState.IsWin11       = [bool]$data.IsWin11
        $script:AppState.LocalSid      = $data.LocalSid
        $script:AppState.NetworkInfo   = $data.NetworkInfo
        $script:AppState.ServerBackups = @($data.ServerBackups)

        Update-HeaderAndWppUi

        foreach ($cb in $script:Ui.OnEnvRefreshed) {
            try { & $cb } catch {}
        }
        Sync-AllUiButtonStates

        if ($cbState -is [scriptblock]) {
            try { & $cbState } catch { Add-UiLog -Message "초기화 후속 작업 오류: $($_.Exception.Message)" -Level 'ERROR' }
        }
    }

    Invoke-AsanAsyncTask -TaskName '환경 및 네트워크 새로고침' -WorkScript $work -OnComplete $done -CallbackState $AfterRefresh
}

# ============================================================================
# [C2 Fix] 메인 WinForms 셸 조립 (전 영역 Dock + RightFlowStrip 구조화)
# ============================================================================
function Initialize-MainGuiShell {
    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "아산병원 프린터/드라이버 통합 마이그레이션 도구 v$($global:AsanCtx.AppVersion)"
    $form.Size          = New-Object System.Drawing.Size(1040, 720)
    $form.MinimumSize   = New-Object System.Drawing.Size(960, 640)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor     = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $form.Font          = $script:FontBase
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $form.KeyPreview    = $true

    # ---------------- [1] 최상단 고정 상태 바 (3행 Dock 구조) ----------------
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height    = 88
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $pnlHeader.Padding   = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)

    # Row 1: 좌 타이틀 / 우 새로고침 + 네트워크 배지
    $pnlHdrRow1 = New-Object System.Windows.Forms.Panel
    $pnlHdrRow1.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlHdrRow1.Height    = 32
    $pnlHdrRow1.BackColor = [System.Drawing.Color]::Transparent

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "아산병원 프린터/드라이버 통합 마이그레이션 도구 v$($global:AsanCtx.AppVersion)"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font      = $script:FontTitle
    $lblTitle.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $flpHdrRight1 = New-RightFlowStrip -TopPadding 2 -RightPadding 0

    $btnRefresh = New-StyledButton -Text '새로고침 (F5)' -Width 112 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85)) -RegisterBusy
    $btnRefresh.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnRefresh.Add_Click({ Invoke-EnvironmentRefreshAsync })

    $lblNetBadge = New-Object System.Windows.Forms.Label
    $lblNetBadge.Text      = ' ● 연결 확인 중... '
    $lblNetBadge.ForeColor = [System.Drawing.Color]::White
    $lblNetBadge.BackColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $lblNetBadge.Font      = $script:FontBold
    $lblNetBadge.AutoSize  = $true
    $lblNetBadge.Padding   = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
    $lblNetBadge.Margin    = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)

    # RightToLeft 순서: 먼저 추가한 컨트롤이 가장 오른쪽에 배치됨
    $flpHdrRight1.Controls.Add($btnRefresh)
    $flpHdrRight1.Controls.Add($lblNetBadge)

    $pnlHdrRow1.Controls.Add($lblTitle)
    $pnlHdrRow1.Controls.Add($flpHdrRight1)

    # Row 2: 좌 OS + PC/IP + Machine SID / 우 SID 복사 버튼
    $pnlHdrRow2 = New-Object System.Windows.Forms.Panel
    $pnlHdrRow2.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlHdrRow2.Height    = 26
    $pnlHdrRow2.BackColor = [System.Drawing.Color]::Transparent

    $flpHdrMeta = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpHdrMeta.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $flpHdrMeta.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpHdrMeta.WrapContents  = $false
    $flpHdrMeta.BackColor     = [System.Drawing.Color]::Transparent
    $flpHdrMeta.Padding       = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

    $lblOs = New-Object System.Windows.Forms.Label
    $lblOs.Text      = 'OS: 확인 중...'
    $lblOs.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
    $lblOs.Font      = $script:FontSmall
    $lblOs.AutoSize  = $true
    $lblOs.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)

    $lblPcIp = New-Object System.Windows.Forms.Label
    $lblPcIp.Text      = "PC: $($env:COMPUTERNAME) (확인 중...)"
    $lblPcIp.ForeColor = [System.Drawing.Color]::FromArgb(125, 211, 252)
    $lblPcIp.Font      = $script:FontBold
    $lblPcIp.AutoSize  = $true
    $lblPcIp.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)

    $lblSid = New-Object System.Windows.Forms.Label
    $lblSid.Text      = 'Machine SID: 조회 중...'
    $lblSid.ForeColor = [System.Drawing.Color]::FromArgb(253, 224, 71)
    $lblSid.Font      = $script:FontSmall
    $lblSid.AutoSize  = $true

    $flpHdrMeta.Controls.AddRange(@($lblOs, $lblPcIp, $lblSid))

    $flpHdrRight2 = New-RightFlowStrip -TopPadding 2 -RightPadding 0
    $btnBugReport = New-StyledButton -Text '오류/버그 리포트' -Width 116 -Height 22 -BackColor ([System.Drawing.Color]::FromArgb(234, 88, 12)) -RegisterBusy
    $btnBugReport.Font   = $script:FontSmall
    $btnBugReport.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $btnBugReport.Add_Click({ Show-BugReportDialog })

    $btnCopySid = New-StyledButton -Text 'SID 복사' -Width 74 -Height 22 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnCopySid.Font = $script:FontSmall
    $btnCopySid.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:AppState.LocalSid)) {
            try {
                [System.Windows.Forms.Clipboard]::SetText($script:AppState.LocalSid)
                Add-UiLog -Message "현재 PC Machine SID가 클립보드에 복사되었습니다: $($script:AppState.LocalSid)" -Level 'INFO'
            } catch {}
        }
    })
    $flpHdrRight2.Controls.Add($btnBugReport)
    $flpHdrRight2.Controls.Add($btnCopySid)

    $pnlHdrRow2.Controls.Add($flpHdrMeta)
    $pnlHdrRow2.Controls.Add($flpHdrRight2)

    # Row 3: 서버 경로/상태 메시지
    $lblServerPath = New-Object System.Windows.Forms.Label
    $lblServerPath.Text      = '백업 경로: 확인 중...'
    $lblServerPath.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $lblServerPath.Font      = $script:FontSmall
    $lblServerPath.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblServerPath.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # Dock 순서: Fill(Row3) -> Top(Row2) -> Top(Row1 최상단)
    $pnlHeader.Controls.Add($lblServerPath)
    $pnlHeader.Controls.Add($pnlHdrRow2)
    $pnlHeader.Controls.Add($pnlHdrRow1)

    # ---------------- [2] WPP 경고 배너 (Dock + RightFlowStrip) ----------------
    $pnlWpp = New-Object System.Windows.Forms.Panel
    $pnlWpp.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlWpp.Height    = 44
    $pnlWpp.BackColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    $pnlWpp.Padding   = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $pnlWpp.Visible   = $false

    $lblWppTitle = New-Object System.Windows.Forms.Label
    $lblWppTitle.Text      = '[경고] Windows 보호 인쇄 모드(WPP)가 활성화되어 있습니다!'
    $lblWppTitle.ForeColor = [System.Drawing.Color]::White
    $lblWppTitle.Font      = $script:FontBold
    $lblWppTitle.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblWppTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $flpWppRight = New-RightFlowStrip -TopPadding 8 -RightPadding 0

    $btnWppAction = New-StyledButton -Text '프린터 설정 열기' -Width 130 -Height 28 -BackColor ([System.Drawing.Color]::White) -ForeColor ([System.Drawing.Color]::FromArgb(185, 28, 28))
    $btnWppAction.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnWppAction.Add_Click({
        $wpp = $null
        if ($script:AppState.NetworkInfo) { $wpp = $script:AppState.NetworkInfo.WppStatus }
        if ($wpp) {
            try {
                if ($wpp.IsPolicyEnforced) { Start-Process -FilePath 'mmc.exe' -ArgumentList 'gpedit.msc' }
                else { Start-Process -FilePath $wpp.SettingsUri }
            } catch {}
        }
    })

    $btnWppGuide = New-StyledButton -Text '조치 방법 안내' -Width 118 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(127, 29, 29))
    $btnWppGuide.Add_Click({
        if ($script:AppState.NetworkInfo -and $script:AppState.NetworkInfo.WppStatus) {
            Show-WppRemediationDialog -WppStatus $script:AppState.NetworkInfo.WppStatus
        }
    })

    $flpWppRight.Controls.Add($btnWppAction)
    $flpWppRight.Controls.Add($btnWppGuide)

    $pnlWpp.Controls.Add($lblWppTitle)
    $pnlWpp.Controls.Add($flpWppRight)

    # ---------------- [3] 하단 진행률 바 + 접이식 실시간 로그 (Dock 구조) ----------------
    $pnlFooter = New-Object System.Windows.Forms.Panel
    $pnlFooter.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlFooter.Height    = 146
    $pnlFooter.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $pnlFooter.Padding   = New-Object System.Windows.Forms.Padding(10, 4, 10, 8)

    $pnlFootTop = New-Object System.Windows.Forms.Panel
    $pnlFootTop.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlFootTop.Height    = 30
    $pnlFootTop.BackColor = [System.Drawing.Color]::Transparent

    $prgBar = New-Object System.Windows.Forms.ProgressBar
    $prgBar.Location = New-Object System.Drawing.Point(0, 5)
    $prgBar.Size     = New-Object System.Drawing.Size(210, 19)
    $prgBar.Minimum  = 0
    $prgBar.Maximum  = 100

    $lblProgressText = New-Object System.Windows.Forms.Label
    $lblProgressText.Text      = '준비 완료'
    $lblProgressText.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblProgressText.Font      = $script:FontBold
    $lblProgressText.AutoSize  = $true
    $lblProgressText.Location  = New-Object System.Drawing.Point(220, 7)

    $pnlFootLeft = New-Object System.Windows.Forms.Panel
    $pnlFootLeft.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlFootLeft.BackColor = [System.Drawing.Color]::Transparent
    $pnlFootLeft.Controls.AddRange(@($prgBar, $lblProgressText))

    $flpFootRight = New-RightFlowStrip -TopPadding 3 -RightPadding 0

    $btnToggleLog = New-StyledButton -Text '로그 접기 ▼' -Width 92 -Height 22 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnToggleLog.Font   = $script:FontSmall
    $btnToggleLog.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $btnToggleLog.Add_Click({
        if ($script:Ui.LogExpanded) {
            $script:Ui.LogExpanded       = $false
            $script:Ui.TxtLog.Visible    = $false
            $script:Ui.PnlFooter.Height  = 38
            $script:Ui.BtnToggleLog.Text = '로그 펼치기 ▲'
        } else {
            $script:Ui.LogExpanded       = $true
            $script:Ui.TxtLog.Visible    = $true
            $script:Ui.PnlFooter.Height  = 146
            $script:Ui.BtnToggleLog.Text = '로그 접기 ▼'
        }
    })

    $btnClearLog = New-StyledButton -Text '로그 지우기' -Width 86 -Height 22 -BackColor ([System.Drawing.Color]::FromArgb(100, 116, 139))
    $btnClearLog.Font = $script:FontSmall
    $btnClearLog.Add_Click({ $script:Ui.TxtLog.Clear() })

    $flpFootRight.Controls.Add($btnToggleLog)
    $flpFootRight.Controls.Add($btnClearLog)

    $pnlFootTop.Controls.Add($pnlFootLeft)
    $pnlFootTop.Controls.Add($flpFootRight)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtLog.Multiline   = $true
    $txtLog.ReadOnly    = $true
    $txtLog.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtLog.BackColor   = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $txtLog.ForeColor   = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $txtLog.Font        = $script:FontMono
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $pnlFooter.Controls.Add($txtLog)
    $pnlFooter.Controls.Add($pnlFootTop)

    # ---------------- [4] 중앙 4개 탭 컨테이너 ----------------
    $tabMain = New-Object System.Windows.Forms.TabControl
    $tabMain.Dock    = [System.Windows.Forms.DockStyle]::Fill
    $tabMain.Font    = $script:FontBold
    $tabMain.Padding = New-Object System.Drawing.Point(14, 6)

    $tabBackup  = New-Object System.Windows.Forms.TabPage(' 1. 백업 (Win 10 / Alt+1) ')
    $tabRestore = New-Object System.Windows.Forms.TabPage(' 2. 복원 (Win 11 / Alt+2) ')
    $tabVerify  = New-Object System.Windows.Forms.TabPage(' 3. 검증/테스트 (Alt+3) ')
    $tabServer  = New-Object System.Windows.Forms.TabPage(' 4. 서버 관리 (Alt+4) ')

    foreach ($tp in @($tabBackup, $tabRestore, $tabVerify, $tabServer)) {
        $tp.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
        $tp.Padding   = New-Object System.Windows.Forms.Padding(10)
        $tp.Font      = $script:FontBase
        $tabMain.TabPages.Add($tp)
    }

    # WinForms Dock Z-Order: Fill(0) -> Bottom -> Inner Top(WPP) -> Outer Top(Header)
    $form.Controls.Add($tabMain)
    $form.Controls.Add($pnlFooter)
    $form.Controls.Add($pnlWpp)
    $form.Controls.Add($pnlHeader)
    $tabMain.BringToFront()

    # ---------------- [5] 비동기 폴링 타이머 (150ms / C1·C3 반영) ----------------
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({
        try {
            Drain-AsyncLogQueue
            if ($script:AsyncState.AsyncResult -and $script:AsyncState.AsyncResult.IsCompleted) {
                $script:AsyncState.PollTimer.Stop()
                $psRef      = $script:AsyncState.PowerShell
                $resRef     = $script:AsyncState.AsyncResult
                $cbRef      = $script:AsyncState.OnComplete
                $cbStateRef = $script:AsyncState.CallbackState
                $tName      = $script:AsyncState.TaskName

                $okFlag  = $false
                $outData = $null
                $errMsg  = $null

                try {
                    $rawOut = $psRef.EndInvoke($resRef)
                    Drain-AsyncLogQueue
                    $first = @($rawOut) | Select-Object -Last 1
                    if ($first -and $first.PSObject.Properties.Name -contains 'Ok') {
                        $okFlag  = [bool]$first.Ok
                        $outData = $first.Data
                        $errMsg  = [string]$first.Error
                    } elseif ($psRef.HadErrors -and $psRef.Streams.Error.Count -gt 0) {
                        $errMsg = ($psRef.Streams.Error | ForEach-Object { $_.ToString() }) -join "`r`n"
                    } else {
                        $okFlag  = $true
                        $outData = $first
                    }
                }
                catch {
                    $errMsg = $_.Exception.Message
                }
                finally {
                    Stop-ActiveAsyncRunspace
                }

                $doneText = "[$tName] 완료"
                $logLvl   = 'INFO'
                if (-not $okFlag) {
                    $doneText = "[$tName] 오류 발생"
                    $logLvl   = 'ERROR'
                }

                Set-UiBusyState -IsBusy $false -StatusText $doneText
                Add-UiLog -Message "=== $doneText ===" -Level $logLvl

                if ($cbRef) {
                    try { & $cbRef $okFlag $outData $errMsg $cbStateRef }
                    catch { Add-UiLog -Message "완료 후 UI 처리 오류: $($_.Exception.Message)" -Level 'ERROR' }
                }
                Sync-AllUiButtonStates
            }
        }
        catch {
            $script:AsyncState.PollTimer.Stop()
            Add-UiLog -Message "타이머 처리 오류: $($_.Exception.Message)" -Level 'ERROR'
        }
    })
    $script:AsyncState.PollTimer = $timer

    # ---------------- [6] 전역 단축키 (F5 / Alt+1~4) & 안전한 종료 가드 ----------------
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5 -and -not $script:AsyncState.IsBusy) {
            $e.Handled = $true
            Invoke-EnvironmentRefreshAsync
        } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D1) {
            $e.Handled = $true; $script:Ui.TabMain.SelectedIndex = 0
        } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D2) {
            $e.Handled = $true; $script:Ui.TabMain.SelectedIndex = 1
        } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D3) {
            $e.Handled = $true; $script:Ui.TabMain.SelectedIndex = 2
        } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D4) {
            $e.Handled = $true; $script:Ui.TabMain.SelectedIndex = 3
        }
    })

    $form.Add_FormClosing({
        param($sender, $e)
        if ($script:AsyncState.IsBusy) {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                "현재 '$($script:AsyncState.TaskName)' 작업이 진행 중입니다.`r`n강제 종료하면 프린터 설정이 불완전할 수 있습니다. 정말 종료하시겠습니까?",
                '작업 중 종료 확인',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
                return
            }
        }
        Stop-ActiveAsyncRunspace
    })

    $script:Ui.Form            = $form
    $script:Ui.PnlHeader       = $pnlHeader
    $script:Ui.PnlWppBanner    = $pnlWpp
    $script:Ui.PnlFooter       = $pnlFooter
    $script:Ui.TabMain         = $tabMain
    $script:Ui.TabBackup       = $tabBackup
    $script:Ui.TabRestore      = $tabRestore
    $script:Ui.TabVerify       = $tabVerify
    $script:Ui.TabServer       = $tabServer
    $script:Ui.LblTitle        = $lblTitle
    $script:Ui.LblOs           = $lblOs
    $script:Ui.LblPcIp         = $lblPcIp
    $script:Ui.LblSid          = $lblSid
    $script:Ui.BtnCopySid      = $btnCopySid
    $script:Ui.BtnBugReport    = $btnBugReport
    $script:Ui.LblNetBadge     = $lblNetBadge
    $script:Ui.LblServerPath   = $lblServerPath
    $script:Ui.BtnRefresh      = $btnRefresh
    $script:Ui.LblWppTitle     = $lblWppTitle
    $script:Ui.BtnWppGuide     = $btnWppGuide
    $script:Ui.BtnWppAction    = $btnWppAction
    $script:Ui.PrgBar          = $prgBar
    $script:Ui.LblProgressText = $lblProgressText
    $script:Ui.TxtLog          = $txtLog
    $script:Ui.BtnToggleLog    = $btnToggleLog
    $script:Ui.BtnClearLog     = $btnClearLog
}

# ============================================================================
# [탭 1] 백업 (Win 10 / 오프라인 ZIP) UI 및 이벤트 로직
# ============================================================================
$script:Tab1Ui = @{
    PnlBanner        = $null
    LblBanner        = $null
    BtnScan          = $null
    ChkShowVirtual   = $null
    LblLegend        = $null
    DgvPrinters      = $null
    LblScanSummary   = $null
    BtnUnclassScan   = $null
    LblTwainWarn     = $null
    BtnBackupServer  = $null
    BtnBackupOffline = $null
    BtnOpenOffline   = $null
    HasScannedOnce   = $false
    LastScanOffline  = $false
}

function Update-Tab1NetworkState {
    if (-not $script:Tab1Ui.BtnBackupServer) { return }
    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir))

    Sync-AllUiButtonStates

    if (-not $script:Tab1Ui.HasScannedOnce) {
        if ($isOnline) {
            $script:Tab1Ui.PnlBanner.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
            $script:Tab1Ui.LblBanner.ForeColor = [System.Drawing.Color]::FromArgb(30, 58, 138)
            $script:Tab1Ui.LblBanner.Text      = '사내망·서버 온라인 확인됨 — [프린터/스캐너 다시 스캔]으로 현재 PC 프린터를 진단하세요.'
        } else {
            $script:Tab1Ui.PnlBanner.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
            $script:Tab1Ui.LblBanner.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
            $script:Tab1Ui.LblBanner.Text      = '오프라인 상태 — IP 설정 후 새로고침(F5)하거나, 구 PC 예외 시 하단 [오프라인 ZIP 백업]을 사용하세요.'
        }
    }
}

function Render-Tab1PrinterGrid {
    $dgv = $script:Tab1Ui.DgvPrinters
    if (-not $dgv -or $dgv.IsDisposed) { return }

    $dgv.SuspendLayout()
    try {
        $dgv.Rows.Clear()
        $showVirt = [bool]$script:Tab1Ui.ChkShowVirtual.Checked
        $items    = @($script:AppState.DiagnosedPrinters)

        $cntHealthy = 0
        $cntWsd     = 0
        $cntSpecial = 0
        $cntWarn    = 0
        $cntVirtual = 0

        foreach ($p in $items) {
            if ($p.StatusCode -eq 'ExcludedVirtual') {
                $cntVirtual++
                if (-not $showVirt) { continue }
            } elseif ($p.StatusCode -eq 'ExcludedNoDriver') {
                # LPT1 무드라이버 장비(EPSON TM-T88 등): 백업 제외 대상이나 현장 확인용으로 항상 표시
            } else {
                if ($p.SpecialType -ne 'STANDARD') { $cntSpecial++ }
                elseif ($p.StatusCode -eq 'WsdConvert') { $cntWsd++ }
                elseif ($p.StatusCode -eq 'Healthy') { $cntHealthy++ }
                else { $cntWarn++ }
            }

            $defMark = ''
            if ($p.IsDefault) { $defMark = '★' }

            $portDisplay = [string]$p.PortName
            if ($p.PortKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$p.WsdTargetIp)) {
                $portDisplay = "$($p.PortName) -> $($p.WsdTargetIp)"
            }

            $rowIdx = $dgv.Rows.Add(
                $defMark,
                [string]$p.StatusText,
                [string]$p.Category,
                [string]$p.PrinterName,
                $portDisplay,
                [string]$p.DriverName,
                [string]$p.Reason
            )
            $row     = $dgv.Rows[$rowIdx]
            $row.Tag = $p

            if ($p.StatusCode -eq 'ExcludedVirtual' -or $p.StatusCode -eq 'ExcludedNoDriver') {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
            } elseif ($p.SpecialType -ne 'STANDARD') {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(243, 232, 255)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(88, 28, 135)
            } elseif ($p.StatusCode -eq 'WsdConvert') {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
            } elseif ($p.StatusCode -eq 'AuthOrSidConflict') {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
            } elseif ($p.StatusCode -in @('SuspectedInactive', 'Ambiguous', 'OfflineUnverified')) {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
            } else {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
            }
        }

        if ($script:Tab1Ui.HasScannedOnce) {
            $validTotal = $cntHealthy + $cntWsd + $cntSpecial + $cntWarn
            if ($script:Tab1Ui.LastScanOffline) {
                $script:Tab1Ui.PnlBanner.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
                $script:Tab1Ui.LblBanner.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
                $script:Tab1Ui.LblBanner.Text      = "[오프라인 스캔] 백업 대상 ${validTotal}대 (특수 ${cntSpecial}대 / 가상 제외 ${cntVirtual}대) — 새 PC 복원 시 지연 검증 자동 수행"
            } elseif ($cntWarn -gt 0) {
                $script:Tab1Ui.PnlBanner.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
                $script:Tab1Ui.LblBanner.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
                $script:Tab1Ui.LblBanner.Text      = "진단 완료: 총 ${validTotal}대 (정상 ${cntHealthy} / WSD전환 ${cntWsd} / 특수 ${cntSpecial} / 비활성·주의 ${cntWarn} / 가상제외 ${cntVirtual}) — 주의 항목도 백업에 보존됩니다."
            } else {
                $script:Tab1Ui.PnlBanner.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
                $script:Tab1Ui.LblBanner.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
                $script:Tab1Ui.LblBanner.Text      = "진단 완료: 백업 대상 ${validTotal}대 모두 정상 확인 (일반 ${cntHealthy} / WSD전환 ${cntWsd} / 특수 ${cntSpecial} / 가상제외 ${cntVirtual})"
            }
        }
    }
    finally {
        $dgv.ResumeLayout()
    }
}

function Update-Tab1ScannerBar {
    $inv = $script:AppState.ScannerInventory
    if (-not $inv) {
        $script:Tab1Ui.LblScanSummary.Text    = 'WIA 스캔 드라이버: 스캔 대기 중'
        $script:Tab1Ui.BtnUnclassScan.Visible = $false
        $script:Tab1Ui.LblTwainWarn.Visible   = $false
        return
    }

    $autoCnt    = (@($inv.AutoScanners)).Count
    $unclassAll = @($inv.UnclassifiedScanners)
    $unclassSel = (@($unclassAll | Where-Object { $_.Selected })).Count
    $twains     = @($inv.TwainFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $script:Tab1Ui.LblScanSummary.Text = "WIA 스캔 드라이버: 자동 백업 ${autoCnt}개 | 미분류 선택 ${unclassSel}/$($unclassAll.Count)개"

    if ($unclassAll.Count -gt 0) {
        $script:Tab1Ui.BtnUnclassScan.Text    = "미분류 이미징 장치 선택 ($unclassSel/$($unclassAll.Count))"
        $script:Tab1Ui.BtnUnclassScan.Visible = $true
    } else {
        $script:Tab1Ui.BtnUnclassScan.Visible = $false
    }

    if ($twains.Count -gt 0) {
        $script:Tab1Ui.LblTwainWarn.Text    = "▲ TWAIN 감지($($twains -join ', ')) — 복원 후 네트워크 스캔 IP 확인 필요"
        $script:Tab1Ui.LblTwainWarn.Visible = $true
    } else {
        $script:Tab1Ui.LblTwainWarn.Visible = $false
    }
}

# [C1 Fix] DialogResult + $sender.CommitEdit로 클로저 소실 완전 제거
function Show-UnclassifiedScannerDialog {
    $inv = $script:AppState.ScannerInventory
    if (-not $inv -or (@($inv.UnclassifiedScanners)).Count -eq 0) { return }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = '미분류 이미징(스캐너) 드라이버 수동 선택'
    $dlg.Size            = New-Object System.Drawing.Size(660, 385)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [System.Drawing.Color]::White
    $dlg.Font            = $script:FontBase
    $dlg.Padding         = New-Object System.Windows.Forms.Padding(14)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text      = '기본 제조사 목록 및 웹캠 제외 목록 어디에도 속하지 않은 이미징 장치입니다. 임대·연구용 스캐너라면 체크하세요.'
    $lblDesc.Dock      = [System.Windows.Forms.DockStyle]::Top
    $lblDesc.Height    = 36
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 46
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $flpBotRight = New-RightFlowStrip -TopPadding 0 -RightPadding 0

    $btnCancel = New-StyledButton -Text '취소' -Width 96 -Height 32 -BackColor ([System.Drawing.Color]::FromArgb(100, 116, 139))
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnOk = New-StyledButton -Text '선택 적용' -Width 110 -Height 32 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235))
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $flpBotRight.Controls.Add($btnCancel)
    $flpBotRight.Controls.Add($btnOk)
    $pnlBot.Controls.Add($flpBotRight)

    $dgv = New-StyledGrid -AllowCheckEdit
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    $colChk = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colChk.HeaderText = '백업'
    $colChk.Width      = 46
    [void]$dgv.Columns.Add($colChk)

    foreach ($cSpec in @(
        @{ Header = '공급자(제조사)'; Width = 175 },
        @{ Header = '원본 INF';       Width = 140 },
        @{ Header = '게시 이름';      Width = 95 },
        @{ Header = '버전';           Width = 140 }
    )) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.HeaderText = $cSpec.Header
        $col.Width      = $cSpec.Width
        $col.ReadOnly   = $true
        [void]$dgv.Columns.Add($col)
    }

    $dgv.Add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty) {
            [void]$sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

    foreach ($sc in @($inv.UnclassifiedScanners)) {
        $rIdx = $dgv.Rows.Add([bool]$sc.Selected, [string]$sc.ProviderName, [string]$sc.OriginalName, [string]$sc.PublishedName, [string]$sc.DriverVersion)
        $dgv.Rows[$rIdx].Tag = $sc
    }

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.Add($dgv)
    $dlg.Controls.Add($pnlBot)
    $dlg.Controls.Add($lblDesc)
    $dgv.BringToFront()

    if ($dlg.ShowDialog($script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $dgv.EndEdit() | Out-Null
        foreach ($r in $dgv.Rows) {
            if ($r.Tag) { $r.Tag.Selected = ($r.Cells[0].Value -eq $true) }
        }
        Update-Tab1ScannerBar
        Add-UiLog -Message '미분류 이미징 드라이버 선택 상태를 업데이트했습니다.' -Level 'INFO'
    }
    $dlg.Dispose()
}

# ============================================================================
# 탭 1 비동기 액션: 사전 진단 스캔 / 온라인 서버 백업 / 오프라인 ZIP 백업
# ============================================================================
function Invoke-Tab1ScanAsync {
    param(
        [switch]$ForceOfflineProbe,
        [scriptblock]$AfterScan = $null
    )

    $net        = $script:AppState.NetworkInfo
    $useOffline = [bool]$ForceOfflineProbe
    if (-not $useOffline) {
        if (-not $net -or $net.Status -eq 'Offline') { $useOffline = $true }
    }

    $work = {
        param($arg)
        $off = [bool]$arg.OfflineMode
        if ($off) {
            Write-ProgressSafe -Percent 20 -Message '오프라인 모드로 로컬 프린터 목록 스캔 중 (생존 검증 생략)...'
        } else {
            Write-ProgressSafe -Percent 20 -Message '설치된 프린터 포트 생존 검증(TCP/공유 3종 인증/WSD 추출) 중...'
        }
        $printers = @(Get-LocalPrinterDiagnostics -OfflineMode:$off)

        Write-ProgressSafe -Percent 75 -Message 'WIA 스캔 드라이버(3분류), TWAIN 및 장치관리자 LPT 포트 점검 중...'
        $scanners = Get-ScannerDriverInventory
        $lptPorts = @(Get-DeviceManagerLptPorts)

        Write-ProgressSafe -Percent 100 -Message "사전 진단 완료 (총 $($printers.Count)개 항목 감지)"
        return [pscustomobject]@{
            Printers        = $printers
            ScannerInv      = $scanners
            LptPorts        = $lptPorts
            UsedOfflineMode = $off
        }
    }

    # [C1 Fix] $cbState로 $AfterScan 전달받아 PS 5.1 클로저 소실 차단
    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data) {
            Add-UiLog -Message "프린터 사전 진단 실패: $err" -Level 'ERROR'
            [System.Windows.Forms.MessageBox]::Show("프린터 진단 중 오류가 발생했습니다:`r`n$err", '진단 오류', 'OK', 'Error') | Out-Null
            return
        }
        $script:AppState.DiagnosedPrinters = @($data.Printers)
        $script:AppState.ScannerInventory  = $data.ScannerInv
        $script:Tab1Ui.HasScannedOnce      = $true
        $script:Tab1Ui.LastScanOffline     = [bool]$data.UsedOfflineMode

        $lpts = @($data.LptPorts)
        if ($lpts.Count -gt 0) {
            $lptTxt = ($lpts | ForEach-Object { "$($_.PortName)($($_.Status))" }) -join ', '
            Add-UiLog -Message "장치관리자 LPT 포트 감지: $lptTxt (EPSON TM-T88VI 등 LPT1 무드라이버 장비는 드라이버 백업 제외, LPT1 인식만 확인)" -Level 'INFO'
        }

        Render-Tab1PrinterGrid
        Update-Tab1ScannerBar
        Update-Tab1NetworkState

        if ($cbState -is [scriptblock]) {
            try { & $cbState } catch { Add-UiLog -Message "스캔 후속 작업 오류: $($_.Exception.Message)" -Level 'ERROR' }
        }
    }

    Invoke-AsanAsyncTask -TaskName '프린터/스캐너 사전 진단' -WorkScript $work -Params @{ OfflineMode = $useOffline } -OnComplete $done -CallbackState $AfterScan
}

# [C5 Fix] -SkipOverwritePrompt 추가로 재스캔 후 중복 덮어쓰기 팝업 차단
function Start-Tab1BackupExecution {
    param(
        [switch]$OfflineZipMode,
        [switch]$SkipOverwritePrompt
    )

    $net       = $script:AppState.NetworkInfo
    $pcIp      = 'NO_IP'
    $prtBakDir = $null
    if ($net) {
        $pcIp      = [string]$net.IPAddress
        $prtBakDir = $net.PrtBakDir
    }

    if (-not $OfflineZipMode) {
        if (-not $net -or $net.Status -ne 'Online' -or [string]::IsNullOrWhiteSpace([string]$prtBakDir)) {
            [System.Windows.Forms.MessageBox]::Show(
                "백업 서버에 연결되어 있지 않습니다.`r`n네트워크를 설정한 뒤 새로고침(F5)하거나 [오프라인 ZIP 백업]을 사용하세요.",
                '서버 미연결',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        if (-not $SkipOverwritePrompt) {
            $folderId         = Get-BackupFolderId -PcIp $pcIp
            $existingEntry    = @($script:AppState.ServerBackups | Where-Object { $_.Name -ieq $folderId }) | Select-Object -First 1
            $existingTimeText = $null
            if ($existingEntry) {
                $existingTimeText = $existingEntry.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            } else {
                $candDir = Join-Path $prtBakDir $folderId
                if (Test-Path -LiteralPath $candDir) {
                    $di = Get-Item -LiteralPath $candDir -Force -ErrorAction SilentlyContinue
                    if ($di) { $existingTimeText = $di.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
                }
            }

            if ($existingTimeText) {
                $ans = [System.Windows.Forms.MessageBox]::Show(
                    "서버에 동일 PC 백업('$folderId')이 이미 존재합니다.`r`n- 기존 백업 일시: $existingTimeText`r`n`r`n기존 백업을 덮어쓰시겠습니까?",
                    '기존 백업 덮어쓰기 확인',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                    Add-UiLog -Message '사용자가 기존 백업 덮어쓰기를 취소했습니다.' -Level 'INFO'
                    return
                }
            }
        }

        if (-not $script:Tab1Ui.HasScannedOnce -or $script:Tab1Ui.LastScanOffline) {
            Invoke-Tab1ScanAsync -AfterScan { Start-Tab1BackupExecution -SkipOverwritePrompt }
            return
        }
    }

    $needScanInside = (-not $script:Tab1Ui.HasScannedOnce)
    $diagList       = @($script:AppState.DiagnosedPrinters)
    $scanners       = @()
    $twains         = @()
    if ($script:AppState.ScannerInventory) {
        $scanners = @($script:AppState.ScannerInventory.AutoScanners) + @($script:AppState.ScannerInventory.UnclassifiedScanners)
        $twains   = @($script:AppState.ScannerInventory.TwainFolders)
    }

    $taskParams = @{
        NeedScanInside    = $needScanInside
        DiagnosedPrinters = $diagList
        SelectedScanners  = $scanners
        TwainFolders      = $twains
        PcIp              = $pcIp
        PrtBakDir         = $prtBakDir
        OfflineZipMode    = [bool]$OfflineZipMode
    }

    $work = {
        param($arg)
        $prts    = @($arg.DiagnosedPrinters)
        $scans   = @($arg.SelectedScanners)
        $tws     = @($arg.TwainFolders)
        $isOff   = [bool]$arg.OfflineZipMode
        $usedInv = $null

        if ([bool]$arg.NeedScanInside) {
            Write-ProgressSafe -Percent 5 -Message '사전 스캔 데이터 없음 — 오프라인 프린터/스캐너 진단 선행 중...'
            $prts    = @(Get-LocalPrinterDiagnostics -OfflineMode:$isOff)
            $usedInv = Get-ScannerDriverInventory
            $scans   = @($usedInv.AutoScanners) + @($usedInv.UnclassifiedScanners)
            $tws     = @($usedInv.TwainFolders)
        }

        $res = Invoke-PrinterBackupEngine `
            -DiagnosedPrinters $prts `
            -SelectedScanners $scans `
            -TwainFolders $tws `
            -PcIp ([string]$arg.PcIp) `
            -PrtBakDir ([string]$arg.PrtBakDir) `
            -OfflineZipMode:$isOff

        $updatedServerList = $null
        if (-not $isOff -and -not [string]::IsNullOrWhiteSpace([string]$arg.PrtBakDir)) {
            $updatedServerList = @(Get-ServerBackupEntries -PrtBakDir ([string]$arg.PrtBakDir) -PcIp ([string]$arg.PcIp))
        }

        return [pscustomobject]@{
            BackupResult      = $res
            UsedPrinters      = $prts
            UsedScannerInv    = $usedInv
            UpdatedServerList = $updatedServerList
        }
    }

    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok -or -not $data -or -not $data.BackupResult) {
            Add-UiLog -Message "백업 실패: $err" -Level 'ERROR'
            $repAns = [System.Windows.Forms.MessageBox]::Show(
                "백업 작업 중 오류가 발생했습니다:`r`n$err`r`n`r`n이 오류 내용을 서버 리포트함(_PRTBAK\_REPORTS)으로 전송하시겠습니까?",
                '백업 실패',
                'YesNo',
                'Error'
            )
            if ($repAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                Show-BugReportDialog -DefaultCategory '백업 오류' -ErrorSummary ([string]$err)
            }
            return
        }

        $res = $data.BackupResult
        if (-not $script:Tab1Ui.HasScannedOnce -and $data.UsedPrinters) {
            $script:AppState.DiagnosedPrinters = @($data.UsedPrinters)
            if ($data.UsedScannerInv) { $script:AppState.ScannerInventory = $data.UsedScannerInv }
            $script:Tab1Ui.HasScannedOnce      = $true
            $script:Tab1Ui.LastScanOffline     = ($res.Mode -eq 'OfflineZip')
            Render-Tab1PrinterGrid
            Update-Tab1ScannerBar
        }

        if ($null -ne $data.UpdatedServerList) {
            $script:AppState.ServerBackups = @($data.UpdatedServerList)
            foreach ($cb in $script:Ui.OnEnvRefreshed) {
                try { & $cb } catch {}
            }
        }

        $noteLines = [System.Collections.Generic.List[string]]::new()
        foreach ($n in @($res.Notes | Select-Object -First 8)) {
            $noteLines.Add(" - [$($n.Level)] $($n.Target): $($n.Message)")
        }
        $noteSummary = '특이사항 없음'
        if ($noteLines.Count -gt 0) { $noteSummary = ($noteLines -join "`r`n") }

        if ($res.Mode -eq 'OfflineZip') {
            $usbLine = 'USB 동시 복사: 없음 (로컬 C:\_AsanPrtOffline에만 저장됨 — SSD 직결 또는 수동 복사)'
            if (-not [string]::IsNullOrWhiteSpace([string]$res.UsbCopyPath)) {
                $usbLine = "USB 동시 복사: $($res.UsbCopyPath)"
            }
            $msg = @(
                "오프라인 ZIP 백업이 완료되었습니다.",
                "",
                "• 로컬 저장 경로: $($res.SavedPath)",
                "• $usbLine",
                "• 백업 내역: 프린터 $($res.PrinterCount)대 / WIA 스캐너 $($res.ScannerCount)개",
                "",
                "[백업 시점 특이사항 (복원 화면에서 자동 재알림)]",
                $noteSummary,
                "",
                "저장 폴더(C:\_AsanPrtOffline)를 탐색기로 여시겠습니까?"
            ) -join "`r`n"

            $openAns = [System.Windows.Forms.MessageBox]::Show($msg, '오프라인 ZIP 백업 완료', 'YesNo', 'Information')
            if ($openAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                Open-FolderInExplorerSafe -FolderPath $global:AsanCtx.OfflineLocalRoot
            }
        } else {
            $msg = @(
                "사내 백업 서버 업로드가 완료되었습니다.",
                "",
                "• 서버 저장 경로: $($res.SavedPath)",
                "• 백업 내역: 프린터 $($res.PrinterCount)대 / WIA 스캐너 $($res.ScannerCount)개",
                "",
                "[백업 시점 특이사항 (새 Win 11 복원 시 자동 재알림)]",
                $noteSummary
            ) -join "`r`n"
            [System.Windows.Forms.MessageBox]::Show($msg, '서버 백업 완료', 'OK', 'Information') | Out-Null
        }
    }

    $tLabel = '사내 서버 프린터/드라이버 백업'
    if ($OfflineZipMode) { $tLabel = '오프라인 ZIP 백업 (C:\_AsanPrtOffline)' }
    Invoke-AsanAsyncTask -TaskName $tLabel -WorkScript $work -Params $taskParams -OnComplete $done
}

# ============================================================================
# [C2 + C4 Fix] 탭 1 컨트롤 배치 초기화 (Dock + RightFlowStrip 구조화)
# ============================================================================
function Initialize-Tab1BackupUi {
    $parent = $script:Ui.TabBackup

    # [1] 상단 진단 요약/오프라인 경고 배너
    $pnlBanner = New-Object System.Windows.Forms.Panel
    $pnlBanner.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlBanner.Height    = 34
    $pnlBanner.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
    $pnlBanner.Padding   = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)

    $lblBanner = New-Object System.Windows.Forms.Label
    $lblBanner.Text      = '환경 확인 중...'
    $lblBanner.ForeColor = [System.Drawing.Color]::FromArgb(30, 58, 138)
    $lblBanner.Font      = $script:FontBold
    $lblBanner.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblBanner.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $pnlBanner.Controls.Add($lblBanner)

    # [2] 툴바 (좌: 다시 스캔 + 가상 프린터 토글 / 우: 색상 범례)
    $pnlToolbar = New-Object System.Windows.Forms.Panel
    $pnlToolbar.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlToolbar.Height    = 40
    $pnlToolbar.BackColor = [System.Drawing.Color]::Transparent

    $pnlToolLeft = New-Object System.Windows.Forms.Panel
    $pnlToolLeft.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlToolLeft.BackColor = [System.Drawing.Color]::Transparent

    $btnScan = New-StyledButton -Text '프린터/스캐너 다시 스캔' -Width 176 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85)) -RegisterBusy
    $btnScan.Location = New-Object System.Drawing.Point(0, 6)
    $btnScan.Add_Click({ Invoke-Tab1ScanAsync })

    $chkVirt = New-Object System.Windows.Forms.CheckBox
    $chkVirt.Text      = '제외된 가상 프린터 함께 보기 (PDF/OneNote/Fax 등)'
    $chkVirt.AutoSize  = $true
    $chkVirt.Location  = New-Object System.Drawing.Point(188, 10)
    $chkVirt.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $chkVirt.Add_CheckedChanged({ Render-Tab1PrinterGrid })
    $pnlToolLeft.Controls.AddRange(@($btnScan, $chkVirt))

    $flpToolRight = New-RightFlowStrip -TopPadding 12 -RightPadding 2
    $lblLegend = New-Object System.Windows.Forms.Label
    $lblLegend.Text      = '■ 정상  ■ WSD전환  ■ 특수장비  ■ 비활성의심  ■ 인증/SID'
    $lblLegend.AutoSize  = $true
    $lblLegend.Font      = $script:FontSmall
    $lblLegend.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $flpToolRight.Controls.Add($lblLegend)

    $pnlToolbar.Controls.Add($pnlToolLeft)
    $pnlToolbar.Controls.Add($flpToolRight)

    # [3] 중앙 프린터 진단 그리드
    $dgv = New-StyledGrid
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    foreach ($colDef in @(
        @{ Name = 'Default';  Header = '기본';           Width = 42 },
        @{ Name = 'Status';   Header = '진단 상태';       Width = 112 },
        @{ Name = 'Category'; Header = '구분';           Width = 108 },
        @{ Name = 'Printer';  Header = '프린터 이름';     Width = 195 },
        @{ Name = 'Port';     Header = '포트 / 전환 IP';  Width = 165 },
        @{ Name = 'Driver';   Header = '설치된 드라이버'; Width = 195 },
        @{ Name = 'Reason';   Header = '진단 상세 사유';  Width = 280 }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $colDef.Name
        $c.HeaderText = $colDef.Header
        $c.Width      = $colDef.Width
        [void]$dgv.Columns.Add($c)
    }

    # [4] 하단 스캐너 3분류 요약 패널 (FlowLayoutPanel로 DPI 배율 겹침 차단)
    $pnlScanner = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlScanner.Dock          = [System.Windows.Forms.DockStyle]::Bottom
    $pnlScanner.Height        = 40
    $pnlScanner.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlScanner.WrapContents  = $false
    $pnlScanner.BackColor     = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $pnlScanner.Padding       = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)

    $lblScanSum = New-Object System.Windows.Forms.Label
    $lblScanSum.Text      = 'WIA 스캔 드라이버: 스캔 대기 중'
    $lblScanSum.AutoSize  = $true
    $lblScanSum.Font      = $script:FontBold
    $lblScanSum.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblScanSum.Margin    = New-Object System.Windows.Forms.Padding(0, 5, 14, 0)

    $btnUnclass = New-StyledButton -Text '미분류 이미징 장치 선택 (0/0)' -Width 204 -Height 26 -BackColor ([System.Drawing.Color]::FromArgb(217, 119, 6)) -RegisterBusy
    $btnUnclass.Font    = $script:FontSmall
    $btnUnclass.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    $btnUnclass.Visible = $false
    $btnUnclass.Add_Click({ Show-UnclassifiedScannerDialog })

    $lblTwain = New-Object System.Windows.Forms.Label
    $lblTwain.Text      = ''
    $lblTwain.AutoSize  = $true
    $lblTwain.Font      = $script:FontSmall
    $lblTwain.ForeColor = [System.Drawing.Color]::FromArgb(180, 83, 9)
    $lblTwain.Margin    = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $lblTwain.Visible   = $false

    $pnlScanner.Controls.AddRange(@($lblScanSum, $btnUnclass, $lblTwain))

    # [5] 최하단 백업 실행 액션 바 (Dock + RightFlowStrip)
    $pnlAction = New-Object System.Windows.Forms.Panel
    $pnlAction.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlAction.Height    = 48
    $pnlAction.BackColor = [System.Drawing.Color]::Transparent

    $pnlActLeft = New-Object System.Windows.Forms.Panel
    $pnlActLeft.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlActLeft.BackColor = [System.Drawing.Color]::Transparent

    $btnServer = New-StyledButton -Text '서버로 백업 시작' -Width 185 -Height 36 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235)) -RegisterBusy
    $btnServer.Location = New-Object System.Drawing.Point(0, 8)
    $btnServer.Add_Click({ Start-Tab1BackupExecution })

    $btnOffline = New-StyledButton -Text '오프라인 ZIP 백업 (C:\_AsanPrtOffline)' -Width 265 -Height 36 -BackColor ([System.Drawing.Color]::FromArgb(15, 118, 110)) -RegisterBusy
    $btnOffline.Location = New-Object System.Drawing.Point(198, 8)
    $btnOffline.Add_Click({ Start-Tab1BackupExecution -OfflineZipMode })
    $pnlActLeft.Controls.AddRange(@($btnServer, $btnOffline))

    $flpActRight = New-RightFlowStrip -TopPadding 8 -RightPadding 0
    $btnOpenOff = New-StyledButton -Text '오프라인 백업 폴더 열기' -Width 168 -Height 36 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnOpenOff.Add_Click({
        $dir = $global:AsanCtx.OfflineLocalRoot
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Open-FolderInExplorerSafe -FolderPath $dir
    })
    $flpActRight.Controls.Add($btnOpenOff)

    $pnlAction.Controls.Add($pnlActLeft)
    $pnlAction.Controls.Add($flpActRight)

    # Dock Z-Order: Fill(0) -> Bottom(Inner) -> Bottom(Outer) -> Top(Inner) -> Top(Outer)
    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlScanner)
    $parent.Controls.Add($pnlAction)
    $parent.Controls.Add($pnlToolbar)
    $parent.Controls.Add($pnlBanner)
    $dgv.BringToFront()

    $script:Tab1Ui.PnlBanner        = $pnlBanner
    $script:Tab1Ui.LblBanner        = $lblBanner
    $script:Tab1Ui.BtnScan          = $btnScan
    $script:Tab1Ui.ChkShowVirtual   = $chkVirt
    $script:Tab1Ui.LblLegend        = $lblLegend
    $script:Tab1Ui.DgvPrinters      = $dgv
    $script:Tab1Ui.LblScanSummary   = $lblScanSum
    $script:Tab1Ui.BtnUnclassScan   = $btnUnclass
    $script:Tab1Ui.LblTwainWarn     = $lblTwain
    $script:Tab1Ui.BtnBackupServer  = $btnServer
    $script:Tab1Ui.BtnBackupOffline = $btnOffline
    $script:Tab1Ui.BtnOpenOffline   = $btnOpenOff

    $script:Ui.OnEnvRefreshed.Add({ Update-Tab1NetworkState })
}
