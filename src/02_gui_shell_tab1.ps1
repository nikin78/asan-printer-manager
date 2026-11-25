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
    PicBadge           = $null
    BadgeImage         = $null
    AppIcon            = $null
    ToolTip            = $null
    LblTitle           = $null
    LblSubtitle        = $null
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
    LogExpanded        = $false
    ButtonStyles       = @{}
    DisabledReasons    = @{}
    LastDisabledBtn    = $null
    LastDisabledHost   = $null
    SidFlashTimer      = $null
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
# 고시인성 아산 그린·오렌지 테마 팔레트 · 순수 GDI+ 프린터 심볼 · 공용 UI 팩토리
# - 제3자 로고 이미지 미사용(저작권 리스크 0), 모든 아이콘/심볼 순수 GDI+ 생성
# ============================================================================
$script:Theme = @{
    AsanGreen      = [System.Drawing.Color]::FromArgb(0, 103, 105)
    AsanDeep       = [System.Drawing.Color]::FromArgb(0, 77, 79)
    HeaderBg       = [System.Drawing.Color]::FromArgb(0, 86, 88)
    HeaderSubFg    = [System.Drawing.Color]::FromArgb(202, 232, 231)
    HeaderUtilBg   = [System.Drawing.Color]::FromArgb(16, 112, 114)
    HeaderUtilHov  = [System.Drawing.Color]::FromArgb(24, 132, 134)
    HeaderUtilBord = [System.Drawing.Color]::FromArgb(95, 170, 169)
    GridHeadBg     = [System.Drawing.Color]::FromArgb(11, 79, 81)
    GridHeadFg     = [System.Drawing.Color]::White
    AsanLight      = [System.Drawing.Color]::FromArgb(2, 128, 168)
    AsanMint       = [System.Drawing.Color]::FromArgb(228, 242, 241)
    AsanMintSoft   = [System.Drawing.Color]::FromArgb(217, 231, 230)
    AsanMintHover  = [System.Drawing.Color]::FromArgb(204, 229, 227)
    AsanMintBorder = [System.Drawing.Color]::FromArgb(95, 160, 158)
    MetaBarBg      = [System.Drawing.Color]::FromArgb(237, 243, 243)
    BadgeOnlineBg  = [System.Drawing.Color]::FromArgb(20, 138, 94)
    AsanOrange     = [System.Drawing.Color]::FromArgb(224, 112, 8)
    AsanOrangeDeep = [System.Drawing.Color]::FromArgb(191, 90, 4)
    AsanOrangeLine = [System.Drawing.Color]::FromArgb(246, 139, 31)
    AsanOrangeText = [System.Drawing.Color]::FromArgb(154, 71, 0)
    AsanOrangeTint = [System.Drawing.Color]::FromArgb(255, 241, 222)
    AsanOrangeBord = [System.Drawing.Color]::FromArgb(224, 156, 82)
    DangerRed      = [System.Drawing.Color]::FromArgb(192, 57, 43)
    DangerRedDeep  = [System.Drawing.Color]::FromArgb(158, 38, 28)
    DangerRedTint  = [System.Drawing.Color]::FromArgb(253, 236, 234)
    DangerRedBord  = [System.Drawing.Color]::FromArgb(217, 130, 121)
    SpecialPurple  = [System.Drawing.Color]::FromArgb(98, 36, 198)
    SpecialTint    = [System.Drawing.Color]::FromArgb(242, 236, 255)
    CanvasBg       = [System.Drawing.Color]::FromArgb(231, 238, 238)
    CardBg         = [System.Drawing.Color]::White
    RowAltBg       = [System.Drawing.Color]::FromArgb(244, 248, 248)
    Border         = [System.Drawing.Color]::FromArgb(198, 212, 211)
    GridLine       = [System.Drawing.Color]::FromArgb(211, 223, 223)
    BorderBtn      = [System.Drawing.Color]::FromArgb(142, 165, 164)
    InkPrimary     = [System.Drawing.Color]::FromArgb(20, 34, 35)
    InkSecondary   = [System.Drawing.Color]::FromArgb(47, 66, 68)
    InkMuted       = [System.Drawing.Color]::FromArgb(80, 99, 101)
    DisabledBg     = [System.Drawing.Color]::FromArgb(241, 243, 243)
    DisabledFg     = [System.Drawing.Color]::FromArgb(148, 160, 162)
    DisabledBorder = [System.Drawing.Color]::FromArgb(192, 204, 204)
    LogBg          = [System.Drawing.Color]::FromArgb(22, 34, 35)
    LogFg          = [System.Drawing.Color]::FromArgb(226, 236, 235)
}

$script:FontBase     = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Regular)
$script:FontBold     = New-Object System.Drawing.Font('맑은 고딕', 9, [System.Drawing.FontStyle]::Bold)
$script:FontTab      = New-Object System.Drawing.Font('맑은 고딕', 9.5, [System.Drawing.FontStyle]::Bold)
$script:FontTabIdle  = New-Object System.Drawing.Font('맑은 고딕', 9.5, [System.Drawing.FontStyle]::Regular)
$script:FontTitle    = New-Object System.Drawing.Font('맑은 고딕', 12.5, [System.Drawing.FontStyle]::Bold)
$script:FontSubtitle = New-Object System.Drawing.Font('맑은 고딕', 8.5, [System.Drawing.FontStyle]::Regular)
$script:FontSmall    = New-Object System.Drawing.Font('맑은 고딕', 8.5, [System.Drawing.FontStyle]::Regular)
$script:FontSmallB   = New-Object System.Drawing.Font('맑은 고딕', 8.5, [System.Drawing.FontStyle]::Bold)
$script:FontMono     = New-Object System.Drawing.Font('Consolas', 8.5, [System.Drawing.FontStyle]::Regular)

function New-AsanPrinterSymbolBitmap {
    param(
        [int]$Size = 64,
        [switch]$OnDarkHeader
    )
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $scale = [float]($Size / 64.0)
        $g.ScaleTransform($scale, $scale)

        $bgColor = $script:Theme.AsanGreen
        if ($OnDarkHeader) { $bgColor = [System.Drawing.Color]::FromArgb(14, 118, 120) }

        # 둥근 사각 배경
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 14
        $gp.AddArc(2, 2, $r * 2, $r * 2, 180, 90)
        $gp.AddArc(62 - $r * 2, 2, $r * 2, $r * 2, 270, 90)
        $gp.AddArc(62 - $r * 2, 62 - $r * 2, $r * 2, $r * 2, 0, 90)
        $gp.AddArc(2, 62 - $r * 2, $r * 2, $r * 2, 90, 90)
        $gp.CloseFigure()
        $brBg = New-Object System.Drawing.SolidBrush($bgColor)
        $g.FillPath($brBg, $gp)
        if ($OnDarkHeader) {
            $penFrame = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(115, 195, 194), 2.0)
            $g.DrawPath($penFrame, $gp)
            $penFrame.Dispose()
        }
        $brBg.Dispose()
        $gp.Dispose()

        # 흰색 프린터 실루엣 (상단 용지 + 본체 + 하단 출력지)
        $brW = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $brT = New-Object System.Drawing.SolidBrush($bgColor)
        $g.FillRectangle($brW, 20, 12, 24, 12)
        $g.FillRectangle($brW, 12, 22, 40, 20)
        $g.FillRectangle($brT, 18, 34, 28, 6)
        $g.FillRectangle($brW, 20, 35, 24, 17)
        $penLine = New-Object System.Drawing.Pen($script:Theme.AsanLight, 2)
        $g.DrawLine($penLine, 24, 41, 40, 41)
        $g.DrawLine($penLine, 24, 46, 36, 46)
        $penLine.Dispose()
        $brT.Dispose()
        $brW.Dispose()

        # 우측 하단 아산 오렌지 체크 배지
        $brO = New-Object System.Drawing.SolidBrush($script:Theme.AsanOrangeLine)
        $penRing = New-Object System.Drawing.Pen($bgColor, 2.5)
        $g.FillEllipse($brO, 39, 39, 21, 21)
        $g.DrawEllipse($penRing, 39, 39, 21, 21)
        $penChk = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.6)
        $penChk.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $penChk.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $penChk.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawLines($penChk, @(
            (New-Object System.Drawing.PointF(44.5, 49.5)),
            (New-Object System.Drawing.PointF(48.2, 53.2)),
            (New-Object System.Drawing.PointF(55.0, 45.8))
        ))
        $penChk.Dispose()
        $penRing.Dispose()
        $brO.Dispose()
    }
    finally { $g.Dispose() }
    return $bmp
}

function New-AsanPrinterBadgeImage {
    try { return (New-AsanPrinterSymbolBitmap -Size 40 -OnDarkHeader) }
    catch { return $null }
}

function New-AsanPrinterAppIcon {
    # 순수 GDI+ 64x64 아산 그린 프린터 심볼 -> PNG-in-ICO 스트림으로 매니지드 Icon 생성 (HICON 누수 0)
    try {
        $bmp = New-AsanPrinterSymbolBitmap -Size 64
        try {
            $pngMs = New-Object System.IO.MemoryStream
            try {
                $bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
                $pngBytes = $pngMs.ToArray()
            }
            finally { $pngMs.Dispose() }

            $icoMs = New-Object System.IO.MemoryStream
            try {
                $bw = New-Object System.IO.BinaryWriter($icoMs)
                $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
                $bw.Write([byte]64); $bw.Write([byte]64); $bw.Write([byte]0); $bw.Write([byte]0)
                $bw.Write([uint16]1); $bw.Write([uint16]32)
                $bw.Write([uint32]$pngBytes.Length); $bw.Write([uint32]22)
                $bw.Write($pngBytes)
                $bw.Flush()
                $icoMs.Position = 0
                return (New-Object System.Drawing.Icon($icoMs))
            }
            finally { $icoMs.Dispose() }
        }
        finally { $bmp.Dispose() }
    } catch {
        return $null
    }
}

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

