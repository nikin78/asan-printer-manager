# PowerShell 5.1 WinForms 실전 구현 패턴 (Asan Desktop UI Reference)

이 문서는 `asan-desktop-ui` 스킬의 보조 레퍼런스입니다. PowerShell 5.1 + `.NET Framework 4.x` WinForms 기반 단일 `.bat`/`.ps1` 도구를 제작할 때 아래 검증된 패턴을 그대로 재사용하세요.

> **PS 5.1 엄격 문법 주의:** `? :`, `??`, `&&`, `||`, 해시테이블 리터럴(`@{ ... }`) 내부 `if`, WinForms 이벤트 핸들러 내 로컬 변수 클로저 캡처(`$sender`, `$script:Ui`, `DialogResult`만 사용), C# 6+ 문법을 절대 사용하지 마세요.

---

## 1. 테마 토큰 & 폰트 초기화

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
```

---

## 2. 비활성 점선 버튼 + 부모 라우팅 사유 툴팁 패턴

WinForms의 2가지 고질적 한계를 한 번에 해결하는 핵심 패턴입니다.
1. `FlatStyle=Flat` 비활성 버튼이 `ForeColor`를 무시하고 `SystemColors.GrayText`로 그려지는 문제 → `Add_Paint`에서 점선 테두리·연한 무채색·비굵은 글씨 직접 렌더.
2. `Enabled=$false` 버튼에서 `ToolTip`이 발동하지 않는 문제 → `Register-DisabledTooltipTree`로 부모 컨테이너의 `MouseMove`/`GetChildAtPoint`에 툴팁 라우팅.

```powershell
function Apply-ButtonVisualState {
    param([System.Windows.Forms.Button]$Button)
    if (-not $Button -or $Button.IsDisposed) { return }
    if (-not $script:Ui.ButtonStyles.ContainsKey($Button)) { return }
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
    if ($Button.Enabled -ne $Enabled) { $Button.Enabled = $Enabled }
}

