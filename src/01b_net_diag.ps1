# ============================================================================
# Windows 보호 인쇄 모드(WPP) 사전 감지 및 단계별 조치 안내
# ============================================================================
function Test-WindowsProtectedPrintMode {
    $localEnabled  = $false
    $policyEnabled = $false

    try {
        $printKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print'
        if (Test-Path -LiteralPath $printKey) {
            $v = (Get-ItemProperty -LiteralPath $printKey -Name 'WindowsProtectedPrintMode' -ErrorAction SilentlyContinue).WindowsProtectedPrintMode
            if ($null -ne $v -and [int]$v -eq 1) { $localEnabled = $true }
        }
    } catch {}

    foreach ($polKey in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP'
    )) {
        try {
            if (Test-Path -LiteralPath $polKey) {
                $props = Get-ItemProperty -LiteralPath $polKey -ErrorAction SilentlyContinue
                if ($props) {
                    foreach ($pName in @('WindowsProtectedPrintGroupPolicyState', 'WindowsProtectedPrintMode')) {
                        if ($props.PSObject.Properties.Name -contains $pName) {
                            $pv = $props.$pName
                            if ($null -ne $pv -and [int]$pv -eq 1) { $policyEnabled = $true }
                        }
                    }
                }
            }
        } catch {}
    }

    $isEnabled = ($localEnabled -or $policyEnabled)
    if (-not $isEnabled) {
        return [pscustomobject]@{
            IsEnabled        = $false
            IsPolicyEnforced = $false
            SettingsUri      = 'ms-settings:printers'
            BannerTitle      = ''
            Summary          = 'Windows 보호 인쇄 모드(WPP) 비활성화 (정상)'
            RemediationGuide = ''
        }
    }

    if ($policyEnabled) {
        $title = '그룹 정책으로 Windows 보호 인쇄 모드가 켜져 있어 드라이버 복원이 차단됩니다.'
        $guide = @(
            '현재 PC에 그룹 정책(GPO)으로 Windows 보호 인쇄 모드가 적용되어 있어',
            '교세라, 삼성, 바코드, 진료카드 등 제조사 전용 드라이버를 설치하거나 복원할 수 없습니다.',
            '',
            '해결 방법',
            '1. 아래 그룹 정책 열기 버튼을 누르거나 Win+R에서 gpedit.msc를 실행해 주세요.',
            '2. 컴퓨터 구성 > 관리 템플릿 > 프린터 > Windows 보호 인쇄 구성을 열어 주세요.',
            '3. 사용 안 함 또는 구성되지 않음으로 변경한 뒤 관리자 CMD에서 gpupdate /force를 실행해 주세요.',
            '4. 보안 정책으로 변경할 수 없다면 IT서비스팀 시스템 관리자에게 정책 해제를 요청해 주세요.',
            '5. 정책을 해제한 뒤 상단 새로고침을 눌러 경고가 사라지면 복원을 진행해 주세요.'
        ) -join "`r`n"
    } else {
        $title = 'Windows 보호 인쇄 모드가 켜져 있어 새 PC 드라이버 복원이 차단됩니다.'
        $guide = @(
            '현재 PC에 Windows 보호 인쇄 모드가 켜져 있어',
            '기존 PC에서 백업한 드라이버와 제조사 전용 드라이버를 복원할 수 없습니다.',
            '',
            '해결 방법',
            '1. 아래 Windows 프린터 설정 열기 버튼을 눌러 주세요.',
            '2. Bluetooth 및 장치 > 프린터 및 스캐너 화면으로 이동해 주세요.',
            '3. 아래쪽 프린터 기본 설정에서 Windows 보호 인쇄 모드를 끄기로 변경해 주세요.',
            '4. 설정을 끄고 상단 새로고침을 눌러 경고 배너가 사라지면 복원을 진행해 주세요.'
        ) -join "`r`n"
    }

    return [pscustomobject]@{
        IsEnabled        = $true
        IsPolicyEnforced = $policyEnabled
        SettingsUri      = 'ms-settings:printers'
        BannerTitle      = $title
        Summary          = $title
        RemediationGuide = $guide
    }
}

# ============================================================================
# 공통 유틸리티 (안전 실행, IPv4 검증, 다중 NIC, Machine SID, 폴더 ID)
# ============================================================================
function Write-ProgressSafe {
    param(
        [scriptblock]$OnProgress,
        [int]$Percent,
        [string]$Message
    )
    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('HH:mm:ss')
        Percent   = $Percent
        Message   = $Message
    }
    try { $global:AsanCtx.LogQueue.Enqueue($entry) } catch {}
    if ($OnProgress) {
        try { & $OnProgress $Percent $Message } catch {}
    }
}

function Get-SafeFileName {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 'Item' }
    return ($Text -replace '[\\/:*?"<>|\s]+', '_')
}

function Get-BackupFolderId {
    param([string]$PcIp)
    $safeHost = Get-SafeFileName -Text $env:COMPUTERNAME
    # '_' 접두어는 시스템 폴더(_REPORTS, _TMP 등) 예약어이므로 호스트명이 '_'로 시작하면 'PC' 접두어 부여
    if ($safeHost.StartsWith('_')) { $safeHost = 'PC' + $safeHost }
    $safeIp   = Get-SafeFileName -Text $PcIp
    return "$safeHost($safeIp)"
}

function Test-IsUsableIPv4 {
    param([string]$IpText)
    if ([string]::IsNullOrWhiteSpace($IpText)) { return $false }
    $ipObj = $null
    if (-not [System.Net.IPAddress]::TryParse($IpText.Trim(), [ref]$ipObj)) { return $false }
    if ($ipObj.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $b = $ipObj.GetAddressBytes()
    if ($b[0] -eq 0 -or $b[0] -eq 127 -or $b[0] -ge 224) { return $false }
    if ($b[0] -eq 169 -and $b[1] -eq 254) { return $false }
    return $true
}

function Select-FirstUsableIPv4 {
    param(
        [string]$Text,
        [switch]$UrlOnly
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $urlMatches = [regex]::Matches($Text, 'https?://(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?:[:/\s]|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($um in $urlMatches) {
        $cand = $um.Groups[1].Value
        if (Test-IsUsableIPv4 -IpText $cand) { return $cand }
    }
    if ($UrlOnly) { return $null }

    $rawMatches = [regex]::Matches($Text, '(?<![\d\.vV])(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?![\d\.])')
    foreach ($rm in $rawMatches) {
        $cand = $rm.Groups[1].Value
        if (Test-IsUsableIPv4 -IpText $cand) { return $cand }
    }
    return $null
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lines = [System.Collections.Generic.List[string]]::new()
    $rc = 1
    try {
        $global:LASTEXITCODE = 0
        $raw = & $FilePath @Arguments 2>&1
        $rc = $LASTEXITCODE
        foreach ($item in @($raw)) {
            if ($null -eq $item) { continue }
            if ($item -is [System.Management.Automation.ErrorRecord]) {
                $lines.Add($item.ToString())
            } else {
                $lines.Add([string]$item)
            }
        }
    }
    catch {
        $lines.Add($_.Exception.Message)
        $rc = 1
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
    return [pscustomobject]@{
        ExitCode = $rc
        Output   = ($lines.ToArray() -join [Environment]::NewLine)
        Lines    = $lines.ToArray()
    }
}

function Test-TcpPortFast {
    param(
        [string]$HostIp,
        [int]$Port,
        [int]$TimeoutMs = 1500
    )
    if ([string]::IsNullOrWhiteSpace($HostIp)) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    $iar    = $null
    try {
        $iar = $client.BeginConnect($HostIp, $Port, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if ($iar -and $iar.AsyncWaitHandle) { try { $iar.AsyncWaitHandle.Close() } catch {} }
        try { $client.Close() } catch {}
    }
}

function Test-PingFast {
    param(
        [string]$HostIp,
        [int]$TimeoutMs = 1000
    )
    if ([string]::IsNullOrWhiteSpace($HostIp)) { return $false }
    $ping = $null
    try {
        $ping  = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($HostIp, $TimeoutMs)
        if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if ($ping) { try { $ping.Dispose() } catch {} }
    }
}

function Get-EffectiveDefaultUser {
    $ru = [string]$global:AsanCtx.RuntimeUser
    if (-not [string]::IsNullOrWhiteSpace($ru)) { return $ru.Trim() }
    return [string]$global:AsanCtx.DefaultUser
}

function Import-RuntimeSecretsIfPresent {
    param(
        [string]$ExplicitPath = '',
        [switch]$ForceReload
    )
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add($ExplicitPath.Trim())
    } else {
        if (-not [string]::IsNullOrWhiteSpace($env:ASAN_SECRETS_FILE)) {
            $candidates.Add($env:ASAN_SECRETS_FILE.Trim())
        }
        $origPath = [string]$global:AsanCtx.OriginalScriptPath
        if (-not [string]::IsNullOrWhiteSpace($origPath)) {
            try {
                $origDir = [IO.Path]::GetDirectoryName($origPath)
                if (-not [string]::IsNullOrWhiteSpace($origDir)) {
                    $candidates.Add((Join-Path $origDir 'secrets.local.json'))
                    $candidates.Add((Join-Path $origDir 'secrets.local.json.txt'))
                    $candidates.Add((Join-Path $origDir 'secrets.local.json.json'))
                }
            } catch {}
        }
    }

    $foundPath = $null
    foreach ($cand in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path -LiteralPath $cand -PathType Leaf)) {
            $foundPath = $cand
            break
        }
    }
    if (-not $foundPath) {
        return [pscustomobject]@{ Loaded = $false; SourcePath = $null; PasswordCount = 0; UserName = $null }
    }

    if ((-not $ForceReload) -and ([string]$global:AsanCtx.RuntimeSecretsSource -ieq $foundPath) -and ((@($global:AsanCtx.RuntimePasswords)).Count -gt 0)) {
        return [pscustomobject]@{
            Loaded        = $true
            SourcePath    = $foundPath
            PasswordCount = (@($global:AsanCtx.RuntimePasswords)).Count
            UserName      = (Get-EffectiveDefaultUser)
        }
    }

    try {
        $raw = $null
        try {
            $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
            $raw = [IO.File]::ReadAllText($foundPath, $utf8Strict)
        } catch {
            $raw = [IO.File]::ReadAllText($foundPath, [Text.Encoding]::Default)
        }
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
        $obj = $raw | ConvertFrom-Json

        $filePws = [System.Collections.Generic.List[string]]::new()
        if ($obj -and ($obj.PSObject.Properties.Name -contains 'DefaultPasswords')) {
            foreach ($pw in @($obj.DefaultPasswords)) {
                $s = [string]$pw
                if (-not [string]::IsNullOrWhiteSpace($s) -and $s -ne '__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__' -and $s -notmatch '(?i)^CHANGE_ME_') {
                    if (-not $filePws.Contains($s)) { $filePws.Add($s) }
                }
            }
        }

        $fileUser = $null
        if ($obj -and ($obj.PSObject.Properties.Name -contains 'DefaultUser')) {
            $uVal = [string]$obj.DefaultUser
            if (-not [string]::IsNullOrWhiteSpace($uVal)) { $fileUser = $uVal.Trim() }
        }

        if ($filePws.Count -gt 0) {
            # 기존 세션 중 수동 입력된 암호가 있다면 우선순위를 유지하며 병합
            $merged = [System.Collections.Generic.List[string]]::new()
            foreach ($cur in @($global:AsanCtx.RuntimePasswords)) {
                $cs = [string]$cur
                if (-not [string]::IsNullOrWhiteSpace($cs) -and (-not $merged.Contains($cs))) { $merged.Add($cs) }
            }
            foreach ($fp in $filePws) {
                if (-not $merged.Contains($fp)) { $merged.Add($fp) }
            }
            $global:AsanCtx.RuntimePasswords     = @($merged.ToArray())
            $global:AsanCtx.RuntimeSecretsSource = $foundPath
            if ($fileUser -and [string]::IsNullOrWhiteSpace([string]$global:AsanCtx.RuntimeUser)) {
                $global:AsanCtx.RuntimeUser = $fileUser
            }
            return [pscustomobject]@{
                Loaded        = $true
                SourcePath    = $foundPath
                PasswordCount = $filePws.Count
                UserName      = (Get-EffectiveDefaultUser)
            }
        }
    } catch {}

    return [pscustomobject]@{ Loaded = $false; SourcePath = $foundPath; PasswordCount = 0; UserName = $null }
}

function Get-ConfiguredDefaultPasswords {
    $valid = [System.Collections.Generic.List[string]]::new()
    foreach ($pw in @($global:AsanCtx.RuntimePasswords)) {
        $s = [string]$pw
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -ne '__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__' -and $s -notmatch '(?i)^CHANGE_ME_') {
            if (-not $valid.Contains($s)) { $valid.Add($s) }
        }
    }
    foreach ($pw in @($global:AsanCtx.DefaultPasswords)) {
        $s = [string]$pw
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -ne '__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__' -and $s -notmatch '(?i)^CHANGE_ME_') {
            if (-not $valid.Contains($s)) { $valid.Add($s) }
        }
    }
    return @($valid.ToArray())
}

function Stop-SpoolerSafe {
    param([int]$TimeoutSeconds = 10)
    $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }
    if ($svc.Status -eq 'Stopped') { return $true }
    try { Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue } catch {}
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Stopped') { return $true }
        Start-Sleep -Milliseconds 300
    }
    # 인쇄 작업 교착(spoolsv.exe 응답 없음) 시 프로세스 강제 정리 후 정지 재확인
    try { Stop-Process -Name 'spoolsv' -Force -ErrorAction SilentlyContinue } catch {}
    $killDeadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $killDeadline) {
        $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Stopped') { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Start-SpoolerSafe {
    param([int]$TimeoutSeconds = 10)
    $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if ($svc.Status -ne 'Running') {
        try {
            if ($svc.StartType -eq 'Disabled') {
                Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' -Name 'Start' -Value 2 -Type DWord -ErrorAction SilentlyContinue
                Set-Service -Name Spooler -StartupType Automatic -ErrorAction SilentlyContinue
            }
        } catch {}
        try { Start-Service -Name Spooler -ErrorAction SilentlyContinue } catch {}
        $svcAfter = Get-Service -Name Spooler -ErrorAction SilentlyContinue
        if ($svcAfter -and $svcAfter.Status -ne 'Running' -and $svcAfter.Status -ne 'StartPending') {
            try {
                Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler' -Name 'Start' -Value 2 -Type DWord -ErrorAction SilentlyContinue
                Set-Service -Name Spooler -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name Spooler -ErrorAction SilentlyContinue
            } catch {}
        }
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { break }
            Start-Sleep -Milliseconds 300
        }
    }
}