function Show-AsanMessageBox {
    param(
        [string]$Text,
        [string]$Caption = '알림',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information,
        [System.Windows.Forms.IWin32Window]$Owner = $null
    )
    $win = $Owner
    if ($null -eq $win -and $script:Ui -and $script:Ui.Form -and (-not $script:Ui.Form.IsDisposed) -and $script:Ui.Form.Visible) {
        $win = $script:Ui.Form
    }
    if ($null -ne $win) {
        return [System.Windows.Forms.MessageBox]::Show($win, $Text, $Caption, $Buttons, $Icon)
    }
    return [System.Windows.Forms.MessageBox]::Show($Text, $Caption, $Buttons, $Icon)
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

function Apply-ButtonVisualState {
    param([System.Windows.Forms.Button]$Button)
    if (-not $Button -or $Button.IsDisposed) { return }
    if (-not $script:Ui.ButtonStyles -or -not $script:Ui.ButtonStyles.ContainsKey($Button)) { return }
    $st = $script:Ui.ButtonStyles[$Button]
    if ($Button.Enabled) {
        $Button.BackColor = $st.Bg
        $Button.ForeColor = $st.Fg
        $Button.FlatAppearance.BorderSize         = $st.BorderSize
        $Button.FlatAppearance.BorderColor        = $st.Border
        $Button.FlatAppearance.MouseOverBackColor = $st.Hover
        $Button.FlatAppearance.MouseDownBackColor = $st.Hover
        $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    } else {
        $Button.BackColor = $script:Theme.DisabledBg
        $Button.ForeColor = $script:Theme.DisabledFg
        $Button.FlatAppearance.BorderSize         = 0
        $Button.FlatAppearance.BorderColor        = $script:Theme.DisabledBorder
        $Button.FlatAppearance.MouseOverBackColor = $script:Theme.DisabledBg
        $Button.FlatAppearance.MouseDownBackColor = $script:Theme.DisabledBg
        $Button.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    $Button.Invalidate()
}

function Set-ButtonTipState {
    param(
        [System.Windows.Forms.Button]$Button,
        [bool]$Enabled,
        [string]$DisabledReason = ''
    )
    if (-not $Button -or $Button.IsDisposed) { return }
    if ($Enabled) {
        if ($script:Ui.DisabledReasons.ContainsKey($Button)) { $script:Ui.DisabledReasons.Remove($Button) }
        if ($script:Ui.LastDisabledBtn -eq $Button -and $script:Ui.LastDisabledHost -and $script:Ui.ToolTip) {
            try { $script:Ui.ToolTip.Hide($script:Ui.LastDisabledHost) } catch {}
            $script:Ui.LastDisabledBtn  = $null
            $script:Ui.LastDisabledHost = $null
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($DisabledReason)) {
        $script:Ui.DisabledReasons[$Button] = $DisabledReason
    }
    if ($Button.Enabled -ne $Enabled) {
        $Button.Enabled = $Enabled
    }
}

function Register-DisabledTooltipTree {
    param([System.Windows.Forms.Control]$Root)
    if (-not $Root -or $Root.IsDisposed) { return }

    $hasChildBtn = $false
    foreach ($ch in $Root.Controls) {
        if ($ch -is [System.Windows.Forms.Button]) { $hasChildBtn = $true }
        if ($ch.Controls.Count -gt 0) {
            Register-DisabledTooltipTree -Root $ch
        }
    }

    if ($hasChildBtn) {
        $Root.Add_MouseMove({
            param($sender, $e)
            if (-not $script:Ui.ToolTip) { return }
            $hit = $sender.GetChildAtPoint($e.Location)
            if ($hit -and ($hit -is [System.Windows.Forms.Button]) -and (-not $hit.Enabled)) {
                $reason = ''
                if ($script:Ui.DisabledReasons.ContainsKey($hit)) {
                    $reason = [string]$script:Ui.DisabledReasons[$hit]
                } elseif ($script:AsyncState.IsBusy) {
                    $reason = '현재 다른 작업이 진행 중입니다. 완료 후 다시 시도해 주세요.'
                }
                if (-not [string]::IsNullOrWhiteSpace($reason)) {
                    if ($script:Ui.LastDisabledBtn -ne $hit) {
                        if ($script:Ui.LastDisabledHost) {
                            try { $script:Ui.ToolTip.Hide($script:Ui.LastDisabledHost) } catch {}
                        }
                        try {
                            $script:Ui.ToolTip.Show($reason, $sender, ($hit.Left + 6), ($hit.Bottom + 4), 7000)
                            $script:Ui.LastDisabledBtn  = $hit
                            $script:Ui.LastDisabledHost = $sender
                        } catch {}
                    }
                    return
                }
            }
            if ($script:Ui.LastDisabledBtn -and $script:Ui.LastDisabledHost) {
                try { $script:Ui.ToolTip.Hide($script:Ui.LastDisabledHost) } catch {}
                $script:Ui.LastDisabledBtn  = $null
                $script:Ui.LastDisabledHost = $null
            }
        })
        $Root.Add_MouseLeave({
            param($sender, $e)
            if ($script:Ui.LastDisabledHost -eq $sender -and $script:Ui.ToolTip) {
                try { $script:Ui.ToolTip.Hide($sender) } catch {}
                $script:Ui.LastDisabledBtn  = $null
                $script:Ui.LastDisabledHost = $null
            }
        })
    }
}

function New-StyledButton {
    param(
        [string]$Text,
        [int]$Width = 120,
        [int]$Height = 30,
        [string]$Variant = 'Custom',
        [System.Drawing.Color]$BackColor = ([System.Drawing.Color]::FromArgb(0, 103, 105)),
        [System.Drawing.Color]$ForeColor = ([System.Drawing.Color]::White),
        [switch]$RegisterBusy
    )
    $bg    = $BackColor
    $fg    = $ForeColor
    $bd    = $BackColor
    $bdSz  = 0
    $hover = $script:Theme.AsanDeep
    $font  = $script:FontBold
    $disF  = $script:FontBase

    switch ($Variant) {
        'Primary' {
            $bg = $script:Theme.AsanGreen; $fg = [System.Drawing.Color]::White
            $bd = $script:Theme.AsanGreen; $bdSz = 1; $hover = $script:Theme.AsanDeep
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'Secondary' {
            $bg = $script:Theme.CardBg; $fg = $script:Theme.InkPrimary
            $bd = $script:Theme.BorderBtn; $bdSz = 1; $hover = $script:Theme.AsanMint
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'HeaderUtil' {
            $bg = $script:Theme.HeaderUtilBg; $fg = [System.Drawing.Color]::White
            $bd = $script:Theme.HeaderUtilBord; $bdSz = 1; $hover = $script:Theme.HeaderUtilHov
            $font = $script:FontSmallB; $disF = $script:FontSmall
        }
        'SoftTeal' {
            $bg = $script:Theme.AsanMint; $fg = $script:Theme.AsanDeep
            $bd = $script:Theme.AsanMintBorder; $bdSz = 1; $hover = $script:Theme.AsanMintHover
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'Orange' {
            $bg = $script:Theme.AsanOrange; $fg = [System.Drawing.Color]::White
            $bd = $script:Theme.AsanOrange; $bdSz = 1; $hover = $script:Theme.AsanOrangeDeep
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'SoftOrange' {
            $bg = $script:Theme.AsanOrangeTint; $fg = $script:Theme.AsanOrangeText
            $bd = $script:Theme.AsanOrangeBord; $bdSz = 1; $hover = [System.Drawing.Color]::FromArgb(255, 226, 189)
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'Danger' {
            $bg = $script:Theme.DangerRed; $fg = [System.Drawing.Color]::White
            $bd = $script:Theme.DangerRed; $bdSz = 1; $hover = $script:Theme.DangerRedDeep
            $font = $script:FontBold; $disF = $script:FontBase
        }
        'DangerOutline' {
            $bg = [System.Drawing.Color]::FromArgb(255, 244, 243); $fg = $script:Theme.DangerRedDeep
            $bd = $script:Theme.DangerRedBord; $bdSz = 1; $hover = $script:Theme.DangerRedTint
            $font = $script:FontBold; $disF = $script:FontBase
        }
        default {
            $hover = $bg
        }
    }

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = $Text
    $btn.Size      = New-Object System.Drawing.Size($Width, $Height)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.Font      = $font
    $btn.UseVisualStyleBackColor = $false

    $script:Ui.ButtonStyles[$btn] = @{
        Bg           = $bg
        Fg           = $fg
        Border       = $bd
        BorderSize   = $bdSz
        Hover        = $hover
        Font         = $font
        DisabledFont = $disF
    }
    Apply-ButtonVisualState -Button $btn
    $btn.Add_EnabledChanged({
        param($sender, $e)
        Apply-ButtonVisualState -Button $sender
    })
    # WinForms 기본 GrayText(#6D6D6D)를 대체해 비활성 상태를 점선 테두리·연한 무채색으로 직관적 표시
    $btn.Add_Paint({
        param($sender, $e)
        if ($sender.Enabled) { return }
        $g  = $e.Graphics
        $rc = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
        $br = New-Object System.Drawing.SolidBrush($script:Theme.DisabledBg)
        $g.FillRectangle($br, $rc)
        $br.Dispose()

        $pen = New-Object System.Drawing.Pen($script:Theme.DisabledBorder, 1)
        $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $pen.Dispose()

        $drawFont = $script:FontBase
        if ($sender.Font -and $sender.Font.Size -lt 8.8) { $drawFont = $script:FontSmall }
        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
        [System.Windows.Forms.TextRenderer]::DrawText($g, $sender.Text, $drawFont, $rc, $script:Theme.DisabledFg, $flags)
    })

    if ($RegisterBusy) { $script:Ui.BusyControls.Add($btn) }
    return $btn
}

function Add-ColorLegendChip {
    param(
        [System.Windows.Forms.FlowLayoutPanel]$TargetFlow,
        [string]$LabelText,
        [System.Drawing.Color]$DotColor
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = "● $LabelText"
    $lbl.AutoSize  = $true
    $lbl.Font      = $script:FontSmallB
    $lbl.ForeColor = $DotColor
    $lbl.Margin    = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $TargetFlow.Controls.Add($lbl)
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
    $dgv.BackgroundColor             = $script:Theme.CardBg
    $dgv.BorderStyle                 = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgv.CellBorderStyle             = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $dgv.ColumnHeadersBorderStyle    = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::Single
    $dgv.GridColor                   = $script:Theme.GridLine
    $dgv.EnableHeadersVisualStyles   = $false
    $dgv.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $dgv.ColumnHeadersHeight         = 32
    $dgv.RowTemplate.Height          = 30
    $dgv.Font                        = $script:FontBase
    $dgv.ShowCellToolTips            = $true
    $dgv.AutoSizeColumnsMode         = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None

    $dgv.ColumnHeadersDefaultCellStyle.BackColor = $script:Theme.GridHeadBg
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $script:Theme.GridHeadFg
    $dgv.ColumnHeadersDefaultCellStyle.Font      = $script:FontBold
    $dgv.ColumnHeadersDefaultCellStyle.Padding   = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
    $dgv.DefaultCellStyle.BackColor              = $script:Theme.CardBg
    $dgv.DefaultCellStyle.ForeColor              = $script:Theme.InkPrimary
    $dgv.DefaultCellStyle.Padding                = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
    $dgv.AlternatingRowsDefaultCellStyle.BackColor = $script:Theme.RowAltBg
    $dgv.DefaultCellStyle.SelectionBackColor     = $script:Theme.AsanMintHover
    $dgv.DefaultCellStyle.SelectionForeColor     = $script:Theme.InkPrimary

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

function Set-FooterLogExpanded {
    param([bool]$Expanded)
    $script:Ui.LogExpanded = $Expanded
    if ($script:Ui.TxtLog -and -not $script:Ui.TxtLog.IsDisposed) {
        $script:Ui.TxtLog.Visible = $Expanded
    }
    if ($script:Ui.BtnClearLog -and -not $script:Ui.BtnClearLog.IsDisposed) {
        $script:Ui.BtnClearLog.Visible = $Expanded
    }
    if ($script:Ui.PnlFooter -and -not $script:Ui.PnlFooter.IsDisposed) {
        if ($Expanded) { $script:Ui.PnlFooter.Height = 120 }
        else { $script:Ui.PnlFooter.Height = 38 }
    }
    if ($script:Ui.BtnToggleLog -and -not $script:Ui.BtnToggleLog.IsDisposed) {
        if ($Expanded) { $script:Ui.BtnToggleLog.Text = '상세 로그 접기' }
        else { $script:Ui.BtnToggleLog.Text = '상세 로그 보기' }
    }
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
# [C3 Fix] 전 탭 조건부 버튼 활성 상태 + 비활성 사유 툴팁 중앙 동기화
# ============================================================================
function Sync-AllUiButtonStates {
    $busy     = [bool]$script:AsyncState.IsBusy
    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir))
    $busyMsg  = '현재 작업이 진행 중입니다. 완료 후 다시 시도해 주세요.'

    # 탭 1: 서버 백업 버튼은 사내망·서버 연결 시에만 활성
    if ($script:Tab1Ui -and $script:Tab1Ui.BtnBackupServer -and -not $script:Tab1Ui.BtnBackupServer.IsDisposed) {
        $r1 = $busyMsg
        if (-not $busy) {
            if ($net -and $net.Status -eq 'IntranetOnly') {
                $r1 = '사내망은 연결되었으나 백업 서버가 응답하지 않습니다. ZIP 파일로 저장을 이용해 주세요.'
            } else {
                $r1 = '병원 사내망에 연결되지 않아 서버 백업을 사용할 수 없습니다. 네트워크를 연결하거나 ZIP 파일로 저장을 이용해 주세요.'
            }
        }
        Set-ButtonTipState -Button $script:Tab1Ui.BtnBackupServer -Enabled ((-not $busy) -and $isOnline) -DisabledReason $r1
    }

    # 탭 2: 백업 로드 여부, 선택 개수, 실패 건수, 특수장비 조건 + 사유 툴팁 동기화
    if ($script:Tab2Ui -and $script:Tab2Ui.DgvRestore -and -not $script:Tab2Ui.DgvRestore.IsDisposed) {
        $hasServer = ((@($script:Tab2Ui.ComboBackupEntries)).Count -gt 0)
        $hasLoaded = (-not [string]::IsNullOrWhiteSpace([string]$script:Tab2Ui.LoadedSourcePath))
        $hasFail   = ((@($script:Tab2Ui.LastFailures)).Count -gt 0)
        $selCnt    = 0
        foreach ($r in $script:Tab2Ui.DgvRestore.Rows) {
            if ($r.Cells[0].Value -eq $true) { $selCnt++ }
        }
        $hasSip2     = ($null -ne $script:Tab2Ui.CurrentSpecInfo -and [bool]$script:Tab2Ui.CurrentSpecInfo.Info.HasStep2)
        $hasSpec     = ($null -ne $script:Tab2Ui.CurrentSpecInfo)
        $selSpecType = ''
        if ($hasSpec -and $script:Tab2Ui.CurrentSpecInfo.Row) { $selSpecType = [string]$script:Tab2Ui.CurrentSpecInfo.Row.SpecialType }
        $hasSpecExe  = ($hasSpec -and $script:Tab2Ui.CurrentSpecInfo.Info.Installer -and $script:Tab2Ui.CurrentSpecInfo.Info.Installer.Found -and -not [string]::IsNullOrWhiteSpace([string]$script:Tab2Ui.CurrentSpecInfo.Info.Installer.ExePath))
        $hasSpecDir  = ($hasSpec -and $script:Tab2Ui.CurrentSpecInfo.Info.Installer -and $script:Tab2Ui.CurrentSpecInfo.Info.Installer.Found -and -not [string]::IsNullOrWhiteSpace([string]$script:Tab2Ui.CurrentSpecInfo.Info.Installer.Folder))

        if ($script:Tab2Ui.BtnLoadServer) {
            $rLoad = $busyMsg
            if (-not $busy) {
                if (-not $isOnline) { $rLoad = '사내 백업 서버에 연결되지 않아 목록을 불러올 수 없습니다. ZIP 파일 열기를 이용해 주세요.' }
                else { $rLoad = '서버에 저장된 백업 폴더가 없습니다.' }
            }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnLoadServer -Enabled ((-not $busy) -and $hasServer) -DisabledReason $rLoad
        }
        if ($script:Tab2Ui.BtnRunDeferred) {
            $rDef = $busyMsg
            if (-not $busy) { $rDef = '먼저 1단계에서 서버 백업이나 ZIP 파일을 불러와 주세요.' }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnRunDeferred -Enabled ((-not $busy) -and $hasLoaded) -DisabledReason $rDef
        }
        if ($script:Tab2Ui.BtnStartRestore) {
            $rStart = $busyMsg
            if (-not $busy) {
                if (-not $hasLoaded) { $rStart = '먼저 1단계에서 복원할 백업을 불러와 주세요.' }
                else { $rStart = '2단계 목록에서 복원할 프린터를 1대 이상 체크해 주세요.' }
            }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnStartRestore -Enabled ((-not $busy) -and $hasLoaded -and ($selCnt -gt 0)) -DisabledReason $rStart
        }
        if ($script:Tab2Ui.BtnRetryFailed) {
            $rRetry = $busyMsg
            if (-not $busy) {
                if (-not $hasLoaded) { $rRetry = '먼저 1단계에서 복원할 백업을 불러와 주세요.' }
                else { $rRetry = '복원에 실패한 프린터가 없어 다시 시도할 항목이 없습니다.' }
            }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnRetryFailed -Enabled ((-not $busy) -and $hasLoaded -and $hasFail) -DisabledReason $rRetry
        }
        if ($script:Tab2Ui.BtnSpecInstall) {
            $rInst = $busyMsg
            if (-not $busy) {
                if (-not $hasSpec) { $rInst = '감지된 특수 장비가 없습니다.' }
                elseif ($selSpecType -eq 'EPSON_TMT88_LPT') { $rInst = 'EPSON TM-T88VI는 드라이버를 설치하지 않고 LPT1 직결로 사용하는 장비입니다.' }
                else { $rInst = '이 PC의 로컬 드라이버 폴더에서 해당 장비의 설치 파일을 찾지 못했습니다.' }
            }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnSpecInstall -Enabled ((-not $busy) -and $hasSpecExe) -DisabledReason $rInst
        }
        if ($script:Tab2Ui.BtnSpecStep2) {
            $rS2 = $busyMsg
            if (-not $busy) { $rS2 = 'SIP-30M 진료카드 발급기를 선택했을 때만 사용할 수 있는 마무리 기능입니다.' }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnSpecStep2 -Enabled ((-not $busy) -and $hasSip2) -DisabledReason $rS2
        }
        if ($script:Tab2Ui.BtnSpecFolder) {
            $rDir = '이 장비의 로컬 설치 폴더를 찾지 못했습니다.'
            if (-not $hasSpec) { $rDir = '감지된 특수 장비가 없습니다.' }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnSpecFolder -Enabled $hasSpecDir -DisabledReason $rDir
        }
        if ($script:Tab2Ui.BtnSpecProps) {
            $rPrp = $busyMsg
            if (-not $busy) { $rPrp = '감지된 특수 장비가 없습니다.' }
            Set-ButtonTipState -Button $script:Tab2Ui.BtnSpecProps -Enabled ((-not $busy) -and $hasSpec) -DisabledReason $rPrp
        }
    }

    # 탭 3: 선택된 프린터 행 유무에 따라 선택 전용 버튼 활성 상태 및 사유 툴팁 동기화
    if ($script:Tab3Ui -and $script:Tab3Ui.DgvVerify -and -not $script:Tab3Ui.DgvVerify.IsDisposed) {
        $hasSel3 = ($script:Tab3Ui.DgvVerify.SelectedRows.Count -gt 0)
        $rSel3   = $busyMsg
        if (-not $busy) { $rSel3 = '먼저 위 목록에서 프린터를 하나 선택해 주세요.' }
        if ($script:Tab3Ui.BtnSingleTest) { Set-ButtonTipState -Button $script:Tab3Ui.BtnSingleTest -Enabled ((-not $busy) -and $hasSel3) -DisabledReason $rSel3 }
        if ($script:Tab3Ui.BtnProps)      { Set-ButtonTipState -Button $script:Tab3Ui.BtnProps      -Enabled ((-not $busy) -and $hasSel3) -DisabledReason $rSel3 }
        if ($script:Tab3Ui.BtnPrefs)      { Set-ButtonTipState -Button $script:Tab3Ui.BtnPrefs      -Enabled ((-not $busy) -and $hasSel3) -DisabledReason $rSel3 }
        if ($script:Tab3Ui.BtnSetDefault) { Set-ButtonTipState -Button $script:Tab3Ui.BtnSetDefault -Enabled ((-not $busy) -and $hasSel3) -DisabledReason $rSel3 }
    }

    # 탭 4: 5일 경과 수, 검색어, 행 선택 상태 및 사유 툴팁 동기화
    if ($script:Tab4Ui -and $script:Tab4Ui.DgvServer -and -not $script:Tab4Ui.DgvServer.IsDisposed) {
        $old5      = (@($script:AppState.ServerBackups | Where-Object { $_.IsOld5Days })).Count
        $hasSel    = ($script:Tab4Ui.DgvServer.SelectedRows.Count -gt 0)
        $hasSearch = ($script:Tab4Ui.TxtSearch -and -not [string]::IsNullOrWhiteSpace($script:Tab4Ui.TxtSearch.Text))

        if ($script:Tab4Ui.BtnClearSearch) {
            Set-ButtonTipState -Button $script:Tab4Ui.BtnClearSearch -Enabled $hasSearch -DisabledReason '입력된 검색어가 없습니다.'
        }
        if ($script:Tab4Ui.BtnCleanOld5) {
            $rOld = $busyMsg
            if (-not $busy) {
                if (-not $isOnline) { $rOld = '사내 백업 서버에 연결되지 않아 정리할 수 없습니다.' }
                else { $rOld = '5일 이상 지난 서버 백업이 없어 정리할 항목이 없습니다.' }
            }
            Set-ButtonTipState -Button $script:Tab4Ui.BtnCleanOld5 -Enabled ((-not $busy) -and $isOnline -and ($old5 -gt 0)) -DisabledReason $rOld
        }
        if ($script:Tab4Ui.BtnLoadToTab2) {
            $rL2 = $busyMsg
            if (-not $busy) { $rL2 = '먼저 위 목록에서 불러올 백업 폴더를 선택해 주세요.' }
            Set-ButtonTipState -Button $script:Tab4Ui.BtnLoadToTab2 -Enabled ((-not $busy) -and $hasSel) -DisabledReason $rL2
        }
        if ($script:Tab4Ui.BtnDeleteOne) {
            $rDel = $busyMsg
            if (-not $busy) {
                if (-not $isOnline) { $rDel = '사내 백업 서버에 연결되지 않아 삭제할 수 없습니다.' }
                else { $rDel = '먼저 위 목록에서 삭제할 백업 폴더를 선택해 주세요.' }
            }
            Set-ButtonTipState -Button $script:Tab4Ui.BtnDeleteOne -Enabled ((-not $busy) -and $isOnline -and $hasSel) -DisabledReason $rDel
        }
    }
}

function Set-UiBusyState {
    param(
        [bool]$IsBusy,
        [string]$StatusText = '',
        [switch]$Indeterminate,
        [switch]$IsError
    )
    $script:AsyncState.IsBusy = $IsBusy
    if ($script:Ui.LastDisabledHost -and $script:Ui.ToolTip) {
        try { $script:Ui.ToolTip.Hide($script:Ui.LastDisabledHost) } catch {}
        $script:Ui.LastDisabledBtn  = $null
        $script:Ui.LastDisabledHost = $null
    }
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
    if ($script:Ui.LblProgressText -and -not $script:Ui.LblProgressText.IsDisposed) {
        if (-not [string]::IsNullOrWhiteSpace($StatusText)) {
            $script:Ui.LblProgressText.Text = $StatusText
        }
        if ($IsError) {
            $script:Ui.LblProgressText.ForeColor = $script:Theme.DangerRedDeep
        } elseif ($IsBusy) {
            $script:Ui.LblProgressText.ForeColor = $script:Theme.AsanDeep
        } else {
            $script:Ui.LblProgressText.ForeColor = $script:Theme.InkSecondary
        }
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
    param([switch]$ForceAbort)
    if ($script:AsyncState.PollTimer) {
        try { $script:AsyncState.PollTimer.Stop() } catch {}
    }
    if ($script:AsyncState.PowerShell) {
        if ($ForceAbort) {
            try { [void]$script:AsyncState.PowerShell.BeginStop($null, $null) } catch {}
        } else {
            try { $script:AsyncState.PowerShell.Stop() } catch {}
            try { $script:AsyncState.PowerShell.Dispose() } catch {}
        }
        $script:AsyncState.PowerShell = $null
    }
    if ($script:AsyncState.Runspace) {
        if ($ForceAbort) {
            try { $script:AsyncState.Runspace.CloseAsync() } catch {}
        } else {
            try { $script:AsyncState.Runspace.Close() } catch {}
            try { $script:AsyncState.Runspace.Dispose() } catch {}
        }
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
        [void](Show-AsanMessageBox -Text "현재 '$($script:AsyncState.TaskName)' 작업이 진행 중입니다. 완료 후 다시 시도하세요." -Caption '작업 진행 중' -Buttons 'OK' -Icon 'Information')
        return
    }

    $dummy = $null
    while ($global:AsanCtx.LogQueue.TryDequeue([ref]$dummy)) {}

    Set-UiBusyState -IsBusy $true -StatusText "$TaskName 시작 중..." -Indeterminate:$Indeterminate
    Add-UiLog -Message "=== [$TaskName] 시작 ===" -Level 'INFO'

    try {
        $iss = New-AsanChildInitialSessionState
        $rs  = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $script:AsyncState.Runspace = $rs
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()

        $ps = [System.Management.Automation.PowerShell]::Create()
        $script:AsyncState.PowerShell = $ps
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
        $script:AsyncState.AsyncResult   = $asyncRes
        $script:AsyncState.OnComplete    = $OnComplete
        $script:AsyncState.CallbackState = $CallbackState

        $script:AsyncState.PollTimer.Start()
    }
    catch {
        $startErr = $_.Exception.Message
        Stop-ActiveAsyncRunspace
        Set-UiBusyState -IsBusy $false -StatusText '작업 시작 실패' -IsError
        Add-UiLog -Message "비동기 작업 기동 오류: $startErr" -Level 'ERROR'
        Invoke-ErrorWithAutoReportPrompt -Caption '실행 오류' -Message "작업을 시작할 수 없습니다:`r`n$startErr" -Category 'UI/프로그램 버그' -ErrorDetail $startErr
    }
}

# ============================================================================
# [C1 Fix] WPP 조치 안내 대화상자 (클로저 소실 제거: Tag + DialogResult)
# ============================================================================
function Show-WppRemediationDialog {
    param($WppStatus)
    if (-not $WppStatus -or -not $WppStatus.IsEnabled) { return }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Windows 보호 인쇄 모드 해제 안내'
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
    $lblHead.BackColor = $script:Theme.DangerRed
    $lblHead.ForeColor = [System.Drawing.Color]::White
    $lblHead.Font      = $script:FontBold
    $lblHead.Padding   = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)
    $lblHead.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 52
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)

    $btnOpen = New-StyledButton -Text 'Windows 프린터 설정 열기' -Width 210 -Height 34 -Variant 'Danger'
    if ($WppStatus.IsPolicyEnforced) { $btnOpen.Text = '로컬 그룹 정책 열기' }
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
            [void](Show-AsanMessageBox -Text "설정 창을 열지 못했습니다: $($_.Exception.Message)" -Caption '열기 실패' -Buttons 'OK' -Icon 'Warning' -Owner ($sender.FindForm()))
        }
    })

    $btnClose = New-StyledButton -Text '닫기' -Width 104 -Height 34 -Variant 'Secondary'
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
    $txtGuide.BackColor   = $script:Theme.DangerRedTint
    $txtGuide.ForeColor   = $script:Theme.InkPrimary
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
# [자동 오류 리포트 안내 + 버그 리포트 팝업] 온·오프라인 자동 분기 + 클로저 안전
# ============================================================================
function Invoke-ErrorWithAutoReportPrompt {
    param(
        [string]$Caption = '작업 오류',
        [string]$Message = '작업 중 예기치 않은 오류가 발생했습니다.',
        [string]$Category = 'UI/프로그램 버그',
        [string]$ErrorDetail = '',
        [string]$TargetPrinter = ''
    )
    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir))
    $netLabel = '사내망 미연결'
    if ($net) {
        if ($net.Status -eq 'Online') { $netLabel = '사내망·서버 연결됨' }
        elseif ($net.Status -eq 'IntranetOnly') { $netLabel = '사내망 연결됨 (서버 응답 없음)' }
    }

    if ($isOnline) {
        $promptTail = "오류 진단 리포트를 자동으로 구성해 사내 리포트함으로 보낼까요?`r`nPC 환경과 작업 로그가 자동 첨부되며 비밀번호는 안전하게 가려집니다."
    } else {
        $promptTail = "현재 사내 백업 서버에 연결되어 있지 않습니다.`r`n오류 진단 리포트를 자동으로 구성해 이 PC의 로컬 폴더(C:\_AsanPrtOffline\_Reports)에 저장할까요?`r`n비밀번호는 안전하게 가려지며, 나중에 파일만 담당자에게 전달해 주시면 됩니다."
    }

    $fullMsg = "$Message`r`n`r`n$promptTail"
    $ans = Show-AsanMessageBox -Text $fullMsg -Caption $Caption -Buttons 'YesNo' -Icon 'Error'
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
        $autoSum = @(
            "발생 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
            "오류 분류: $Category",
            "네트워크 상태: $netLabel",
            "오류 내용: $ErrorDetail"
        ) -join "`r`n"
        Show-BugReportDialog -DefaultCategory $Category -DefaultPrinter $TargetPrinter -ErrorSummary $autoSum
    }
}

function Show-BugReportDialog {
    param(
        [string]$DefaultCategory = '복원/드라이버 오류',
        [string]$DefaultPrinter = '',
        [string]$ErrorSummary = ''
    )

    if ($script:AsyncState.IsBusy) {
        [void](Show-AsanMessageBox -Text '현재 진행 중인 작업이 완료된 뒤 리포트를 전송해 주세요.' -Caption '작업 진행 중' -Buttons 'OK' -Icon 'Information')
        return
    }

    $netNow   = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $netNow -and $netNow.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$netNow.PrtBakDir))

    $dlg = New-Object System.Windows.Forms.Form
    if ($isOnline) { $dlg.Text = '오류 리포트 보내기' }
    else { $dlg.Text = '오류 리포트 로컬 저장' }
    $dlg.Size            = New-Object System.Drawing.Size(570, 430)
    $dlg.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [System.Drawing.Color]::White
    $dlg.Font            = $script:FontBase
    $dlg.Padding         = New-Object System.Windows.Forms.Padding(14)

    $lblGuide = New-Object System.Windows.Forms.Label
    if ($isOnline) {
        $lblGuide.Text      = 'PC 환경, 프린터·포트 상태, 작업 로그를 모아 사내 서버 리포트함으로 전송합니다. 비밀번호는 자동으로 가려집니다.'
        $lblGuide.BackColor = $script:Theme.AsanMint
        $lblGuide.ForeColor = $script:Theme.AsanDeep
    } else {
        $lblGuide.Text      = '현재 사내 백업 서버에 연결되어 있지 않아 이 PC(C:\_AsanPrtOffline\_Reports)에 리포트를 저장합니다. 비밀번호는 자동으로 가려지며, 저장 후 파일만 담당자에게 전달해 주세요.'
        $lblGuide.BackColor = $script:Theme.AsanOrangeTint
        $lblGuide.ForeColor = $script:Theme.AsanOrangeText
    }
    $lblGuide.Dock        = [System.Windows.Forms.DockStyle]::Top
    $lblGuide.Height      = 46
    $lblGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lblGuide.Padding     = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
    $lblGuide.Font        = $script:FontSmallB

    # DPI 125~150% 라벨-입력창 겹침 방지 TableLayoutPanel
    $pnlFields = New-Object System.Windows.Forms.TableLayoutPanel
    $pnlFields.Dock        = [System.Windows.Forms.DockStyle]::Top
    $pnlFields.AutoSize    = $true
    $pnlFields.ColumnCount = 2
    $pnlFields.RowCount    = 2
    $pnlFields.Padding     = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    [void]$pnlFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$pnlFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $lblCat = New-Object System.Windows.Forms.Label
    $lblCat.Text      = '증상 분류:'
    $lblCat.Font      = $script:FontBold
    $lblCat.AutoSize  = $true
    $lblCat.Anchor    = [System.Windows.Forms.AnchorStyles]::Left
    $lblCat.Margin    = New-Object System.Windows.Forms.Padding(0, 6, 10, 6)

    $cmbCat = New-Object System.Windows.Forms.ComboBox
    $cmbCat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbCat.Width         = 240
    $cmbCat.Anchor        = [System.Windows.Forms.AnchorStyles]::Left
    $cmbCat.Margin        = New-Object System.Windows.Forms.Padding(0, 3, 0, 4)
    foreach ($cat in @('복원/드라이버 오류', '백업 오류', 'WSD/포트 전환', '공유 인증/SID 충돌', '특수/바코드 프린터', 'UI/프로그램 버그', '기타')) {
        [void]$cmbCat.Items.Add($cat)
    }
    $catIdx = $cmbCat.Items.IndexOf($DefaultCategory)
    if ($catIdx -lt 0) { $catIdx = 0 }
    $cmbCat.SelectedIndex = $catIdx

    $lblPrt = New-Object System.Windows.Forms.Label
    $lblPrt.Text      = '대상 프린터:'
    $lblPrt.Font      = $script:FontBold
    $lblPrt.AutoSize  = $true
    $lblPrt.Anchor    = [System.Windows.Forms.AnchorStyles]::Left
    $lblPrt.Margin    = New-Object System.Windows.Forms.Padding(0, 6, 10, 6)

    $cmbPrt = New-Object System.Windows.Forms.ComboBox
    $cmbPrt.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cmbPrt.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $cmbPrt.Margin        = New-Object System.Windows.Forms.Padding(0, 3, 0, 4)
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

    $pnlFields.Controls.Add($lblCat, 0, 0)
    $pnlFields.Controls.Add($cmbCat, 1, 0)
    $pnlFields.Controls.Add($lblPrt, 0, 1)
    $pnlFields.Controls.Add($cmbPrt, 1, 1)

    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height  = 46
    $pnlBot.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $flpRight = New-RightFlowStrip -TopPadding 0 -RightPadding 0
    $btnCan = New-StyledButton -Text '취소' -Width 92 -Height 32 -Variant 'Secondary'
    $btnCan.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCan.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $sendBtnText = '서버로 리포트 전송'
    if (-not $isOnline) { $sendBtnText = '로컬 폴더에 저장' }
    $btnSend = New-StyledButton -Text $sendBtnText -Width 146 -Height 32 -Variant 'Orange'
    $btnSend.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $flpRight.Controls.Add($btnCan)
    $flpRight.Controls.Add($btnSend)
    $pnlBot.Controls.Add($flpRight)

    $pnlMemo = New-Object System.Windows.Forms.Panel
    $pnlMemo.Dock    = [System.Windows.Forms.DockStyle]::Fill
    $pnlMemo.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $lblMemo = New-Object System.Windows.Forms.Label
    $lblMemo.Text   = '발생한 문제나 현장 상황을 간단히 적어 주세요'
    $lblMemo.Font   = $script:FontBold
    $lblMemo.Dock   = [System.Windows.Forms.DockStyle]::Top
    $lblMemo.Height = 22

    $txtMemo = New-Object System.Windows.Forms.TextBox
    $txtMemo.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $txtMemo.Multiline     = $true
    $txtMemo.AcceptsReturn = $true
    $txtMemo.ScrollBars    = [System.Windows.Forms.ScrollBars]::Vertical
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
            [void](Show-AsanMessageBox -Text "버그 리포트 전송 중 오류가 발생했습니다:`r`n$err" -Caption '전송 오류' -Buttons 'OK' -Icon 'Error')
            return
        }
        if ($data.SavedToServer) {
            Add-UiLog -Message "서버 리포트함 전송 완료: $($data.SavedPath)" -Level 'INFO'
            [void](Show-AsanMessageBox -Text "오류/버그 리포트가 사내 서버 리포트함으로 전송되었습니다.`r`n`r`n• 리포트 ID: $($data.ReportId)`r`n• 저장 경로: $($data.SavedPath)" -Caption '리포트 전송 완료' -Buttons 'OK' -Icon 'Information')
        } else {
            $fbDetail = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$data.FallbackNote)) {
                $fbDetail = "`r`n• 서버 전송 실패 사유: $($data.FallbackNote)"
                Add-UiLog -Message "서버 리포트 전송 실패 사유: $($data.FallbackNote)" -Level 'WARN'
            }
            Add-UiLog -Message "로컬 리포트 저장 완료: $($data.SavedPath)" -Level 'WARN'
            $openRep = Show-AsanMessageBox -Text "사내 서버에 연결되지 않아 이 PC의 오프라인 리포트 폴더에 저장했습니다.$fbDetail`r`n`r`n저장 경로: $($data.SavedPath)`r`n나중에 해당 폴더의 파일을 담당자에게 전달해 주세요.`r`n`r`n저장된 폴더를 바로 열어 확인하시겠습니까?" -Caption '로컬 리포트 저장 완료' -Buttons 'YesNo' -Icon 'Information'
            if ($openRep -eq [System.Windows.Forms.DialogResult]::Yes) {
                Open-FolderInExplorerSafe -FolderPath $data.SavedPath
            }
        }
    }

    Invoke-AsanAsyncTask -TaskName '오류/버그 리포트 수집 및 전송' -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
}

