# ============================================================================
# [Module 04] 탭 3 (검증/테스트 인쇄) + 탭 4 (서버 관리) + 앱 메인 진입점 최종본
# - Module 03(탭 2 복원 최종본) 하단에 무손실 결합됨
# - 3-5B 패치 반영: C2, C3, C4, H2(코어 이관 반영), H3
# ============================================================================
$script:Tab3Ui = @{
    BtnRefresh      = $null
    BtnFixPolicy    = $null
    BtnResetSpooler = $null
    ChkShowVirtual  = $null
    LblSummary      = $null
    DgvVerify       = $null
    BtnBulkTest     = $null
    BtnSingleTest   = $null
    BtnProps        = $null
    BtnPrefs        = $null
    BtnSetDefault   = $null
    InstalledList   = @()
    HasLoadedOnce   = $false
    NeedsRefresh    = $false
}

$script:Tab4Ui = @{
    TxtSearch            = $null
    BtnRefreshSrv        = $null
    BtnCleanOld5         = $null
    LblSrvSummary        = $null
    DgvServer            = $null
    TxtPreview           = $null
    BtnLoadToTab2        = $null
    BtnOpenFolder        = $null
    BtnDeleteOne         = $null
    PreviewCache         = @{}
    PreviewGen           = 0
    PreviewReqGen        = 0
    PreviewPs            = $null
    PreviewRs            = $null
    PreviewAsync         = $null
    PreviewTimer         = $null
    PreviewDebounceTimer = $null
    PreviewCacheKey      = $null
    SuppressPreviewEvent = $false
    RetiredPreviews      = [System.Collections.Generic.List[object]]::new()
}

# ============================================================================
# [탭 3 UI] 설치 프린터 검증 그리드 렌더링 및 액션 함수
# ============================================================================
function Render-Tab3VerifyGrid {
    $dgv = $script:Tab3Ui.DgvVerify
    if (-not $dgv -or $dgv.IsDisposed) { return }

    $showVirt = [bool]$script:Tab3Ui.ChkShowVirtual.Checked
    $items    = @($script:Tab3Ui.InstalledList)

    $cntNormal  = 0
    $cntSpecial = 0
    $cntPolicy  = 0

    $dgv.SuspendLayout()
    try {
        $dgv.Rows.Clear()
        foreach ($p in $items) {
            if ($p.IsVirtual) {
                if (-not $showVirt) { continue }
            } else {
                if ($p.IsSpecial) { $cntSpecial++ } else { $cntNormal++ }
                if ($p.SnmpWarn -or $p.BidiWarn) { $cntPolicy++ }
            }

            $defMark = ''
            if ($p.IsDefault) { $defMark = '★' }

            $rIdx = $dgv.Rows.Add(
                $defMark,
                [string]$p.Category,
                [string]$p.PrinterName,
                [string]$p.PortName,
                [string]$p.SnmpState,
                [string]$p.BidiState,
                [string]$p.DriverName,
                [string]$p.StatusText
            )
            $row     = $dgv.Rows[$rIdx]
            $row.Tag = $p

            if ($p.IsVirtual) {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
            } elseif ($p.IsSpecial) {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(243, 232, 255)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(88, 28, 135)
            } else {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
            }

            if ($p.SnmpWarn) {
                $row.Cells[4].Style.BackColor = [System.Drawing.Color]::FromArgb(254, 202, 202)
                $row.Cells[4].Style.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
                $row.Cells[4].Style.Font      = $script:FontBold
            } elseif ($p.SnmpState -eq 'OFF') {
                $row.Cells[4].Style.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
            }

            if ($p.BidiWarn) {
                $row.Cells[5].Style.BackColor = [System.Drawing.Color]::FromArgb(254, 202, 202)
                $row.Cells[5].Style.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
                $row.Cells[5].Style.Font      = $script:FontBold
            } elseif ($p.BidiState -eq 'OFF') {
                $row.Cells[5].Style.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
            }
        }
    }
    finally {
        $dgv.ResumeLayout()
    }

    $script:Tab3Ui.LblSummary.Text = "설치 프린터: 일반 ${cntNormal}대 / 특수 ${cntSpecial}대 | SNMP·양방향 수정 필요: ${cntPolicy}대"
    if ($cntPolicy -gt 0) {
        $script:Tab3Ui.LblSummary.ForeColor = [System.Drawing.Color]::FromArgb(185, 28, 28)
    } else {
        $script:Tab3Ui.LblSummary.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
    }
}

function Invoke-Tab3RefreshAsync {
    $work = {
        param($arg)
        Write-ProgressSafe -Percent 40 -Message '설치된 프린터 및 SNMP/양방향 레지스트리 상태 조회 중...'
        $res = @(Get-InstalledPrintersVerifyInfo)
        Write-ProgressSafe -Percent 100 -Message "검증 목록 갱신 완료 ($($res.Count)개 감지)"
        return $res
    }
    $done = {
        param($ok, $data, $err, $cbState)
        if (-not $ok) {
            Add-UiLog -Message "검증 목록 조회 실패: $err" -Level 'ERROR'
            return
        }
        $script:Tab3Ui.InstalledList = @($data)
        $script:Tab3Ui.HasLoadedOnce = $true
        $script:Tab3Ui.NeedsRefresh  = $false
        Render-Tab3VerifyGrid
    }
    Invoke-AsanAsyncTask -TaskName '설치 프린터 검증 상태 조회' -WorkScript $work -OnComplete $done -Indeterminate
}

function Get-Tab3SelectedPrinterItem {
    $dgv = $script:Tab3Ui.DgvVerify
    if (-not $dgv -or $dgv.SelectedRows.Count -eq 0) { return $null }
    return $dgv.SelectedRows[0].Tag
}

function Send-PrinterTestPageSafe {
    param([string]$PrinterName)
    if ([string]::IsNullOrWhiteSpace($PrinterName)) { return $false }
    try {
        $safeArg = 'printui.dll,PrintUIEntry /k /n "' + ($PrinterName -replace '"', '\"') + '"'
        Start-Process -FilePath 'rundll32.exe' -ArgumentList $safeArg
        return $true
    } catch {
        return $false
    }
}