function Get-OsVersionInfoSafe {
    $caption = ''
    $build   = 0
    try {
        $cvKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        if (Test-Path -LiteralPath $cvKey) {
            $cv = Get-ItemProperty -LiteralPath $cvKey -ErrorAction SilentlyContinue
            if ($cv) {
                if ($cv.PSObject.Properties.Name -contains 'ProductName') {
                    $caption = [string]$cv.ProductName
                }
                if ($cv.PSObject.Properties.Name -contains 'CurrentBuildNumber') {
                    [void][int]::TryParse([string]$cv.CurrentBuildNumber, [ref]$build)
                } elseif ($cv.PSObject.Properties.Name -contains 'CurrentBuild') {
                    [void][int]::TryParse([string]$cv.CurrentBuild, [ref]$build)
                }
            }
        }
    } catch {}
    if ($build -le 0) {
        try { $build = [int][System.Environment]::OSVersion.Version.Build } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($caption)) {
        try {
            $osObj = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($osObj) {
                $caption = [string]$osObj.Caption
                if ($build -le 0) { [void][int]::TryParse([string]$osObj.BuildNumber, [ref]$build) }
            }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($caption)) { $caption = 'Windows' }
    $caption = ($caption -replace '^Microsoft\s+', '').Trim()
    # Windows 11에서도 CurrentVersion\ProductName 레지스트리가 'Windows 10 ...'으로 남는 OS 특성 보정
    if ($build -ge 22000 -and $caption -match 'Windows 10') {
        $caption = $caption -replace 'Windows 10', 'Windows 11'
    }
    return [pscustomobject]@{
        Caption = $caption
        Build   = $build
        IsWin11 = ($build -ge 22000 -or $caption -match 'Windows 11')
    }
}

function Get-LocalMachineSID {
    # 1순위: WMI 무관 순수 Win32 NetUserModalsGet API (클래스 오류 0%, AD 도메인 가입 PC에서도 로컬 SAM SID 정확 반환)
    try {
        $nativeSid = [AsanWin32.NativeApi]::GetLocalMachineSid()
        if (-not [string]::IsNullOrWhiteSpace($nativeSid) -and $nativeSid -match '^S-1-5-21-\d+-\d+-\d+$') {
            return $nativeSid
        }
    } catch {}

    # 2순위: WMI 폴백
    try {
        $adminAcct = @(Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount = True AND SID LIKE '%-500'" -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($adminAcct -and $adminAcct.SID -match '^S-1-5-21-\d+-\d+-\d+-500$') {
            return ([string]$adminAcct.SID -replace '-500$', '')
        }
        $acct = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True' -ErrorAction SilentlyContinue |
            Where-Object { $_.SID -match '^S-1-5-21-\d+-\d+-\d+-\d+$' }) | Select-Object -First 1
        if ($acct -and $acct.SID) {
            return ([string]$acct.SID -replace '-\d+$', '')
        }
    } catch {}
    return 'SID-조회불가'
}

# ============================================================================
# WMI 클래스 손상 환경(잘못된 클래스입니다 / 0x80041010) 완전 대응 네이티브 프린터·포트·드라이버 조회기
# ============================================================================
function Get-LocalPrintersSafe {
    $outList = [System.Collections.Generic.List[object]]::new()
    $seen    = @{}

    # 1순위: Win32 Spooler 네이티브 API (winspool.drv EnumPrintersW — WMI/CIM 클래스 불필요)
    try {
        $nativePrts = @([AsanWin32.NativeApi]::EnumInstalledPrinters())
        foreach ($np in $nativePrts) {
            if (-not $np -or [string]::IsNullOrWhiteSpace([string]$np.Name)) { continue }
            $nm = [string]$np.Name
            $k  = $nm.ToLowerInvariant()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $outList.Add([pscustomobject]@{
                Name            = $nm
                DriverName      = [string]$np.DriverName
                PortName        = [string]$np.PortName
                Default         = [bool]$np.Default
                Network         = [bool]$np.Network
                ServerName      = [string]$np.ServerName
                ShareName       = [string]$np.ShareName
                WorkOffline     = [bool]$np.WorkOffline
                PrinterStatus   = [int]$np.PrinterStatus
                Attributes      = [uint32]$np.Attributes
                _NativeFallback = $true
            })
        }
    } catch {}

    # 2순위: Win32 EnumPrinters가 비었을 때만 WMI 폴백 (try/catch 완전 격리)
    if ($outList.Count -eq 0) {
        try {
            foreach ($cp in @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)) {
                if (-not $cp -or [string]::IsNullOrWhiteSpace([string]$cp.Name)) { continue }
                $nm = [string]$cp.Name
                $k  = $nm.ToLowerInvariant()
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true
                $pStat = 0
                if ($null -ne $cp.PrinterStatus) { $pStat = [int]$cp.PrinterStatus }
                $pAttr = [uint32]0
                if ($null -ne $cp.Attributes) { $pAttr = [uint32]([int64]$cp.Attributes -band [int64]0xFFFFFFFF) }
                $outList.Add([pscustomobject]@{
                    Name            = $nm
                    DriverName      = [string]$cp.DriverName
                    PortName        = [string]$cp.PortName
                    Default         = [bool]$cp.Default
                    Network         = [bool]$cp.Network
                    ServerName      = [string]$cp.ServerName
                    ShareName       = [string]$cp.ShareName
                    WorkOffline     = [bool]$cp.WorkOffline
                    PrinterStatus   = $pStat
                    Attributes      = $pAttr
                    _NativeFallback = $true
                })
            }
        } catch {}
    }

    # 3순위: 스풀러·WMI 모두 응답 불가 시 레지스트리 직접 폴백
    if ($outList.Count -eq 0) {
        $defPrtReg = ''
        try {
            $devRaw = [string](Get-ItemProperty -LiteralPath 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'Device' -ErrorAction SilentlyContinue).Device
            if ($devRaw -match '^([^,]+)') { $defPrtReg = $matches[1].Trim() }
        } catch {}
        try {
            $prtRegRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers'
            if (Test-Path -LiteralPath $prtRegRoot) {
                foreach ($pk in @(Get-ChildItem -LiteralPath $prtRegRoot -ErrorAction SilentlyContinue)) {
                    $nm = [string]$pk.PSChildName
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $k = $nm.ToLowerInvariant()
                    if ($seen.ContainsKey($k)) { continue }
                    $rp   = Get-ItemProperty -LiteralPath $pk.PSPath -ErrorAction SilentlyContinue
                    $drv  = ''
                    $port = ''
                    $attr = [uint32]0
                    if ($rp) {
                        if ($rp.PSObject.Properties.Name -contains 'Printer Driver') { $drv = [string]$rp.'Printer Driver' }
                        if ($rp.PSObject.Properties.Name -contains 'Port')           { $port = [string]$rp.Port }
                        if ($rp.PSObject.Properties.Name -contains 'Attributes' -and $null -ne $rp.Attributes) {
                            $attr = [uint32]([int64]$rp.Attributes -band [int64]0xFFFFFFFF)
                        }
                    }
                    $seen[$k] = $true
                    $outList.Add([pscustomobject]@{
                        Name            = $nm
                        DriverName      = $drv
                        PortName        = $port
                        Default         = ((-not [string]::IsNullOrWhiteSpace($defPrtReg)) -and ($nm -ieq $defPrtReg))
                        Network         = $nm.StartsWith('\\')
                        ServerName      = ''
                        ShareName       = ''
                        WorkOffline     = (($attr -band [uint32]0x00000400) -ne 0)
                        PrinterStatus   = 0
                        Attributes      = $attr
                        _NativeFallback = $true
                    })
                }
            }
        } catch {}
        try {
            $connRegRoot = 'HKCU:\Printers\Connections'
            if (Test-Path -LiteralPath $connRegRoot) {
                foreach ($ck in @(Get-ChildItem -LiteralPath $connRegRoot -ErrorAction SilentlyContinue)) {
                    # 레지스트리 키 이름: ,,Server,Share 형식 -> \\Server\Share 복원
                    $rawKey = [string]$ck.PSChildName
                    $uncPrt = ($rawKey -replace '^,+', '\\') -replace ',', '\'
                    if (-not $uncPrt.StartsWith('\\')) { continue }
                    $k = $uncPrt.ToLowerInvariant()
                    if ($seen.ContainsKey($k)) { continue }
                    $cpProps = Get-ItemProperty -LiteralPath $ck.PSPath -ErrorAction SilentlyContinue
                    $srvN = ''
                    if ($cpProps -and ($cpProps.PSObject.Properties.Name -contains 'Server')) { $srvN = [string]$cpProps.Server }
                    $seen[$k] = $true
                    $outList.Add([pscustomobject]@{
                        Name            = $uncPrt
                        DriverName      = ''
                        PortName        = $uncPrt
                        Default         = ((-not [string]::IsNullOrWhiteSpace($defPrtReg)) -and ($uncPrt -ieq $defPrtReg))
                        Network         = $true
                        ServerName      = $srvN
                        ShareName       = ([IO.Path]::GetFileName($uncPrt))
                        WorkOffline     = $false
                        PrinterStatus   = 0
                        Attributes      = [uint32]0x00000010
                        _NativeFallback = $true
                    })
                }
            }
        } catch {}
    }

    return @($outList.ToArray())
}

function Get-LocalTcpPrinterPortsSafe {
    $ports = [System.Collections.Generic.List[object]]::new()
    $seen  = @{}

    # 1순위: 레지스트리 직접 조회 (Win32_TCPIPPrinterPort WMI 클래스 손상 완전 우회)
    try {
        $tcpRegRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports'
        if (Test-Path -LiteralPath $tcpRegRoot) {
            foreach ($pk in @(Get-ChildItem -LiteralPath $tcpRegRoot -ErrorAction SilentlyContinue)) {
                $pName = [string]$pk.PSChildName
                if ([string]::IsNullOrWhiteSpace($pName)) { continue }
                $props = Get-ItemProperty -LiteralPath $pk.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $hostAddr = ''
                if ($props.PSObject.Properties.Name -contains 'HostName' -and -not [string]::IsNullOrWhiteSpace([string]$props.HostName)) {
                    $hostAddr = [string]$props.HostName
                } elseif ($props.PSObject.Properties.Name -contains 'IPAddress' -and -not [string]::IsNullOrWhiteSpace([string]$props.IPAddress)) {
                    $hostAddr = [string]$props.IPAddress
                }
                if ([string]::IsNullOrWhiteSpace($hostAddr) -and (Test-IsUsableIPv4 -IpText $pName)) {
                    $hostAddr = $pName
                }

                $proto = 1
                if ($props.PSObject.Properties.Name -contains 'Protocol' -and $null -ne $props.Protocol) {
                    $proto = [int]$props.Protocol
                }
                $portNum = [uint32]9100
                if ($proto -eq 2) { $portNum = [uint32]515 }
                if ($props.PSObject.Properties.Name -contains 'PortNumber' -and $null -ne $props.PortNumber -and [int64]$props.PortNumber -gt 0) {
                    $portNum = [uint32]$props.PortNumber
                }
                $queueName = ''
                if ($props.PSObject.Properties.Name -contains 'Queue') { $queueName = [string]$props.Queue }
                $byteCnt = $false
                if ($props.PSObject.Properties.Name -contains 'LPR Byte Counting' -and $null -ne $props.'LPR Byte Counting') {
                    $byteCnt = ([int]$props.'LPR Byte Counting' -ne 0)
                }
                $snmpOn = $false
                if ($props.PSObject.Properties.Name -contains 'SNMP Enabled' -and $null -ne $props.'SNMP Enabled') {
                    $snmpOn = ([int]$props.'SNMP Enabled' -ne 0)
                }

                $seen[$pName.ToLowerInvariant()] = $true
                $ports.Add([pscustomobject]@{
                    Name        = $pName
                    HostAddress = $hostAddr
                    Protocol    = $proto
                    PortNumber  = $portNum
                    Queue       = $queueName
                    ByteCount   = $byteCnt
                    SNMPEnabled = $snmpOn
                })
            }
        }
    } catch {}

    # 2순위: 레지스트리에 없는 항목 보충용 WMI 조회 (오류 무시)
    try {
        foreach ($tp in @(Get-CimInstance -ClassName Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue)) {
            if (-not $tp -or [string]::IsNullOrWhiteSpace([string]$tp.Name)) { continue }
            $k = ([string]$tp.Name).ToLowerInvariant()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $ports.Add([pscustomobject]@{
                Name        = [string]$tp.Name
                HostAddress = [string]$tp.HostAddress
                Protocol    = [int]$tp.Protocol
                PortNumber  = [uint32]$tp.PortNumber
                Queue       = [string]$tp.Queue
                ByteCount   = [bool]$tp.ByteCount
                SNMPEnabled = [bool]$tp.SNMPEnabled
            })
        }
    } catch {}

    return @($ports.ToArray())
}

function Get-PrinterSafe {
    try {
        $res = @(Get-Printer -ErrorAction Stop)
        if ($res.Count -gt 0) { return $res }
    } catch {}
    return @(Get-LocalPrintersSafe)
}

