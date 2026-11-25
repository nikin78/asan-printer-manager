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
        $title = '[경고] 그룹 정책으로 Windows 보호 인쇄 모드(WPP)가 활성화되어 있습니다! (서드파티 드라이버 복원 차단)'
        $guide = @(
            '현재 PC에 그룹 정책(GPO)으로 Windows 보호 인쇄 모드(WPP)가 강제 적용되어 있어,',
            '교세라·삼성·바코드·진료카드(SIP-30M) 등 서드파티 프린터 드라이버 설치 및 복원이 전면 차단됩니다.',
            '',
            '[조치 후 프로그램 이용 방법]',
            '1. 실행(Win+R) -> gpedit.msc 실행',
            '2. [컴퓨터 구성] -> [관리 템플릿] -> [프린터] -> [Windows 보호 인쇄 구성] 더블클릭',
            '3. [사용 안 함] 또는 [구성되지 않음] 선택 후 확인 -> 관리자 CMD에서 gpupdate /force 실행',
            '4. 도메인/보안 정책으로 변경이 불가하면 IT서비스팀 시스템 관리자에게 정책 해제를 요청하세요.',
            '5. 정책 해제 완료 후 본 프로그램 상단 [새로고침(F5)]을 눌러 경고가 사라진 뒤 복원을 진행하세요.'
        ) -join "`r`n"
    } else {
        $title = '[경고] Windows 보호 인쇄 모드(WPP)가 켜져 있습니다! 해제 후 복원을 진행하세요.'
        $guide = @(
            '현재 PC에 Windows 11 [Windows 보호 인쇄 모드]가 활성화되어 있어,',
            '기존 Win 10 백업 드라이버 및 제조사 전용 드라이버(v3/v4) 복원이 차단됩니다.',
            '',
            '[조치 후 프로그램 이용 방법]',
            '1. 아래 [Windows 프린터 설정 열기] 버튼을 누르거나 Windows 설정(Win+I) 실행',
            '2. [Bluetooth 및 장치] -> [프린터 및 스캐너]로 이동',
            '3. 하단 [프린터 기본 설정] 항목의 [Windows 보호 인쇄 모드]에서 [끄기] 클릭 후 확인',
            '4. 해제가 끝나면 본 프로그램 상단 [새로고침(F5)]을 눌러 경고 배너가 사라진 것을 확인한 뒤',
            '   [선택 항목 복원 시작]을 진행하세요.'
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

function Extract-FirstUsableIPv4 {
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

function Get-ConfiguredDefaultPasswords {
    $valid = [System.Collections.Generic.List[string]]::new()
    foreach ($pw in @($global:AsanCtx.DefaultPasswords)) {
        $s = [string]$pw
        if (-not [string]::IsNullOrWhiteSpace($s) -and $s -ne '__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__') {
            $valid.Add($s)
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
    return $false
}

function Ensure-SpoolerRunning {
    param([int]$TimeoutSeconds = 10)
    $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if ($svc.Status -ne 'Running') {
        try { Start-Service -Name Spooler -ErrorAction SilentlyContinue } catch {}
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { break }
            Start-Sleep -Milliseconds 300
        }
    }
}

function Get-LocalMachineSID {
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

function Get-ActiveNetworkInfo {
    $ip          = 'NO_IP'
    $gw          = $null
    $adapterName = ''
    $bestIfIdx   = -1

    $excludeAliasRegex = '(?i)Loopback|Teredo|isatap|Bluetooth|TAP-|VPN'
    $excludeDescRegex  = '(?i)Loopback|Bluetooth|TAP-Windows|Kernel Debug'

    $adapterMap = @{}
    foreach ($na in @(Get-NetAdapter -ErrorAction SilentlyContinue)) {
        $adapterMap[[int]$na.ifIndex] = $na
    }

    $metricMap = @{}
    foreach ($ni in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        $metricMap[[int]$ni.ifIndex] = [int]$ni.InterfaceMetric
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($cfg in @(Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        if (-not $cfg.NetAdapter -or $cfg.NetAdapter.Status -ne 'Up') { continue }
        $alias = [string]$cfg.InterfaceAlias
        $desc  = [string]$cfg.InterfaceDescription
        if ($alias -match $excludeAliasRegex -or $desc -match $excludeDescRegex) { continue }

        $usableIp = $null
        foreach ($v4 in @($cfg.IPv4Address)) {
            if (Test-IsUsableIPv4 -IpText ([string]$v4.IPAddress)) {
                $usableIp = [string]$v4.IPAddress
                break
            }
        }
        if (-not $usableIp) { continue }

        $ifIdx  = [int]$cfg.InterfaceIndex
        $isPhys = $false
        if ($adapterMap.ContainsKey($ifIdx)) { $isPhys = [bool]$adapterMap[$ifIdx].HardwareInterface }
        $gwIp   = $null
        $hasGw  = $false
        if ($cfg.IPv4DefaultGateway) {
            $firstGw = @($cfg.IPv4DefaultGateway) | Select-Object -First 1
            if ($firstGw -and -not [string]::IsNullOrWhiteSpace([string]$firstGw.NextHop)) {
                $gwIp  = [string]$firstGw.NextHop
                $hasGw = $true
            }
        }
        $metric = 9999
        if ($metricMap.ContainsKey($ifIdx)) { $metric = $metricMap[$ifIdx] }

        $tier = 4
        if ($isPhys -and $hasGw) { $tier = 1 }
        elseif ($hasGw) { $tier = 2 }
        elseif ($isPhys) { $tier = 3 }

        $candidates.Add([pscustomobject]@{
            Tier           = $tier
            Metric         = $metric
            IPAddress      = $usableIp
            Gateway        = $gwIp
            AdapterName    = $alias
            InterfaceIndex = $ifIdx
        })
    }

    $best = $candidates | Sort-Object Tier, Metric | Select-Object -First 1
    if ($best) {
        $ip          = $best.IPAddress
        $gw          = $best.Gateway
        $adapterName = $best.AdapterName
        $bestIfIdx   = [int]$best.InterfaceIndex
    }

    return [pscustomobject]@{
        IPAddress      = $ip
        Gateway        = $gw
        AdapterName    = $adapterName
        InterfaceIndex = $bestIfIdx
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
}

function Connect-AsanBackupServer {
    $srvIp = $global:AsanCtx.ServerIP
    if (-not (Test-TcpPortFast -HostIp $srvIp -Port 445 -TimeoutMs 2000)) {
        return $null
    }

    $activeShare = $null
    foreach ($s in $global:AsanCtx.CandidateShares) {
        if (Test-Path -LiteralPath $s) { $activeShare = $s; break }
    }

    if (-not $activeShare) {
        $ipcPath  = "\\$srvIp\IPC$"
        $qualUser = Get-QualifiedRemoteUser -HostName $srvIp -UserName $global:AsanCtx.DefaultUser
        foreach ($pw in @(Get-ConfiguredDefaultPasswords)) {
            [void][AsanWin32.NativeApi]::DisconnectShare($ipcPath)
            $rc = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $qualUser, $pw)
            if ($rc -eq 1219) {
                Disconnect-AllHostSessions -HostName $srvIp
                $rc = [AsanWin32.NativeApi]::ConnectShare($ipcPath, $qualUser, $pw)
            }
            if ($rc -eq 0) {
                # [보안] 백업 서버 관리자 자격증명은 로컬 PC 자격증명 관리자에 영구 저장하지 않고 세션 연결만 사용
                foreach ($s in $global:AsanCtx.CandidateShares) {
                    if (Test-Path -LiteralPath $s) { $activeShare = $s; break }
                    [void][AsanWin32.NativeApi]::ConnectShare($s, $qualUser, $pw)
                    if (Test-Path -LiteralPath $s) { $activeShare = $s; break }
                }
            }
            if ($activeShare) { break }
        }
    }

    if (-not $activeShare) { return $null }

    $prtBakDir = Join-Path $activeShare '_PRTBAK'
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

function Test-AsanNetworkAndServer {
    $netInfo   = Get-ActiveNetworkInfo
    $wppInfo   = Test-WindowsProtectedPrintMode
    $dnsOk     = $false
    $dnsConf   = $false
    $serverTcp = $false
    $prtBakDir = $null
    $status    = 'Offline'
    $message   = '사내망 미연결 — 고정 IP 및 DNS(10.71.1.5)를 먼저 설정하세요.'

    if ($netInfo.HasValidIP) {
        if ($netInfo.InterfaceIndex -gt 0) {
            try {
                $dnsServers = @(Get-DnsClientServerAddress -InterfaceIndex $netInfo.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses })
                if ($dnsServers -contains $global:AsanCtx.InternalDnsIP) { $dnsConf = $true }
            } catch {}
        }

        $dnsOk     = (Test-TcpPortFast -HostIp $global:AsanCtx.InternalDnsIP -Port 53 -TimeoutMs 1200) -or (Test-PingFast -HostIp $global:AsanCtx.InternalDnsIP -TimeoutMs 1000)
        $serverTcp = Test-TcpPortFast -HostIp $global:AsanCtx.ServerIP -Port 445 -TimeoutMs 2000

        if ($serverTcp) {
            $prtBakDir = Connect-AsanBackupServer
            if ($prtBakDir) {
                $status  = 'Online'
                $message = "사내망 및 백업 서버 정상 연결됨 ($prtBakDir)"
            } else {
                $status  = 'IntranetOnly'
                $message = "백업 서버($($global:AsanCtx.ServerIP)) SMB 포트는 열려 있으나 공유 폴더 접근/인증에 실패했습니다."
            }
        } elseif ($dnsOk -or ($dnsConf -and $netInfo.Gateway -and (Test-PingFast -HostIp $netInfo.Gateway -TimeoutMs 1000))) {
            $status  = 'IntranetOnly'
            $message = "사내망은 연결되었으나 백업 서버($($global:AsanCtx.ServerIP))가 응답하지 않습니다."
        }
    }

    return [pscustomobject]@{
        Status      = $status
        Message     = $message
        IPAddress   = $netInfo.IPAddress
        Gateway     = $netInfo.Gateway
        AdapterName = $netInfo.AdapterName
        DnsOk       = $dnsOk
        ServerTcpOk = $serverTcp
        PrtBakDir   = $prtBakDir
        WppStatus   = $wppInfo
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
            Label              = '진료카드(SIP-30M)'
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
            Label              = '네임바코드(세우)'
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
            Label              = '라벨(ZT410/411)'
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
            Label              = '검사/투약(ZD410)'
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
            Label              = '팔찌바코드(TX220)'
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
                Label              = 'LPT1무드라이버(TM-T88)'
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
            Label              = '영수증/라벨(TM-T88)'
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
            Label              = '기타 라벨/특수'
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
    return @($lpts.ToArray())
}

function Get-BrokenBarcodeUsbDevices {
    param([switch]$IncludeHealthyBarcode)

    # 검증된 바코드 프린터 VID/모델만 허용 (Zebra=0A5F, BIXOLON=1504; 범용 Netchip 0525 및 Win10 Sewoo 제외)
    $vidRegex     = '(?i)VID_(0A5F|1504)'
    $nameRegex    = '(?i)Zebra|ZDesigner|ZD410|ZD411|ZT410|ZT411|BIXOLON|SLP-TX|TX220|TX-220'
    $excludeRegex = '(?i)Sewoo|SLK-TE|LK-TE'

    $found = [System.Collections.Generic.List[object]]::new()
    try {
        $pnpAll = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.DeviceID) -match '^(?i)(USB\\VID_|USBPRINT\\)'
        })
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
    return @($found.ToArray() | Sort-Object SortRank, DeviceID)
}

function Invoke-UsbBarcodeAutoReenumerate {
    param(
        [int]$WaitSeconds = 8,
        [switch]$ForceAllBarcodeUsb,
        [scriptblock]$OnProgress = $null
    )

    $beforePorts = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name } | Sort-Object)
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
            $curPorts = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name })
            $addedNow = @($curPorts | Where-Object { $beforePorts -notcontains $_ })
            if ($addedNow.Count -gt 0) { break }
            if ($sec -ge 3) {
                $stillNow = @(Get-BrokenBarcodeUsbDevices)
                if (($beforeProb -gt 0 -and $stillNow.Count -lt $beforeProb) -or ($beforeProb -eq 0 -and $curPorts.Count -gt 0 -and $stillNow.Count -eq 0)) { break }
            }
        }
    }

    $afterPorts  = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^USB\d+' } | ForEach-Object { [string]$_.Name } | Sort-Object)
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
        $qUser = Get-QualifiedRemoteUser -HostName $HostName -UserName $CustomUser
        $attempts.Add([pscustomobject]@{ User = $qUser; Pass = [string]$CustomPass; IsCustom = $true })
    } else {
        $qDef = Get-QualifiedRemoteUser -HostName $HostName -UserName $global:AsanCtx.DefaultUser
        foreach ($pw in @(Get-ConfiguredDefaultPasswords)) {
            $attempts.Add([pscustomobject]@{ User = $qDef; Pass = $pw; IsCustom = $false })
        }
    }

    if ($attempts.Count -eq 0) {
        return [pscustomobject]@{
            Success    = $false
            Status     = 'AuthOrSidConflict'
            Win32Error = 1326
            Reason     = '기본 공용 암호가 구성되지 않았습니다(secrets.local.json 확인) — 하단 인증 패널에서 직접 계정을 입력하세요.'
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
            [void][AsanWin32.NativeApi]::WriteDomainCredential($HostName, $att.User, $att.Pass)
            $global:AsanCtx.HostCredCache[$cacheKey] = [pscustomobject]@{ User = $att.User; Pass = $att.Pass }
            return [pscustomobject]@{ Success = $true; Status = 'Authenticated'; Win32Error = 0; Reason = "인증 성공 ($($att.User))"; UsedUser = $att.User; UsedPass = $att.Pass }
        }

        $lastRc = $rc
        if ($rc -in @(5, 86, 1326, 1331, 1909)) {
            $authErrDetected = $true
        }
    }

    if ($authErrDetected) {
        $sidHint = "기본 공용 암호 3종 인증 실패 (Win32=$lastRc) -> 메인 PC 암호 변경 또는 동일 Windows SID 충돌 의심"
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

    return [pscustomobject]@{
        Success    = $false
        Status     = 'ConnectError'
        Win32Error = $lastRc
        Reason     = "공유 호스트($HostName) SMB 연결 실패 (Win32 Error=$lastRc)"
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
    $matched = $enumRes.Shares | Where-Object { $_ -ieq $shareName } | Select-Object -First 1
    if ($matched) {
        return [pscustomobject]@{ Status = 'Healthy'; Reason = "공유 호스트 인증 및 프린터 공유($shareName) 정상 확인"; HostName = $hostName; ShareName = $shareName }
    }

    if (Test-Path -LiteralPath $UncPath) {
        return [pscustomobject]@{ Status = 'Healthy'; Reason = "UNC 공유 경로($UncPath) 접근 정상 확인"; HostName = $hostName; ShareName = $shareName }
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

function Clean-DeviceString {
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
    $foundIp    = Extract-FirstUsableIPv4 -Text "$PortName $PrinterName"
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
                    $cand = Extract-FirstUsableIPv4 -Text $pv
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
                    $cleanFn = Clean-DeviceString -Raw $fName
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
                    $propsList = @(Get-PnpDeviceProperty -InstanceId $instId -ErrorAction SilentlyContinue)
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
                                $pvCln = Clean-DeviceString -Raw $pvTxt
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
                            $candIp = Extract-FirstUsableIPv4 -Text $pVal
                            if ($candIp) { $foundIp = $candIp; break }
                        } elseif ($pVal -match 'https?://') {
                            $candIp = Extract-FirstUsableIPv4 -Text $pVal -UrlOnly
                            if ($candIp) { $foundIp = $candIp; break }
                        }
                    }
                }

                if (-not $foundModel) {
                    foreach ($pr in $props) {
                        $pKey = [string]$pr.KeyName
                        if ($pKey -match '(?i)(ModelName|Model$|FriendlyName|DeviceDesc)') {
                            $pVal = if ($pr.Data -is [array]) { ($pr.Data -join ' ') } else { [string]$pr.Data }
                            $candModel = Clean-DeviceString -Raw $pVal
                            if ($candModel) { $foundModel = $candModel; break }
                        }
                    }
                    if (-not $foundModel) {
                        $candFn = Clean-DeviceString -Raw $fName
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
                        $rc = Clean-DeviceString -Raw $rv
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
                            $cand = Extract-FirstUsableIPv4 -Text $pv
                            if ($cand) { $foundIp = $cand; break }
                        } elseif ($pv -match 'https?://') {
                            $cand = Extract-FirstUsableIPv4 -Text $pv -UrlOnly
                            if ($cand) { $foundIp = $cand; break }
                        }
                    }
                }
            }

            if (-not $foundModel -and $subProps) {
                foreach ($propName in @('FriendlyName', 'DeviceDesc')) {
                    $cand = Clean-DeviceString -Raw ([string]$subProps.$propName)
                    if ($cand) { $foundModel = $cand; break }
                }
                if (-not $foundModel -and $subProps.HardwareID) {
                    $hwStr = (@($subProps.HardwareID) -join ' ')
                    $hm = [regex]::Match($hwStr, '(?i)(?:Samsung|Kyocera|HP|Canon|Epson|Brother|Ricoh|Sindoh|Xerox|Konica)[^\\,;]+')
                    if ($hm.Success) { $foundModel = ($hm.Value -replace '_', ' ').Trim() }
                }
            }
        }
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
    if ($res.ExitCode -ne 0 -or $res.Lines.Count -eq 0) { return @() }

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
            elseif ($k -match '^(Provider Name|공급자 이름)$') {
                $h['ProviderName'] = $v
            }
            elseif ($k -match '^(Class Name|클래스 이름)$') {
                $h['ClassName'] = $v
            }
            elseif ($k -match '^(Class GUID|클래스 GUID)$' -or ($v -match '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$')) {
                $h['ClassGuid'] = $v.ToLowerInvariant()
            }
            elseif ($k -match '^(Driver Version|드라이버 버전)$' -or ($v -match '^\d{2}/\d{2}/\d{4}\s+[\d\.]+$' -and -not $h.ContainsKey('DriverVersion'))) {
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

    Ensure-SpoolerRunning
    $cimPrinters = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue)
    $tcpPorts    = @(Get-CimInstance -ClassName Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue)
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
            $statusText     = '애매함(WSD)'
            if ($wsd.Status -eq 'WsdConvert') { $statusText = 'WSD전환대상' }
            $reason         = $wsd.Reason
        } elseif ($OfflineMode) {
            $statusCode = 'OfflineUnverified'
            $statusText = '미검증(오프라인)'
            $reason     = '오프라인 모드 — 생존 검증 생략 후 전체 백업 (새 PC 복원 시 지연 검증 수행)'
        } elseif ($portKind -eq 'TCPIP') {
            $chk = Test-TcpIpPrinterHealth -HostAddress $hostAddress -Protocol $protocol -PortNumber ([int]$portNumber) -SkipAliveFilter:$spec.SkipAliveFilter
            $statusCode = $chk.Status
            $reason     = $chk.Reason
            if ($statusCode -eq 'Healthy') { $statusText = '정상' }
            elseif ($statusCode -eq 'Ambiguous') { $statusText = '애매함' }
            else { $statusText = '비활성의심' }
        } elseif ($portKind -eq 'LOCAL_UNC' -or $portKind -eq 'SHARED_UNC') {
            $targetUnc = $port
            if ($connName) { $targetUnc = $connName }
            $chk = Test-UncSharePrinterAlive -UncPath $targetUnc
            $statusCode = $chk.Status
            $reason     = $chk.Reason
            if ($statusCode -eq 'Healthy') { $statusText = '정상' }
            elseif ($statusCode -eq 'AuthOrSidConflict') { $statusText = '인증/SID의심' }
            elseif ($statusCode -eq 'Ambiguous') { $statusText = '애매함' }
            else { $statusText = '비활성의심' }
        } elseif ($portKind -in @('USB', 'LPT', 'COM')) {
            $statusCode = 'Healthy'
            $statusText = '정상(직결)'
            $reason     = "로컬 직결 포트($portKind)"
        }

        if ($spec.IsSpecial) {
            if ($spec.Win11ReinstallOnly) { $reason = "[Win11 전용 재설치 필수] $reason" }
            if ($spec.IsSubPcShared)      { $reason = "[서브 PC 공유 바코드 — 출력 불가 시 유지보수팀 인계] $reason" }
            if ($statusCode -eq 'Healthy') { $statusText = "특수($($spec.Label))" }
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