function Invoke-Tab3BulkNormalTestPrint {
    $all     = @($script:Tab3Ui.InstalledList)
    $targets = @($all | Where-Object { -not $_.ExcludeBulkTest })
    $skipped = @($all | Where-Object { (-not $_.IsVirtual) -and $_.IsSpecial })

    if ($targets.Count -eq 0) {
        [void](Show-AsanMessageBox -Text '테스트 인쇄할 일반 프린터가 없습니다. (바코드·진료카드 특수 프린터는 안전을 위해 전체 인쇄에서 자동 제외됩니다.)' -Caption '인쇄 대상 없음' -Buttons 'OK' -Icon 'Information')
        return
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("아래 일반 프린터 $($targets.Count)대에 테스트 페이지를 일괄 전송합니다:")
    foreach ($t in $targets) {
        $lines.Add("  • $($t.PrinterName)  ($($t.PortName))")
    }
    if ($skipped.Count -gt 0) {
        $lines.Add("")
        $lines.Add("[자동 제외된 특수 프린터 — AMIS에서 직접 테스트 필요]")
        foreach ($s in $skipped) {
            $lines.Add("  - [$($s.Category)] $($s.PrinterName)")
        }
    }
    $lines.Add("")
    $lines.Add("계속하시겠습니까?")

    $ans = Show-AsanMessageBox -Text ($lines -join "`r`n") -Caption '일반 프린터 전체 테스트 인쇄' -Buttons 'YesNo' -Icon 'Question'
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $sent = 0
    foreach ($t in $targets) {
        if (Send-PrinterTestPageSafe -PrinterName $t.PrinterName) {
            $sent++
            Add-UiLog -Message "테스트 페이지 전송: $($t.PrinterName)" -Level 'INFO'
        }
    }
    [void](Show-AsanMessageBox -Text "일반 프린터 ${sent}대에 테스트 페이지 전송을 요청했습니다." -Caption '테스트 인쇄 요청 완료' -Buttons 'OK' -Icon 'Information')
}

function Initialize-Tab3VerifyUi {
    $parent = $script:Ui.TabVerify

    # [1] 상단 툴바
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock   = [System.Windows.Forms.DockStyle]::Top
    $pnlTop.Height = 64

    $btnRef = New-StyledButton -Text '목록 새로고침' -Width 112 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85)) -RegisterBusy
    $btnRef.Location = New-Object System.Drawing.Point(0, 4)
    $btnRef.Add_Click({ Invoke-Tab3RefreshAsync })

    $btnFix = New-StyledButton -Text 'SNMP / 양방향 일괄 수정' -Width 182 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(217, 119, 6)) -RegisterBusy
    $btnFix.Location = New-Object System.Drawing.Point(120, 4)
    $btnFix.Add_Click({
        $work = {
            param($arg)
            Write-ProgressSafe -Percent 40 -Message 'Spooler 안전 중지 후 SNMP/양방향 OFF 일괄 적용 중...'
            Invoke-AsanStandardPolicyAtomic
            Write-ProgressSafe -Percent 80 -Message '적용 후 프린터 상태 재조회 중...'
            return @(Get-InstalledPrintersVerifyInfo)
        }
        $done = {
            param($ok, $data, $err, $cbState)
            if (-not $ok) {
                [void](Show-AsanMessageBox -Text "일괄 수정 오류: $err" -Caption '오류' -Buttons 'OK' -Icon 'Error')
                return
            }
            $script:Tab3Ui.InstalledList = @($data)
            Render-Tab3VerifyGrid
            [void](Show-AsanMessageBox -Text '모든 TCP/IP SNMP 해제 및 일반 프린터 양방향 지원 해제를 완료했습니다.' -Caption '일괄 수정 완료' -Buttons 'OK' -Icon 'Information')
        }
        Invoke-AsanAsyncTask -TaskName 'SNMP/양방향 아산 표준 일괄 적용' -WorkScript $work -OnComplete $done -Indeterminate
    })

    $btnReset = New-StyledButton -Text '클라이언트 스풀러 초기화' -Width 176 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(185, 28, 28)) -RegisterBusy
    $btnReset.Location = New-Object System.Drawing.Point(310, 4)
    $btnReset.Add_Click({
        $ans = Show-AsanMessageBox -Text "현재 PC의 Print Spooler를 중지하고 대기열 잔여물(spool\PRINTERS)을 모두 비운 뒤 재시작합니다.`r`n계속하시겠습니까?" -Caption '스풀러 초기화 확인' -Buttons 'YesNo' -Icon 'Warning'
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $work = {
            param($arg)
            Write-ProgressSafe -Percent 40 -Message 'Print Spooler 중지 및 대기열 잔여물 초기화 중...'
            $r = Reset-ClientSpoolerAndHostCred
            Write-ProgressSafe -Percent 85 -Message '초기화 후 프린터 목록 재조회 중...'
            $list = @(Get-InstalledPrintersVerifyInfo)
            return [pscustomobject]@{ Result = $r; Printers = $list }
        }
        $done = {
            param($ok, $data, $err, $cbState)
            if (-not $ok -or -not $data) {
                [void](Show-AsanMessageBox -Text "스풀러 초기화 오류: $err" -Caption '오류' -Buttons 'OK' -Icon 'Error')
                return
            }
            $script:Tab3Ui.InstalledList = @($data.Printers)
            Render-Tab3VerifyGrid
            [void](Show-AsanMessageBox -Text $data.Result.Reason -Caption '스풀러 초기화 완료' -Buttons 'OK' -Icon 'Information')
        }
        Invoke-AsanAsyncTask -TaskName '클라이언트 스풀러 초기화' -WorkScript $work -OnComplete $done -Indeterminate
    })

    $chkVirt = New-Object System.Windows.Forms.CheckBox
    $chkVirt.Text      = '가상 프린터 함께 보기'
    $chkVirt.AutoSize  = $true
    $chkVirt.Location  = New-Object System.Drawing.Point(500, 9)
    $chkVirt.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $chkVirt.Add_CheckedChanged({ Render-Tab3VerifyGrid })

    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.Text      = '설치 프린터: 조회 대기 중'
    $lblSum.Font      = $script:FontBold
    $lblSum.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblSum.AutoSize  = $true
    $lblSum.Location  = New-Object System.Drawing.Point(2, 40)

    $pnlTop.Controls.AddRange(@($btnRef, $btnFix, $btnReset, $chkVirt, $lblSum))

    # [2] 중앙 설치 프린터 검증 그리드
    $dgv = New-StyledGrid
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    foreach ($cDef in @(
        @{ Name = 'Default';  Header = '기본';       Width = 42 },
        @{ Name = 'Category'; Header = '구분';       Width = 105 },
        @{ Name = 'Printer';  Header = '프린터 이름'; Width = 200 },
        @{ Name = 'Port';     Header = '포트';       Width = 170 },
        @{ Name = 'Snmp';     Header = 'SNMP';       Width = 64 },
        @{ Name = 'Bidi';     Header = '양방향';     Width = 72 },
        @{ Name = 'Driver';   Header = '드라이버';   Width = 220 },
        @{ Name = 'Status';   Header = '상태';       Width = 85 }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $cDef.Name
        $c.HeaderText = $cDef.Header
        $c.Width      = $cDef.Width
        [void]$dgv.Columns.Add($c)
    }

    # [3] 하단 테스트 인쇄 및 제어 액션 바 (DPI 125~150% 대응 FlowLayoutPanel)
    $pnlBot = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlBot.Dock          = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlBot.WrapContents  = $true
    $pnlBot.AutoSize      = $true
    $pnlBot.AutoSizeMode  = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $pnlBot.Padding       = New-Object System.Windows.Forms.Padding(0, 6, 0, 2)

    $btnBulk = New-StyledButton -Text '일반 프린터 전체 인쇄 (특수제외)' -Width 230 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(22, 163, 74)) -RegisterBusy
    $btnBulk.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
    $btnBulk.Add_Click({ Invoke-Tab3BulkNormalTestPrint })

    $btnSingle = New-StyledButton -Text '선택 테스트 인쇄' -Width 130 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235)) -RegisterBusy
    $btnSingle.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
    $btnSingle.Add_Click({
        $sel = Get-Tab3SelectedPrinterItem
        if (-not $sel) {
            [void](Show-AsanMessageBox -Text '테스트 인쇄할 프린터 행을 선택하세요.' -Caption '선택 없음' -Buttons 'OK' -Icon 'Warning')
            return
        }
        if ($sel.IsSpecial) {
            $warn = Show-AsanMessageBox -Text "선택한 '$($sel.PrinterName)' 은(는) [$($sel.Category)] 특수 장비입니다.`r`nWindows 테스트 페이지를 보내면 공카드·팔찌·라벨이 낭비되거나 걸릴 수 있으며, 일반적으로 AMIS에서 테스트합니다.`r`n`r`n그래도 테스트 페이지를 전송하시겠습니까?" -Caption '특수 장비 테스트 인쇄 주의' -Buttons 'YesNo' -Icon 'Warning'
            if ($warn -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        if (Send-PrinterTestPageSafe -PrinterName $sel.PrinterName) {
            Add-UiLog -Message "선택 프린터 테스트 페이지 전송: $($sel.PrinterName)" -Level 'INFO'
        }
    })

    $btnProps = New-StyledButton -Text '프린터 속성' -Width 105 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105)) -RegisterBusy
    $btnProps.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
    $btnProps.Add_Click({
        $sel = Get-Tab3SelectedPrinterItem
        if (-not $sel) { return }
        $arg = 'printui.dll,PrintUIEntry /p /n "' + ($sel.PrinterName -replace '"', '\"') + '"'
        try { Start-Process -FilePath 'rundll32.exe' -ArgumentList $arg } catch {}
    })

    $btnPrefs = New-StyledButton -Text '인쇄 기본 설정' -Width 118 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105)) -RegisterBusy
    $btnPrefs.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 2)
    $btnPrefs.Add_Click({
        $sel = Get-Tab3SelectedPrinterItem
        if (-not $sel) { return }
        $arg = 'printui.dll,PrintUIEntry /e /n "' + ($sel.PrinterName -replace '"', '\"') + '"'
        try { Start-Process -FilePath 'rundll32.exe' -ArgumentList $arg } catch {}
    })

    $btnDef = New-StyledButton -Text '기본 프린터 지정' -Width 126 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(15, 118, 110)) -RegisterBusy
    $btnDef.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $btnDef.Add_Click({
        $sel = Get-Tab3SelectedPrinterItem
        if (-not $sel) { return }
        if (Set-DefaultPrinterSafe -PrinterName $sel.PrinterName) {
            Add-UiLog -Message "기본 프린터 지정 완료: $($sel.PrinterName)" -Level 'INFO'
            Invoke-Tab3RefreshAsync
        } else {
            [void](Show-AsanMessageBox -Text "기본 프린터 지정에 실패했습니다: $($sel.PrinterName)" -Caption '지정 실패' -Buttons 'OK' -Icon 'Warning')
        }
    })

    $pnlBot.Controls.AddRange(@($btnBulk, $btnSingle, $btnProps, $btnPrefs, $btnDef))

    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlBot)
    $parent.Controls.Add($pnlTop)
    $dgv.BringToFront()

    $script:Tab3Ui.BtnRefresh      = $btnRef
    $script:Tab3Ui.BtnFixPolicy    = $btnFix
    $script:Tab3Ui.BtnResetSpooler = $btnReset
    $script:Tab3Ui.ChkShowVirtual  = $chkVirt
    $script:Tab3Ui.LblSummary      = $lblSum
    $script:Tab3Ui.DgvVerify       = $dgv
    $script:Tab3Ui.BtnBulkTest     = $btnBulk
    $script:Tab3Ui.BtnSingleTest   = $btnSingle
    $script:Tab3Ui.BtnProps        = $btnProps
    $script:Tab3Ui.BtnPrefs        = $btnPrefs
    $script:Tab3Ui.BtnSetDefault   = $btnDef

    $script:Ui.OnRestoreCompleted.Add({
        $script:Tab3Ui.NeedsRefresh = $true
    })
}