function Get-PrinterPortSafe {
    try {
        $res = @(Get-PrinterPort -ErrorAction Stop)
        if ($res.Count -gt 0) { return $res }
    } catch {}

    $list = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($tp in @(Get-LocalTcpPrinterPortsSafe)) {
        $k = ([string]$tp.Name).ToLowerInvariant()
        if (-not $seen.ContainsKey($k)) {
            $seen[$k] = $true
            $list.Add([pscustomobject]@{ Name = [string]$tp.Name; PrinterHostAddress = [string]$tp.HostAddress })
        }
    }
    try {
        $monRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors'
        if (Test-Path -LiteralPath $monRoot) {
            foreach ($mon in @(Get-ChildItem -LiteralPath $monRoot -ErrorAction SilentlyContinue)) {
                $pSub = Join-Path $mon.PSPath 'Ports'
                if (Test-Path -LiteralPath $pSub) {
                    foreach ($pk in @(Get-ChildItem -LiteralPath $pSub -ErrorAction SilentlyContinue)) {
                        $nm = [string]$pk.PSChildName
                        if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                        $k = $nm.ToLowerInvariant()
                        if (-not $seen.ContainsKey($k)) {
                            $seen[$k] = $true
                            $list.Add([pscustomobject]@{ Name = $nm; PrinterHostAddress = '' })
                        }
                    }
                }
            }
        }
    } catch {}
    try {
        $ntPortsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports'
        if (Test-Path -LiteralPath $ntPortsKey) {
            $ntProps = Get-ItemProperty -LiteralPath $ntPortsKey -ErrorAction SilentlyContinue
            if ($ntProps) {
                foreach ($pr in $ntProps.PSObject.Properties) {
                    if ($pr.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
                    $nm = ([string]$pr.Name).Trim()
                    if ([string]::IsNullOrWhiteSpace($nm)) { continue }
                    $k = $nm.ToLowerInvariant()
                    $kNoColon = $k.TrimEnd(':')
                    if ((-not $seen.ContainsKey($k)) -and (-not $seen.ContainsKey($kNoColon))) {
                        $seen[$k] = $true
                        $list.Add([pscustomobject]@{ Name = $nm; PrinterHostAddress = '' })
                    }
                }
            }
        }
    } catch {}
    foreach ($lp in @(Get-LocalPrintersSafe)) {
        foreach ($rawP in @(([string]$lp.PortName) -split ',')) {
            $pn = $rawP.Trim()
            if ([string]::IsNullOrWhiteSpace($pn)) { continue }
            $k = $pn.ToLowerInvariant()
            if (-not $seen.ContainsKey($k)) {
                $seen[$k] = $true
                $list.Add([pscustomobject]@{ Name = $pn; PrinterHostAddress = '' })
            }
        }
    }
    return @($list.ToArray())
}

function Get-PrinterDriverSafe {
    try {
        $res = @(Get-PrinterDriver -ErrorAction Stop)
        if ($res.Count -gt 0) { return $res }
    } catch {}

    $list = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($envPair in @(
        @{ Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers'; Env = 'Windows x64' },
        @{ Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows NT x86\Drivers'; Env = 'Windows x86' }
    )) {
        try {
            if (-not (Test-Path -LiteralPath $envPair.Key)) { continue }
            foreach ($verSub in @(Get-ChildItem -LiteralPath $envPair.Key -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Version-*' })) {
                foreach ($dk in @(Get-ChildItem -LiteralPath $verSub.PSPath -ErrorAction SilentlyContinue)) {
                    $dName = [string]$dk.PSChildName
                    if ([string]::IsNullOrWhiteSpace($dName)) { continue }
                    $uniqKey = "$($envPair.Env)|$($dName.ToLowerInvariant())"
                    if ($seen.ContainsKey($uniqKey)) { continue }
                    $seen[$uniqKey] = $true
                    $dp  = Get-ItemProperty -LiteralPath $dk.PSPath -ErrorAction SilentlyContinue
                    $inf = ''
                    if ($dp -and ($dp.PSObject.Properties.Name -contains 'InfPath')) { $inf = [string]$dp.InfPath }
                    $list.Add([pscustomobject]@{
                        Name               = $dName
                        InfPath            = $inf
                        PrinterEnvironment = $envPair.Env
                        _NativeFallback    = $true
                    })
                }
            }
        } catch {}
    }
    return @($list.ToArray())
}

function Get-ActiveNetworkInfo {
    $ip          = 'NO_IP'
    $gw          = $null
    $adapterName = ''
    $bestIfIdx   = -1
    $dnsListOut  = @()

    $excludeNameRegex = '(?i)^(Loopback|Teredo|isatap)|Bluetooth|TAP-Windows|Npcap Loopback'
    $virtualOnlyRegex = '(?i)(vEthernet|Hyper-V|VMware|VMnet|VirtualBox|WSL|Docker|ZeroTier|Tailscale|WireGuard|Mirage|Goodus|Pseudo)'
    $candidates       = [System.Collections.Generic.List[object]]::new()

    # 1순위: WMI/CIM(Get-NetAdapter/Get-NetIPConfiguration) 완전 배제 -> 순수 .NET NetworkInterface 직접 조회 (클래스 오류 0%)
    try {
        foreach ($nic in @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces())) {
            if (-not $nic) { continue }
            if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
            if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -or
                $nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel) { continue }

            $nName = [string]$nic.Name
            $nDesc = [string]$nic.Description
            if ($nName -match $excludeNameRegex -or $nDesc -match $excludeNameRegex) { continue }

            $ipProps = $null
            try { $ipProps = $nic.GetIPProperties() } catch { continue }
            if (-not $ipProps) { continue }

            $gwIp  = $null
            $hasGw = $false
            foreach ($ga in @($ipProps.GatewayAddresses)) {
                if ($ga -and $ga.Address -and $ga.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $gStr = $ga.Address.IPAddressToString
                    if (Test-IsUsableIPv4 -IpText $gStr) {
                        $gwIp  = $gStr
                        $hasGw = $true
                        break
                    }
                }
            }

            $usableIps = [System.Collections.Generic.List[string]]::new()
            foreach ($ua in @($ipProps.UnicastAddresses)) {
                if (-not $ua -or -not $ua.Address) { continue }
                if ($ua.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                $candStr = $ua.Address.IPAddressToString
                if (Test-IsUsableIPv4 -IpText $candStr) {
                    $usableIps.Add($candStr)
                }
            }
            if ($usableIps.Count -eq 0) { continue }

            $usableIp = $usableIps[0]
            if ($hasGw -and $usableIps.Count -gt 1 -and $gwIp -match '^(\d+\.\d+\.)') {
                $gwPfx = $matches[1]
                foreach ($uCand in $usableIps) {
                    if ($uCand.StartsWith($gwPfx)) { $usableIp = $uCand; break }
                }
            }

            $nicDns = [System.Collections.Generic.List[string]]::new()
            foreach ($da in @($ipProps.DnsAddresses)) {
                if ($da -and $da.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $nicDns.Add($da.IPAddressToString)
                }
            }

            $ifIdx = -1
            try {
                $v4p = $ipProps.GetIPv4Properties()
                if ($v4p) { $ifIdx = [int]$v4p.Index }
            } catch {}

            $isVirtualSwitch = ($nName -match $virtualOnlyRegex -or $nDesc -match $virtualOnlyRegex)
            $isPhys = ($nic.NetworkInterfaceType -in @(
                [System.Net.NetworkInformation.NetworkInterfaceType]::Ethernet,
                [System.Net.NetworkInformation.NetworkInterfaceType]::Wireless80211,
                [System.Net.NetworkInformation.NetworkInterfaceType]::GigabitEthernet,
                [System.Net.NetworkInformation.NetworkInterfaceType]::FastEthernetT,
                [System.Net.NetworkInformation.NetworkInterfaceType]::FastEthernetFx
            )) -and (-not $isVirtualSwitch) -and ($nDesc -notmatch '(?i)Virtual|VPN|Miniport')

            $hasAsanDns = ($nicDns -contains $global:AsanCtx.InternalDnsIP)
            # 망분리 VM/Host-Only 가상 스위치(게이트웨이·사내 DNS 모두 없음)가 오프라인 시 가짜 사내 IP로 오인되는 현상 차단
            if ((-not $isPhys) -and (-not $hasGw) -and (-not $hasAsanDns)) { continue }

            $tier = 5
            if ($hasAsanDns -and $hasGw) { $tier = 1 }
            elseif ($isPhys -and $hasGw) { $tier = 2 }
            elseif ($hasGw)              { $tier = 3 }
            elseif ($isPhys)             { $tier = 4 }

            $candidates.Add([pscustomobject]@{
                Tier           = $tier
                IPAddress      = $usableIp
                Gateway        = $gwIp
                AdapterName    = $nName
                InterfaceIndex = $ifIdx
                DnsServers     = $nicDns.ToArray()
            })
        }
    } catch {}

    # 2순위: 사내 백업 서버 방향 커널 라우팅 테이블 역추적 (패킷 전송 없음, 0.1ms)
    $routeLocalIp = $null
    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        try {
            $udp.Connect($global:AsanCtx.ServerIP, 445)
            $ep = [System.Net.IPEndPoint]$udp.Client.LocalEndPoint
            if ($ep -and $ep.Address) {
                $rStr = $ep.Address.IPAddressToString
                if (Test-IsUsableIPv4 -IpText $rStr) { $routeLocalIp = $rStr }
            }
        } finally {
            $udp.Close()
        }
    } catch {}

    $best = $null
    if ($routeLocalIp) {
        $best = $candidates | Where-Object { $_.IPAddress -eq $routeLocalIp } | Sort-Object Tier | Select-Object -First 1
    }
    if (-not $best) {
        $best = $candidates | Sort-Object Tier | Select-Object -First 1
    }

    if ($best) {
        $ip          = $best.IPAddress
        $gw          = $best.Gateway
        $adapterName = $best.AdapterName
        $bestIfIdx   = [int]$best.InterfaceIndex
        $dnsListOut  = @($best.DnsServers)
    } elseif ($routeLocalIp) {
        $ip          = $routeLocalIp
        $adapterName = 'RouteDetected'
    }

    return [pscustomobject]@{
        IPAddress      = $ip
        Gateway        = $gw
        AdapterName    = $adapterName
        InterfaceIndex = $bestIfIdx
        DnsServers     = $dnsListOut
        HasValidIP     = (Test-IsUsableIPv4 -IpText $ip)
    }
}

function Get-QualifiedRemoteUser {
    param(
        [string]$HostName,
        [string]$UserName
    )
    if ([string]::IsNullOrWhiteSpace($UserName)) { return $UserName }
    if ($UserName -match '[\\@]' -or [string]::IsNullOrWhiteSpace($HostName)) { return $UserName }
    return "$HostName\$UserName"
}

function Disconnect-AllHostSessions {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    [void][AsanWin32.NativeApi]::DisconnectShare("\\$HostName\IPC$")
    if ($HostName -ieq $global:AsanCtx.ServerIP) {
        foreach ($candShare in @($global:AsanCtx.CandidateShares)) {
            [void][AsanWin32.NativeApi]::DisconnectShare([string]$candShare)
        }
    }
    try {
        $conns = @(Get-SmbConnection -ErrorAction SilentlyContinue | Where-Object { $_.ServerName -ieq $HostName })
        foreach ($c in $conns) {
            [void][AsanWin32.NativeApi]::DisconnectShare("\\$($c.ServerName)\$($c.ShareName)")
        }
    } catch {}
    try {
        $maps = @(Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object { $_.RemotePath -like "\\$HostName\*" })
        foreach ($mp in $maps) {
            if (-not [string]::IsNullOrWhiteSpace([string]$mp.LocalPath)) {
                [void][AsanWin32.NativeApi]::DisconnectShare([string]$mp.LocalPath)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$mp.RemotePath)) {
                [void][AsanWin32.NativeApi]::DisconnectShare([string]$mp.RemotePath)
            }
        }
    } catch {}
}

function Get-RemoteUserCandidates {
    param(
        [string]$HostName,
        [string]$UserName
    )
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($UserName)) { return @() }
    $u = $UserName.Trim()
    if ($u -match '[\\@]') {
        $list.Add($u)
        $plain = ($u -split '[\\@]')[-1]
        if (-not [string]::IsNullOrWhiteSpace($plain) -and -not $list.Contains($plain)) { $list.Add($plain) }
        return @($list.ToArray())
    }
    # NAS/Samba/Windows 파일서버 모두 호환되도록 단독 계정명(admin) -> IP\admin -> .\admin 순차 시도
    $list.Add($u)
    if (-not [string]::IsNullOrWhiteSpace($HostName)) {
        $q = "$HostName\$u"
        if (-not $list.Contains($q)) { $list.Add($q) }
    }
    $dot = ".\$u"
    if (-not $list.Contains($dot)) { $list.Add($dot) }
    return @($list.ToArray())
}

function Resolve-AsanBackupShareRoot {
    param([string]$ServerIp = $global:AsanCtx.ServerIP)
    foreach ($s in @($global:AsanCtx.CandidateShares)) {
        try {
            if (Test-Path -LiteralPath $s) { return [string]$s }
        } catch {}
    }
    try {
        $diskRes = [AsanWin32.NativeApi]::EnumDiskSharesEx("\\$ServerIp")
        if ($diskRes -and ($diskRes.Win32Error -eq 0 -or $diskRes.Win32Error -eq 234) -and $diskRes.Shares) {
            foreach ($sh in @($diskRes.Shares)) {
                if ([string]::IsNullOrWhiteSpace($sh) -or $sh.EndsWith('$')) { continue }
                $unc = "\\$ServerIp\$sh"
                if ($sh -match '(?i)백업|backup|prtbak') {
                    try { if (Test-Path -LiteralPath $unc) { return $unc } } catch {}
                }
            }
            foreach ($sh in @($diskRes.Shares)) {
                if ([string]::IsNullOrWhiteSpace($sh) -or $sh.EndsWith('$')) { continue }
                $unc = "\\$ServerIp\$sh"
                try {
                    if (Test-Path -LiteralPath (Join-Path $unc '_PRTBAK')) { return $unc }
                } catch {}
            }
        }
    } catch {}
    return $null
}

function Initialize-AsanPrtBakDirectory {
    param([string]$ActiveShare)
    if ([string]::IsNullOrWhiteSpace($ActiveShare)) { return $null }
    $prtBakDir = Join-Path $ActiveShare '_PRTBAK'
    try {
        if (-not (Test-Path -LiteralPath $prtBakDir)) {
            $dirItem = New-Item -ItemType Directory -Path $prtBakDir -Force -ErrorAction Stop
            try { $dirItem.Attributes = $dirItem.Attributes -bor [IO.FileAttributes]::Hidden } catch {}
        } else {
            try {
                $dirItem = Get-Item -LiteralPath $prtBakDir -Force -ErrorAction Stop
                if (($dirItem.Attributes -band [IO.FileAttributes]::Hidden) -eq 0) {
                    $dirItem.Attributes = $dirItem.Attributes -bor [IO.FileAttributes]::Hidden
                }
            } catch {}
        }
    } catch {
        if (-not (Test-Path -LiteralPath $prtBakDir)) { return $null }
    }
    return $prtBakDir
}