function Update-HeaderAndWppUi {
    $net = $script:AppState.NetworkInfo
    $shortOs = ([string]$script:AppState.OsCaption) -replace '^Microsoft\s+', ''
    if ([string]::IsNullOrWhiteSpace($shortOs)) { $shortOs = 'Windows' }
    $script:Ui.LblOs.Text  = $shortOs
    $script:Ui.LblSid.Text = "SID  $($script:AppState.LocalSid)"

    $ipText = '확인 중'
    if ($net) { $ipText = $net.IPAddress }
    $script:Ui.LblPcIp.Text = "$($env:COMPUTERNAME)  $ipText"

    $tip = $script:Ui.ToolTip
    if (-not $net) {
        $script:Ui.LblNetBadge.Text      = ' ● 네트워크 확인 중 '
        $script:Ui.LblNetBadge.BackColor = $script:Theme.InkMuted
        $script:Ui.LblServerPath.Text    = '사내망 및 서버 연결 확인 중'
        $script:Ui.PnlWppBanner.Visible  = $false
        return
    }

    if ($net.Status -eq 'Online') {
        $script:Ui.LblNetBadge.Text      = ' ● 사내망 · 서버 연결됨 '
        $script:Ui.LblNetBadge.BackColor = $script:Theme.BadgeOnlineBg
        $script:Ui.LblServerPath.Text    = "백업 서버  $($global:AsanCtx.ServerIP) 연결됨"
        if ($tip) { $tip.SetToolTip($script:Ui.LblNetBadge, "병원 사내망과 백업 서버($($global:AsanCtx.ServerIP))에 정상 연결되어 있습니다.") }
    } elseif ($net.Status -eq 'IntranetOnly') {
        $script:Ui.LblNetBadge.Text      = ' ▲ 사내망 연결 · 서버 미응답 '
        $script:Ui.LblNetBadge.BackColor = $script:Theme.AsanOrange
        $script:Ui.LblServerPath.Text    = '사내망 연결됨 · 백업 서버 응답 없음 · ZIP 백업 가능'
        if ($tip) { $tip.SetToolTip($script:Ui.LblNetBadge, "병원 사내망은 연결되었으나 백업 서버($($global:AsanCtx.ServerIP))가 응답하지 않습니다. ZIP 파일 백업·복원은 사용할 수 있습니다.") }
    } else {
        $script:Ui.LblNetBadge.Text      = ' ■ 사내망 미연결 '
        $script:Ui.LblNetBadge.BackColor = $script:Theme.DangerRed
        $script:Ui.LblServerPath.Text    = '사내망 미연결 · 네트워크 없이 ZIP 백업·복원 가능'
        if ($tip) { $tip.SetToolTip($script:Ui.LblNetBadge, "병원 사내망 네트워크에 연결되지 않았습니다. 랜선·고정 IP·사내 DNS($($global:AsanCtx.InternalDnsIP))를 확인하거나 ZIP 파일 백업·복원을 이용해 주세요.") }
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
            Invoke-ErrorWithAutoReportPrompt -Caption '환경 진단 오류' -Message "PC 환경과 네트워크를 확인하는 중 오류가 발생했습니다:`r`n$err" -Category 'UI/프로그램 버그' -ErrorDetail ([string]$err)
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
# [C2 Fix] 메인 WinForms 셸 조립 — 고시인성 아산 딥그린 헤더 + 단계형 4탭 셸
# ============================================================================
function Initialize-MainGuiShell {
    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "프린터 마이그레이션 도구 v$($global:AsanCtx.AppVersion)"
    $form.Size          = New-Object System.Drawing.Size(1040, 720)
    $form.MinimumSize   = New-Object System.Drawing.Size(960, 640)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor     = $script:Theme.CanvasBg
    $form.Font          = $script:FontBase
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $form.KeyPreview    = $true

    $appIcon = New-AsanPrinterAppIcon
    if ($appIcon) { $form.Icon = $appIcon }

    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.AutoPopDelay = 8000
    $tip.InitialDelay = 350
    $tip.ReshowDelay  = 200
    $tip.ShowAlways   = $true

    # ---------------- [1] 최상단 딥그린 헤더 + 2px 오렌지 포인트 바 + 고시인성 환경 요약 바 ----------------
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height    = 82
    $pnlHeader.BackColor = $script:Theme.HeaderBg

    # Row 1 (52px): 자체 프린터 심볼 | 제목·부제 / 우측 상태 배지 + 새로고침 + 오류 신고
    $pnlBrand = New-Object System.Windows.Forms.Panel
    $pnlBrand.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlBrand.Height    = 52
    $pnlBrand.BackColor = $script:Theme.HeaderBg
    $pnlBrand.Padding   = New-Object System.Windows.Forms.Padding(14, 6, 14, 6)

    $badgeImg = New-AsanPrinterBadgeImage
    $picBadge = New-Object System.Windows.Forms.PictureBox
    $picBadge.Dock      = [System.Windows.Forms.DockStyle]::Left
    $picBadge.Width     = 42
    $picBadge.Padding   = New-Object System.Windows.Forms.Padding(0, 1, 6, 1)
    $picBadge.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $picBadge.BackColor = [System.Drawing.Color]::Transparent
    if ($badgeImg) { $picBadge.Image = $badgeImg } else { $picBadge.Visible = $false }

    $pnlTitleStack = New-Object System.Windows.Forms.Panel
    $pnlTitleStack.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlTitleStack.BackColor = [System.Drawing.Color]::Transparent
    $pnlTitleStack.Padding   = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = '프린터 · 드라이버 마이그레이션 도구'
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font      = $script:FontTitle
    $lblTitle.Dock      = [System.Windows.Forms.DockStyle]::Top
    $lblTitle.Height    = 24
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text      = "기존 PC와 새 PC 간 프린터·드라이버 간편 이관  v$($global:AsanCtx.AppVersion)"
    $lblSubtitle.ForeColor = $script:Theme.HeaderSubFg
    $lblSubtitle.Font      = $script:FontSubtitle
    $lblSubtitle.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblSubtitle.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $tip.SetToolTip($lblSubtitle, '단축키: 탭 이동 Alt+1~4, 연결 새로고침 F5')

    $pnlTitleStack.Controls.Add($lblSubtitle)
    $pnlTitleStack.Controls.Add($lblTitle)

    $flpHdrRight1 = New-RightFlowStrip -TopPadding 5 -RightPadding 0

    $btnBugReport = New-StyledButton -Text '오류 신고' -Width 86 -Height 30 -Variant 'Orange' -RegisterBusy
    $btnBugReport.Font   = $script:FontSmallB
    $btnBugReport.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnBugReport.Add_Click({ Show-BugReportDialog })
    $tip.SetToolTip($btnBugReport, '문제가 생기면 진단 정보와 로그를 담당자에게 전송합니다')

    $btnRefresh = New-StyledButton -Text '새로고침' -Width 86 -Height 30 -Variant 'HeaderUtil' -RegisterBusy
    $btnRefresh.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnRefresh.Add_Click({ Invoke-EnvironmentRefreshAsync })
    $tip.SetToolTip($btnRefresh, '네트워크와 서버 연결 상태를 다시 확인합니다 (단축키 F5)')

    $lblNetBadge = New-Object System.Windows.Forms.Label
    $lblNetBadge.Text      = ' ● 네트워크 확인 중 '
    $lblNetBadge.ForeColor = [System.Drawing.Color]::White
    $lblNetBadge.BackColor = $script:Theme.InkMuted
    $lblNetBadge.Font      = $script:FontSmallB
    $lblNetBadge.AutoSize  = $true
    $lblNetBadge.Padding   = New-Object System.Windows.Forms.Padding(10, 7, 10, 7)
    $lblNetBadge.Margin    = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)

    # RightToLeft 순서: 먼저 추가한 컨트롤이 가장 오른쪽에 배치됨
    $flpHdrRight1.Controls.Add($btnBugReport)
    $flpHdrRight1.Controls.Add($btnRefresh)
    $flpHdrRight1.Controls.Add($lblNetBadge)

    $pnlBrand.Controls.Add($pnlTitleStack)
    $pnlBrand.Controls.Add($flpHdrRight1)
    $pnlBrand.Controls.Add($picBadge)

    # 2px 아산 오렌지 포인트 라인
    $pnlAccentBar = New-Object System.Windows.Forms.Panel
    $pnlAccentBar.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlAccentBar.Height    = 2
    $pnlAccentBar.BackColor = $script:Theme.AsanOrangeLine

    # Row 2 (28px): 고시인성 환경 요약 바 (PC/IP · OS · 서버 / 우측 SID + 복사)
    $pnlMetaBar = New-Object System.Windows.Forms.Panel
    $pnlMetaBar.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlMetaBar.BackColor = $script:Theme.MetaBarBg
    $pnlMetaBar.Padding   = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)

    $pnlMetaBottomLine = New-Object System.Windows.Forms.Panel
    $pnlMetaBottomLine.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlMetaBottomLine.Height    = 1
    $pnlMetaBottomLine.BackColor = $script:Theme.Border

    $flpHdrMeta = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpHdrMeta.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $flpHdrMeta.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpHdrMeta.WrapContents  = $false
    $flpHdrMeta.BackColor     = [System.Drawing.Color]::Transparent
    $flpHdrMeta.Padding       = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)

    $lblPcIp = New-Object System.Windows.Forms.Label
    $lblPcIp.Text      = "$($env:COMPUTERNAME)  확인 중"
    $lblPcIp.ForeColor = $script:Theme.InkPrimary
    $lblPcIp.Font      = $script:FontSmallB
    $lblPcIp.AutoSize  = $true
    $lblPcIp.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)

    $lblOs = New-Object System.Windows.Forms.Label
    $lblOs.Text      = 'Windows 확인 중'
    $lblOs.ForeColor = $script:Theme.InkSecondary
    $lblOs.Font      = $script:FontSmallB
    $lblOs.AutoSize  = $true
    $lblOs.Margin    = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)

    $lblServerPath = New-Object System.Windows.Forms.Label
    $lblServerPath.Text      = '백업 서버 확인 중'
    $lblServerPath.ForeColor = $script:Theme.InkSecondary
    $lblServerPath.Font      = $script:FontSmall
    $lblServerPath.AutoSize  = $true
    $lblServerPath.Margin    = New-Object System.Windows.Forms.Padding(0)

    $flpHdrMeta.Controls.AddRange(@($lblPcIp, $lblOs, $lblServerPath))

    $flpHdrRight2 = New-RightFlowStrip -TopPadding 2 -RightPadding 0
    $sidTimer = New-Object System.Windows.Forms.Timer
    $sidTimer.Interval = 1500
    $sidTimer.Add_Tick({
        if ($script:Ui.SidFlashTimer) { $script:Ui.SidFlashTimer.Stop() }
        if ($script:Ui.BtnCopySid -and -not $script:Ui.BtnCopySid.IsDisposed) {
            $script:Ui.BtnCopySid.Text = 'SID 복사'
        }
    })
    $script:Ui.SidFlashTimer = $sidTimer

    $btnCopySid = New-StyledButton -Text 'SID 복사' -Width 72 -Height 22 -Variant 'Secondary'
    $btnCopySid.Font   = $script:FontSmallB
    $btnCopySid.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $btnCopySid.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:AppState.LocalSid)) {
            try {
                [System.Windows.Forms.Clipboard]::SetText($script:AppState.LocalSid)
                Add-UiLog -Message "현재 PC Machine SID가 클립보드에 복사되었습니다: $($script:AppState.LocalSid)" -Level 'INFO'
                if ($script:Ui.LblProgressText -and (-not $script:AsyncState.IsBusy)) {
                    $script:Ui.LblProgressText.Text      = '현재 PC의 Machine SID를 클립보드에 복사했습니다.'
                    $script:Ui.LblProgressText.ForeColor = $script:Theme.AsanDeep
                }
                if ($script:Ui.BtnCopySid -and -not $script:Ui.BtnCopySid.IsDisposed) {
                    $script:Ui.BtnCopySid.Text = '복사됨'
                }
                if ($script:Ui.SidFlashTimer) {
                    $script:Ui.SidFlashTimer.Stop()
                    $script:Ui.SidFlashTimer.Start()
                }
            } catch {}
        }
    })
    $tip.SetToolTip($btnCopySid, '공유 프린터 SID 충돌 확인 시 현재 PC의 SID를 복사합니다')

    $lblSid = New-Object System.Windows.Forms.Label
    $lblSid.Text      = 'SID 조회 중'
    $lblSid.ForeColor = $script:Theme.InkSecondary
    $lblSid.Font      = $script:FontSmall
    $lblSid.AutoSize  = $true
    $lblSid.Margin    = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

    $flpHdrRight2.Controls.Add($btnCopySid)
    $flpHdrRight2.Controls.Add($lblSid)

    $pnlMetaBar.Controls.Add($flpHdrMeta)
    $pnlMetaBar.Controls.Add($flpHdrRight2)
    $pnlMetaBar.Controls.Add($pnlMetaBottomLine)

    # Dock 순서: Fill(Row2) -> Top(Accent 2px) -> Top(Brand 최상단)
    $pnlHeader.Controls.Add($pnlMetaBar)
    $pnlHeader.Controls.Add($pnlAccentBar)
    $pnlHeader.Controls.Add($pnlBrand)

    # ---------------- [2] WPP 경고 배너 (Dock + RightFlowStrip) ----------------
    $pnlWpp = New-Object System.Windows.Forms.Panel
    $pnlWpp.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlWpp.Height    = 38
    $pnlWpp.BackColor = $script:Theme.DangerRed
    $pnlWpp.Padding   = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)
    $pnlWpp.Visible   = $false

    $lblWppTitle = New-Object System.Windows.Forms.Label
    $lblWppTitle.Text      = 'Windows 보호 인쇄 모드가 켜져 있어 드라이버 복원이 차단됩니다.'
    $lblWppTitle.ForeColor = [System.Drawing.Color]::White
    $lblWppTitle.Font      = $script:FontBold
    $lblWppTitle.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblWppTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $flpWppRight = New-RightFlowStrip -TopPadding 5 -RightPadding 0

    $btnWppAction = New-StyledButton -Text '프린터 설정 열기' -Width 130 -Height 28 -BackColor ([System.Drawing.Color]::White) -ForeColor $script:Theme.DangerRed
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

    $btnWppGuide = New-StyledButton -Text '조치 방법 안내' -Width 116 -Height 28 -BackColor $script:Theme.DangerRedDeep -ForeColor ([System.Drawing.Color]::White)
    $btnWppGuide.Add_Click({
        if ($script:AppState.NetworkInfo -and $script:AppState.NetworkInfo.WppStatus) {
            Show-WppRemediationDialog -WppStatus $script:AppState.NetworkInfo.WppStatus
        }
    })

    $flpWppRight.Controls.Add($btnWppAction)
    $flpWppRight.Controls.Add($btnWppGuide)

    $pnlWpp.Controls.Add($lblWppTitle)
    $pnlWpp.Controls.Add($flpWppRight)

    # ---------------- [3] 하단 클린 상태 바 + 기본 접힘 실시간 로그 (DPI 100% 안전 Dock 구조) ----------------
    $pnlFooter = New-Object System.Windows.Forms.Panel
    $pnlFooter.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlFooter.Height    = 38
    $pnlFooter.BackColor = $script:Theme.CardBg

    $pnlFootLine = New-Object System.Windows.Forms.Panel
    $pnlFootLine.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlFootLine.Height    = 1
    $pnlFootLine.BackColor = $script:Theme.Border

    $pnlFootBody = New-Object System.Windows.Forms.Panel
    $pnlFootBody.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlFootBody.Padding   = New-Object System.Windows.Forms.Padding(14, 4, 14, 5)
    $pnlFootBody.BackColor = $script:Theme.CardBg

    $pnlFootTop = New-Object System.Windows.Forms.Panel
    $pnlFootTop.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlFootTop.Height    = 28
    $pnlFootTop.BackColor = [System.Drawing.Color]::Transparent

    $pnlPrgWrap = New-Object System.Windows.Forms.Panel
    $pnlPrgWrap.Dock      = [System.Windows.Forms.DockStyle]::Left
    $pnlPrgWrap.Width     = 196
    $pnlPrgWrap.Padding   = New-Object System.Windows.Forms.Padding(0, 5, 12, 5)
    $pnlPrgWrap.BackColor = [System.Drawing.Color]::Transparent

    $prgBar = New-Object System.Windows.Forms.ProgressBar
    $prgBar.Dock    = [System.Windows.Forms.DockStyle]::Fill
    $prgBar.Minimum = 0
    $prgBar.Maximum = 100
    $pnlPrgWrap.Controls.Add($prgBar)

    $lblProgressText = New-Object System.Windows.Forms.Label
    $lblProgressText.Text      = '준비 완료'
    $lblProgressText.ForeColor = $script:Theme.InkSecondary
    $lblProgressText.Font      = $script:FontSmallB
    $lblProgressText.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblProgressText.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $flpFootRight = New-RightFlowStrip -TopPadding 2 -RightPadding 0

    $btnToggleLog = New-StyledButton -Text '상세 로그 보기' -Width 108 -Height 24 -Variant 'Secondary'
    $btnToggleLog.Font   = $script:FontSmallB
    $btnToggleLog.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $btnToggleLog.Add_Click({
        Set-FooterLogExpanded -Expanded (-not $script:Ui.LogExpanded)
    })

    $btnClearLog = New-StyledButton -Text '로그 지우기' -Width 86 -Height 24 -Variant 'Secondary'
    $btnClearLog.Font    = $script:FontSmallB
    $btnClearLog.Visible = $false
    $btnClearLog.Add_Click({ $script:Ui.TxtLog.Clear() })

    $flpFootRight.Controls.Add($btnToggleLog)
    $flpFootRight.Controls.Add($btnClearLog)

    $pnlFootTop.Controls.Add($lblProgressText)
    $pnlFootTop.Controls.Add($flpFootRight)
    $pnlFootTop.Controls.Add($pnlPrgWrap)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtLog.Multiline   = $true
    $txtLog.ReadOnly    = $true
    $txtLog.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtLog.BackColor   = $script:Theme.LogBg
    $txtLog.ForeColor   = $script:Theme.LogFg
    $txtLog.Font        = $script:FontMono
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtLog.Visible     = $false

    $pnlFootBody.Controls.Add($txtLog)
    $pnlFootBody.Controls.Add($pnlFootTop)
    $pnlFooter.Controls.Add($pnlFootBody)
    $pnlFooter.Controls.Add($pnlFootLine)

    # ---------------- [4] 중앙 4단계 탭 컨테이너 (서울아산병원 아산 그린 활성 바) ----------------
    $pnlMainWrap = New-Object System.Windows.Forms.Panel
    $pnlMainWrap.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlMainWrap.BackColor = $script:Theme.CanvasBg
    $pnlMainWrap.Padding   = New-Object System.Windows.Forms.Padding(10, 6, 10, 4)

    $tabMain = New-Object System.Windows.Forms.TabControl
    $tabMain.Dock     = [System.Windows.Forms.DockStyle]::Fill
    $tabMain.Font     = $script:FontTab
    $tabMain.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $tabMain.ItemSize = New-Object System.Drawing.Size(0, 32)
    $tabMain.Padding  = New-Object System.Drawing.Point(18, 6)

    $tabMain.Add_DrawItem({
        param($sender, $e)
        $g   = $e.Graphics
        $tab = $sender.TabPages[$e.Index]
        $rc  = $sender.GetTabRect($e.Index)
        $sel = ($sender.SelectedIndex -eq $e.Index)

        $bgCol = $script:Theme.AsanMintSoft
        $fgCol = $script:Theme.InkSecondary
        $fnt   = $script:FontTabIdle
        if ($sel) {
            $bgCol = $script:Theme.CardBg
            $fgCol = $script:Theme.AsanDeep
            $fnt   = $script:FontTab
        }

        $brBg = New-Object System.Drawing.SolidBrush($bgCol)
        $g.FillRectangle($brBg, $rc)
        $brBg.Dispose()

        if ($sel) {
            $brBar = New-Object System.Drawing.SolidBrush($script:Theme.AsanGreen)
            $g.FillRectangle($brBar, $rc.Left, $rc.Top, $rc.Width, 4)
            $brBar.Dispose()
            $penSel = New-Object System.Drawing.Pen($script:Theme.BorderBtn, 1)
            $g.DrawLine($penSel, $rc.Left, $rc.Top, $rc.Left, ($rc.Bottom - 1))
            $g.DrawLine($penSel, ($rc.Right - 1), $rc.Top, ($rc.Right - 1), ($rc.Bottom - 1))
            $penSel.Dispose()
        } else {
            $penDiv = New-Object System.Drawing.Pen($script:Theme.Border, 1)
            $g.DrawRectangle($penDiv, $rc.Left, $rc.Top, ($rc.Width - 1), ($rc.Height - 1))
            $penDiv.Dispose()
        }

        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
        [System.Windows.Forms.TextRenderer]::DrawText($g, $tab.Text, $fnt, $rc, $fgCol, $flags)
    })

    $tabBackup  = New-Object System.Windows.Forms.TabPage(' 1. 기존 PC 백업 ')
    $tabRestore = New-Object System.Windows.Forms.TabPage(' 2. 새 PC 복원 ')
    $tabVerify  = New-Object System.Windows.Forms.TabPage(' 3. 출력 확인 ')
    $tabServer  = New-Object System.Windows.Forms.TabPage(' 4. 서버 관리 ')

    foreach ($tp in @($tabBackup, $tabRestore, $tabVerify, $tabServer)) {
        $tp.BackColor = $script:Theme.CanvasBg
        $tp.Padding   = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)
        $tp.Font      = $script:FontBase
        $tabMain.TabPages.Add($tp)
    }

    $pnlMainWrap.Controls.Add($tabMain)

    # WinForms Dock Z-Order: Fill(0) -> Bottom -> Inner Top(WPP) -> Outer Top(Header)
    $form.Controls.Add($pnlMainWrap)
    $form.Controls.Add($pnlFooter)
    $form.Controls.Add($pnlWpp)
    $form.Controls.Add($pnlHeader)
    $pnlMainWrap.BringToFront()

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

                Set-UiBusyState -IsBusy $false -StatusText $doneText -IsError:(-not $okFlag)
                Add-UiLog -Message "=== $doneText ===" -Level $logLvl

                if ($cbRef) {
                    try { & $cbRef $okFlag $outData $errMsg $cbStateRef }
                    catch { Add-UiLog -Message "완료 후 UI 처리 오류: $($_.Exception.Message)" -Level 'ERROR' }
                }
                Sync-AllUiButtonStates
            }
        }
        catch {
            if ($script:AsyncState.PollTimer) { try { $script:AsyncState.PollTimer.Stop() } catch {} }
            Add-UiLog -Message "타이머 처리 오류: $($_.Exception.Message)" -Level 'ERROR'
            try { Stop-ActiveAsyncRunspace -ForceAbort } catch {}
            try { Set-UiBusyState -IsBusy $false -StatusText '타이머 오류로 작업이 중단되었습니다' } catch {}
            try { Sync-AllUiButtonStates } catch {}
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
        $wasBusy    = [bool]$script:AsyncState.IsBusy
        $pausedPoll = $false
        if ($wasBusy) {
            # 종료 확인 팝업 표시 중 PollTimer 재진입(완료 콜백 중복/상태 변이) 차단
            if ($script:AsyncState.PollTimer -and $script:AsyncState.PollTimer.Enabled) {
                try { $script:AsyncState.PollTimer.Stop(); $pausedPoll = $true } catch {}
            }
            $ans = Show-AsanMessageBox -Text "현재 '$($script:AsyncState.TaskName)' 작업이 진행 중입니다.`r`n강제 종료하면 프린터 설정이 불완전할 수 있습니다. 정말 종료하시겠습니까?" -Caption '작업 중 종료 확인' -Buttons 'YesNo' -Icon 'Warning'
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                $e.Cancel = $true
                if ($pausedPoll -and $script:AsyncState.PollTimer -and $script:AsyncState.AsyncResult) {
                    try { $script:AsyncState.PollTimer.Start() } catch {}
                }
                return
            }
        }
        # Disconnect-AllHostSessions 이전에 탭 4 비동기 미리보기 Runspace/타이머 선중단·해제
        try { Stop-Tab4PreviewAsync } catch {}
        if ($script:Tab4Ui) {
            if ($script:Tab4Ui.PreviewDebounceTimer) {
                try { $script:Tab4Ui.PreviewDebounceTimer.Stop(); $script:Tab4Ui.PreviewDebounceTimer.Dispose() } catch {}
                $script:Tab4Ui.PreviewDebounceTimer = $null
            }
            if ($script:Tab4Ui.PreviewTimer) {
                try { $script:Tab4Ui.PreviewTimer.Stop(); $script:Tab4Ui.PreviewTimer.Dispose() } catch {}
                $script:Tab4Ui.PreviewTimer = $null
            }
            try { Clear-RetiredTab4Previews } catch {}
        }
        Stop-ActiveAsyncRunspace -ForceAbort:$wasBusy
        if ($script:AsyncState.PollTimer) {
            try { $script:AsyncState.PollTimer.Dispose() } catch {}
            $script:AsyncState.PollTimer = $null
        }
        if ($script:Ui.SidFlashTimer) {
            try { $script:Ui.SidFlashTimer.Stop(); $script:Ui.SidFlashTimer.Dispose() } catch {}
            $script:Ui.SidFlashTimer = $null
        }
        # [보안] 종료 시 사내 백업 서버 SMB 세션을 즉시 끊어 교체 PC에 관리자 접근이 남지 않도록 차단
        try { Disconnect-AllHostSessions -HostName $global:AsanCtx.ServerIP } catch {}
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
    $script:Ui.PicBadge        = $picBadge
    $script:Ui.BadgeImage      = $badgeImg
    $script:Ui.AppIcon         = $appIcon
    $script:Ui.ToolTip         = $tip
    $script:Ui.LblTitle        = $lblTitle
    $script:Ui.LblSubtitle     = $lblSubtitle
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
# [탭 1] 기존 PC 백업 (Windows 10 / 11 공용 · 서버 / 오프라인 ZIP) UI 및 이벤트 로직
# ============================================================================
$script:Tab1Ui = @{
    PnlBanner        = $null
    PnlBannerAccent  = $null
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
            $script:Tab1Ui.PnlBanner.BackColor       = $script:Theme.AsanMint
            $script:Tab1Ui.PnlBannerAccent.BackColor = $script:Theme.AsanGreen
            $script:Tab1Ui.LblBanner.ForeColor       = $script:Theme.AsanDeep
            $script:Tab1Ui.LblBanner.Text            = '아래 프린터 목록을 확인한 뒤 서버에 백업하기를 눌러 주세요.'
        } else {
            $script:Tab1Ui.PnlBanner.BackColor       = $script:Theme.AsanOrangeTint
            $script:Tab1Ui.PnlBannerAccent.BackColor = $script:Theme.AsanOrange
            $script:Tab1Ui.LblBanner.ForeColor       = $script:Theme.AsanOrangeText
            if ($script:AppState.IsWin11) {
                $script:Tab1Ui.LblBanner.Text        = "사내망 또는 백업 서버에 연결되지 않았습니다. 백업은 ZIP 파일로 저장, 새 PC 복원은 '2. 새 PC 복원' 탭을 이용해 주세요."
            } else {
                $script:Tab1Ui.LblBanner.Text        = '사내망 또는 백업 서버에 연결되지 않았습니다. 아래 ZIP 파일로 저장을 눌러 백업해 주세요.'
            }
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
            if ($p.IsDefault) { $defMark = '기본' }

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
            $row.Cells[4].ToolTipText = $portDisplay
            $row.Cells[5].ToolTipText = [string]$p.DriverName
            $row.Cells[6].ToolTipText = [string]$p.Reason

            if ($p.IsDefault) {
                $row.Cells[0].Style.ForeColor = $script:Theme.AsanGreen
                $row.Cells[0].Style.Font      = $script:FontBold
            }

            if ($p.StatusCode -eq 'ExcludedVirtual' -or $p.StatusCode -eq 'ExcludedNoDriver') {
                $row.DefaultCellStyle.BackColor = $script:Theme.DisabledBg
                $row.DefaultCellStyle.ForeColor = $script:Theme.InkMuted
            } else {
                $stCell = $row.Cells[1]
                $stCell.Style.Font = $script:FontBold
                if ($p.SpecialType -ne 'STANDARD') {
                    $stCell.Style.BackColor = $script:Theme.SpecialTint
                    $stCell.Style.ForeColor = $script:Theme.SpecialPurple
                } elseif ($p.StatusCode -eq 'WsdConvert') {
                    $stCell.Style.BackColor = [System.Drawing.Color]::FromArgb(226, 243, 249)
                    $stCell.Style.ForeColor = $script:Theme.AsanLight
                } elseif ($p.StatusCode -eq 'AuthOrSidConflict') {
                    $stCell.Style.BackColor = $script:Theme.DangerRedTint
                    $stCell.Style.ForeColor = $script:Theme.DangerRedDeep
                } elseif ($p.StatusCode -in @('SuspectedInactive', 'Ambiguous', 'OfflineUnverified')) {
                    $stCell.Style.BackColor = $script:Theme.AsanOrangeTint
                    $stCell.Style.ForeColor = $script:Theme.AsanOrangeText
                } else {
                    $stCell.Style.BackColor = $script:Theme.AsanMint
                    $stCell.Style.ForeColor = $script:Theme.AsanDeep
                }
            }
        }

        if ($script:Tab1Ui.HasScannedOnce) {
            $validTotal = $cntHealthy + $cntWsd + $cntSpecial + $cntWarn
            if ($script:Tab1Ui.LastScanOffline) {
                $script:Tab1Ui.PnlBanner.BackColor       = $script:Theme.AsanOrangeTint
                $script:Tab1Ui.PnlBannerAccent.BackColor = $script:Theme.AsanOrange
                $script:Tab1Ui.LblBanner.ForeColor       = $script:Theme.AsanOrangeText
                if ($script:AppState.IsWin11) {
                    $script:Tab1Ui.LblBanner.Text        = "사내망 미연결 상태로 프린터 ${validTotal}대를 확인했습니다. 백업은 ZIP 파일로 저장, 새 PC 복원은 '2. 새 PC 복원' 탭을 이용해 주세요."
                } else {
                    $script:Tab1Ui.LblBanner.Text        = "사내망 미연결 상태로 백업 대상 ${validTotal}대를 확인했습니다. 아래 ZIP 파일로 저장을 눌러 주세요."
                }
            } elseif ($cntWarn -gt 0) {
                $script:Tab1Ui.PnlBanner.BackColor       = $script:Theme.AsanOrangeTint
                $script:Tab1Ui.PnlBannerAccent.BackColor = $script:Theme.AsanOrange
                $script:Tab1Ui.LblBanner.ForeColor       = $script:Theme.AsanOrangeText
                $script:Tab1Ui.LblBanner.Text            = "프린터 ${validTotal}대 중 확인이 필요한 항목이 ${cntWarn}대 있습니다. 상태를 확인한 뒤 백업을 진행해 주세요."
            } else {
                $script:Tab1Ui.PnlBanner.BackColor       = $script:Theme.AsanMint
                $script:Tab1Ui.PnlBannerAccent.BackColor = $script:Theme.AsanGreen
                $script:Tab1Ui.LblBanner.ForeColor       = $script:Theme.AsanDeep
                $script:Tab1Ui.LblBanner.Text            = "백업 대상 프린터 ${validTotal}대가 모두 정상입니다. 아래에서 서버에 백업하기를 눌러 주세요."
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
        $script:Tab1Ui.LblScanSummary.Text    = '스캐너 드라이버 확인 대기 중'
        $script:Tab1Ui.BtnUnclassScan.Visible = $false
        $script:Tab1Ui.LblTwainWarn.Visible   = $false
        return
    }

    $autoCnt    = (@($inv.AutoScanners)).Count
    $unclassAll = @($inv.UnclassifiedScanners)
    $unclassSel = (@($unclassAll | Where-Object { $_.Selected })).Count
    $twains     = @($inv.TwainFolders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    if ($unclassAll.Count -gt 0) {
        $script:Tab1Ui.LblScanSummary.Text    = "스캐너 드라이버  자동 백업 ${autoCnt}개 · 추가 선택 가능 $($unclassAll.Count)개"
        $script:Tab1Ui.BtnUnclassScan.Text    = "미분류 스캐너 선택 ($unclassSel/$($unclassAll.Count))"
        $script:Tab1Ui.BtnUnclassScan.Visible = $true
    } else {
        $script:Tab1Ui.LblScanSummary.Text    = "스캐너 드라이버  자동 백업 대상 ${autoCnt}개"
        $script:Tab1Ui.BtnUnclassScan.Visible = $false
    }

    if ($twains.Count -gt 0) {
        $script:Tab1Ui.LblTwainWarn.Text    = "TWAIN 스캐너 감지 ($($twains -join ', ')) · 복원 후 스캔 IP를 확인해 주세요"
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

    $btnCancel = New-StyledButton -Text '취소' -Width 96 -Height 32 -Variant 'Secondary'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Margin       = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnOk = New-StyledButton -Text '선택 적용' -Width 110 -Height 32 -Variant 'Primary'
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
            Invoke-ErrorWithAutoReportPrompt -Caption '진단 오류' -Message "프린터 진단 중 오류가 발생했습니다:`r`n$err" -Category '백업 오류' -ErrorDetail ([string]$err)
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
            [void](Show-AsanMessageBox -Text "백업 서버에 연결되어 있지 않습니다.`r`n네트워크를 설정한 뒤 새로고침(F5)하거나 [오프라인 ZIP 백업]을 사용하세요." -Caption '서버 미연결' -Buttons 'OK' -Icon 'Warning')
            return
        }

        if (-not $SkipOverwritePrompt) {
            # UI 스레드 SMB I/O 차단: 동기화된 $script:AppState.ServerBackups 캐시 기준으로 기존 백업 확인
            $folderId         = Get-BackupFolderId -PcIp $pcIp
            $existingEntry    = @($script:AppState.ServerBackups | Where-Object { $_.Name -ieq $folderId }) | Select-Object -First 1
            $existingTimeText = $null
            if ($existingEntry) {
                $existingTimeText = $existingEntry.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            }

            if ($existingTimeText) {
                $ans = Show-AsanMessageBox -Text "서버에 동일 PC 백업('$folderId')이 이미 존재합니다.`r`n- 기존 백업 일시: $existingTimeText`r`n`r`n기존 백업을 덮어쓰시겠습니까?" -Caption '기존 백업 덮어쓰기 확인' -Buttons 'YesNo' -Icon 'Question'
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
            Invoke-ErrorWithAutoReportPrompt -Caption '백업 실패' -Message "백업 작업 중 오류가 발생했습니다:`r`n$err" -Category '백업 오류' -ErrorDetail ([string]$err)
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
            $usbLine = 'USB 동시 복사: 연결된 USB가 없어 로컬 폴더에만 저장되었습니다.'
            if (-not [string]::IsNullOrWhiteSpace([string]$res.UsbCopyPath)) {
                $usbLine = "USB 동시 복사: $($res.UsbCopyPath)"
            }
            $msg = @(
                "오프라인 ZIP 백업을 완료했습니다.",
                "",
                "저장 경로: $($res.SavedPath)",
                "$usbLine",
                "백업 내역: 프린터 $($res.PrinterCount)대, 스캐너 드라이버 $($res.ScannerCount)개",
                "",
                "새 PC 복원 시 다시 안내되는 참고 사항",
                $noteSummary,
                "",
                "저장 폴더를 열어 확인하시겠습니까?"
            ) -join "`r`n"

            $openAns = Show-AsanMessageBox -Text $msg -Caption '오프라인 ZIP 백업 완료' -Buttons 'YesNo' -Icon 'Information'
            if ($openAns -eq [System.Windows.Forms.DialogResult]::Yes) {
                Open-FolderInExplorerSafe -FolderPath $global:AsanCtx.OfflineLocalRoot
            }
        } else {
            $msg = @(
                "사내 백업 서버에 저장을 완료했습니다.",
                "",
                "저장 경로: $($res.SavedPath)",
                "백업 내역: 프린터 $($res.PrinterCount)대, 스캐너 드라이버 $($res.ScannerCount)개",
                "",
                "새 PC 복원 시 다시 안내되는 참고 사항",
                $noteSummary
            ) -join "`r`n"
            [void](Show-AsanMessageBox -Text $msg -Caption '서버 백업 완료' -Buttons 'OK' -Icon 'Information')
        }
    }

    $tLabel = '사내 서버 백업'
    if ($OfflineZipMode) { $tLabel = '오프라인 ZIP 백업' }
    Invoke-AsanAsyncTask -TaskName $tLabel -WorkScript $work -Params $taskParams -OnComplete $done
}

# ============================================================================
# [C2 + C4 Fix] 탭 1 컨트롤 배치 초기화 — 고시인성 카드 + 직관적 워크플로우
# ============================================================================
function Initialize-Tab1BackupUi {
    $parent = $script:Ui.TabBackup
    $tip    = $script:Ui.ToolTip

    # [1] 상단 안내 배너 (좌측 4px 상태 컬러 바 + 선명한 테두리)
    $pnlBanner = New-Object System.Windows.Forms.Panel
    $pnlBanner.Dock        = [System.Windows.Forms.DockStyle]::Top
    $pnlBanner.Height      = 38
    $pnlBanner.BackColor   = $script:Theme.AsanMint
    $pnlBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $pnlBannerAccent = New-Object System.Windows.Forms.Panel
    $pnlBannerAccent.Dock      = [System.Windows.Forms.DockStyle]::Left
    $pnlBannerAccent.Width     = 4
    $pnlBannerAccent.BackColor = $script:Theme.AsanGreen

    $lblBanner = New-Object System.Windows.Forms.Label
    $lblBanner.Text      = '아래 프린터 목록을 확인한 뒤 서버에 백업하기를 눌러 주세요.'
    $lblBanner.ForeColor = $script:Theme.AsanDeep
    $lblBanner.Font      = $script:FontBold
    $lblBanner.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblBanner.Padding   = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
    $lblBanner.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $pnlBanner.Controls.Add($lblBanner)
    $pnlBanner.Controls.Add($pnlBannerAccent)

    # [2] 툴바 (좌: 다시 스캔 + 가상 프린터 토글 / 우: 실제 컬러 상태 범례)
    $pnlToolbar = New-Object System.Windows.Forms.Panel
    $pnlToolbar.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlToolbar.Height    = 40
    $pnlToolbar.BackColor = [System.Drawing.Color]::Transparent

    $flpToolLeft = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpToolLeft.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $flpToolLeft.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpToolLeft.WrapContents  = $false
    $flpToolLeft.BackColor     = [System.Drawing.Color]::Transparent
    $flpToolLeft.Padding       = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $btnScan = New-StyledButton -Text '다시 스캔' -Width 100 -Height 28 -Variant 'Secondary' -RegisterBusy
    $btnScan.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $btnScan.Add_Click({ Invoke-Tab1ScanAsync })

    $chkVirt = New-Object System.Windows.Forms.CheckBox
    $chkVirt.Text      = '가상 프린터도 함께 보기'
    $chkVirt.AutoSize  = $true
    $chkVirt.Font      = $script:FontBase
    $chkVirt.ForeColor = $script:Theme.InkPrimary
    $chkVirt.Margin    = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)
    $chkVirt.Add_CheckedChanged({ Render-Tab1PrinterGrid })
    if ($tip) { $tip.SetToolTip($chkVirt, 'PDF, OneNote, Fax 등 기본 가상 프린터를 목록에 함께 표시합니다') }
    $flpToolLeft.Controls.AddRange(@($btnScan, $chkVirt))

    $flpToolRight = New-RightFlowStrip -TopPadding 11 -RightPadding 2
    # RightToLeft이므로 역순 추가 -> 화면 좌->우: 정상 · WSD 전환 · 특수 장비 · 확인 필요 · 인증 오류
    Add-ColorLegendChip -TargetFlow $flpToolRight -LabelText '인증 오류' -DotColor $script:Theme.DangerRed
    Add-ColorLegendChip -TargetFlow $flpToolRight -LabelText '확인 필요' -DotColor $script:Theme.AsanOrange
    Add-ColorLegendChip -TargetFlow $flpToolRight -LabelText '특수 장비' -DotColor $script:Theme.SpecialPurple
    Add-ColorLegendChip -TargetFlow $flpToolRight -LabelText 'WSD 전환'  -DotColor $script:Theme.AsanLight
    Add-ColorLegendChip -TargetFlow $flpToolRight -LabelText '정상'      -DotColor $script:Theme.AsanGreen

    $pnlToolbar.Controls.Add($flpToolLeft)
    $pnlToolbar.Controls.Add($flpToolRight)

    # [3] 중앙 프린터 진단 그리드 (마지막 컬럼 Fill로 우측 여백 제거)
    $dgv = New-StyledGrid
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    foreach ($colDef in @(
        @{ Name = 'Default';  Header = '기본';         Width = 50;  Fill = $false },
        @{ Name = 'Status';   Header = '상태';         Width = 108; Fill = $false },
        @{ Name = 'Category'; Header = '구분';         Width = 112; Fill = $false },
        @{ Name = 'Printer';  Header = '프린터 이름';   Width = 185; Fill = $false },
        @{ Name = 'Port';     Header = '포트 / 전환 IP'; Width = 160; Fill = $false },
        @{ Name = 'Driver';   Header = '드라이버';     Width = 190; Fill = $false },
        @{ Name = 'Reason';   Header = '상세 내용';    Width = 180; Fill = $true }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $colDef.Name
        $c.HeaderText = $colDef.Header
        $c.Width      = $colDef.Width
        if ($colDef.Fill) {
            $c.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
            $c.MinimumWidth = 160
        }
        [void]$dgv.Columns.Add($c)
    }

    # [4] 하단 스캐너 요약 카드 스트립 (FlowLayoutPanel로 DPI 배율 겹침 차단)
    $pnlScannerWrap = New-Object System.Windows.Forms.Panel
    $pnlScannerWrap.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlScannerWrap.Height    = 44
    $pnlScannerWrap.Padding   = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $pnlScannerWrap.BackColor = [System.Drawing.Color]::Transparent

    $pnlScanner = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlScanner.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $pnlScanner.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlScanner.WrapContents  = $false
    $pnlScanner.BackColor     = $script:Theme.CardBg
    $pnlScanner.BorderStyle   = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pnlScanner.Padding       = New-Object System.Windows.Forms.Padding(10, 5, 10, 4)

    $lblScanSum = New-Object System.Windows.Forms.Label
    $lblScanSum.Text      = '스캐너 드라이버 확인 대기 중'
    $lblScanSum.AutoSize  = $true
    $lblScanSum.Font      = $script:FontBold
    $lblScanSum.ForeColor = $script:Theme.InkPrimary
    $lblScanSum.Margin    = New-Object System.Windows.Forms.Padding(0, 5, 14, 0)

    $btnUnclass = New-StyledButton -Text '미분류 스캐너 선택 (0/0)' -Width 188 -Height 26 -Variant 'SoftOrange' -RegisterBusy
    $btnUnclass.Font    = $script:FontSmallB
    $btnUnclass.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    $btnUnclass.Visible = $false
    $btnUnclass.Add_Click({ Show-UnclassifiedScannerDialog })

    $lblTwain = New-Object System.Windows.Forms.Label
    $lblTwain.Text      = ''
    $lblTwain.AutoSize  = $true
    $lblTwain.Font      = $script:FontSmallB
    $lblTwain.ForeColor = $script:Theme.AsanOrangeText
    $lblTwain.Margin    = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $lblTwain.Visible   = $false

    $pnlScanner.Controls.AddRange(@($lblScanSum, $btnUnclass, $lblTwain))
    $pnlScannerWrap.Controls.Add($pnlScanner)

    # [5] 최하단 백업 실행 액션 바 (FlowLayoutPanel + RightFlowStrip — DPI 안전)
    $pnlAction = New-Object System.Windows.Forms.Panel
    $pnlAction.Dock      = [System.Windows.Forms.DockStyle]::Bottom
    $pnlAction.Height    = 50
    $pnlAction.BackColor = [System.Drawing.Color]::Transparent

    $flpActLeft = New-Object System.Windows.Forms.FlowLayoutPanel
    $flpActLeft.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $flpActLeft.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flpActLeft.WrapContents  = $false
    $flpActLeft.BackColor     = [System.Drawing.Color]::Transparent
    $flpActLeft.Padding       = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $btnServer = New-StyledButton -Text '서버에 백업하기' -Width 168 -Height 36 -Variant 'Primary' -RegisterBusy
    $btnServer.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnServer.Add_Click({ Start-Tab1BackupExecution })

    $btnOffline = New-StyledButton -Text 'ZIP 파일로 저장' -Width 150 -Height 36 -Variant 'SoftTeal' -RegisterBusy
    $btnOffline.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $btnOffline.Add_Click({ Start-Tab1BackupExecution -OfflineZipMode })

    $lblOffHint = New-Object System.Windows.Forms.Label
    $lblOffHint.Text      = 'ZIP 파일은 C:\_AsanPrtOffline과 연결된 USB에 함께 저장됩니다.'
    $lblOffHint.Font      = $script:FontSmall
    $lblOffHint.ForeColor = $script:Theme.InkSecondary
    $lblOffHint.AutoSize  = $true
    $lblOffHint.Margin    = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)

    $flpActLeft.Controls.AddRange(@($btnServer, $btnOffline, $lblOffHint))

    $flpActRight = New-RightFlowStrip -TopPadding 10 -RightPadding 0
    $btnOpenOff = New-StyledButton -Text '저장 폴더 열기' -Width 126 -Height 36 -Variant 'Secondary'
    $btnOpenOff.Add_Click({
        $dir = $global:AsanCtx.OfflineLocalRoot
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            Open-FolderInExplorerSafe -FolderPath $dir
        } catch {
            [void](Show-AsanMessageBox -Text "오프라인 백업 폴더를 열 수 없습니다:`r`n$($_.Exception.Message)" -Caption '폴더 열기 오류' -Buttons 'OK' -Icon 'Warning')
        }
    })
    if ($tip) { $tip.SetToolTip($btnOpenOff, '로컬 ZIP 저장 폴더(C:\_AsanPrtOffline)를 엽니다') }
    $flpActRight.Controls.Add($btnOpenOff)

    $pnlAction.Controls.Add($flpActLeft)
    $pnlAction.Controls.Add($flpActRight)

    # Dock Z-Order: Fill(0) -> Bottom(Inner) -> Bottom(Outer) -> Top(Inner) -> Top(Outer)
    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlScannerWrap)
    $parent.Controls.Add($pnlAction)
    $parent.Controls.Add($pnlToolbar)
    $parent.Controls.Add($pnlBanner)
    $dgv.BringToFront()

    $script:Tab1Ui.PnlBanner        = $pnlBanner
    $script:Tab1Ui.PnlBannerAccent  = $pnlBannerAccent
    $script:Tab1Ui.LblBanner        = $lblBanner
    $script:Tab1Ui.BtnScan          = $btnScan
    $script:Tab1Ui.ChkShowVirtual   = $chkVirt
    $script:Tab1Ui.LblLegend        = $flpToolRight
    $script:Tab1Ui.DgvPrinters      = $dgv
    $script:Tab1Ui.LblScanSummary   = $lblScanSum
    $script:Tab1Ui.BtnUnclassScan   = $btnUnclass
    $script:Tab1Ui.LblTwainWarn     = $lblTwain
    $script:Tab1Ui.BtnBackupServer  = $btnServer
    $script:Tab1Ui.BtnBackupOffline = $btnOffline
    $script:Tab1Ui.BtnOpenOffline   = $btnOpenOff

    $script:Ui.OnEnvRefreshed.Add({ Update-Tab1NetworkState })
}