# ============================================================================
# [탭 4 UI] 서버 백업 관리 ([C2] RightFlowStrip + [H3] PreviewCache + [C4])
# ============================================================================
function Render-Tab4ServerGrid {
    $dgv = $script:Tab4Ui.DgvServer
    if (-not $dgv -or $dgv.IsDisposed) { return }

    $filter = ''
    if ($script:Tab4Ui.TxtSearch) { $filter = $script:Tab4Ui.TxtSearch.Text.Trim() }

    $all   = @($script:AppState.ServerBackups | Sort-Object MatchRank, @{ Expression = { $_.LastWriteTime }; Descending = $true })
    $old5  = (@($all | Where-Object { $_.IsOld5Days })).Count
    $shown = 0

    $script:Tab4Ui.SuppressPreviewEvent = $true
    $dgv.SuspendLayout()
    try {
        $dgv.Rows.Clear()
        foreach ($e in $all) {
            if (-not [string]::IsNullOrWhiteSpace($filter) -and $e.Name.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                continue
            }
            $shown++
            $mTxt = '-'
            if ($e.MatchRank -eq 1) { $mTxt = '자동매칭★' }
            elseif ($e.IsMatched)   { $mTxt = '유사매칭' }

            $brmTxt = '없음'
            if ($e.HasBrm) { $brmTxt = '포함' }

            $rIdx = $dgv.Rows.Add(
                $mTxt,
                [string]$e.Name,
                $e.LastWriteTime.ToString('yyyy-MM-dd HH:mm'),
                "$($e.AgeDays)일",
                $brmTxt,
                [string]$e.FullPath
            )
            $row     = $dgv.Rows[$rIdx]
            $row.Tag = $e

            if ($e.MatchRank -eq 1) {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(22, 101, 52)
            } elseif ($e.IsOld5Days) {
                $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
                $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
            }
        }
    }
    finally {
        $dgv.ResumeLayout()
        $script:Tab4Ui.SuppressPreviewEvent = $false
    }

    $net      = $script:AppState.NetworkInfo
    $isOnline = ($null -ne $net -and $net.Status -eq 'Online' -and -not [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir))
    if ($isOnline) {
        $script:Tab4Ui.LblSrvSummary.Text = "서버 백업 총 $($all.Count)개 (표시 ${shown}개) | 5일 이상 경과: ${old5}개"
    } else {
        $script:Tab4Ui.LblSrvSummary.Text = '백업 서버 미연결 — 네트워크 확인 후 상단 [새로고침(F5)]을 누르세요.'
    }

    if ($script:Tab4Ui.BtnCleanOld5) {
        $script:Tab4Ui.BtnCleanOld5.Text = "5일 경과 일괄 정리 (${old5}개)"
    }
    Sync-AllUiButtonStates
}