function Connect-AsanBackupServer {
    $srvIp = $global:AsanCtx.ServerIP
    $global:AsanCtx.LastServerAuthDiag = ''
    if (-not (Test-TcpPortFast -HostIp $srvIp -Port 445 -TimeoutMs 2200)) {
        $global:AsanCtx.LastServerAuthDiag = 'TCP445_CLOSED'
        return $null
    }

    [void](Import-RuntimeSecretsIfPresent)

    # 1단계: 이미 열려 있는 세션/기본 권한으로 바로 접근 가능한지 먼저 확인 (불필요한 세션 끊기 방지)
    $activeShare = Resolve-AsanBackupShareRoot -ServerIp $srvIp
    if ($activeShare) {
        $resDir = Initialize-AsanPrtBakDirectory -ActiveShare $activeShare
        if ($resDir) {
            $global:AsanCtx.LastServerAuthDiag = "EXISTING_SESSION_OK($activeShare)"
            return $resDir
        }
    }

    # 2단계: 내장/외부 암호 목록 x 다중 계정 포맷(admin, IP\admin, .\admin)으로 공유폴더 직접 연결 및 IPC$ 병행 시도
    $ipcPath    = "\\$srvIp\IPC$"
    $userCands  = @(Get-RemoteUserCandidates -HostName $srvIp -UserName (Get-EffectiveDefaultUser))
    $pwCands    = @(Get-ConfiguredDefaultPasswords)
    $diagCodes  = [System.Collections.Generic.List[string]]::new()
    $didReset1219 = $false

    foreach ($pw in $pwCands) {
        foreach ($uFmt in $userCands) {
            # (A) 공유 후보 직접 인증 시도 (IPC$ 제한 서버/NAS 호환)
            foreach ($candShare in @($global:AsanCtx.CandidateShares)) {
                $rcS = [AsanWin32.NativeApi]::ConnectShare([string]$candShare, $uFmt, $pw)
                if ($rcS -eq 1219 -and (-not $didReset1219)) {
                    $didReset1219 = $true
                    $chk1219 = Resolve-AsanBackupShareRoot -ServerIp $srvIp
                    if ($chk1219) { $activeShare = $chk1219; break }
                    Disconnect-AllHostSessions -HostName $srvIp
                    $rcS = [AsanWin32.NativeApi]::ConnectShare([string]$candShare, $uFmt, $pw)
                }
                if ($rcS -eq 0 -or $rcS -eq 85 -or (Test-Path -LiteralPath $candShare)) {
                    if (Test-Path -LiteralPath $candShare) {
                        $activeShare = [string]$candShare
                        break
                    }
                } else {
                    $codeTag = "Share:$rcS"
                    if (-not $diagCodes.Contains($codeTag)) { $diagCodes.Add($codeTag) }
                }
            }
            if ($activeShare) { break }

            # (B) IPC$ 인증 후 디스크 공유 탐색 (공유명이 다를 경우 자동 발견 포함)
            [void][AsanWin32.NativeApi]::DisconnectShare($ipcPath)
            $rcI = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $uFmt, $pw)
            if ($rcI -eq 1219 -and (-not $didReset1219)) {
                $didReset1219 = $true
                Disconnect-AllHostSessions -HostName $srvIp
                $rcI = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $uFmt, $pw)
            }
            if ($rcI -eq 0 -or $rcI -eq 1219) {
                $activeShare = Resolve-AsanBackupShareRoot -ServerIp $srvIp
                if (-not $activeShare) {
                    foreach ($s in @($global:AsanCtx.CandidateShares)) {
                        [void][AsanWin32.NativeApi]::ConnectShare([string]$s, $uFmt, $pw)
                        if (Test-Path -LiteralPath $s) { $activeShare = [string]$s; break }
                    }
                }
                if ($activeShare) { break }
            } else {
                $codeTagI = "IPC:$rcI"
                if (-not $diagCodes.Contains($codeTagI)) { $diagCodes.Add($codeTagI) }
            }
        }
        if ($activeShare) { break }
    }

    if (-not $activeShare) {
        $global:AsanCtx.LastServerAuthDiag = "AUTH_FAIL(" + ($diagCodes -join ',') + ")"
        return $null
    }

    $finalDir = Initialize-AsanPrtBakDirectory -ActiveShare $activeShare
    if (-not $finalDir) {
        $global:AsanCtx.LastServerAuthDiag = "PRTBAK_CREATE_FAIL($activeShare)"
        return $null
    }
    $global:AsanCtx.LastServerAuthDiag = "CONNECTED($activeShare)"
    return $finalDir
}

function Connect-AsanBackupServerWithCred {
    param(
        [string]$UserName,
        [string]$Password
    )
    $srvIp = $global:AsanCtx.ServerIP
    $u = [string]$UserName
    if ([string]::IsNullOrWhiteSpace($u)) { $u = Get-EffectiveDefaultUser }
    $u = $u.Trim()
    $p = [string]$Password
    if ([string]::IsNullOrEmpty($p)) {
        return [pscustomobject]@{ Ok = $false; PrtBakDir = $null; ErrorCode = 87; Message = '암호를 입력해 주세요.' }
    }
    if (-not (Test-TcpPortFast -HostIp $srvIp -Port 445 -TimeoutMs 2500)) {
        return [pscustomobject]@{ Ok = $false; PrtBakDir = $null; ErrorCode = 53; Message = "백업 서버($srvIp)에 연결할 수 없습니다. 사내망 연결 상태를 확인해 주세요." }
    }

    $ipcPath     = "\\$srvIp\IPC$"
    $userCands   = @(Get-RemoteUserCandidates -HostName $srvIp -UserName $u)
    $activeShare = $null
    $lastRc      = 0

    Disconnect-AllHostSessions -HostName $srvIp

    foreach ($uFmt in $userCands) {
        foreach ($candShare in @($global:AsanCtx.CandidateShares)) {
            $rcS = [AsanWin32.NativeApi]::ConnectShare([string]$candShare, $uFmt, $p)
            if ($rcS -eq 1219) {
                if (Test-Path -LiteralPath $candShare) { $activeShare = [string]$candShare; break }
                Disconnect-AllHostSessions -HostName $srvIp
                $rcS = [AsanWin32.NativeApi]::ConnectShare([string]$candShare, $uFmt, $p)
            }
            if ($rcS -eq 0 -or (Test-Path -LiteralPath $candShare)) {
                $activeShare = [string]$candShare
                break
            }
            $lastRc = $rcS
        }
        if ($activeShare) { break }

        [void][AsanWin32.NativeApi]::DisconnectShare($ipcPath)
        $rcI = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $uFmt, $p)
        if ($rcI -eq 0 -or $rcI -eq 1219) {
            $activeShare = Resolve-AsanBackupShareRoot -ServerIp $srvIp
            if ($activeShare) { break }
        } else {
            $lastRc = $rcI
        }
    }

    if (-not $activeShare) {
        $errMsg = "백업 서버($srvIp) 연결에 실패했습니다 (Win32 오류 코드: $lastRc)."
        if ($lastRc -in @(5, 86, 1326, 1331, 1909)) {
            $errMsg = "아이디 또는 암호가 일치하지 않습니다 (오류 코드 $lastRc). 계정 정보를 다시 확인해 주세요."
        } elseif ($lastRc -eq 1272) {
            $errMsg = 'Windows 11 24H2 보안 정책이 게스트 공유 연결을 차단했습니다 (오류 코드 1272). 서버 계정과 암호를 다시 확인해 주세요.'
        } elseif ($lastRc -eq 384) {
            $errMsg = '대상 서버가 구형 SMB1 프로토콜만 요구하여 연결이 차단되었습니다 (오류 코드 384).'
        } elseif ($lastRc -eq 1219) {
            $errMsg = '윈도우 탐색기 등에 다른 계정으로 서버가 이미 연결되어 있습니다. 열린 서버 폴더 창을 닫고 다시 시도해 주세요.'
        } elseif ($lastRc -eq 67 -or $lastRc -eq 53) {
            $errMsg = "백업 공유 폴더($($global:AsanCtx.CandidateShares -join ' 또는 '))를 찾지 못했습니다 (오류 코드 $lastRc)."
        }
        return [pscustomobject]@{ Ok = $false; PrtBakDir = $null; ErrorCode = $lastRc; Message = $errMsg }
    }

    $merged = [System.Collections.Generic.List[string]]::new()
    $merged.Add($p)
    foreach ($cur in @($global:AsanCtx.RuntimePasswords)) {
        $cs = [string]$cur
        if (-not [string]::IsNullOrWhiteSpace($cs) -and (-not $merged.Contains($cs))) { $merged.Add($cs) }
    }
    $global:AsanCtx.RuntimeUser      = $u
    $global:AsanCtx.RuntimePasswords = @($merged.ToArray())
    if ([string]::IsNullOrWhiteSpace([string]$global:AsanCtx.RuntimeSecretsSource)) {
        $global:AsanCtx.RuntimeSecretsSource = '수동 로그인'
    }

    $prtBakDir = Initialize-AsanPrtBakDirectory -ActiveShare $activeShare
    if (-not $prtBakDir) {
        return [pscustomobject]@{ Ok = $false; PrtBakDir = $null; ErrorCode = 5; Message = "공유 폴더($activeShare)에는 연결되었으나 하위 _PRTBAK 폴더 접근 권한이 없습니다." }
    }

    return [pscustomobject]@{
        Ok        = $true
        PrtBakDir = $prtBakDir
        ErrorCode = 0
        Message   = "백업 서버($srvIp)에 연결되었습니다."
    }
}

function Test-AsanNetworkAndServer {
    [void](Import-RuntimeSecretsIfPresent)
    $netInfo       = Get-ActiveNetworkInfo
    $wppInfo       = Test-WindowsProtectedPrintMode
    $dnsConf       = (@($netInfo.DnsServers) -contains $global:AsanCtx.InternalDnsIP)
    $dnsOk         = $false
    $serverTcp     = $false
    $serverAuthReq = $false
    $prtBakDir     = $null
    $status        = 'Offline'
    $message       = '사내망 미연결 — 고정 IP 및 DNS(10.71.1.5)를 먼저 설정해 주세요.'
    $hasCfgPws     = ((@(Get-ConfiguredDefaultPasswords)).Count -gt 0)

    # [핵심 수정] 어댑터 IP 판별 결과와 무관하게 백업 서버(445) 도달 여부를 항상 직접 확인
    $serverTcp = Test-TcpPortFast -HostIp $global:AsanCtx.ServerIP -Port 445 -TimeoutMs 2000
    if ($serverTcp -or $netInfo.HasValidIP) {
        $dnsOk = (Test-TcpPortFast -HostIp $global:AsanCtx.InternalDnsIP -Port 53 -TimeoutMs 1200) -or (Test-PingFast -HostIp $global:AsanCtx.InternalDnsIP -TimeoutMs 1000)
    }

    if ($serverTcp) {
        $prtBakDir = Connect-AsanBackupServer
        if ($prtBakDir) {
            $status  = 'Online'
            $message = "사내망 및 백업 서버 정상 연결됨 ($prtBakDir)"
        } else {
            $status        = 'IntranetOnly'
            $serverAuthReq = $true
            $diagNote      = [string]$global:AsanCtx.LastServerAuthDiag
            $message       = "백업 서버($($global:AsanCtx.ServerIP)) 공유 폴더 인증에 실패했습니다 [$diagNote]. 상단 '서버 로그인'으로 계정을 확인해 주세요."
        }
    } elseif ($dnsOk -or ($netInfo.HasValidIP -and $dnsConf -and $netInfo.Gateway -and (Test-PingFast -HostIp $netInfo.Gateway -TimeoutMs 1000))) {
        $status  = 'IntranetOnly'
        $message = "사내망은 연결되었으나 백업 서버($($global:AsanCtx.ServerIP))가 응답하지 않습니다."
    }

    return [pscustomobject]@{
        Status                 = $status
        Message                = $message
        IPAddress              = $netInfo.IPAddress
        Gateway                = $netInfo.Gateway
        AdapterName            = $netInfo.AdapterName
        DnsOk                  = $dnsOk
        ServerTcpOk            = $serverTcp
        ServerAuthRequired     = $serverAuthReq
        ServerAuthDiag         = [string]$global:AsanCtx.LastServerAuthDiag
        HasConfiguredPasswords = $hasCfgPws
        SecretsLoadedFrom      = $global:AsanCtx.RuntimeSecretsSource
        PrtBakDir              = $prtBakDir
        WppStatus              = $wppInfo
    }
}

# ============================================================================
# 가상 프린터 제외 및 특수/라벨 프린터 4종 분류기
# ============================================================================
function Test-IsVirtualPrinter {
    param(
        [string]$PrinterName,
        [string]$PortName
    )
    if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
        if ($global:AsanCtx.VirtualPrinterExact -contains $PrinterName) { return $true }
        if ($PrinterName -match $global:AsanCtx.VirtualPrinterRegex) { return $true }
    }
    if (-not [string]::IsNullOrWhiteSpace($PortName)) {
        if ($PortName -match $global:AsanCtx.VirtualPortRegex) { return $true }
    }
    return $false
}

function Get-SpecialPrinterProfile {
    param(
        [string]$PrinterName,
        [string]$DriverName,
        [string]$PortName
    )
    $combined = "$PrinterName | $DriverName"
    $isShared = ($PortName -match '^\\\\') -or ($PrinterName -match '^\\\\')

    if ($combined -match '(?i)SIP-30|HODOO|SISS' -or $PrinterName -match '(?i)^id카드$') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'SIP30M_IDCARD'
            Label              = '진료카드 SIP-30M'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $true
        }
    }
    if ($combined -match '(?i)SLK-TE|LK-TE|Sewoo|POS PRINTER' -or $PortName -match '(?i)^USBPOS') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'SEWOO_TE201'
            Label              = '네임바코드 세우'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $true
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }
    if ($combined -match '(?i)ZT410|ZT411') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'ZEBRA_ZT411'
            Label              = '라벨 ZT410/411'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }
    if ($combined -match '(?i)ZDesigner|ZD410|ZD411|Zebra') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'ZD410_411'
            Label              = '검사·투약 ZD410'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }
    if ($combined -match '(?i)BIXOLON|SLP-TX220|TX220|TX-220') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'BIXOLON_TX220'
            Label              = '팔찌바코드 TX220'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }
    if ($combined -match '(?i)TM-?T88|TMT88') {
        $isLptTm = ([string]::IsNullOrWhiteSpace($PortName)) -or ($PortName -match '(?i)^LPT')
        if ($isLptTm) {
            return [pscustomobject]@{
                IsSpecial          = $true
                Type               = 'EPSON_TMT88_LPT'
                Label              = 'LPT1 무드라이버'
                ExcludeFromPcl6    = $true
                ExcludeBulkTest    = $true
                Win11ReinstallOnly = $false
                NoDriverBackup     = $true
                IsSubPcShared      = $isShared
                SkipAliveFilter    = $true
            }
        }
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'OTHER_SPECIAL'
            Label              = '영수증 TM-T88'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }
    if ($combined -match '(?i)Barcode|Label|\bTSC\b|SATO|Honeywell|Citizen|Dymo|Brother QL|Thermal|Receipt') {
        return [pscustomobject]@{
            IsSpecial          = $true
            Type               = 'OTHER_SPECIAL'
            Label              = '기타 특수장비'
            ExcludeFromPcl6    = $true
            ExcludeBulkTest    = $true
            Win11ReinstallOnly = $false
            NoDriverBackup     = $false
            IsSubPcShared      = $isShared
            SkipAliveFilter    = $false
        }
    }

    return [pscustomobject]@{
        IsSpecial          = $false
        Type               = 'STANDARD'
        Label              = '일반'
        ExcludeFromPcl6    = $false
        ExcludeBulkTest    = $false
        Win11ReinstallOnly = $false
        NoDriverBackup     = $false
        IsSubPcShared      = $false
        SkipAliveFilter    = $false
    }
}