function Register-DisabledTooltipTree {
    param([System.Windows.Forms.Control]$Root)
    if (-not $Root -or $Root.IsDisposed) { return }
    $hasChildBtn = $false
    foreach ($ch in $Root.Controls) {
        if ($ch -is [System.Windows.Forms.Button]) { $hasChildBtn = $true }
        if ($ch.Controls.Count -gt 0) { Register-DisabledTooltipTree -Root $ch }
    }
    if ($hasChildBtn) {
        $Root.Add_MouseMove({
            param($sender, $e)
            if (-not $script:Ui.ToolTip) { return }
            $hit = $sender.GetChildAtPoint($e.Location)
            if ($hit -and ($hit -is [System.Windows.Forms.Button]) -and (-not $hit.Enabled)) {
                $reason = ''
                if ($script:Ui.DisabledReasons.ContainsKey($hit)) { $reason = [string]$script:Ui.DisabledReasons[$hit] }
                elseif ($script:AsyncState.IsBusy) { $reason = '현재 다른 작업이 진행 중입니다. 완료 후 다시 시도해 주세요.' }
                if (-not [string]::IsNullOrWhiteSpace($reason)) {
                    if ($script:Ui.LastDisabledBtn -ne $hit) {
                        if ($script:Ui.LastDisabledHost) { try { $script:Ui.ToolTip.Hide($script:Ui.LastDisabledHost) } catch {} }
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
```

> `New-StyledButton` 생성 직후 `$btn.Add_Paint`에서 `if ($sender.Enabled) { return }` 가드를 두고 `DisabledBg` 채움 + `DashStyle::Dash` 1px 사각형 + `TextRenderer::DrawText`(`DisabledFg`, 비굵은 폰트)를 그리면 완료됩니다. 참고 원본: `src/02_gui_shell_tab1.ps1`.

---

## 3. 여백 안전 멀티라인 텍스트박스 · DPI 안전 레이아웃 · 고대비 그리드 패턴

### 3-1. `New-PaddedTextBoxPanel` (테두리-텍스트 붙음 방지 필수 래퍼)

WinForms 기본 `TextBox(BorderStyle=FixedSingle)`은 글자가 테두리에 1px로 붙어 답답하므로, 모든 테두리형 멀티라인 입력/표시 창(안내 배너, 체크리스트, 리포트 미리보기, 로그, 메모)은 아래 래퍼로 감쌉니다. 배경색을 동적으로 바꿀 때는 `$tb.BackColor`와 래퍼 `$wrap.BackColor`를 함께 변경하세요.

```powershell
function New-PaddedTextBoxPanel {
    param(
        [System.Drawing.Color]$BackColor = ([System.Drawing.Color]::White),
        [System.Drawing.Color]$ForeColor = ([System.Drawing.Color]::FromArgb(20, 34, 35)),
        [System.Drawing.Font]$Font = $null,
        [int]$PadX = 10,
        [int]$PadY = 6,
        [bool]$ReadOnly = $true,
        [bool]$AcceptsReturn = $false,
        [string]$InitialText = ''
    )
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $wrap.BackColor   = $BackColor
    $wrap.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $wrap.Padding     = New-Object System.Windows.Forms.Padding($PadX, $PadY, ([math]::Max(4, $PadX - 2)), $PadY)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $tb.Multiline     = $true
    $tb.ReadOnly      = $ReadOnly
    $tb.AcceptsReturn = $AcceptsReturn
    $tb.ScrollBars    = [System.Windows.Forms.ScrollBars]::Vertical
    $tb.BorderStyle   = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor     = $BackColor
    $tb.ForeColor     = $ForeColor
    if ($Font) { $tb.Font = $Font } else { $tb.Font = $script:FontSmall }
    if (-not [string]::IsNullOrEmpty($InitialText)) { $tb.Text = $InitialText }

    $wrap.Controls.Add($tb)
    return [pscustomobject]@{ Panel = $wrap; TextBox = $tb }
}
```

### 3-2. 레이아웃 · 그리드 · 탭 표준

* **우측 버튼 스트립 (`New-RightFlowStrip`):** `Dock = Right`, `FlowDirection = RightToLeft`, `WrapContents = $false`, `AutoSize = $true` (`AutoSizeMode = GrowAndShrink`). 주의: `RightToLeft`이므로 **먼저 추가한 컨트롤이 가장 오른쪽**에 배치됩니다.
* **그리드 (`New-StyledGrid`):**
  * `EnableHeadersVisualStyles = $false`, `ColumnHeadersHeight = 34`, `RowTemplate.Height = 32`, `ShowCellToolTips = $true`, `DoubleBuffered = $true`(리플렉션 설정).
  * `ColumnHeadersDefaultCellStyle.WrapMode = False`(2글자 헤더 세로 줄바꿈 차단), `ColumnHeadersDefaultCellStyle.Padding = (8, 2, 8, 2)`, `DefaultCellStyle.Padding = (8, 2, 8, 2)`.
  * `ColumnHeadersDefaultCellStyle.BackColor = $script:Theme.GridHeadBg` (`#0B4F51`), `ForeColor = White`.
  * 2글자 고정 열(`복원`/`기본`) 최소 폭 `54px`, 마지막 설명/경로 열은 `AutoSizeMode = Fill`, `MinimumWidth = 150`, 전체 폭+Fill 최소폭 합 `<= 930px`.
* **단계형 탭 (`OwnerDrawFixed`):**
  * `ItemSize = (0, 32)`, `Padding = (18, 6)`, 활성 탭은 흰 배경 + 상단 `4px` `#006769` 바 + `#004D4F` Bold, 비활성 탭은 `#D9E7E6` + `#2F4244` Regular.
* **리소스 해제 (`finally`):** GDI+ `Bitmap`(헤더 배지), `Icon`, `ToolTip`, 모든 `System.Windows.Forms.Timer`는 `ShowDialog()` 종료 `finally` 블록에서 반드시 `.Dispose()` 합니다.

---

## 4. 순수 GDI+ 아이콘 생성 패턴 (저작권·HICON 누수 0)

외부 로고 이미지 대신 64×64 `Bitmap`에 GDI+ `AntiAlias` 도형(둥근 사각 배경 + 흰색 아이콘 실루엣 + 우측 하단 `#F68B1F` 체크/상태 배지)을 그린 뒤 **22바이트 PNG-in-ICO 헤더**를 붙여 `System.Drawing.Icon`으로 변환합니다. `GetHicon()`을 쓰지 않으므로 비관리 `HICON` 핸들 누수가 발생하지 않습니다. 참고 원본: `New-AsanPrinterSymbolBitmap` / `New-AsanPrinterAppIcon` (`src/02_gui_shell_tab1.ps1`).

---

## 5. 온·오프라인 자동 오류 리포트 안내 패턴

```powershell
function Invoke-ErrorWithAutoReportPrompt {
    param(
        [string]$Caption = '작업 오류',
        [string]$Message = '작업 중 예기치 않은 오류가 발생했습니다.',
        [string]$Category = '일반 오류',
        [string]$ErrorDetail = '',
        [string]$TargetItem = ''
    )
    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.ReportRoot))
    if ($isOnline) {
        $tail = "오류 진단 리포트를 자동으로 구성해 사내 리포트함으로 보낼까요?`r`nPC 환경과 작업 로그가 자동 첨부되며 비밀번호는 안전하게 가려집니다."
    } else {
        $tail = "현재 사내 서버에 연결되어 있지 않습니다.`r`n오류 진단 리포트를 이 PC의 로컬 폴더에 저장할까요?`r`n비밀번호는 안전하게 가려지며, 나중에 파일만 담당자에게 전달해 주시면 됩니다."
    }
    $ans = Show-AsanMessageBox -Text "$Message`r`n`r`n$tail" -Caption $Caption -Buttons 'YesNo' -Icon 'Error'
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
        Show-BugReportDialog -DefaultCategory $Category -DefaultTarget $TargetItem -ErrorSummary $ErrorDetail
    }
}
```

---

## 6. 자동 레이아웃 + 픽셀 시각 감사 스크립트 패턴

UI 수정 후 `-STA` PowerShell 5.1 프로세스에서 폼을 띄워 아래 2가지를 자동 확인합니다.
1. **레이아웃 수치 감사:** `1040×720` 및 `960×640`(+ 경고 배너 표시 상태)에서 재귀적으로 모든 보이는 `Button`의 `Right <= Parent.ClientSize.Width + 3`, `Bottom <= Parent.ClientSize.Height + 3`, 버튼 간 `Rectangle::Intersect` 겹침 `0건`, 보이는 `DataGridView.Height >= 80`, 멀티라인 `TextBox.Height >= 40` 검증.
2. **시각 감사:** `$form.DrawToBitmap($bmp, ...)`로 사내망 연결/미연결·비활성 버튼 포함 화면·최소 크기(`960×640`) PNG를 scratch 폴더에 저장 후 에이전트가 직접 이미지 파일을 열어 대비·정렬·줄바꿈·잘림을 육안 검수합니다.