function Get-Tab4SelectedBackupEntry {
    $dgv = $script:Tab4Ui.DgvServer
    if (-not $dgv -or $dgv.SelectedRows.Count -eq 0) { return $null }
    return $dgv.SelectedRows[0].Tag
}

# [H3 Fix + 비동기 경량 로더] 탭 4 활성 시에만 SMB 조회 + PreviewCache + 디바운스 + Dispose 보장
function Clear-RetiredTab4Previews {
    if (-not $script:Tab4Ui -or -not $script:Tab4Ui.RetiredPreviews) { return }
    $remain = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $script:Tab4Ui.RetiredPreviews) {
        if ($null -eq $item) { continue }
        $arDone = ($null -eq $item.Async) -or $item.Async.IsCompleted
        $rsDone = ($null -eq $item.Rs) -or ($item.Rs.RunspaceStateInfo.State -in @(
            [System.Management.Automation.Runspaces.RunspaceState]::Closed,
            [System.Management.Automation.Runspaces.RunspaceState]::Broken,
            [System.Management.Automation.Runspaces.RunspaceState]::BeforeOpen
        ))
        if ($arDone -and $rsDone) {
            if ($item.Ps) { try { $item.Ps.Dispose() } catch {} }
            if ($item.Rs) { try { $item.Rs.Dispose() } catch {} }
        } else {
            $remain.Add($item)
        }
    }
    $script:Tab4Ui.RetiredPreviews = $remain
}

function Stop-Tab4PreviewAsync {
    if ($script:Tab4Ui.PreviewDebounceTimer) {
        try { $script:Tab4Ui.PreviewDebounceTimer.Stop() } catch {}
    }
    if ($script:Tab4Ui.PreviewTimer) {
        try { $script:Tab4Ui.PreviewTimer.Stop() } catch {}
    }
    $psRef = $script:Tab4Ui.PreviewPs
    $rsRef = $script:Tab4Ui.PreviewRs
    $arRef = $script:Tab4Ui.PreviewAsync
    $script:Tab4Ui.PreviewPs       = $null
    $script:Tab4Ui.PreviewRs       = $null
    $script:Tab4Ui.PreviewAsync    = $null
    $script:Tab4Ui.PreviewCacheKey = $null
    $script:Tab4Ui.PreviewReqGen   = 0

    if ($psRef -or $rsRef) {
        $isIdleOrDone = ($null -eq $arRef) -or $arRef.IsCompleted
        if ($isIdleOrDone) {
            if ($psRef) { try { $psRef.Dispose() } catch {} }
            if ($rsRef) {
                try {
                    if ($rsRef.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                        $rsRef.Close()
                    }
                } catch {}
                try { $rsRef.Dispose() } catch {}
            }
        } else {
            if ($psRef) { try { [void]$psRef.BeginStop($null, $null) } catch {} }
            if ($rsRef) { try { $rsRef.CloseAsync() } catch {} }
            if ($script:Tab4Ui.RetiredPreviews) {
                $script:Tab4Ui.RetiredPreviews.Add([pscustomobject]@{ Ps = $psRef; Rs = $rsRef; Async = $arRef })
            }
        }
    }
    Clear-RetiredTab4Previews
}

function Request-Tab4PreviewDebounced {
    if ($script:Tab4Ui.SuppressPreviewEvent) { return }
    if ($script:Ui.TabMain -and $script:Ui.TabMain.SelectedIndex -ne 3) { return }
    $sel = Get-Tab4SelectedBackupEntry
    if (-not $sel) {
        Update-Tab4PreviewBox
        return
    }
    $cacheKey = ([string]$sel.FullPath).ToLowerInvariant()
    if ($script:Tab4Ui.PreviewCache.ContainsKey($cacheKey)) {
        Update-Tab4PreviewBox
        return
    }
    if ($script:Tab4Ui.PreviewDebounceTimer) {
        $script:Tab4Ui.PreviewDebounceTimer.Stop()
        $script:Tab4Ui.PreviewDebounceTimer.Start()
    } else {
        Update-Tab4PreviewBox
    }
}