function Get-DeviceManagerLptPorts {
    $lpts = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    try {
        $portDevs = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "ClassGuid = '{4d36e978-e325-11ce-bfc1-08002be2092f}'" -ErrorAction SilentlyContinue)
        foreach ($d in $portDevs) {
            $dName = [string]$d.Name
            $m = [regex]::Match($dName, '\((LPT\d+)\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) {
                $pTag    = $m.Groups[1].Value.ToUpperInvariant()
                $stat    = [string]$d.Status
                $errCode = 0
                if ($null -ne $d.ConfigManagerErrorCode) { $errCode = [int]$d.ConfigManagerErrorCode }
                $seen[$pTag] = $true
                $lpts.Add([pscustomobject]@{
                    PortName  = $pTag
                    Name      = $dName
                    Status    = $stat
                    ErrorCode = $errCode
                    IsHealthy = ($errCode -eq 0 -and $stat -ieq 'OK')
                })
            }
        }
    } catch {}

    # 커널 DEVICEMAP 레지스트리를 항상 병행 조회 (WMI 손상 및 PCIe LPT 카드 이름에 '(LPT1)' 미표기 환경 완벽 보완)
    try {
        $parMapKey = 'HKLM:\HARDWARE\DEVICEMAP\PARALLEL PORTS'
        if (Test-Path -LiteralPath $parMapKey) {
            $pmProps = Get-ItemProperty -LiteralPath $parMapKey -ErrorAction SilentlyContinue
            if ($pmProps) {
                foreach ($pr in $pmProps.PSObject.Properties) {
                    if ($pr.Name -match '^PS(Path|ParentPath|ChildName|Drive|Provider)$') { continue }
                    $val = [string]$pr.Value
                    $m = [regex]::Match($val, '(LPT\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    if ($m.Success) {
                        $pTag = $m.Groups[1].Value.ToUpperInvariant()
                        if (-not $seen.ContainsKey($pTag)) {
                            $seen[$pTag] = $true
                            $lpts.Add([pscustomobject]@{
                                PortName  = $pTag
                                Name      = "프린터 포트 ($pTag)"
                                Status    = 'OK'
                                ErrorCode = 0
                                IsHealthy = $true
                            })
                        }
                    }
                }
            }
        }
    } catch {}
    return @($lpts.ToArray())
}

function Get-BrokenBarcodeUsbDevices {
    param([switch]$IncludeHealthyBarcode)

    # 검증된 바코드 프린터 VID/모델만 허용 (Zebra=0A5F, BIXOLON=1504; 범용 Netchip 0525 및 Win10 Sewoo 제외)
    $vidRegex     = '(?i)VID_(0A5F|1504)'
    $nameRegex    = '(?i)Zebra|ZDesigner|ZD410|ZD411|ZT410|ZT411|BIXOLON|SLP-TX|TX220|TX-220'
    $excludeRegex = '(?i)Sewoo|SLK-TE|LK-TE'

    $found  = [System.Collections.Generic.List[object]]::new()
    $wmiRan = $false
    try {
        $pnpAll = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
            ([string]$_.DeviceID) -match '^(?i)(USB\\VID_|USBPRINT\\)'
        })
        $wmiRan = $true
        foreach ($dev in $pnpAll) {
            $devId   = [string]$dev.DeviceID
            $devName = [string]$dev.Name
            $pnpCls  = [string]$dev.PNPClass
            $stat    = [string]$dev.Status
            $errCode = 0
            if ($null -ne $dev.ConfigManagerErrorCode) { $errCode = [int]$dev.ConfigManagerErrorCode }

            if (($devName -match $excludeRegex) -or ($devId -match $excludeRegex)) { continue }
            $isUsbPrint   = ($devId -match '^(?i)USBPRINT\\')
            $isBarcodeUsb = ($devId -match $vidRegex) -or ($devId -match $nameRegex) -or ($devName -match $nameRegex) -or ($isUsbPrint -and ($devId -match '(?i)ZTC'))
            if (-not $isBarcodeUsb) { continue }

            # 정상 동작 중인 USB Printing Support(PNPClass=USB, ErrorCode=0, Status=OK)는 절대 건드리지 않음
            # 반면 USBPRINT\ 자식 노드가 Printer/PrintQueue가 아니면 '지정되지 않음' 미결합 상태로 판정
            $isUnboundClass = [string]::IsNullOrWhiteSpace($pnpCls) -or ($pnpCls -match '(?i)^(Unknown|Other|OtherDevices)$')
            if ($isUsbPrint -and ($pnpCls -notmatch '(?i)^(Printer|PrintQueue)$')) {
                $isUnboundClass = $true
            }
            $isProblem = ($errCode -ne 0) -or ($stat -ine 'OK') -or $isUnboundClass

            $sortRank = 2
            if ($isUsbPrint) { $sortRank = 1 }

            if ($IncludeHealthyBarcode -or $isProblem) {
                $found.Add([pscustomobject]@{
                    DeviceID  = $devId
                    Name      = $devName
                    PNPClass  = $pnpCls
                    Status    = $stat
                    ErrorCode = $errCode
                    IsProblem = $isProblem
                    SortRank  = $sortRank
                })
            }
        }
    } catch {}

    # WMI(Win32_PnPEntity) 클래스 손상 시 네이티브 pnputil /enum-devices 폴백 조회
    if (-not $wmiRan) {
        try {
            $enumDev = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/enum-devices', '/connected')
            if ($enumDev.ExitCode -eq 0 -and $enumDev.Lines.Count -gt 0) {
                $curId = ''; $curDesc = ''; $curCls = ''; $curStat = ''
                $flushDev = {
                    param($id, $desc, $cls, $st, $outList)
                    if ([string]::IsNullOrWhiteSpace($id)) { return }
                    if ($id -notmatch '^(?i)(USB\\VID_|USBPRINT\\)') { return }
                    if (($desc -match $excludeRegex) -or ($id -match $excludeRegex)) { return }
                    $isUp = ($id -match '^(?i)USBPRINT\\')
                    $isBc = ($id -match $vidRegex) -or ($id -match $nameRegex) -or ($desc -match $nameRegex) -or ($isUp -and ($id -match '(?i)ZTC'))
                    if (-not $isBc) { return }
                    $prob = ($st -match '(?i)Problem|문제|Stopped|중지|Disabled|사용 안 함|Error|오류') -or [string]::IsNullOrWhiteSpace($cls) -or ($cls -match '(?i)^(Unknown|Other|알 수 없음|기타)')
                    if ($isUp -and ($cls -notmatch '(?i)(Printer|PrintQueue|프린터|인쇄)')) { $prob = $true }
                    $sr = 2; if ($isUp) { $sr = 1 }
                    if ($IncludeHealthyBarcode -or $prob) {
                        $outList.Add([pscustomobject]@{
                            DeviceID = $id; Name = $desc; PNPClass = $cls; Status = $st; ErrorCode = 0; IsProblem = $prob; SortRank = $sr
                        })
                    }
                }
                foreach ($ln in $enumDev.Lines) {
                    $t = $ln.Trim()
                    if ([string]::IsNullOrWhiteSpace($t)) {
                        & $flushDev $curId $curDesc $curCls $curStat $found
                        $curId = ''; $curDesc = ''; $curCls = ''; $curStat = ''
                        continue
                    }
                    if ($t -match '^(?:Instance ID|인스턴스 ID)\s*:\s*(.+)$') { $curId = $matches[1].Trim() }
                    elseif ($t -match '^(?:Device Description|장치 설명)\s*:\s*(.+)$') { $curDesc = $matches[1].Trim() }
                    elseif ($t -match '^(?:Class Name|클래스 이름)\s*:\s*(.+)$') { $curCls = $matches[1].Trim() }
                    elseif ($t -match '^(?:Status|상태)\s*:\s*(.+)$') { $curStat = $matches[1].Trim() }
                }
                & $flushDev $curId $curDesc $curCls $curStat $found
            }
        } catch {}
    }

    return @($found.ToArray() | Sort-Object SortRank, DeviceID)
}

function Invoke-UsbBarcodeAutoReenumerate {
    param(
        [int]$WaitSeconds = 8,
        [switch]$ForceAllBarcodeUsb,
        [scriptblock]$OnProgress = $null
    )

    $beforePorts = @(Get-PrinterPortSafe | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name } | Sort-Object)
    $candidates  = @(Get-BrokenBarcodeUsbDevices -IncludeHealthyBarcode:$ForceAllBarcodeUsb)
    $beforeProb  = (@($candidates | Where-Object { $_.IsProblem })).Count

    $removedIds = [System.Collections.Generic.List[string]]::new()
    if ($candidates.Count -gt 0) {
        Write-ProgressSafe -OnProgress $OnProgress -Percent 52 -Message "USB 바코드 장치 $($candidates.Count)개 소프트웨어 재인식(제거 후 하드웨어 재검색) 시도 중..."
        foreach ($c in $candidates) {
            $rRem = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/remove-device', $c.DeviceID)
            if ($rRem.ExitCode -eq 0) {
                $removedIds.Add($c.DeviceID)
            } else {
                $rRst = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/restart-device', $c.DeviceID)
                if ($rRst.ExitCode -eq 0) { $removedIds.Add($c.DeviceID) }
            }
        }
        Start-Sleep -Seconds 1
        [void](Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/scan-devices'))

        $maxWait = [math]::Max(2, $WaitSeconds)
        for ($sec = 0; $sec -lt $maxWait; $sec++) {
            Start-Sleep -Seconds 1
            $curPorts = @(Get-PrinterPortSafe | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name })
            $addedNow = @($curPorts | Where-Object { $beforePorts -notcontains $_ })
            if ($addedNow.Count -gt 0) { break }
            if ($sec -ge 3) {
                $stillNow = @(Get-BrokenBarcodeUsbDevices)
                if (($beforeProb -gt 0 -and $stillNow.Count -lt $beforeProb) -or ($beforeProb -eq 0 -and $curPorts.Count -gt 0 -and $stillNow.Count -eq 0)) { break }
            }
        }
    } elseif ($ForceAllBarcodeUsb -or $beforePorts.Count -eq 0) {
        # 수동 'USB 다시 인식' 요청 또는 USB 포트 부재 시 PnP 하드웨어 재검색 1회 강제 수행
        Write-ProgressSafe -OnProgress $OnProgress -Percent 55 -Message 'PnP 하드웨어 변경 사항 재검색 실행 중...'
        [void](Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/scan-devices'))
        Start-Sleep -Seconds 2
    }

    $afterPorts  = @(Get-PrinterPortSafe | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name } | Sort-Object)
    $newPorts    = @($afterPorts | Where-Object { $beforePorts -notcontains $_ })
    $stillBroken = @(Get-BrokenBarcodeUsbDevices)
    $promotedOk  = ($newPorts.Count -gt 0) -or ($beforeProb -gt 0 -and $stillBroken.Count -lt $beforeProb)
    $needsReplug = ($candidates.Count -gt 0) -and (-not $promotedOk) -and ($stillBroken.Count -gt 0 -or $afterPorts.Count -eq 0)

    $summary = '재인식이 필요한 미등록 USB 바코드 장치가 감지되지 않았습니다.'
    if ($candidates.Count -gt 0) {
        if ($newPorts.Count -gt 0) {
            $summary = "USB 바코드 소프트웨어 재인식 성공 (대상 $($candidates.Count)개 처리, 신규 USB 포트 생성: $($newPorts -join ', '))"
        } elseif ($promotedOk) {
            $summary = "USB 바코드 소프트웨어 재인식 완료 (대상 $($candidates.Count)개 처리, 이상 장치 해제 확인 / 현재 USB 포트: $($afterPorts -join ', '))"
        } elseif (-not $needsReplug -and $afterPorts.Count -gt 0 -and $stillBroken.Count -eq 0) {
            $summary = "USB 바코드 소프트웨어 재인식 완료 (대상 $($candidates.Count)개 재검색, 현재 USB 포트: $($afterPorts -join ', ') / 이상 장치 없음)"
        } else {
            $summary = "USB 바코드 $($candidates.Count)개 소프트웨어 재인식을 시도했으나 신규 USB 포트가 생성되지 않았습니다 — USB 케이블을 1회 뽑았다 다시 연결하세요."
        }
    }

    return [pscustomobject]@{
        AttemptedCount    = $candidates.Count
        RemovedIds        = $removedIds.ToArray()
        BeforeUsbPorts    = $beforePorts
        AfterUsbPorts     = $afterPorts
        NewUsbPorts       = $newPorts
        StillBrokenCount  = $stillBroken.Count
        NeedsManualReplug = $needsReplug
        Summary           = $summary
    }
}

# ============================================================================
# Win32 네이티브 공유 호스트 인증(CredWriteW/CredDeleteW) + SID 충돌 판별
# ============================================================================
function Get-RemoteSharedPrintersResult {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return [pscustomobject]@{ Win32Error = -1; Shares = @() }
    }
    $serverUnc = $HostName.Trim()
    if (-not $serverUnc.StartsWith('\\')) { $serverUnc = "\\$serverUnc" }
    try {
        $r = [AsanWin32.NativeApi]::EnumPrintSharesEx($serverUnc)
        return [pscustomobject]@{ Win32Error = [int]$r.Win32Error; Shares = @($r.Shares) }
    } catch {
        return [pscustomobject]@{ Win32Error = -1; Shares = @() }
    }
}

function Get-RemoteSharedPrinters {
    param([string]$HostName)
    $res = Get-RemoteSharedPrintersResult -HostName $HostName
    return @($res.Shares)
}

function Test-HasAuthenticatedHostCred {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    try {
        if ([AsanWin32.NativeApi]::HasStoredCredential($HostName)) { return $true }
    } catch {}
    try {
        $authConn = @(Get-SmbConnection -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ServerName -ieq $HostName -and
                -not [string]::IsNullOrWhiteSpace([string]$_.UserName) -and
                ([string]$_.UserName) -notmatch '(?i)(guest|anonymous|nobody)'
            }) | Select-Object -First 1
        if ($authConn) { return $true }
    } catch {}
    return $false
}

function Connect-SharedHostSmart {
    param(
        [string]$HostName,
        [string]$CustomUser = $null,
        [string]$CustomPass = $null,
        [switch]$ForceResetSession
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return [pscustomobject]@{ Success = $false; Status = 'InvalidHost'; Win32Error = -1; Reason = '호스트 IP/이름이 비어 있습니다.'; UsedUser = $null; UsedPass = $null }
    }

    if (-not (Test-TcpPortFast -HostIp $HostName -Port 445 -TimeoutMs 1500)) {
        return [pscustomobject]@{
            Success    = $false
            Status     = 'HostOffline'
            Win32Error = 53
            Reason     = "공유 메인 PC($HostName) SMB(445) 응답 없음 (전원 꺼짐 또는 네트워크 단절 의심)"
            UsedUser   = $null
            UsedPass   = $null
        }
    }

    $cacheKey = $HostName.ToLowerInvariant()
    if (-not $ForceResetSession -and [string]::IsNullOrWhiteSpace($CustomUser)) {
        if ($global:AsanCtx.HostCredCache.ContainsKey($cacheKey)) {
            $cached = $global:AsanCtx.HostCredCache[$cacheKey]
            return [pscustomobject]@{ Success = $true; Status = 'Authenticated'; Win32Error = 0; Reason = '캐시된 자격 증명 사용'; UsedUser = $cached.User; UsedPass = $cached.Pass }
        }
        if (Test-HasAuthenticatedHostCred -HostName $HostName) {
            $preProbe = Get-RemoteSharedPrintersResult -HostName $HostName
            if ($preProbe.Win32Error -eq 0 -or $preProbe.Win32Error -eq 234) {
                return [pscustomobject]@{ Success = $true; Status = 'ExistingSession'; Win32Error = 0; Reason = '기존 PC 저장 자격 증명으로 정상 접근 확인'; UsedUser = '(existing)'; UsedPass = $null }
            }
        }
    }

    if ($ForceResetSession) {
        Disconnect-AllHostSessions -HostName $HostName
        [AsanWin32.NativeApi]::DeleteDomainCredential($HostName)
        if ($global:AsanCtx.HostCredCache.ContainsKey($cacheKey)) { $global:AsanCtx.HostCredCache.Remove($cacheKey) }
    }

    $attempts = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrWhiteSpace($CustomUser)) {
        foreach ($uCand in @(Get-RemoteUserCandidates -HostName $HostName -UserName $CustomUser)) {
            $attempts.Add([pscustomobject]@{ User = $uCand; Pass = [string]$CustomPass; IsCustom = $true })
        }
    } else {
        $uCandsDef = @(Get-RemoteUserCandidates -HostName $HostName -UserName (Get-EffectiveDefaultUser))
        foreach ($pw in @(Get-ConfiguredDefaultPasswords)) {
            foreach ($uDef in $uCandsDef) {
                $attempts.Add([pscustomobject]@{ User = $uDef; Pass = $pw; IsCustom = $false })
            }
        }
    }

    if ($attempts.Count -eq 0) {
        return [pscustomobject]@{
            Success    = $false
            Status     = 'AuthOrSidConflict'
            Win32Error = 1326
            Reason     = '기본 공용 암호가 설정되지 않았습니다. 실행 폴더에 secrets.local.json을 두거나 공유 인증 도우미에서 계정을 입력해 주세요.'
            UsedUser   = $null
            UsedPass   = $null
        }
    }

    $ipcPath         = "\\$HostName\IPC$"
    $lastRc          = 0
    $authErrDetected = $false

    foreach ($att in $attempts) {
        [void][AsanWin32.NativeApi]::DisconnectShare($ipcPath)
        $rc = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $att.User, $att.Pass)

        if ($rc -eq 1219) {
            Disconnect-AllHostSessions -HostName $HostName
            $rc = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $att.User, $att.Pass)
        }

        if ($rc -eq 0) {
            if ($HostName -ine $global:AsanCtx.ServerIP) {
                [void][AsanWin32.NativeApi]::WriteDomainCredential($HostName, $att.User, $att.Pass)
            }
            $global:AsanCtx.HostCredCache[$cacheKey] = [pscustomobject]@{ User = $att.User; Pass = $att.Pass }
            return [pscustomobject]@{ Success = $true; Status = 'Authenticated'; Win32Error = 0; Reason = "인증 성공 ($($att.User))"; UsedUser = $att.User; UsedPass = $att.Pass }
        }

        $lastRc = $rc
        if ($rc -in @(5, 86, 1272, 1326, 1331, 1909)) {
            $authErrDetected = $true
        }
    }

    if ($authErrDetected) {
        $sidHint = "기본 공용 암호 3종 인증 실패 (Win32=$lastRc) -> 메인 PC 암호 변경 또는 동일 Windows SID 충돌 의심"
        if ($lastRc -eq 1272) {
            $sidHint = "Windows 11 24H2 게스트 공유 보안 차단 (Win32=1272) -> 메인 PC 계정/암호 입력 필요"
        }
        if (-not [string]::IsNullOrWhiteSpace($CustomUser)) {
            $sidHint = "입력한 계정($CustomUser)도 로그온 거부됨 (Win32=$lastRc) -> 메인 PC와 Windows Machine SID 동일 충돌 가능성 높음!"
        }
        return [pscustomobject]@{
            Success    = $false
            Status     = 'AuthOrSidConflict'
            Win32Error = $lastRc
            Reason     = $sidHint
            UsedUser   = $null
            UsedPass   = $null
        }
    }

    $connErrReason = "공유 호스트($HostName) SMB 연결 실패 (Win32 Error=$lastRc)"
    if ($lastRc -eq 384) {
        $connErrReason = "공유 호스트($HostName)가 구형 SMB1 프로토콜만 지원하여 연결할 수 없습니다 (Win32=384)"
    }
    return [pscustomobject]@{
        Success    = $false
        Status     = 'ConnectError'
        Win32Error = $lastRc
        Reason     = $connErrReason
        UsedUser   = $null
        UsedPass   = $null
    }
}

function Test-UncSharePrinterAlive {
    param(
        [string]$UncPath,
        [string]$CustomUser = $null,
        [string]$CustomPass = $null
    )
    $m = [regex]::Match($UncPath, '^\\\\([^\\]+)\\(.+)$')
    if (-not $m.Success) {
        return [pscustomobject]@{ Status = 'Ambiguous'; Reason = "UNC 경로 형식 불명확 ($UncPath)"; HostName = $null; ShareName = $null }
    }

    $hostName  = $m.Groups[1].Value
    $shareName = $m.Groups[2].Value.TrimEnd('\')

    $auth = Connect-SharedHostSmart -HostName $hostName -CustomUser $CustomUser -CustomPass $CustomPass
    if (-not $auth.Success) {
        $mappedStatus = 'SuspectedInactive'
        if ($auth.Status -eq 'AuthOrSidConflict') { $mappedStatus = 'AuthOrSidConflict' }
        return [pscustomobject]@{
            Status    = $mappedStatus
            Reason    = $auth.Reason
            HostName  = $hostName
            ShareName = $shareName
        }
    }

    $enumRes = Get-RemoteSharedPrintersResult -HostName $hostName
    if ($enumRes.Win32Error -notin @(0, 234)) {
        if ($enumRes.Win32Error -in @(5, 86, 1326, 1331, 1909)) {
            $cacheKey = $hostName.ToLowerInvariant()
            if ($global:AsanCtx.HostCredCache.ContainsKey($cacheKey)) { $global:AsanCtx.HostCredCache.Remove($cacheKey) }
            $reAuth = Connect-SharedHostSmart -HostName $hostName -CustomUser $CustomUser -CustomPass $CustomPass -ForceResetSession
            if (-not $reAuth.Success) {
                $reStat = 'AuthOrSidConflict'
                if ($reAuth.Status -ne 'AuthOrSidConflict') { $reStat = 'Ambiguous' }
                return [pscustomobject]@{ Status = $reStat; Reason = $reAuth.Reason; HostName = $hostName; ShareName = $shareName }
            }
            $enumRes = Get-RemoteSharedPrintersResult -HostName $hostName
        }
    }

    $matched = $enumRes.Shares | Where-Object { $_ -ieq $shareName } | Select-Object -First 1
    if ($matched) {
        return [pscustomobject]@{ Status = 'Healthy'; Reason = "공유 호스트 인증 및 프린터 공유($shareName) 정상 확인"; HostName = $hostName; ShareName = $shareName }
    }

    if (Test-Path -LiteralPath $UncPath) {
        return [pscustomobject]@{ Status = 'Healthy'; Reason = "UNC 공유 경로($UncPath) 접근 정상 확인"; HostName = $hostName; ShareName = $shareName }
    }

    if ($enumRes.Win32Error -in @(5, 86, 1326, 1331, 1909)) {
        return [pscustomobject]@{
            Status    = 'AuthOrSidConflict'
            Reason    = "메인 PC($hostName) 공유 목록 조회 권한 거부 (Win32=$($enumRes.Win32Error)) — 암호 변경 또는 동일 SID 충돌 의심"
            HostName  = $hostName
            ShareName = $shareName
        }
    }
    if ($enumRes.Win32Error -notin @(0, 234)) {
        return [pscustomobject]@{
            Status    = 'Ambiguous'
            Reason    = "메인 PC($hostName) 공유 목록 조회 오류 (Win32=$($enumRes.Win32Error)) — 일시적 SMB 응답 지연 또는 네트워크 확인 필요"
            HostName  = $hostName
            ShareName = $shareName
        }
    }

    return [pscustomobject]@{
        Status    = 'SuspectedInactive'
        Reason    = "메인 PC($hostName) 접속은 성공했으나 공유 프린터 '$shareName' 이(가) 존재하지 않음 (공유 해제/이름 변경 의심)"
        HostName  = $hostName
        ShareName = $shareName
    }
}

# ============================================================================
# TCP/IP 생존 검증 & WSD UUID 연결 + DriverVersion IP 오인 차단
# ============================================================================
function Test-TcpIpPrinterHealth {
    param(
        [string]$HostAddress,
        [string]$Protocol = 'RAW',
        [int]$PortNumber = 9100,
        [bool]$SkipAliveFilter = $false
    )
    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        return [pscustomobject]@{ Status = 'Ambiguous'; Reason = 'TCP/IP 호스트 주소가 비어 있음' }
    }

    $primaryPort = 9100
    if ($Protocol -eq 'LPR') { $primaryPort = 515 }
    elseif ($PortNumber -gt 0) { $primaryPort = $PortNumber }

    $checkPorts = @($primaryPort, 9100, 515, 631) | Select-Object -Unique
    foreach ($pt in $checkPorts) {
        if (Test-TcpPortFast -HostIp $HostAddress -Port $pt -TimeoutMs 1200) {
            return [pscustomobject]@{ Status = 'Healthy'; Reason = "인쇄 포트($HostAddress`:$pt) 정상 응답" }
        }
    }

    if ($SkipAliveFilter) {
        return [pscustomobject]@{
            Status = 'Healthy'
            Reason = "특수 장비(SIP-30M 등) 보호 예외 적용 — Generic Network Card 특성으로 보존됨 ($HostAddress)"
        }
    }

    $pingOk = Test-PingFast -HostIp $HostAddress -TimeoutMs 1000
    $webOk  = (Test-TcpPortFast -HostIp $HostAddress -Port 80 -TimeoutMs 1000) -or (Test-TcpPortFast -HostIp $HostAddress -Port 443 -TimeoutMs 1000)

    if ($pingOk -or $webOk) {
        return [pscustomobject]@{
            Status = 'Ambiguous'
            Reason = "호스트($HostAddress)는 응답하나 인쇄 포트(9100/515/631)가 닫혀 있음 (타 장비 할당 또는 포트 차단 의심)"
        }
    }

    return [pscustomobject]@{
        Status = 'SuspectedInactive'
        Reason = "TCP/IP($HostAddress) 무응답 (프린터 전원 꺼짐 또는 폐기/IP 변경 의심)"
    }
}

function Format-DeviceString {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    if ($Raw -match ';([^;]+)$') { $Raw = $matches[1] }
    $Raw = $Raw.Trim()
    if ($Raw -match '(?i)^(WSD Print Device|WSD 인쇄 장치|Local Print Queue|로컬 인쇄 큐|Microsoft IPP.*)$') { return $null }
    return $Raw
}