function Update-Tab4PreviewBox {
    $txt = $script:Tab4Ui.TxtPreview
    if (-not $txt -or $txt.IsDisposed) { return }
    if ($script:Ui.TabMain -and $script:Ui.TabMain.SelectedIndex -ne 3) { return }

    $sel = Get-Tab4SelectedBackupEntry
    if (-not $sel) {
        Stop-Tab4PreviewAsync
        $txt.Text = '목록에서 백업 폴더를 선택하면 백업 리포트(Migration_Report.txt) 미리보기가 표시됩니다.'
        return
    }

    $cacheKey = ([string]$sel.FullPath).ToLowerInvariant()
    if ($script:Tab4Ui.PreviewCache.ContainsKey($cacheKey)) {
        Stop-Tab4PreviewAsync
        $txt.Text = $script:Tab4Ui.PreviewCache[$cacheKey]
        return
    }

    # 경량 비동기 Runspace로 SMB 파일 읽기 수행 (UI 스레드 프리징 완전 제거, 메인 IsBusy 잠금 없음)
    Stop-Tab4PreviewAsync
    $script:Tab4Ui.PreviewGen++
    $genNow = [int]$script:Tab4Ui.PreviewGen
    $txt.Text = "리포트 미리보기 불러오는 중... ($($sel.Name))"

    try {
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $script:Tab4Ui.PreviewRs = $rs
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $script:Tab4Ui.PreviewPs = $ps
        $ps.Runspace = $rs

        $previewScript = {
            param([string]$FolderPath, [string]$FolderName, [int]$Gen)
            $outText = ''
            $readOk  = $false
            try {
                $repFile = Join-Path $FolderPath 'Migration_Report.txt'
                if (Test-Path -LiteralPath $repFile) {
                    $outText = [IO.File]::ReadAllText($repFile, [Text.Encoding]::UTF8)
                    $readOk  = $true
                } else {
                    $jsonFile = Join-Path $FolderPath 'PrinterBackup.json'
                    if (Test-Path -LiteralPath $jsonFile) {
                        $d = [IO.File]::ReadAllText($jsonFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
                        $pNames = @($d.Printers | Where-Object { $null -ne $_ } | ForEach-Object { "  - $($_.Name) [$($_.PortName)]" }) -join "`r`n"
                        $outText = "원본 PC: $($d.SourceComputer) ($($d.SourceIP)) | 일시: $($d.ExportedAt)`r`n프린터 목록:`r`n$pNames"
                        $readOk  = $true
                    } else {
                        $outText = "선택한 폴더($FolderName)에 Migration_Report.txt 또는 PrinterBackup.json이 없습니다."
                    }
                }
            } catch {
                $outText = "미리보기 읽기 실패: $($_.Exception.Message)"
            }
            return [pscustomobject]@{ Gen = $Gen; Ok = $readOk; Text = $outText }
        }

        [void]$ps.AddScript($previewScript).AddArgument([string]$sel.FullPath).AddArgument([string]$sel.Name).AddArgument($genNow)
        $script:Tab4Ui.PreviewReqGen   = $genNow
        $script:Tab4Ui.PreviewCacheKey = $cacheKey
        $script:Tab4Ui.PreviewAsync    = $ps.BeginInvoke()
        if ($script:Tab4Ui.PreviewTimer) { $script:Tab4Ui.PreviewTimer.Start() }
    }
    catch {
        Stop-Tab4PreviewAsync
        $txt.Text = "미리보기 읽기 실패: $($_.Exception.Message)"
    }
}

function Initialize-Tab4ServerUi {
    $parent = $script:Ui.TabServer

    # [1] 상단 검색 및 5일 정리 툴바 ([C2] 2행 Dock + FlowLayoutPanel + RightFlowStrip)
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock   = [System.Windows.Forms.DockStyle]::Top
    $pnlTop.Height = 64

    $pnlTopRow1 = New-Object System.Windows.Forms.Panel
    $pnlTopRow1.Dock      = [System.Windows.Forms.DockStyle]::Top
    $pnlTopRow1.Height    = 36
    $pnlTopRow1.BackColor = [System.Drawing.Color]::Transparent

    $pnlTopLeft = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlTopLeft.Dock          = [System.Windows.Forms.DockStyle]::Fill
    $pnlTopLeft.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $pnlTopLeft.WrapContents  = $false
    $pnlTopLeft.BackColor     = [System.Drawing.Color]::Transparent
    $pnlTopLeft.Padding       = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text     = '폴더 검색:'
    $lblSearch.Font     = $script:FontBold
    $lblSearch.AutoSize = $true
    $lblSearch.Margin   = New-Object System.Windows.Forms.Padding(0, 6, 6, 0)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Size   = New-Object System.Drawing.Size(220, 24)
    $txtSearch.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
    $txtSearch.Add_TextChanged({
        Render-Tab4ServerGrid
        Request-Tab4PreviewDebounced
    })

    $btnRefSrv = New-StyledButton -Text '서버 목록 새로고침' -Width 138 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(51, 65, 85)) -RegisterBusy
    $btnRefSrv.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)
    $btnRefSrv.Add_Click({ Invoke-EnvironmentRefreshAsync })

    $pnlTopLeft.Controls.AddRange(@($lblSearch, $txtSearch, $btnRefSrv))

    $flpTopRight = New-RightFlowStrip -TopPadding 4 -RightPadding 0
    $btnClean5 = New-StyledButton -Text '5일 경과 일괄 정리 (0개)' -Width 182 -Height 28 -BackColor ([System.Drawing.Color]::FromArgb(185, 28, 28)) -RegisterBusy
    $btnClean5.Enabled = $false
    $btnClean5.Add_Click({
        $net = $script:AppState.NetworkInfo
        if (-not $net -or [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir)) { return }
        $oldList = @($script:AppState.ServerBackups | Where-Object { $_.IsOld5Days })
        if ($oldList.Count -eq 0) { return }

        $previewNames = ($oldList | Select-Object -First 10 | ForEach-Object { "  • $($_.Name) ($($_.AgeDays)일 경과)" }) -join "`r`n"
        $moreTxt = ''
        if ($oldList.Count -gt 10) { $moreTxt = "`r`n  ... 외 $($oldList.Count - 10)개" }

        $ans = Show-AsanMessageBox -Text "5일 이상 경과된 서버 백업 폴더 $($oldList.Count)개를 일괄 삭제합니다:`r`n$previewNames$moreTxt`r`n`r`n삭제된 백업은 복구할 수 없습니다. 진행하시겠습니까?" -Caption '5일 경과 백업 일괄 정리 확인' -Buttons 'YesNo' -Icon 'Warning'
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $tParams = @{ PrtBakDir = [string]$net.PrtBakDir; PcIp = [string]$net.IPAddress }
        $work = {
            param($arg)
            Write-ProgressSafe -Percent 40 -Message '5일 이상 경과된 백업 폴더 정리 중...'
            $removed = @(Remove-OldServerBackups -PrtBakDir ([string]$arg.PrtBakDir) -DaysThreshold 5)
            Write-ProgressSafe -Percent 85 -Message '정리 후 서버 목록 재조회 중...'
            $entries = @(Get-ServerBackupEntries -PrtBakDir ([string]$arg.PrtBakDir) -PcIp ([string]$arg.PcIp))
            return [pscustomobject]@{ Removed = $removed; Entries = $entries }
        }
        $done = {
            param($ok, $data, $err, $cbState)
            if (-not $ok -or -not $data) {
                [void](Show-AsanMessageBox -Text "정리 중 오류 발생: $err" -Caption '정리 실패' -Buttons 'OK' -Icon 'Error')
                return
            }
            $script:Tab4Ui.PreviewCache.Clear()
            $script:AppState.ServerBackups = @($data.Entries)
            Update-Tab2ServerDropdown
            Render-Tab4ServerGrid
            Update-Tab4PreviewBox
            [void](Show-AsanMessageBox -Text "5일 이상 경과된 백업 폴더 $($data.Removed.Count)개를 정리했습니다." -Caption '일괄 정리 완료' -Buttons 'OK' -Icon 'Information')
        }
        Invoke-AsanAsyncTask -TaskName '5일 경과 서버 백업 정리' -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
    })
    $flpTopRight.Controls.Add($btnClean5)

    $pnlTopRow1.Controls.Add($pnlTopLeft)
    $pnlTopRow1.Controls.Add($flpTopRight)

    $lblSrvSum = New-Object System.Windows.Forms.Label
    $lblSrvSum.Text      = '서버 백업 목록 조회 대기 중...'
    $lblSrvSum.Font      = $script:FontBold
    $lblSrvSum.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblSrvSum.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $lblSrvSum.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $pnlTop.Controls.Add($lblSrvSum)
    $pnlTop.Controls.Add($pnlTopRow1)

    # [2] 중앙 서버 백업 목록 그리드
    $dgv = New-StyledGrid
    $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill

    foreach ($cDef in @(
        @{ Name = 'Match'; Header = '매칭';       Width = 84 },
        @{ Name = 'Name';  Header = '백업 폴더명'; Width = 220 },
        @{ Name = 'Date';  Header = '백업 일시';   Width = 140 },
        @{ Name = 'Age';   Header = '경과일';     Width = 72 },
        @{ Name = 'Brm';   Header = 'PrintBrm';   Width = 74 },
        @{ Name = 'Path';  Header = '서버 경로';   Width = 370 }
    )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name       = $cDef.Name
        $c.HeaderText = $cDef.Header
        $c.Width      = $cDef.Width
        [void]$dgv.Columns.Add($c)
    }
    $dgv.Add_SelectionChanged({
        if (-not $script:Tab4Ui.SuppressPreviewEvent) {
            Request-Tab4PreviewDebounced
            Sync-AllUiButtonStates
        }
    })

    # [3] 하단 리포트 미리보기 창
    $pnlPrev = New-Object System.Windows.Forms.Panel
    $pnlPrev.Dock    = [System.Windows.Forms.DockStyle]::Bottom
    $pnlPrev.Height  = 128
    $pnlPrev.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $txtPrev = New-Object System.Windows.Forms.TextBox
    $txtPrev.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $txtPrev.Multiline   = $true
    $txtPrev.ReadOnly    = $true
    $txtPrev.ScrollBars  = [System.Windows.Forms.ScrollBars]::Vertical
    $txtPrev.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtPrev.BackColor   = [System.Drawing.Color]::White
    $txtPrev.ForeColor   = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $txtPrev.Font        = $script:FontMono
    $txtPrev.Text        = '목록에서 백업 폴더를 선택하면 백업 리포트(Migration_Report.txt) 미리보기가 표시됩니다.'
    $pnlPrev.Controls.Add($txtPrev)

    # [4] 최하단 액션 바 ([C2] RightFlowStrip + [C4] 안전 탐색기 열기)
    $pnlBot = New-Object System.Windows.Forms.Panel
    $pnlBot.Dock   = [System.Windows.Forms.DockStyle]::Bottom
    $pnlBot.Height = 46

    $pnlBotLeft = New-Object System.Windows.Forms.Panel
    $pnlBotLeft.Dock      = [System.Windows.Forms.DockStyle]::Fill
    $pnlBotLeft.BackColor = [System.Drawing.Color]::Transparent

    $btnLoadTab2 = New-StyledButton -Text '선택 백업을 복원 탭으로 불러오기' -Width 230 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(37, 99, 235)) -RegisterBusy
    $btnLoadTab2.Location = New-Object System.Drawing.Point(0, 8)
    $btnLoadTab2.Enabled  = $false
    $btnLoadTab2.Add_Click({
        $sel = Get-Tab4SelectedBackupEntry
        if (-not $sel) {
            [void](Show-AsanMessageBox -Text '복원 탭으로 불러올 백업 폴더를 선택하세요.' -Caption '선택 없음' -Buttons 'OK' -Icon 'Warning')
            return
        }
        $script:Ui.TabMain.SelectedIndex = 1
        Load-Tab2BackupSourceAsync -SourcePath $sel.FullPath
    })

    $btnOpenDir = New-StyledButton -Text '탐색기로 폴더 열기' -Width 142 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(71, 85, 105))
    $btnOpenDir.Location = New-Object System.Drawing.Point(242, 8)
    $btnOpenDir.Add_Click({
        $sel = Get-Tab4SelectedBackupEntry
        $dir = $null
        if ($sel) { $dir = $sel.FullPath }
        elseif ($script:AppState.NetworkInfo) { $dir = $script:AppState.NetworkInfo.PrtBakDir }
        Open-FolderInExplorerSafe -FolderPath $dir
    })

    $pnlBotLeft.Controls.AddRange(@($btnLoadTab2, $btnOpenDir))

    $flpBotRight = New-RightFlowStrip -TopPadding 8 -RightPadding 0
    $btnDelOne = New-StyledButton -Text '선택 백업 삭제' -Width 126 -Height 34 -BackColor ([System.Drawing.Color]::FromArgb(220, 38, 38)) -RegisterBusy
    $btnDelOne.Enabled = $false
    $btnDelOne.Add_Click({
        $sel = Get-Tab4SelectedBackupEntry
        $net = $script:AppState.NetworkInfo
        if (-not $sel -or -not $net -or [string]::IsNullOrWhiteSpace([string]$net.PrtBakDir)) { return }

        $ans = Show-AsanMessageBox -Text "선택한 백업 폴더를 서버에서 영구 삭제하시겠습니까?`r`n- 대상: $($sel.Name)" -Caption '선택 백업 삭제 확인' -Buttons 'YesNo' -Icon 'Warning'
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $tParams = @{ TargetDir = [string]$sel.FullPath; PrtBakDir = [string]$net.PrtBakDir; PcIp = [string]$net.IPAddress }
        $work = {
            param($arg)
            $tFull = [IO.Path]::GetFullPath([string]$arg.TargetDir).TrimEnd('\')
            $bFull = [IO.Path]::GetFullPath([string]$arg.PrtBakDir).TrimEnd('\')
            $pFull = [IO.Path]::GetDirectoryName($tFull).TrimEnd('\')
            $tName = [IO.Path]::GetFileName($tFull)
            if ($pFull -ine $bFull) { throw '안전 가드: _PRTBAK 직계 하위 폴더만 삭제할 수 있습니다.' }
            if ($tName.StartsWith('_')) { throw '안전 가드: 시스템 폴더(_접두어)는 삭제할 수 없습니다.' }
            $hasMarker = (Test-Path -LiteralPath (Join-Path $tFull 'PrinterBackup.json')) -or (Test-Path -LiteralPath (Join-Path $tFull 'PrinterBackup.printerExport'))
            if (-not $hasMarker) { throw '안전 가드: PrinterBackup 파일이 없는 폴더는 삭제할 수 없습니다.' }

            Write-ProgressSafe -Percent 40 -Message "백업 폴더 삭제 중: $tFull"
            Remove-Item -LiteralPath $tFull -Recurse -Force -ErrorAction Stop
            Write-ProgressSafe -Percent 85 -Message '삭제 후 서버 목록 갱신 중...'
            return @(Get-ServerBackupEntries -PrtBakDir ([string]$arg.PrtBakDir) -PcIp ([string]$arg.PcIp))
        }
        $done = {
            param($ok, $data, $err, $cbState)
            if (-not $ok) {
                [void](Show-AsanMessageBox -Text "삭제 실패: $err" -Caption '삭제 오류' -Buttons 'OK' -Icon 'Error')
                return
            }
            $script:Tab4Ui.PreviewCache.Clear()
            $script:AppState.ServerBackups = @($data)
            Update-Tab2ServerDropdown
            Render-Tab4ServerGrid
            Update-Tab4PreviewBox
            Add-UiLog -Message '선택한 서버 백업 폴더를 삭제했습니다.' -Level 'INFO'
        }
        Invoke-AsanAsyncTask -TaskName '선택 서버 백업 삭제' -WorkScript $work -Params $tParams -OnComplete $done -Indeterminate
    })
    $flpBotRight.Controls.Add($btnDelOne)

    $pnlBot.Controls.Add($pnlBotLeft)
    $pnlBot.Controls.Add($flpBotRight)

    $parent.Controls.Add($dgv)
    $parent.Controls.Add($pnlPrev)
    $parent.Controls.Add($pnlBot)
    $parent.Controls.Add($pnlTop)
    $dgv.BringToFront()

    $prevDebounceTimer = New-Object System.Windows.Forms.Timer
    $prevDebounceTimer.Interval = 150
    $prevDebounceTimer.Add_Tick({
        try {
            if ($script:Tab4Ui.PreviewDebounceTimer) { $script:Tab4Ui.PreviewDebounceTimer.Stop() }
            Update-Tab4PreviewBox
        } catch {
            if ($script:Tab4Ui.PreviewDebounceTimer) { try { $script:Tab4Ui.PreviewDebounceTimer.Stop() } catch {} }
        }
    })
    $script:Tab4Ui.PreviewDebounceTimer = $prevDebounceTimer

    $prevTimer = New-Object System.Windows.Forms.Timer
    $prevTimer.Interval = 120
    $prevTimer.Add_Tick({
        try {
            if ($script:Tab4Ui.PreviewAsync -and $script:Tab4Ui.PreviewAsync.IsCompleted) {
                $script:Tab4Ui.PreviewTimer.Stop()
                $psRef     = $script:Tab4Ui.PreviewPs
                $rsRef     = $script:Tab4Ui.PreviewRs
                $arRef     = $script:Tab4Ui.PreviewAsync
                $cKeyRef   = $script:Tab4Ui.PreviewCacheKey
                $reqGenRef = [int]$script:Tab4Ui.PreviewReqGen
                $script:Tab4Ui.PreviewPs       = $null
                $script:Tab4Ui.PreviewRs       = $null
                $script:Tab4Ui.PreviewAsync    = $null
                $script:Tab4Ui.PreviewCacheKey = $null
                $script:Tab4Ui.PreviewReqGen   = 0
                try {
                    $out = @($psRef.EndInvoke($arRef)) | Select-Object -Last 1
                    if ($reqGenRef -eq [int]$script:Tab4Ui.PreviewGen) {
                        if ($out -and [int]$out.Gen -eq [int]$script:Tab4Ui.PreviewGen) {
                            if ($cKeyRef -and [bool]$out.Ok) {
                                $script:Tab4Ui.PreviewCache[$cKeyRef] = [string]$out.Text
                            }
                            if ($script:Tab4Ui.TxtPreview -and -not $script:Tab4Ui.TxtPreview.IsDisposed) {
                                $script:Tab4Ui.TxtPreview.Text = [string]$out.Text
                            }
                        } else {
                            $errInfo = '미리보기 응답 없음'
                            if ($psRef.HadErrors -and $psRef.Streams.Error.Count -gt 0) {
                                $errInfo = ($psRef.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                            }
                            if ($script:Tab4Ui.TxtPreview -and -not $script:Tab4Ui.TxtPreview.IsDisposed) {
                                $script:Tab4Ui.TxtPreview.Text = "미리보기 읽기 실패: $errInfo"
                            }
                        }
                    }
                } catch {
                    if ($reqGenRef -eq [int]$script:Tab4Ui.PreviewGen -and $script:Tab4Ui.TxtPreview -and -not $script:Tab4Ui.TxtPreview.IsDisposed) {
                        $script:Tab4Ui.TxtPreview.Text = "미리보기 읽기 실패: $($_.Exception.Message)"
                    }
                }
                finally {
                    if ($psRef) { try { $psRef.Dispose() } catch {} }
                    if ($rsRef) { try { $rsRef.Close(); $rsRef.Dispose() } catch {} }
                    Clear-RetiredTab4Previews
                }
            } else {
                Clear-RetiredTab4Previews
            }
        } catch {
            try { Stop-Tab4PreviewAsync } catch {}
            if ($script:Tab4Ui.TxtPreview -and -not $script:Tab4Ui.TxtPreview.IsDisposed) {
                $script:Tab4Ui.TxtPreview.Text = "미리보기 처리 오류: $($_.Exception.Message)"
            }
        }
    })
    $script:Tab4Ui.PreviewTimer = $prevTimer

    $script:Tab4Ui.TxtSearch     = $txtSearch
    $script:Tab4Ui.BtnRefreshSrv = $btnRefSrv
    $script:Tab4Ui.BtnCleanOld5  = $btnClean5
    $script:Tab4Ui.LblSrvSummary = $lblSrvSum
    $script:Tab4Ui.DgvServer     = $dgv
    $script:Tab4Ui.TxtPreview    = $txtPrev
    $script:Tab4Ui.BtnLoadToTab2 = $btnLoadTab2
    $script:Tab4Ui.BtnOpenFolder = $btnOpenDir
    $script:Tab4Ui.BtnDeleteOne  = $btnDelOne

    $script:Ui.OnEnvRefreshed.Add({
        $script:Tab4Ui.PreviewCache.Clear()
        Render-Tab4ServerGrid
        Update-Tab4PreviewBox
    })
}

# ============================================================================
# [앱 메인 진입점] 전체 GUI 조립 · OS별 자동 탭 선택 · 정상 종료 코드(99)
# ============================================================================
function Start-AsanPrinterManagerApp {
    Initialize-MainGuiShell
    Initialize-Tab1BackupUi
    Initialize-Tab2RestoreUi
    Initialize-Tab3VerifyUi
    Initialize-Tab4ServerUi
    Sync-AllUiButtonStates

    # 탭 전환 시 지연 로드 처리 (탭 4 이탈 시 미리보기 중단 / 탭 3 자동 갱신 / 탭 4 진입 시 미리보기 갱신)
    $script:Ui.TabMain.Add_SelectedIndexChanged({
        $idx = $script:Ui.TabMain.SelectedIndex
        if ($idx -ne 3) {
            Stop-Tab4PreviewAsync
        }
        if ($idx -eq 2 -and (-not $script:AsyncState.IsBusy)) {
            if (-not $script:Tab3Ui.HasLoadedOnce -or $script:Tab3Ui.NeedsRefresh) {
                Invoke-Tab3RefreshAsync
            }
        } elseif ($idx -eq 3) {
            Update-Tab4PreviewBox
            Sync-AllUiButtonStates
        }
    })

    # 창 최초 표시(Shown) 시 환경 진단 후 OS별 자동 워크플로우 시작
    $script:Ui.Form.Add_Shown({
        Add-UiLog -Message "아산병원 프린터/드라이버 통합 마이그레이션 도구 v$($global:AsanCtx.AppVersion) 기동됨" -Level 'INFO'
        Invoke-EnvironmentRefreshAsync -AfterRefresh {
            if ($script:AppState.IsWin11) {
                $script:Ui.TabMain.SelectedIndex = 1
                $bestMatch = @($script:AppState.ServerBackups | Where-Object { $_.MatchRank -le 2 } | Sort-Object MatchRank, @{ Expression = { $_.LastWriteTime }; Descending = $true }) | Select-Object -First 1
                if ($bestMatch) {
                    Add-UiLog -Message "현재 PC와 일치하는 서버 백업 자동 로드: $($bestMatch.Name)" -Level 'INFO'
                    Load-Tab2BackupSourceAsync -SourcePath $bestMatch.FullPath
                } else {
                    Add-UiLog -Message 'Windows 11 환경 감지 — [2. 복원] 탭에서 서버 백업 또는 오프라인 ZIP을 선택하세요.' -Level 'INFO'
                }
            } else {
                $script:Ui.TabMain.SelectedIndex = 0
                Add-UiLog -Message 'Windows 10 환경 감지 — [1. 백업] 탭에서 설치 프린터 자동 진단을 시작합니다.' -Level 'INFO'
                Invoke-Tab1ScanAsync
            }
        }
    })

    # 정상 파싱 및 GUI 구성 완료 시 배경 CMD 창 숨김
    Hide-ConsoleWindowSafe
    try {
        [void]$script:Ui.Form.ShowDialog()
    } finally {
        Stop-Tab4PreviewAsync
        if ($script:Tab4Ui.PreviewDebounceTimer) { try { $script:Tab4Ui.PreviewDebounceTimer.Dispose() } catch {}; $script:Tab4Ui.PreviewDebounceTimer = $null }
        if ($script:Tab4Ui.PreviewTimer) { try { $script:Tab4Ui.PreviewTimer.Dispose() } catch {}; $script:Tab4Ui.PreviewTimer = $null }
        try { Clear-RetiredTab4Previews } catch {}
        if ($script:AsyncState.PollTimer) { try { $script:AsyncState.PollTimer.Dispose() } catch {}; $script:AsyncState.PollTimer = $null }
        if ($script:Ui.Form) { try { $script:Ui.Form.Dispose() } catch {} }
    }
}

# 앱 실행 및 부트스트랩 정상 종료 마커(99) 반환
Start-AsanPrinterManagerApp
exit 99