function Resolve-WsdPrinterInfo {
    param(
        [string]$PrinterName,
        [string]$PortName,
        [string]$DriverName,
        [switch]$SkipNetworkProbe
    )
    $foundIp    = Select-FirstUsableIPv4 -Text "$PortName $PrinterName"
    $foundModel = $null

    $matchKeys = [System.Collections.Generic.List[string]]::new()
    $guidM     = [regex]::Match($PortName, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($guidM.Success) { $matchKeys.Add($guidM.Value) }
    elseif (-not [string]::IsNullOrWhiteSpace($PortName)) { $matchKeys.Add($PortName) }

    $ipKeyAllowRegex = '(?i)(IPAddress|XAddrs|LocationInfo|Address|Host|Uri|Endpoint|PnpX)'
    $ipKeyDenyRegex  = '(?i)(DriverVersion|DriverDate|Version|HardwareID|CompatibleIDs|InfPath|DriverInf|ClassGuid|MatchingDeviceId)'

    $wsdPortKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\WSD Port\Ports\$PortName"
    if (Test-Path -LiteralPath $wsdPortKey) {
        $wProps = Get-ItemProperty -LiteralPath $wsdPortKey -ErrorAction SilentlyContinue
        if ($wProps) {
            foreach ($prop in $wProps.PSObject.Properties) {
                $pn = [string]$prop.Name
                $pv = [string]$prop.Value
                if ([string]::IsNullOrWhiteSpace($pv)) { continue }
                if ($pn -match '(?i)(UUID|Id|Device)') {
                    $uClean = ($pv -replace '(?i)^urn:uuid:', '').Trim()
                    if ($uClean.Length -ge 8 -and -not $matchKeys.Contains($uClean)) { $matchKeys.Add($uClean) }
                }
                if (-not $foundIp -and ($pn -match $ipKeyAllowRegex -or $pv -match 'https?://') -and $pn -notmatch $ipKeyDenyRegex) {
                    $cand = Select-FirstUsableIPv4 -Text $pv
                    if ($cand) { $foundIp = $cand }
                }
            }
        }
    }

    $pnpDevices   = [System.Collections.Generic.List[object]]::new()
    $pnpPropCache = @{}
    try {
        foreach ($pattern in @('SWD\DAFWSDProvider*', 'SWD\PRINTENUM*')) {
            foreach ($dev in @(Get-PnpDevice -InstanceId $pattern -ErrorAction SilentlyContinue)) {
                $pnpDevices.Add($dev)
            }
        }
    } catch {}

    $enumRoots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SWD\PRINTENUM',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\UMB\UMB'
    )
    $regRecords = $null

    # 전역 3단계 우선순위:
    #   Pass 1: UUID/GUID 정확 매칭 (PnP -> Registry 전체 완료)
    #   Pass 2: 프린터명 완전 일치(-ieq) 폴백 (PnP -> Registry)
    #   Pass 3: 프린터명 부분 일치 폴백 (PnP -> Registry)
    for ($wsdStage = 1; $wsdStage -le 3; $wsdStage++) {
        if ($foundIp -and $foundModel) { break }
        if ($wsdStage -ge 2 -and $PrinterName.Length -lt 3) { break }

        try {
            foreach ($dev in $pnpDevices) {
                if ($foundIp -and $foundModel) { break }
                $instId = [string]$dev.InstanceId
                $fName  = [string]$dev.FriendlyName

                $directHit = $false
                if ($wsdStage -eq 1) {
                    foreach ($mk in $matchKeys) {
                        if ($instId.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $directHit = $true; break }
                    }
                } elseif ($wsdStage -eq 2) {
                    $cleanFn = Format-DeviceString -Raw $fName
                    if (($fName -ieq $PrinterName) -or ($cleanFn -and $cleanFn -ieq $PrinterName)) {
                        $directHit = $true
                    }
                } else {
                    if ($fName.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $directHit = $true
                    }
                }
                if (-not $directHit -and $instId -notlike 'SWD\DAFWSDProvider*') { continue }

                $cachedEntry = $null
                if ($pnpPropCache.ContainsKey($instId)) {
                    $cachedEntry = $pnpPropCache[$instId]
                } else {
                    $propsList = @()
                    try { $propsList = @(Get-PnpDeviceProperty -InstanceId $instId -ErrorAction SilentlyContinue) } catch {}
                    $blobText  = ($propsList | ForEach-Object {
                        if ($_.Data -is [array]) { ($_.Data -join ' ') } else { [string]$_.Data }
                    }) -join ' '
                    $cachedEntry = [pscustomobject]@{ Props = $propsList; Blob = $blobText }
                    $pnpPropCache[$instId] = $cachedEntry
                }
                $props    = $cachedEntry.Props
                $propBlob = $cachedEntry.Blob

                if (-not $directHit) {
                    $propHit = $false
                    if ($wsdStage -eq 1) {
                        foreach ($mk in $matchKeys) {
                            if ($propBlob.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $propHit = $true; break }
                        }
                    } elseif ($wsdStage -eq 2) {
                        foreach ($pr in $props) {
                            if ([string]$pr.KeyName -match '(?i)(FriendlyName|DeviceDesc|ModelName|Model$)') {
                                $pvTxt = if ($pr.Data -is [array]) { ($pr.Data -join ' ') } else { [string]$pr.Data }
                                $pvCln = Format-DeviceString -Raw $pvTxt
                                if (($pvTxt -ieq $PrinterName) -or ($pvCln -and $pvCln -ieq $PrinterName)) { $propHit = $true; break }
                            }
                        }
                    } else {
                        if ($propBlob.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $propHit = $true
                        }
                    }
                    if (-not $propHit) { continue }
                }

                if (-not $foundIp) {
                    foreach ($pr in $props) {
                        $pKey = [string]$pr.KeyName
                        if ($pKey -match $ipKeyDenyRegex) { continue }
                        $pVal = if ($pr.Data -is [array]) { ($pr.Data -join ' ') } else { [string]$pr.Data }
                        if ([string]::IsNullOrWhiteSpace($pVal)) { continue }
                        if ($pKey -match $ipKeyAllowRegex) {
                            $candIp = Select-FirstUsableIPv4 -Text $pVal
                            if ($candIp) { $foundIp = $candIp; break }
                        } elseif ($pVal -match 'https?://') {
                            $candIp = Select-FirstUsableIPv4 -Text $pVal -UrlOnly
                            if ($candIp) { $foundIp = $candIp; break }
                        }
                    }
                }

                if (-not $foundModel) {
                    foreach ($pr in $props) {
                        $pKey = [string]$pr.KeyName
                        if ($pKey -match '(?i)(ModelName|Model$|FriendlyName|DeviceDesc)') {
                            $pVal = if ($pr.Data -is [array]) { ($pr.Data -join ' ') } else { [string]$pr.Data }
                            $candModel = Format-DeviceString -Raw $pVal
                            if ($candModel) { $foundModel = $candModel; break }
                        }
                    }
                    if (-not $foundModel) {
                        $candFn = Format-DeviceString -Raw $fName
                        if ($candFn) { $foundModel = $candFn }
                    }
                }
            }
        } catch {}

        if ($foundIp -and $foundModel) { break }

        # 레지스트리 스캔 (지연 로드 + 루트 미존재 시 continue로 다음 루트 UMB\UMB 검사 보장)
        if ($null -eq $regRecords) {
            $regList = [System.Collections.Generic.List[object]]::new()
            foreach ($root in $enumRoots) {
                if (-not (Test-Path -LiteralPath $root)) { continue }
                foreach ($sub in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                    $subProps     = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
                    $devParamPath = Join-Path $sub.PSPath 'Device Parameters'
                    $dpProps      = $null
                    if (Test-Path -LiteralPath $devParamPath) {
                        $dpProps = Get-ItemProperty -LiteralPath $devParamPath -ErrorAction SilentlyContinue
                    }
                    $blob = ([string]$sub.PSChildName) + ' '
                    if ($subProps) { $blob += (($subProps.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' ') + ' ' }
                    if ($dpProps)  { $blob += (($dpProps.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' ') }
                    $regList.Add([pscustomobject]@{ SubProps = $subProps; DpProps = $dpProps; Blob = $blob })
                }
            }
            $regRecords = $regList.ToArray()
        }

        foreach ($rec in $regRecords) {
            if ($foundIp -and $foundModel) { break }
            $subProps = $rec.SubProps
            $dpProps  = $rec.DpProps
            $blob     = [string]$rec.Blob

            $hit = $false
            if ($wsdStage -eq 1) {
                foreach ($mk in $matchKeys) {
                    if ($blob.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
                }
            } elseif ($wsdStage -eq 2) {
                if ($subProps) {
                    foreach ($propName in @('FriendlyName', 'DeviceDesc')) {
                        $rv = [string]$subProps.$propName
                        $rc = Format-DeviceString -Raw $rv
                        if (($rv -ieq $PrinterName) -or ($rc -and $rc -ieq $PrinterName)) { $hit = $true; break }
                    }
                }
            } else {
                if ($blob.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $hit = $true
                }
            }
            if (-not $hit) { continue }

            if (-not $foundIp) {
                foreach ($obj in @($dpProps, $subProps)) {
                    if (-not $obj -or $foundIp) { continue }
                    foreach ($prop in $obj.PSObject.Properties) {
                        $pn = [string]$prop.Name
                        if ($pn -match $ipKeyDenyRegex) { continue }
                        $pv = [string]$prop.Value
                        if ($pn -match $ipKeyAllowRegex) {
                            $cand = Select-FirstUsableIPv4 -Text $pv
                            if ($cand) { $foundIp = $cand; break }
                        } elseif ($pv -match 'https?://') {
                            $cand = Select-FirstUsableIPv4 -Text $pv -UrlOnly
                            if ($cand) { $foundIp = $cand; break }
                        }
                    }
                }
            }

            if (-not $foundModel -and $subProps) {
                foreach ($propName in @('FriendlyName', 'DeviceDesc')) {
                    $cand = Format-DeviceString -Raw ([string]$subProps.$propName)
                    if ($cand) { $foundModel = $cand; break }
                }
                if (-not $foundModel -and $subProps.HardwareID) {
                    $hwStr = (@($subProps.HardwareID) -join ' ')
                    $hm = [regex]::Match($hwStr, '(?i)(?:Samsung|Kyocera|HP|Canon|Epson|Brother|Ricoh|Sindoh|Xerox|Konica)[^\\,;]+')
                    if ($hm.Success) { $foundModel = ($hm.Value -replace '_', ' ').Trim() }
                }
            }
        }
        # Stage 1(UUID 일치)에서 IP를 이미 확정했다면 Stage 2/3 이름 추측으로 타 WSD 장치 오염 차단
        if ($wsdStage -eq 1 -and $foundIp) { break }
    }

    $modelHintText = ''
    if ($foundModel) { $modelHintText = " / 모델: $foundModel" }

    if (-not $foundIp) {
        return [pscustomobject]@{
            ExtractedIP      = $null
            ExtractedModel   = $foundModel
            RecommendedMode  = 'MANUAL'
            RecommendedShare = $null
            Status           = 'Ambiguous'
            Reason           = "WSD 포트($PortName)에서 IP 주소를 추출하지 못함$modelHintText — 복원 시 수동 IP 확인 필요"
        }
    }

    if ($SkipNetworkProbe) {
        return [pscustomobject]@{
            ExtractedIP      = $foundIp
            ExtractedModel   = $foundModel
            RecommendedMode  = 'TCPIP'
            RecommendedShare = $null
            Status           = 'WsdConvert'
            Reason           = "WSD IP($foundIp$modelHintText) 추출 완료 (오프라인 — 복원 시 지연 검증 예정)"
        }
    }

    if ((Test-TcpPortFast -HostIp $foundIp -Port 9100 -TimeoutMs 1200) -or (Test-TcpPortFast -HostIp $foundIp -Port 515 -TimeoutMs 1000)) {
        return [pscustomobject]@{
            ExtractedIP      = $foundIp
            ExtractedModel   = $foundModel
            RecommendedMode  = 'TCPIP'
            RecommendedShare = $null
            Status           = 'WsdConvert'
            Reason           = "WSD -> TCP/IP($foundIp$modelHintText) 자동 전환 대상 (인쇄 포트 정상 확인)"
        }
    }

    if (Test-TcpPortFast -HostIp $foundIp -Port 445 -TimeoutMs 1200) {
        $auth = Connect-SharedHostSmart -HostName $foundIp
        if ($auth.Success) {
            $shares = @(Get-RemoteSharedPrinters -HostName $foundIp)
            if ($shares.Count -gt 0) {
                $bestShare = $shares[0]
                $hintCombo = "$DriverName $foundModel"
                if ($hintCombo -match '(?i)Kyocera' -and ($shares -contains 'kyoceraf')) { $bestShare = 'kyoceraf' }
                elseif ($hintCombo -match '(?i)Samsung' -and ($shares -contains 'samsungm')) { $bestShare = 'samsungm' }
                return [pscustomobject]@{
                    ExtractedIP      = $foundIp
                    ExtractedModel   = $foundModel
                    RecommendedMode  = 'LOCAL_UNC'
                    RecommendedShare = "\\$foundIp\$bestShare"
                    Status           = 'WsdConvert'
                    Reason           = "WSD -> Local Port(\\$foundIp\$bestShare$modelHintText) 자동 전환 대상 (공유 프린터 확인됨)"
                }
            }
        } elseif ($auth.Status -eq 'AuthOrSidConflict') {
            return [pscustomobject]@{
                ExtractedIP      = $foundIp
                ExtractedModel   = $foundModel
                RecommendedMode  = 'LOCAL_UNC'
                RecommendedShare = $null
                Status           = 'AuthOrSidConflict'
                Reason           = "WSD 호스트($foundIp$modelHintText) 공유 인증/SID 충돌: $($auth.Reason)"
            }
        }
    }

    return [pscustomobject]@{
        ExtractedIP      = $foundIp
        ExtractedModel   = $foundModel
        RecommendedMode  = 'TCPIP'
        RecommendedShare = $null
        Status           = 'Ambiguous'
        Reason           = "WSD IP($foundIp$modelHintText)는 추출되었으나 현재 인쇄 포트/공유 응답 없음 (복원 시 TCP/IP 시도 예정)"
    }
}

# ============================================================================
# Win 10/11 3중 폴백 pnputil 파서 + 스캐너 3분류 인벤토리
# ============================================================================
function Get-PnpUtilDriverBlocks {
    $blocks = [System.Collections.Generic.List[hashtable]]::new()
    $res = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/enum-drivers')
    if ($res.ExitCode -ne 0 -or $res.Lines.Count -eq 0) {
        # 구형 Windows 10 초기 빌드(1507/1511) 및 Win 7 호환 레거시 pnputil -e 시도
        $res = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('-e')
    }

    if ($res.ExitCode -eq 0 -and $res.Lines.Count -gt 0) {
        $rawBlock = [System.Collections.Generic.List[object]]::new()

        $flushBlock = {
            param($pairs, $outList)
            if ($pairs.Count -eq 0) { return }
            $h = @{}
            foreach ($pair in $pairs) {
                $k = $pair.Key
                $v = $pair.Val
                if ($k -match '^(Published Name|게시된 이름)$' -or ($v -match '(?i)^oem\d+\.inf$' -and -not $h.ContainsKey('PublishedName'))) {
                    $h['PublishedName'] = $v
                }
                elseif ($k -match '^(Original Name|원래 이름)$' -or ($v -match '(?i)\.inf$' -and $v -notmatch '(?i)^oem\d+\.inf$' -and -not $h.ContainsKey('OriginalName'))) {
                    $h['OriginalName'] = $v
                }
                elseif ($k -match '^(Provider Name|공급자 이름|드라이버 패키지 공급자)$') {
                    $h['ProviderName'] = $v
                }
                elseif ($k -match '^(Class Name|클래스 이름|클래스)$') {
                    $h['ClassName'] = $v
                }
                elseif ($k -match '^(Class GUID|클래스 GUID)$' -or ($v -match '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$')) {
                    $h['ClassGuid'] = $v.ToLowerInvariant()
                }
                elseif ($k -match '^(Driver Version|드라이버 버전|드라이버 날짜 및 버전)$' -or ($v -match '^\d{2}/\d{2}/\d{4}\s+[\d\.]+$' -and -not $h.ContainsKey('DriverVersion'))) {
                    $h['DriverVersion'] = $v
                }
            }
            if (-not $h.ContainsKey('ProviderName') -and $pairs.Count -ge 3 -and $h.ContainsKey('PublishedName')) {
                $candProv = [string]$pairs[2].Val
                if ($candProv -notmatch '^\{[0-9a-fA-F-]{36}\}$' -and $candProv -notmatch '(?i)\.inf$') {
                    $h['ProviderName'] = $candProv
                }
            }
            if (-not $h.ContainsKey('ClassName') -and $pairs.Count -ge 4 -and $h.ContainsKey('PublishedName')) {
                $candCls = [string]$pairs[3].Val
                if ($candCls -notmatch '^\{[0-9a-fA-F-]{36}\}$') {
                    $h['ClassName'] = $candCls
                }
            }
            if ($h.ContainsKey('PublishedName')) { $outList.Add($h) }
        }

        foreach ($line in $res.Lines) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) {
                & $flushBlock $rawBlock $blocks
                $rawBlock.Clear()
                continue
            }
            $m = [regex]::Match($t, '^([^:]+?)\s*:\s*(.+)$')
            if ($m.Success) {
                $rawBlock.Add([pscustomobject]@{ Key = $m.Groups[1].Value.Trim(); Val = $m.Groups[2].Value.Trim() })
            }
        }
        & $flushBlock $rawBlock $blocks
    }

    # 레거시 pnputil -e (ClassGuid/OriginalName 미출력) 또는 pnputil 손상 시 Windows\INF\oem*.inf 헤더로 직접 보강/생성
    $winInfDir = Join-Path $env:SystemRoot 'INF'
    if (Test-Path -LiteralPath $winInfDir) {
        $byPub = @{}
        foreach ($b in $blocks) {
            if ($b['PublishedName']) { $byPub[([string]$b['PublishedName']).ToLowerInvariant()] = $b }
        }
        $needInfScan = ($blocks.Count -eq 0)
        if (-not $needInfScan) {
            foreach ($b in $blocks) {
                if (-not $b.ContainsKey('ClassGuid')) { $needInfScan = $true; break }
            }
        }
        if ($needInfScan) {
            foreach ($oemFile in @(Get-ChildItem -LiteralPath $winInfDir -Filter 'oem*.inf' -File -ErrorAction SilentlyContinue)) {
                $pubKey = $oemFile.Name.ToLowerInvariant()
                $targetH = $null
                if ($byPub.ContainsKey($pubKey)) {
                    $targetH = $byPub[$pubKey]
                    if ($targetH.ContainsKey('ClassGuid') -and $targetH.ContainsKey('ProviderName')) { continue }
                } else {
                    $targetH = @{ PublishedName = $oemFile.Name }
                }
                try {
                    $headLines = @(Get-Content -LiteralPath $oemFile.FullName -TotalCount 80 -ErrorAction Stop)
                    $headTxt   = $headLines -join "`r`n"
                    if (-not $targetH.ContainsKey('ClassGuid')) {
                        $gm = [regex]::Match($headTxt, '(?im)^\s*ClassGUID\s*=\s*(\{[0-9a-fA-F\-]{36}\})')
                        if ($gm.Success) { $targetH['ClassGuid'] = $gm.Groups[1].Value.ToLowerInvariant() }
                    }
                    if (-not $targetH.ContainsKey('ProviderName')) {
                        $pm = [regex]::Match($headTxt, '(?im)^\s*Provider\s*=\s*([^;\r\n]+)')
                        if ($pm.Success) {
                            $provVal = $pm.Groups[1].Value.Trim().Trim('"')
                            if ($provVal -match '^%([^%]+)%$') {
                                $tokKey = $matches[1].Trim()
                                $fullTxt = Get-Content -LiteralPath $oemFile.FullName -Raw -ErrorAction SilentlyContinue
                                if (-not [string]::IsNullOrWhiteSpace($fullTxt)) {
                                    $bestStr = $null
                                    $bestPr  = 0
                                    $curS    = ''
                                    foreach ($rl in ($fullTxt -split "`r?`n")) {
                                        $tl = $rl.Trim()
                                        if (-not $tl -or $tl.StartsWith(';')) { continue }
                                        $sm2 = [regex]::Match($tl, '^\s*\[([^\]]+)\]\s*(?:;.*)?$')
                                        if ($sm2.Success) { $curS = $sm2.Groups[1].Value.Trim(); continue }
                                        if ($curS -match '(?i)^strings(?:\.([0-9a-f]+))?$') {
                                            $lt2 = ''
                                            if ($matches[1]) { $lt2 = $matches[1].ToLowerInvariant() }
                                            $pr2 = 1
                                            if ($lt2 -eq '') { $pr2 = 3 }
                                            elseif ($lt2 -in @('0412', '0409')) { $pr2 = 2 }
                                            $km2 = [regex]::Match($tl, '^\s*([^=;]+?)\s*=\s*(?:"([^"]+)"|([^;\r\n]+))')
                                            if ($km2.Success -and ($km2.Groups[1].Value.Trim().Trim('%') -ieq $tokKey) -and $pr2 -ge $bestPr) {
                                                $val2 = $km2.Groups[2].Value
                                                if ([string]::IsNullOrWhiteSpace($val2)) { $val2 = $km2.Groups[3].Value }
                                                $val2 = $val2.Trim()
                                                if (-not [string]::IsNullOrWhiteSpace($val2)) {
                                                    $bestPr  = $pr2
                                                    $bestStr = $val2
                                                }
                                            }
                                        }
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($bestStr)) { $provVal = $bestStr }
                                }
                            }
                            $targetH['ProviderName'] = $provVal
                        }
                    }
                    if (-not $targetH.ContainsKey('DriverVersion')) {
                        $vm = [regex]::Match($headTxt, '(?im)^\s*DriverVer\s*=\s*([^;\r\n]+)')
                        if ($vm.Success) { $targetH['DriverVersion'] = $vm.Groups[1].Value.Trim() }
                    }
                    if (-not $targetH.ContainsKey('OriginalName')) {
                        $cm = [regex]::Match($headTxt, '(?im)^\s*CatalogFile(?:\.nt[a-z0-9]*)?\s*=\s*([^\s;\r\n]+)')
                        if ($cm.Success) {
                            $catBase = [IO.Path]::GetFileNameWithoutExtension($cm.Groups[1].Value.Trim())
                            if (-not [string]::IsNullOrWhiteSpace($catBase)) { $targetH['OriginalName'] = "$catBase.inf" }
                        }
                    }
                } catch {}
                if (-not $byPub.ContainsKey($pubKey)) {
                    $byPub[$pubKey] = $targetH
                    $blocks.Add($targetH)
                }
            }
        }
    }

    return @($blocks.ToArray())
}

function Get-ScannerDriverInventory {
    $autoList         = [System.Collections.Generic.List[object]]::new()
    $unclassifiedList = [System.Collections.Generic.List[object]]::new()
    $twainFolders     = [System.Collections.Generic.List[string]]::new()

    $blocks = @(Get-PnpUtilDriverBlocks)
    foreach ($b in $blocks) {
        if ($b['ClassGuid'] -ne $global:AsanCtx.ImageClassGuid) { continue }
        $pub  = [string]$b['PublishedName']
        $orig = [string]$b['OriginalName']
        $prov = [string]$b['ProviderName']
        $ver  = [string]$b['DriverVersion']
        if ([string]::IsNullOrWhiteSpace($pub)) { continue }

        $meta = "$prov | $orig"
        if ($meta -match $global:AsanCtx.ScannerBlacklistRegex) { continue }

        $tier = 'Unclassified'
        $sel  = $false
        if ($meta -match $global:AsanCtx.ScannerWhitelistRegex) {
            $tier = 'AutoWhitelist'
            $sel  = $true
        }

        $item = [pscustomobject]@{
            PublishedName = $pub
            OriginalName  = $orig
            ProviderName  = $prov
            DriverVersion = $ver
            Tier          = $tier
            Selected      = $sel
        }
        if ($sel) { $autoList.Add($item) } else { $unclassifiedList.Add($item) }
    }

    $twainRoot = Join-Path $env:SystemRoot 'twain_32'
    if (Test-Path -LiteralPath $twainRoot) {
        foreach ($d in @(Get-ChildItem -LiteralPath $twainRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -notmatch '(?i)^(wiatwain|microsoft)$') {
                $twainFolders.Add($d.Name)
            }
        }
    }

    return [pscustomobject]@{
        AutoScanners         = $autoList.ToArray()
        UnclassifiedScanners = $unclassifiedList.ToArray()
        TwainFolders         = $twainFolders.ToArray()
    }
}

# ============================================================================
# 현재 PC 전체 프린터 사전 진단 엔진 (탭 1 백업 그리드용)
# ============================================================================
function Get-LocalPrinterDiagnostics {
    param([switch]$OfflineMode)

    Start-SpoolerSafe
    $cimPrinters = @(Get-LocalPrintersSafe)
    $tcpPorts    = @(Get-LocalTcpPrinterPortsSafe)
    $results     = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $cimPrinters) {
        $pName = [string]$p.Name
        $dName = [string]$p.DriverName
        $port  = [string]$p.PortName

        if (Test-IsVirtualPrinter -PrinterName $pName -PortName $port) {
            $results.Add([pscustomobject]@{
                Selected       = $false
                StatusCode     = 'ExcludedVirtual'
                StatusText     = '제외(가상)'
                Category       = '가상'
                SpecialType    = 'VIRTUAL'
                PrinterName    = $pName
                DriverName     = $dName
                PortName       = $port
                PortKind       = 'VIRTUAL'
                HostAddress    = $null
                Protocol       = $null
                PortNumber     = $null
                Queue          = $null
                ByteCount      = $false
                ConnectionName = $null
                WsdTargetIp    = $null
                WsdModelName   = $null
                WsdTargetMode  = $null
                WsdTargetShare = $null
                IsDefault      = [bool]$p.Default
                Reason         = '백업 제외 대상 가상 프린터'
            })
            continue
        }

        $spec = Get-SpecialPrinterProfile -PrinterName $pName -DriverName $dName -PortName $port

        if ($spec.NoDriverBackup) {
            $results.Add([pscustomobject]@{
                Selected       = $false
                StatusCode     = 'ExcludedNoDriver'
                StatusText     = '백업제외(LPT1무드라이버)'
                Category       = $spec.Label
                SpecialType    = $spec.Type
                PrinterName    = $pName
                DriverName     = $dName
                PortName       = $port
                PortKind       = 'LPT'
                HostAddress    = $null
                Protocol       = $null
                PortNumber     = $null
                Queue          = $null
                ByteCount      = $false
                ConnectionName = $null
                WsdTargetIp    = $null
                WsdModelName   = $null
                WsdTargetMode  = $null
                WsdTargetShare = $null
                IsDefault      = [bool]$p.Default
                Reason         = '[드라이버 설치 금지 · 백업 제외] LPT1 유선 직결 후 AMIS 직접 사용 장비 — 장치관리자 LPT1 인식 여부만 확인 (드라이버/설정/에이전트 불필요)'
            })
            continue
        }

        $connName = $null
        if ($pName.StartsWith('\\')) { $connName = $pName }
        elseif ($p.Network -and $p.ServerName -and $p.ShareName) {
            $srv = ([string]$p.ServerName).TrimEnd('\')
            if (-not $srv.StartsWith('\\')) { $srv = '\\' + $srv.TrimStart('\') }
            $connName = "$srv\$($p.ShareName)"
        } elseif ($p.Network -and $port.StartsWith('\\')) {
            $connName = $port
        }

        $tcp         = $tcpPorts | Where-Object { $_.Name -eq $port } | Select-Object -First 1
        $portKind    = 'LOCAL'
        $hostAddress = $null
        $protocol    = $null
        $portNumber  = $null
        $queue       = $null
        $byteCount   = $false

        if ($connName) {
            $portKind = 'SHARED_UNC'
        } elseif ($tcp) {
            $portKind    = 'TCPIP'
            $hostAddress = [string]$tcp.HostAddress
            $protocol    = 'RAW'
            if ([int]$tcp.Protocol -eq 2) { $protocol = 'LPR' }
            $portNumber  = [uint32]$tcp.PortNumber
            $queue       = [string]$tcp.Queue
            $byteCount   = [bool]$tcp.ByteCount
        } elseif ($port -match '^\\\\') {
            $portKind = 'LOCAL_UNC'
        } elseif ($port -match '(?i)^WSD') {
            $portKind = 'WSD'
        } elseif ($port -match '(?i)^USB') {
            $portKind = 'USB'
        } elseif ($port -match '(?i)^LPT') {
            $portKind = 'LPT'
        } elseif ($port -match '(?i)^COM') {
            $portKind = 'COM'
        }

        $statusCode     = 'Healthy'
        $statusText     = '정상'
        $reason         = '정상 확인'
        $wsdTargetIp    = $null
        $wsdModelName   = $null
        $wsdTargetMode  = $null
        $wsdTargetShare = $null

        if ($portKind -eq 'WSD') {
            $wsd = Resolve-WsdPrinterInfo -PrinterName $pName -PortName $port -DriverName $dName -SkipNetworkProbe:$OfflineMode
            $wsdTargetIp    = $wsd.ExtractedIP
            $wsdModelName   = $wsd.ExtractedModel
            $wsdTargetMode  = $wsd.RecommendedMode
            $wsdTargetShare = $wsd.RecommendedShare
            $statusCode     = $wsd.Status
            $statusText     = 'WSD 확인 필요'
            if ($wsd.Status -eq 'WsdConvert') { $statusText = 'WSD 전환' }
            $reason         = $wsd.Reason
        } elseif ($OfflineMode) {
            $statusCode = 'OfflineUnverified'
            $statusText = '네트워크 미확인'
            $reason     = '사내망에 연결되지 않아 프린터 응답을 확인하지 못했습니다. 새 PC에서 사내망 연결 시 자동으로 확인합니다.'
        } elseif ($portKind -eq 'TCPIP') {
            $chk = Test-TcpIpPrinterHealth -HostAddress $hostAddress -Protocol $protocol -PortNumber ([int]$portNumber) -SkipAliveFilter:$spec.SkipAliveFilter
            $statusCode = $chk.Status
            $reason     = $chk.Reason
            if ($statusCode -eq 'Healthy') { $statusText = '정상' }
            elseif ($statusCode -eq 'Ambiguous') { $statusText = '응답 확인 필요' }
            else { $statusText = '응답 없음' }
        } elseif ($portKind -eq 'LOCAL_UNC' -or $portKind -eq 'SHARED_UNC') {
            $targetUnc = $port
            if ($connName) { $targetUnc = $connName }
            $chk = Test-UncSharePrinterAlive -UncPath $targetUnc
            $statusCode = $chk.Status
            $reason     = $chk.Reason
            if ($statusCode -eq 'Healthy') { $statusText = '정상' }
            elseif ($statusCode -eq 'AuthOrSidConflict') { $statusText = '인증 확인 필요' }
            elseif ($statusCode -eq 'Ambiguous') { $statusText = '응답 확인 필요' }
            else { $statusText = '응답 없음' }
        } elseif ($portKind -in @('USB', 'LPT', 'COM')) {
            $statusCode = 'Healthy'
            $statusText = '정상'
            $reason     = "로컬 직결 포트 ($portKind)"
        }

        if ($spec.IsSpecial) {
            if ($spec.Win11ReinstallOnly) { $reason = "새 PC 전용 설치 필요 · $reason" }
            if ($spec.IsSubPcShared)      { $reason = "공유 바코드 장비 · 출력 불가 시 유지보수팀 인계 · $reason" }
            if ($statusCode -eq 'Healthy') { $statusText = '특수 장비' }
        }

        $results.Add([pscustomobject]@{
            Selected       = $true
            StatusCode     = $statusCode
            StatusText     = $statusText
            Category       = $spec.Label
            SpecialType    = $spec.Type
            PrinterName    = $pName
            DriverName     = $dName
            PortName       = $port
            PortKind       = $portKind
            HostAddress    = $hostAddress
            Protocol       = $protocol
            PortNumber     = $portNumber
            Queue          = $queue
            ByteCount      = $byteCount
            ConnectionName = $connName
            WsdTargetIp    = $wsdTargetIp
            WsdModelName   = $wsdModelName
            WsdTargetMode  = $wsdTargetMode
            WsdTargetShare = $wsdTargetShare
            IsDefault      = [bool]$p.Default
            Reason         = $reason
        })
    }

    return @($results.ToArray())
}
