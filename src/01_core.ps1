#Requires -Version 5.1
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'
Import-Module PrintManagement -ErrorAction SilentlyContinue

# ============================================================================
# [Module 01] Runspace 스레드 안전 전역 컨텍스트 ($global:AsanCtx)
# ============================================================================
$resolvedOrigPath = $env:ASAN_ORIGINAL_SELF
if (-not [string]::IsNullOrWhiteSpace($env:ASAN_ORIGINAL_SELF_B64)) {
    try {
        $b64Std = $env:ASAN_ORIGINAL_SELF_B64.Replace('-', '+').Replace('_', '/')
        $padLen = (4 - ($b64Std.Length % 4)) % 4
        if ($padLen -gt 0) { $b64Std = $b64Std + ('=' * $padLen) }
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64Std))
        if (-not [string]::IsNullOrWhiteSpace($decoded)) { $resolvedOrigPath = $decoded }
    } catch {}
}

$serverIpVal = '172.25.152.232'
$prtClass    = '{4d36e979-e325-11ce-bfc1-08002be2092f}'
$pqClass     = '{1ed2bbf9-11f0-4084-b21f-ad83a8e6dcdc}'

$global:AsanCtx = [hashtable]::Synchronized(@{
    AppVersion                 = '1.0.0-beta.3'
    OriginalScriptPath         = $resolvedOrigPath
    ServerIP                   = $serverIpVal
    InternalDnsIP              = '10.71.1.5'
    DefaultUser                = 'admin'
    DefaultPasswords           = @('__ASAN_DEFAULT_PASSWORDS_PLACEHOLDER__')
    CandidateShares            = @("\\$serverIpVal\백업 작업", "\\$serverIpVal\백업폴더")
    DriverRoots                = @(
        'C:\Users\admin\드라이버(win10_x64)\PRT',
        'C:\Users\admin\드라이버(win10x64)\PRT',
        'C:\Users\admin\드라이버(win10_x64)\AMIS3.0장비\PRT',
        'C:\Users\admin\드라이버(win10x64)\AMIS3.0장비\PRT'
    )
    DriverExcludeFolderPattern = '(?i)스캔유틸|ScannerFileUtility|ScanUtility'
    PrintBrmExe                = (Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe')
    OfflineLocalRoot           = 'C:\_AsanPrtOffline'
    WorkBaseDir                = (Join-Path $env:TEMP 'AsanPrinterMgr')
    PrinterClassGuid           = $prtClass
    PrintQueueClassGuid        = $pqClass
    PrinterClassGuids          = @($prtClass, $pqClass)
    ImageClassGuid             = '{6bdd1fc6-810f-11d0-bec7-08002be2092f}'
    VirtualPrinterExact        = @(
        'Microsoft Print to PDF',
        'Microsoft XPS Document Writer',
        'Fax',
        'OneNote 16으로 보내기',
        'OneNote (Desktop)',
        'OneNote for Windows 10',
        'Send To OneNote 2016',
        'PDF24 Fax',
        'PDF24 PDF',
        'Adobe PDF',
        'Hancom PDF'
    )
    VirtualPrinterRegex        = '(?i)^(Microsoft Print to PDF|Microsoft XPS|Fax|OneNote|Send To OneNote|PDF24|Adobe PDF|Hancom PDF|Foxit.*PDF|doPDF|CutePDF|Bullzip|PrimoPDF)'
    VirtualPortRegex           = '(?i)^(PORTPROMPT:|NUL:|FILE:|XPSPort:|SHRFAX:|PDF24|nul$|file$)'
    MicrosoftInboxGenericRegex = '(?i)(Microsoft IPP|Microsoft .*Class Driver|Microsoft Enhanced Point and Print|Generic / Text Only|Point and Print|Class Driver$)'
    VendorUniversalRegex       = '(?i)(KX DRIVER for Universal Printing|HP Universal Printing|Samsung Universal Print Driver|Universal Print Driver|Universal Printing)'
    InboxInfNameRegex          = '(?i)^(ntprint|prn[a-z0-9]+|mxdwdrv|msprint|printqueue|tsprint|c_printer)\.inf$'
    ScannerWhitelistRegex      = '(?i)(Samsung|Kyocera|Hewlett-Packard|\bHP\b|Canon|Epson|Brother|Ricoh|Savin|Lanier|Konica|Minolta|Fuji|Xerox|Sindoh|Sharp|Toshiba|Lexmark|\bOKI\b|Pantum|Panasonic|Fujitsu|\bPFU\b|ScanSnap|Kodak|Alaris|Plustek|Avision|CZUR|\bIRIS\b|Microtek|Visioneer|Mustek|Ambir|Eloam|Hanwang|Nikon|Desko|Thales|Gemalto|\b3M\b|IDCOS|SISS|Sewoo|Bixolon|Zebra|Dymo)'
    ScannerBlacklistRegex      = '(?i)(Microsoft|Intel|AMD|NVIDIA|Realtek|Logitech|Sunplus|Sonix|Chicony|Bison|Quanta|AzureWave|\bOBS\b|DroidCam|Iriun|ManyCam|Razer|Elgato|Insta360|AVerMedia|Creative|Guillemot|Hikvision|WebCam|Virtual Camera)'
    HostCredCache              = [hashtable]::Synchronized(@{})
    LogQueue                   = [System.Collections.Concurrent.ConcurrentQueue[psobject]]::new()
})

# ============================================================================
# Win32 네이티브 API 모듈 (C# 5.0 호환 / CredWriteW·CredDeleteW·CredReadW)
# ============================================================================
if (-not ('AsanWin32.NativeApi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace AsanWin32
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class NETRESOURCE
    {
        public int dwScope = 0;
        public int dwType = 0;
        public int dwDisplayType = 0;
        public int dwUsage = 0;
        public string lpLocalName = null;
        public string lpRemoteName = null;
        public string lpComment = null;
        public string lpProvider = null;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHARE_INFO_1
    {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi1_netname;
        public uint shi1_type;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi1_remark;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct CREDENTIAL
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    public class ShareEnumResult
    {
        public int Win32Error;
        public string[] Shares;
    }

    public static class NativeApi
    {
        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        public static extern int WNetAddConnection2W(
            NETRESOURCE lpNetResource,
            string lpPassword,
            string lpUsername,
            int dwFlags);

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        public static extern int WNetCancelConnection2W(
            string lpName,
            int dwFlags,
            bool fForce);

        [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
        private static extern int NetShareEnum(
            string ServerName,
            int level,
            out IntPtr bufPtr,
            uint prefmaxlen,
            out int entriesread,
            out int totalentries,
            ref int resume_handle);

        [DllImport("netapi32.dll")]
        private static extern int NetApiBufferFree(IntPtr Buffer);

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(
            string target,
            uint type,
            uint reservedFlag,
            out IntPtr credentialPtr);

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(
            ref CREDENTIAL userCredential,
            uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(
            string target,
            uint type,
            uint flags);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern void CredFree(IntPtr buffer);

        public static void HideConsoleWindow()
        {
            IntPtr hwnd = GetConsoleWindow();
            if (hwnd != IntPtr.Zero)
            {
                ShowWindow(hwnd, 0);
            }
        }

        public static bool HasStoredCredential(string targetHost)
        {
            if (string.IsNullOrEmpty(targetHost)) return false;
            string clean = targetHost.Trim().TrimStart('\\');
            string[] candidates = new string[] {
                clean,
                "\\\\" + clean,
                "Domain:target=" + clean
            };
            uint[] types = new uint[] { 2, 4 };
            for (int i = 0; i < candidates.Length; i++)
            {
                for (int t = 0; t < types.Length; t++)
                {
                    IntPtr ptr = IntPtr.Zero;
                    if (CredRead(candidates[i], types[t], 0, out ptr))
                    {
                        if (ptr != IntPtr.Zero) CredFree(ptr);
                        return true;
                    }
                }
            }
            return false;
        }

        public static bool WriteDomainCredential(string targetHost, string username, string password)
        {
            if (string.IsNullOrEmpty(targetHost) || string.IsNullOrEmpty(username)) return false;
            string clean = targetHost.Trim().TrimStart('\\');
            byte[] pwBytes = Encoding.Unicode.GetBytes(password == null ? "" : password);
            IntPtr blobPtr = IntPtr.Zero;
            try
            {
                if (pwBytes.Length > 0)
                {
                    blobPtr = Marshal.AllocCoTaskMem(pwBytes.Length);
                    Marshal.Copy(pwBytes, 0, blobPtr, pwBytes.Length);
                }
                CREDENTIAL cred = new CREDENTIAL();
                cred.Type = 2;
                cred.TargetName = clean;
                cred.UserName = username;
                cred.CredentialBlobSize = (uint)pwBytes.Length;
                cred.CredentialBlob = blobPtr;
                cred.Persist = 2;
                return CredWrite(ref cred, 0);
            }
            finally
            {
                if (pwBytes.Length > 0) Array.Clear(pwBytes, 0, pwBytes.Length);
                if (blobPtr != IntPtr.Zero)
                {
                    byte[] zeros = new byte[pwBytes.Length];
                    Marshal.Copy(zeros, 0, blobPtr, zeros.Length);
                    Marshal.FreeCoTaskMem(blobPtr);
                }
            }
        }

        public static void DeleteDomainCredential(string targetHost)
        {
            if (string.IsNullOrEmpty(targetHost)) return;
            string clean = targetHost.Trim().TrimStart('\\');
            string[] candidates = new string[] {
                clean,
                "\\\\" + clean,
                "Domain:target=" + clean
            };
            uint[] types = new uint[] { 2, 4 };
            for (int i = 0; i < candidates.Length; i++)
            {
                for (int t = 0; t < types.Length; t++)
                {
                    CredDelete(candidates[i], types[t], 0);
                }
            }
        }

        public static int ConnectShare(string remotePath, string username, string password)
        {
            NETRESOURCE nr = new NETRESOURCE();
            nr.dwType = 0;
            nr.lpRemoteName = remotePath;
            return WNetAddConnection2W(nr, password, username, 0);
        }

        public static int DisconnectShare(string remotePath)
        {
            return WNetCancelConnection2W(remotePath, 0, true);
        }

        public static ShareEnumResult EnumPrintSharesEx(string serverUnc)
        {
            ShareEnumResult res = new ShareEnumResult();
            List<string> results = new List<string>();
            IntPtr bufPtr = IntPtr.Zero;
            int entriesRead = 0;
            int totalEntries = 0;
            int resumeHandle = 0;

            int rc = NetShareEnum(serverUnc, 1, out bufPtr, 0xFFFFFFFF, out entriesRead, out totalEntries, ref resumeHandle);
            res.Win32Error = rc;

            if ((rc == 0 || rc == 234) && bufPtr != IntPtr.Zero)
            {
                try
                {
                    int structSize = Marshal.SizeOf(typeof(SHARE_INFO_1));
                    long baseAddr = bufPtr.ToInt64();
                    for (int i = 0; i < entriesRead; i++)
                    {
                        IntPtr itemPtr = new IntPtr(baseAddr + ((long)i * structSize));
                        SHARE_INFO_1 info = (SHARE_INFO_1)Marshal.PtrToStructure(itemPtr, typeof(SHARE_INFO_1));
                        uint baseType = info.shi1_type & 0x0FFFFFFF;
                        if (baseType == 1 && !string.IsNullOrEmpty(info.shi1_netname))
                        {
                            results.Add(info.shi1_netname);
                        }
                    }
                }
                finally
                {
                    NetApiBufferFree(bufPtr);
                }
            }
            res.Shares = results.ToArray();
            return res;
        }
    }
}
'@
}

function Hide-ConsoleWindowSafe {
    try { [AsanWin32.NativeApi]::HideConsoleWindow() } catch {}
}

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

    try {
        $pnpDevices = [System.Collections.Generic.List[object]]::new()
        foreach ($pattern in @('SWD\DAFWSDProvider*', 'SWD\PRINTENUM*')) {
            foreach ($dev in @(Get-PnpDevice -InstanceId $pattern -ErrorAction SilentlyContinue)) {
                $pnpDevices.Add($dev)
            }
        }

        # 1패스: WSD 포트 고유 UUID/GUID 정확 매칭 우선 -> 2패스: 프린터명 부분 일치 폴백
        for ($wsdPass = 1; $wsdPass -le 2; $wsdPass++) {
            if ($foundIp -and $foundModel) { break }
            foreach ($dev in $pnpDevices) {
                if ($foundIp -and $foundModel) { break }
                $instId = [string]$dev.InstanceId
                $fName  = [string]$dev.FriendlyName

                $directHit = $false
                if ($wsdPass -eq 1) {
                    foreach ($mk in $matchKeys) {
                        if ($instId.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $directHit = $true; break }
                    }
                } else {
                    if ($PrinterName.Length -ge 3 -and $fName.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $directHit = $true
                    }
                }
                if (-not $directHit -and $instId -notlike 'SWD\DAFWSDProvider*') { continue }

                $props    = @(Get-PnpDeviceProperty -InstanceId $instId -ErrorAction SilentlyContinue)
                $propBlob = ($props | ForEach-Object {
                    if ($_.Data -is [array]) { ($_.Data -join ' ') } else { [string]$_.Data }
                }) -join ' '

                if (-not $directHit) {
                    $propHit = $false
                    if ($wsdPass -eq 1) {
                        foreach ($mk in $matchKeys) {
                            if ($propBlob.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $propHit = $true; break }
                        }
                    } else {
                        if ($PrinterName.Length -ge 3 -and $propBlob.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
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
        }
    } catch {}

    if (-not $foundIp -or -not $foundModel) {
        $enumRoots = @(
            'HKLM:\SYSTEM\CurrentControlSet\Enum\SWD\PRINTENUM',
            'HKLM:\SYSTEM\CurrentControlSet\Enum\UMB\UMB'
        )
        # 레지스트리 보조 스캔도 1패스(UUID/GUID 우선) -> 2패스(프린터명 부분 일치 폴백)
        for ($regPass = 1; $regPass -le 2; $regPass++) {
            if ($foundIp -and $foundModel) { break }
            foreach ($root in $enumRoots) {
                if (($foundIp -and $foundModel) -or -not (Test-Path -LiteralPath $root)) { break }
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

                    $hit = $false
                    if ($regPass -eq 1) {
                        foreach ($mk in $matchKeys) {
                            if ($blob.IndexOf($mk, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
                        }
                    } else {
                        if ($PrinterName.Length -ge 3 -and $blob.IndexOf($PrinterName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
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
                    if ($foundIp -and $foundModel) { break }
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

# ============================================================================
# 모델 줄기/와일드카드 매칭 + 2패스 드라이버 해결 엔진
# ============================================================================
function Normalize-Text {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant())
}

function Get-DetectedVendors {
    param([string]$Text)
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    if ($Text -match '(?i)Samsung|삼성')                                { $list.Add('SAMSUNG') }
    if ($Text -match '(?i)Kyocera|교세라|ECOSYS|TASKalfa|\bKX DRIVER\b') { $list.Add('KYOCERA') }
    if ($Text -match '(?i)Hewlett-Packard|\bHP\b|LaserJet|OfficeJet')   { $list.Add('HP') }
    if ($Text -match '(?i)Canon|캐논')                                  { $list.Add('CANON') }
    if ($Text -match '(?i)Epson|엡손')                                  { $list.Add('EPSON') }
    if ($Text -match '(?i)Brother|브라더')                              { $list.Add('BROTHER') }
    if ($Text -match '(?i)Ricoh|리코|Savin|Lanier')                     { $list.Add('RICOH') }
    if ($Text -match '(?i)Konica|Minolta|코니카')                       { $list.Add('KONICA') }
    if ($Text -match '(?i)Fuji|Xerox|제록스')                           { $list.Add('XEROX') }
    if ($Text -match '(?i)Sindoh|신도리코')                             { $list.Add('SINDOH') }
    if ($Text -match '(?i)Zebra|ZDesigner|ZD410|ZD411|ZT410|ZT411|ZBRN') { $list.Add('ZEBRA') }
    if ($Text -match '(?i)Bixolon|빅솔론|SLP-TX|TX220|TX-220')           { $list.Add('BIXOLON') }
    if ($Text -match '(?i)Sewoo|세우|SLK-TE|LK-TE')                     { $list.Add('SEWOO') }
    if ($Text -match '(?i)SISS|HODOO|SIP-30|IDCOS')                     { $list.Add('SISS') }
    return @($list.ToArray())
}

function Get-DetectedVendor {
    param([string]$Text)
    $vs = @(Get-DetectedVendors -Text $Text)
    if ($vs.Count -gt 0) { return $vs[0] }
    return $null
}

function Get-SignificantTokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $stopWords = @(
        'kyocera','samsung','driver','drivers','printer','printing','model','series',
        'kx','pcl','pcl5','pcl5e','pcl5c','pcl6','pclxl','ps','postscript','xps','spl',
        'v3','v4','type3','type4','classic','package','packaged','microsoft','windows',
        'win10','win11','x64','64bit','class','universal','generic','for','sl'
    )
    $tokens = [regex]::Matches($Text.ToLowerInvariant(), '[\p{L}\p{Nd}]+') |
        ForEach-Object { $_.Value } |
        Where-Object { $_.Length -ge 3 -and $_ -notin $stopWords } |
        Select-Object -Unique
    return @($tokens)
}

function Get-ModelStems {
    param([string[]]$Tokens)
    $stems = [System.Collections.Generic.List[string]]::new()
    foreach ($t in @($Tokens)) {
        if ($t -notmatch '\d') { continue }
        $clean = $t.ToLowerInvariant() -replace '^sl', ''
        if ($clean.Length -ge 3 -and -not $stems.Contains($clean)) { $stems.Add($clean) }

        $stripped = $clean -replace '(?<=\d)(?:idn|dwf|fdn|fdw|cdw|nd|dn|dw|nx|nf|fw|fn|cw|cn|f|d|n|w|x)$', ''
        if ($stripped.Length -ge 3 -and -not $stems.Contains($stripped)) { $stems.Add($stripped) }

        $numM = [regex]::Match($stripped, '\d{3,}')
        if ($numM.Success -and -not $stems.Contains($numM.Value)) { $stems.Add($numM.Value) }
    }
    return @($stems.ToArray())
}

function Test-WildcardModelMatch {
    param(
        [string]$CandidateDisplayName,
        [string[]]$WantedStems
    )
    if ([string]::IsNullOrWhiteSpace($CandidateDisplayName) -or -not $WantedStems -or $WantedStems.Count -eq 0) { return $false }

    $candTokens = [regex]::Matches($CandidateDisplayName.ToLowerInvariant(), '[a-z]*\d+[a-z0-9]*') | ForEach-Object { $_.Value }
    foreach ($ct in @($candTokens)) {
        if ($ct -match '^([a-z]*\d+)x+$') {
            $pat = '^' + [regex]::Escape($matches[1]) + '[0-9a-z]*$'
            foreach ($ws in $WantedStems) {
                if ($ws -match $pat) { return $true }
            }
        }
        $ctStripped = $ct -replace '(?<=\d)(?:idn|dwf|fdn|fdw|cdw|nd|dn|dw|nx|nf|fw|fn|cw|cn|f|d|n|w|x)$', ''
        if ($ctStripped.Length -ge 3) {
            foreach ($ws in $WantedStems) {
                if ($ws -eq $ctStripped) { return $true }
            }
        }
    }
    return $false
}

function Get-DriverProtocolTag {
    param([string]$DriverName)
    if ([string]::IsNullOrWhiteSpace($DriverName)) { return 'UNKNOWN' }
    if ($DriverName -match '(?i)PCL\s*6|PCL6|PCL\s*XL')  { return 'PCL6' }
    if ($DriverName -match '(?i)\bKX\b')                  { return 'KX' }
    if ($DriverName -match '(?i)PCL\s*5|PCL5')            { return 'PCL5' }
    if ($DriverName -match '(?i)\bPS\b|PostScript|KPDL')  { return 'PS' }
    if ($DriverName -match '(?i)\bXPS\b')                 { return 'XPS' }
    if ($DriverName -match '(?i)\bSPL\b')                 { return 'SPL' }
    if ($DriverName -match '(?i)\bZPL\b|\bEPL\b|\bSLCS\b') { return 'LABEL' }
    return 'OTHER'
}

function Get-ProtocolPreferenceBonus {
    param([string]$DriverName)
    $tag = Get-DriverProtocolTag -DriverName $DriverName
    switch ($tag) {
        'PCL6'  { return 180 }
        'KX'    { return 150 }
        'PCL5'  { return 80 }
        'PS'    { return 40 }
        'XPS'   { return 10 }
        default { return 0 }
    }
}

function Get-InfTextSafe {
    param([string]$InfPath)
    try {
        return (Get-Content -LiteralPath $InfPath -Raw -ErrorAction Stop)
    } catch {
        try { return [IO.File]::ReadAllText($InfPath, [Text.Encoding]::Default) } catch { return $null }
    }
}

function Get-InfDisplayNames {
    param([string]$InfText)
    if ([string]::IsNullOrWhiteSpace($InfText)) { return @() }

    $stringTable    = @{}
    $stringPriority = @{}
    $directNames    = [System.Collections.Generic.List[string]]::new()
    $tokenRefs      = [System.Collections.Generic.List[string]]::new()
    $section        = ''
    $skipDirectSec  = '(?i)^(Version|SourceDisksNames(?:\..+)?|SourceDisksFiles(?:\..+)?|DestinationDirs|ControlFlags|ClassInstall32(?:\..+)?|Manufacturer|DefaultInstall(?:\..+)?)$'

    foreach ($rawLine in ($InfText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        $secM = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
        if ($secM.Success) { $section = $secM.Groups[1].Value.Trim(); continue }
        if ($section -match '(?i)^strings(?:\.([0-9a-f]+))?$') {
            $langTag = ''
            if ($matches[1]) { $langTag = $matches[1].ToLowerInvariant() }
            # 우선순위: [Strings](영문 기본)=3, [Strings.0412](한국어)=2, [Strings.0409]=2, 기타 언어(중국어/러시아어 등)=1
            $prio = 1
            if ($langTag -eq '') { $prio = 3 }
            elseif ($langTag -in @('0412', '0409')) { $prio = 2 }

            $strM = [regex]::Match($line, '^\s*([^=;]+?)\s*=\s*"([^"]+)"')
            if ($strM.Success) {
                $k = $strM.Groups[1].Value.Trim().Trim('%').ToLowerInvariant()
                $v = $strM.Groups[2].Value.Trim()
                if ($k -and $v) {
                    $prevPrio = 0
                    if ($stringPriority.ContainsKey($k)) { $prevPrio = [int]$stringPriority[$k] }
                    if ($prio -ge $prevPrio) {
                        $stringTable[$k]    = $v
                        $stringPriority[$k] = $prio
                    }
                }
            }
            continue
        }
        if ($section -match $skipDirectSec) { continue }
        $dirM = [regex]::Match($line, '^\s*"([^"]+)"\s*=')
        if ($dirM.Success) {
            $v = $dirM.Groups[1].Value.Trim()
            if ($v -and -not $directNames.Contains($v)) { $directNames.Add($v) }
        }
        $tokM = [regex]::Match($line, '^\s*%([^%]+)%\s*=')
        if ($tokM.Success) {
            $k = $tokM.Groups[1].Value.Trim().ToLowerInvariant()
            if ($k -and -not $tokenRefs.Contains($k)) { $tokenRefs.Add($k) }
        }
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $directNames) { if (-not $names.Contains($n)) { $names.Add($n) } }
    foreach ($k in $tokenRefs) {
        if ($stringTable.ContainsKey($k)) {
            $v = [string]$stringTable[$k]
            if ($v -and -not $names.Contains($v)) { $names.Add($v) }
        }
    }
    if ($names.Count -eq 0) {
        foreach ($v in $stringTable.Values) {
            $s = [string]$v
            if ($s.Length -ge 3 -and $s.Length -le 160 -and -not $names.Contains($s)) { $names.Add($s) }
        }
    }
    return @($names.ToArray())
}

function Build-InfIndexCache {
    param([IO.FileInfo[]]$InfFiles)
    $cache = [System.Collections.Generic.List[object]]::new()
    if (-not $InfFiles -or $InfFiles.Count -eq 0) { return @() }

    foreach ($inf in $InfFiles) {
        $text = Get-InfTextSafe -InfPath $inf.FullName
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $dispNames = @(Get-InfDisplayNames -InfText $text)
        $vendorHintText = ($dispNames -join ' ') + ' ' + $inf.Name
        # 모델명 문자열에 제조사 브랜드가 생략된 INF를 위해 Provider/Manufacturer 헤더 보조 확인
        $hdrMatches = [regex]::Matches($text, '(?im)^\s*Provider\s*=\s*(.+)$')
        foreach ($hm in $hdrMatches) { $vendorHintText += ' ' + $hm.Groups[1].Value }
        $vendors = @(Get-DetectedVendors -Text $vendorHintText)
        $cache.Add([pscustomobject]@{
            Path         = $inf.FullName
            FileName     = $inf.Name
            TextNorm     = (Normalize-Text $text)
            DisplayNames = $dispNames
            Vendors      = $vendors
        })
    }
    return @($cache.ToArray())
}

function Get-DriverStorePrinterInfFiles {
    $infList = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $seen    = @{}
    $repoDir = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'
    if (-not (Test-Path -LiteralPath $repoDir)) { return @() }

    $blocks       = @(Get-PnpUtilDriverBlocks)
    $origInfNames = [System.Collections.Generic.List[string]]::new()
    foreach ($b in $blocks) {
        if (($global:AsanCtx.PrinterClassGuids -contains $b['ClassGuid']) -and -not [string]::IsNullOrWhiteSpace([string]$b['OriginalName'])) {
            $o = ([string]$b['OriginalName']).ToLowerInvariant()
            if (-not $origInfNames.Contains($o)) { $origInfNames.Add($o) }
        }
    }

    foreach ($orig in $origInfNames) {
        $prefix = [IO.Path]::GetFileNameWithoutExtension($orig)
        $dirs   = @(Get-ChildItem -LiteralPath $repoDir -Directory -Filter "$prefix.inf_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($sub in $dirs) {
            $cand = Join-Path $sub.FullName $orig
            if (Test-Path -LiteralPath $cand) {
                $key = $cand.ToLowerInvariant()
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $infList.Add((Get-Item -LiteralPath $cand))
                    break
                }
            }
        }
    }
    return @($infList.ToArray())
}

function Get-LocalPrtFolderInfFiles {
    $infList = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $seen    = @{}
    $roots   = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($global:AsanCtx.DriverRoots)) { $roots.Add([string]$r) }
    # 약제팀 ZT411 공식 셋업(zd51177412-certified.exe) 추출 경로 자동 포함
    if (-not $roots.Contains('C:\ZD5-1-17-7412')) { $roots.Add('C:\ZD5-1-17-7412') }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($f.FullName -match $global:AsanCtx.DriverExcludeFolderPattern) { continue }
            $key = $f.FullName.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $infList.Add($f)
            }
        }
    }
    return @($infList.ToArray())
}

function Score-DriverDisplayName {
    param(
        [string]$DisplayName,
        [string]$SearchTarget,
        [string]$WantedNorm,
        [string]$WantedVendor,
        [string[]]$Tokens,
        [string[]]$ModelStems,
        [bool]$WantedHasDigits,
        [bool]$PreferPcl6,
        [bool]$AllowVendorUniversal = $false
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return -1 }
    if ($DisplayName -match $global:AsanCtx.MicrosoftInboxGenericRegex) { return -1 }
    if ($DisplayName -match '(?i)Samsung Universal Print Driver') { return -1 }

    $isVendorUniv = ($DisplayName -match $global:AsanCtx.VendorUniversalRegex)
    if ($isVendorUniv -and -not $AllowVendorUniversal) { return -1 }

    $dnVendors = @(Get-DetectedVendors -Text $DisplayName)
    if ($WantedVendor -and $dnVendors.Count -gt 0 -and ($dnVendors -notcontains $WantedVendor)) { return -1 }

    if ($isVendorUniv) {
        if ($WantedVendor -and ($dnVendors -contains $WantedVendor)) {
            $uScore = 200
            if ($PreferPcl6) { $uScore += (Get-ProtocolPreferenceBonus -DriverName $DisplayName) }
            return $uScore
        }
        return -1
    }

    $dnNorm = Normalize-Text $DisplayName
    $dScore = 0
    if ($DisplayName -eq $SearchTarget) { $dScore += 1200 }
    elseif ($WantedNorm -and $dnNorm -eq $WantedNorm) { $dScore += 1100 }

    $tokHits  = 0
    $digitHit = $false
    foreach ($t in @($Tokens)) {
        $tNorm = Normalize-Text $t
        if ($dnNorm.Contains($tNorm)) {
            $tokHits++
            if ($t -match '\d') { $dScore += 160; $digitHit = $true } else { $dScore += 40 }
        }
    }

    if (-not $digitHit -and $WantedHasDigits) {
        if (Test-WildcardModelMatch -CandidateDisplayName $DisplayName -WantedStems $ModelStems) {
            $dScore += 280
            $digitHit = $true
        }
    }

    if ($Tokens.Count -gt 0 -and $tokHits -eq $Tokens.Count) { $dScore += 300 }
    if ($PreferPcl6) { $dScore += (Get-ProtocolPreferenceBonus -DriverName $DisplayName) }

    if ($WantedHasDigits -and -not $digitHit -and $dScore -lt 900) { return -1 }
    return $dScore
}

function Find-AndInstallDriverFromIndex {
    param(
        [object[]]$InfIndex,
        [string]$SearchTarget,
        [string]$WantedDriverName,
        [string]$WantedVendor,
        [bool]$PreferPcl6 = $true,
        [bool]$AllowVendorUniversal = $false
    )

    if (-not $InfIndex -or $InfIndex.Count -eq 0) { return $null }

    $isWantedInboxGen = ($WantedDriverName -match $global:AsanCtx.MicrosoftInboxGenericRegex)
    $wantedNorm       = Normalize-Text $SearchTarget
    $tokens           = @(Get-SignificantTokens $SearchTarget)
    $modelStems       = @(Get-ModelStems -Tokens $tokens)
    $wantedHasDigits  = ($modelStems.Count -gt 0)

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $InfIndex) {
        if ($WantedVendor -and $entry.Vendors -and $entry.Vendors.Count -gt 0 -and ($entry.Vendors -notcontains $WantedVendor)) { continue }

        $score = 0
        if ($wantedNorm -and $entry.TextNorm.Contains($wantedNorm)) { $score += 1000 }

        $bestDispName  = $null
        $bestDispScore = -1

        foreach ($dn in $entry.DisplayNames) {
            $dScore = Score-DriverDisplayName -DisplayName $dn -SearchTarget $SearchTarget -WantedNorm $wantedNorm -WantedVendor $WantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $PreferPcl6 -AllowVendorUniversal $AllowVendorUniversal
            if ($dScore -ge 160 -and $dScore -gt $bestDispScore) {
                $bestDispScore = $dScore
                $bestDispName  = $dn
            }
        }

        if ($bestDispScore -ge 160 -and $bestDispName) {
            $candidates.Add([pscustomobject]@{
                Path        = $entry.Path
                Score       = ($score + $bestDispScore)
                BestDisplay = $bestDispName
            })
        }
    }

    foreach ($cand in ($candidates | Sort-Object Score -Descending | Select-Object -First 8)) {
        $rc = (Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $cand.Path, '/install')).ExitCode
        if ($rc -eq 0 -or $rc -eq 259 -or $rc -eq 3010) {
            $tryNames = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($cand.BestDisplay)) { $tryNames.Add($cand.BestDisplay) }
            if (-not $AllowVendorUniversal -and -not $isWantedInboxGen -and -not [string]::IsNullOrWhiteSpace($WantedDriverName) -and -not $tryNames.Contains($WantedDriverName)) {
                $tryNames.Add($WantedDriverName)
            }

            foreach ($dn in $tryNames) {
                try {
                    Add-PrinterDriver -Name $dn -ErrorAction Stop
                    $verify = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $dn }) | Select-Object -First 1
                    if ($verify) { return [string]$verify.Name }
                } catch {}
            }
        }
    }
    return $null
}

function Build-ProtocolNoticeText {
    param(
        [string]$DriverName,
        [string]$OrigProto,
        [bool]$PreferPcl6
    )
    if (-not $PreferPcl6) { return $null }
    $newProto = Get-DriverProtocolTag -DriverName $DriverName
    if ($newProto -ne 'PCL6' -and $newProto -ne 'KX') {
        return "PCL6 드라이버 미발견으로 '$newProto'($DriverName) 적용됨"
    }
    if ($OrigProto -ne 'UNKNOWN' -and $OrigProto -ne 'OTHER' -and $newProto -ne $OrigProto) {
        return "프로토콜 변경됨 ($OrigProto -> $newProto)"
    }
    return $null
}

function Resolve-BestDriverForPrinter {
    param(
        [string]$PrinterName,
        [string]$WantedDriverName,
        [string]$ModelHint = $null,
        [hashtable]$DriverIndexCache,
        [bool]$ExcludeFromPcl6 = $false,
        [switch]$ForceUpgradeGeneric
    )

    $preferPcl6       = (-not $ExcludeFromPcl6)
    $isWantedInboxGen = ($WantedDriverName -match $global:AsanCtx.MicrosoftInboxGenericRegex)

    $searchTarget = $WantedDriverName
    if ($isWantedInboxGen -or [string]::IsNullOrWhiteSpace($WantedDriverName)) {
        if (-not [string]::IsNullOrWhiteSpace($ModelHint)) { $searchTarget = $ModelHint }
        else { $searchTarget = $PrinterName }
    }

    $wantedVendor    = Get-DetectedVendor -Text "$WantedDriverName $ModelHint $PrinterName"
    $isSamsung       = ($wantedVendor -eq 'SAMSUNG')
    $origProto       = Get-DriverProtocolTag -DriverName $WantedDriverName
    $wantedNorm      = Normalize-Text $WantedDriverName
    $searchNorm      = Normalize-Text $searchTarget
    $tokens          = @(Get-SignificantTokens $searchTarget)
    $modelStems      = @(Get-ModelStems -Tokens $tokens)
    $wantedHasDigits = ($modelStems.Count -gt 0)

    # [1-A단계] 이미 스풀러에 정상 등록된 원본 드라이버 유지 (MS 인박스 범용 제외)
    $installedAll = @(Get-PrinterDriver -ErrorAction SilentlyContinue)
    if (-not $ForceUpgradeGeneric -and -not $isWantedInboxGen -and -not [string]::IsNullOrWhiteSpace($WantedDriverName)) {
        $exact = $installedAll | Where-Object { ($_.Name -eq $WantedDriverName -or (Normalize-Text $_.Name) -eq $wantedNorm) -and $_.Name -notmatch $global:AsanCtx.MicrosoftInboxGenericRegex } | Select-Object -First 1
        if ($exact) {
            $usedSam = ($exact.Name -match '(?i)Samsung Universal Print Driver')
            return [pscustomobject]@{
                Success         = $true
                DriverName      = [string]$exact.Name
                Source          = 'OriginalRestored'
                UsedSamFallback = $usedSam
                ProtocolNotice  = $null
            }
        }
    }

    # ==================== [PASS 1: 모델 전용 드라이버 전 단계 탐색] ====================
    $expIndex = $DriverIndexCache['Exported']
    $hitExp = Find-AndInstallDriverFromIndex -InfIndex $expIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitExp) {
        $pNotice = Build-ProtocolNoticeText -DriverName $hitExp -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitExp; Source = 'ExportedBackupDriver'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    $bestBuiltIn    = $null
    $bestBuiltScore = -1
    foreach ($drv in $installedAll) {
        $sc = Score-DriverDisplayName -DisplayName $drv.Name -SearchTarget $searchTarget -WantedNorm $searchNorm -WantedVendor $wantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $preferPcl6 -AllowVendorUniversal $false
        if ($sc -ge 160 -and $sc -gt $bestBuiltScore) {
            $bestBuiltScore = $sc
            $bestBuiltIn    = [string]$drv.Name
        }
    }
    if ($bestBuiltIn) {
        $pNotice = Build-ProtocolNoticeText -DriverName $bestBuiltIn -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $bestBuiltIn; Source = 'Win11GoldenSpooler'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    if ($null -eq $DriverIndexCache['DriverStore']) {
        $DriverIndexCache['DriverStore'] = @(Build-InfIndexCache -InfFiles (Get-DriverStorePrinterInfFiles))
    }
    $storeIndex = $DriverIndexCache['DriverStore']
    $hitStore   = Find-AndInstallDriverFromIndex -InfIndex $storeIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitStore) {
        $pNotice = Build-ProtocolNoticeText -DriverName $hitStore -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitStore; Source = 'Win11DriverStore'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    if ($null -eq $DriverIndexCache['LocalPrt']) {
        $DriverIndexCache['LocalPrt'] = @(Build-InfIndexCache -InfFiles (Get-LocalPrtFolderInfFiles))
    }
    $prtIndex = $DriverIndexCache['LocalPrt']
    $hitPrt   = Find-AndInstallDriverFromIndex -InfIndex $prtIndex -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$false
    if ($hitPrt) {
        $pNotice = Build-ProtocolNoticeText -DriverName $hitPrt -OrigProto $origProto -PreferPcl6 $preferPcl6
        return [pscustomobject]@{ Success = $true; DriverName = $hitPrt; Source = 'LocalPrtFolder'; UsedSamFallback = $false; ProtocolNotice = $pNotice }
    }

    # ==================== [PASS 2: 3.5단계 제조사 공식 통합 드라이버 폴백] ====================
    $bestUniv   = $null
    $bestUnivSc = -1
    foreach ($drv in $installedAll) {
        if ($drv.Name -notmatch $global:AsanCtx.VendorUniversalRegex) { continue }
        $sc = Score-DriverDisplayName -DisplayName $drv.Name -SearchTarget $searchTarget -WantedNorm $searchNorm -WantedVendor $wantedVendor -Tokens $tokens -ModelStems $modelStems -WantedHasDigits $wantedHasDigits -PreferPcl6 $preferPcl6 -AllowVendorUniversal $true
        if ($sc -ge 160 -and $sc -gt $bestUnivSc) {
            $bestUnivSc = $sc
            $bestUniv   = [string]$drv.Name
        }
    }
    if ($bestUniv) {
        return [pscustomobject]@{ Success = $true; DriverName = $bestUniv; Source = 'VendorUniversalSpooler'; UsedSamFallback = $false; ProtocolNotice = "모델 전용 드라이버 미발견으로 제조사 공식 통합 드라이버($bestUniv) 적용됨" }
    }

    foreach ($tierPair in @(
        @{ Name = 'VendorUniversalDriverStore'; Index = $storeIndex },
        @{ Name = 'VendorUniversalLocalPrt';    Index = $prtIndex },
        @{ Name = 'VendorUniversalExported';    Index = $expIndex }
    )) {
        $hitUniv = Find-AndInstallDriverFromIndex -InfIndex $tierPair.Index -SearchTarget $searchTarget -WantedDriverName $WantedDriverName -WantedVendor $wantedVendor -PreferPcl6:$preferPcl6 -AllowVendorUniversal:$true
        if ($hitUniv) {
            return [pscustomobject]@{ Success = $true; DriverName = $hitUniv; Source = $tierPair.Name; UsedSamFallback = $false; ProtocolNotice = "모델 전용 드라이버 미발견으로 제조사 공식 통합 드라이버($hitUniv) 적용됨" }
        }
    }

    # ==================== [PASS 3: 4단계 삼성 최후 폴백 (UPD 3)] ====================
    if ($isSamsung) {
        $samUpd = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
        if (-not $samUpd) {
            try { Add-PrinterDriver -Name 'Samsung Universal Print Driver 3' -ErrorAction Stop } catch {}
            $samUpd = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
        }
        if (-not $samUpd -and $prtIndex) {
            $us003 = @($prtIndex | Where-Object { $_.FileName -match '(?i)^us003\.inf$' }) | Select-Object -First 1
            if ($us003) {
                [void](Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $us003.Path, '/install'))
                try { Add-PrinterDriver -Name 'Samsung Universal Print Driver 3' -ErrorAction Stop } catch {}
                $samUpd = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)Samsung Universal Print Driver 3' }) | Select-Object -First 1
            }
        }
        if ($samUpd) {
            return [pscustomobject]@{
                Success         = $true
                DriverName      = [string]$samUpd.Name
                Source          = 'SamsungUniversalFallback'
                UsedSamFallback = $true
                ProtocolNotice  = '[주의] 원본 복원 실패로 삼성 범용 드라이버(UPD 3)로 대체 설치됨 — 테스트 페이지 오류 시 모델 전용 드라이버로 교체 및 장치설정(PCL6) 필요'
            }
        }
    }

    return [pscustomobject]@{
        Success         = $false
        DriverName      = $null
        Source          = 'NotFound'
        UsedSamFallback = $false
        ProtocolNotice  = '백업 원본, Win 11 내장, PRT 폴더 어디에서도 일치하는 드라이버를 찾지 못함'
    }
}

# ============================================================================
# Inbox INF 제외 + 미매칭 서드파티 한정 정밀 oem*.inf 추출
# ============================================================================
function Export-PreciseThirdPartyDrivers {
    param(
        [string[]]$ActiveDriverNames,
        [string[]]$ExplicitPublishedNames,
        [string[]]$ClassGuidFilters,
        [string]$DestinationDir
    )

    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $toExport = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($ExplicitPublishedNames)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not $toExport.Contains($p)) { $toExport.Add($p) }
    }

    $blocks      = @(Get-PnpUtilDriverBlocks)
    $classBlocks = @($blocks | Where-Object { (-not $ClassGuidFilters) -or ($ClassGuidFilters.Count -eq 0) -or ($ClassGuidFilters -contains $_.ClassGuid) })

    $unmatchedThirdParty = [System.Collections.Generic.List[string]]::new()
    if ($ActiveDriverNames -and $ActiveDriverNames.Count -gt 0) {
        $drvMap = @{}
        foreach ($d in @(Get-PrinterDriver -ErrorAction SilentlyContinue)) {
            $k      = [string]$d.Name
            $isX64  = ([string]$d.PrinterEnvironment -match '(?i)x64')
            $hasInf = (-not [string]::IsNullOrWhiteSpace([string]$d.InfPath))
            if (-not $drvMap.ContainsKey($k)) {
                $drvMap[$k] = $d
            } else {
                $prev       = $drvMap[$k]
                $prevIsX64  = ([string]$prev.PrinterEnvironment -match '(?i)x64')
                $prevHasInf = (-not [string]::IsNullOrWhiteSpace([string]$prev.InfPath))
                if (($isX64 -and $hasInf -and (-not ($prevIsX64 -and $prevHasInf))) -or ($hasInf -and -not $prevHasInf)) {
                    $drvMap[$k] = $d
                }
            }
        }

        foreach ($dName in $ActiveDriverNames) {
            if ($dName -match $global:AsanCtx.MicrosoftInboxGenericRegex) { continue }
            $matchedThis = $false
            $isInboxInf  = $false

            if ($drvMap.ContainsKey($dName) -and -not [string]::IsNullOrWhiteSpace([string]$drvMap[$dName].InfPath)) {
                $infFileName = [IO.Path]::GetFileName([string]$drvMap[$dName].InfPath)
                if ($infFileName -match $global:AsanCtx.InboxInfNameRegex) {
                    $isInboxInf = $true
                } else {
                    foreach ($b in $classBlocks) {
                        $pub  = [string]$b['PublishedName']
                        $orig = [string]$b['OriginalName']
                        if (($orig -ieq $infFileName) -or ($pub -ieq $infFileName)) {
                            if ($pub -and -not $toExport.Contains($pub)) { $toExport.Add($pub) }
                            $matchedThis = $true
                        }
                    }
                }
            }
            if (-not $matchedThis -and -not $isInboxInf) {
                $unmatchedThirdParty.Add($dName)
            }
        }
    }

    if ($unmatchedThirdParty.Count -gt 0) {
        # 문자열 단순 포함 대신 표준 벤더 분류(Get-DetectedVendors)로 매칭 (ZDesigner->ZEBRA, ECOSYS->KYOCERA 등 정확 매칭, SEWOO 제외)
        $scopedVendors = [System.Collections.Generic.List[string]]::new()
        foreach ($ud in $unmatchedThirdParty) {
            foreach ($v in @(Get-DetectedVendors -Text $ud)) {
                if ($v -eq 'SEWOO') { continue }
                if (-not $scopedVendors.Contains($v)) { $scopedVendors.Add($v) }
            }
        }
        foreach ($b in $classBlocks) {
            $pub  = [string]$b['PublishedName']
            $meta = "$($b['ProviderName']) $($b['OriginalName'])"
            if ([string]::IsNullOrWhiteSpace($pub)) { continue }
            $blkVendors = @(Get-DetectedVendors -Text $meta)
            if ($blkVendors -contains 'SEWOO') { continue }
            foreach ($sv in $scopedVendors) {
                if ($blkVendors -contains $sv) {
                    if (-not $toExport.Contains($pub)) { $toExport.Add($pub) }
                    break
                }
            }
        }
    }

    $exportedCount = 0
    foreach ($oemInf in $toExport) {
        $subDir = Join-Path $DestinationDir ([IO.Path]::GetFileNameWithoutExtension($oemInf))
        if (-not (Test-Path -LiteralPath $subDir)) { New-Item -ItemType Directory -Path $subDir -Force | Out-Null }
        $r = Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/export-driver', $oemInf, $subDir)
        if ($r.ExitCode -eq 0) { $exportedCount++ }
    }
    return $exportedCount
}

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
    $localTemp         = Join-Path $global:AsanCtx.WorkBaseDir "Work_Bak_$PID"
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
            if (Test-Path -LiteralPath $brmFile) { $brmOk = $true }
            elseif ($brmRes.ExitCode -ne 0) {
                $brmErrShort = ([string]$brmRes.Output -replace '\s+', ' ').Trim()
                if ($brmErrShort.Length -gt 180) { $brmErrShort = $brmErrShort.Substring(0, 180) + '...' }
                $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = "PrintBrm 백업 종료코드=$($brmRes.ExitCode): $brmErrShort" })
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
                Message = '오프라인 상태에서 검증 생략 후 전체 백업됨 — 새 Win 11 PC(온라인)에서 복원 전 지연 검증이 자동 실행됩니다.'
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
        $localSid = Get-LocalMachineSID
        $backupJson = [pscustomobject]@{
            FormatVersion    = 6
            AppVersion       = $global:AsanCtx.AppVersion
            SourceComputer   = $env:COMPUTERNAME
            SourceIP         = $PcIp
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
        if ($OfflineZipMode) { $modeStr = '오프라인 ZIP (지연 검증 대상)' }
        $brmStr = '실패'
        if ($brmOk) { $brmStr = '성공' }

        $repLines = [System.Collections.Generic.List[string]]::new()
        $repLines.Add("=========================================================================")
        $repLines.Add(" 아산병원 프린터/드라이버 마이그레이션 백업 리포트 (v$($global:AsanCtx.AppVersion))")
        $repLines.Add("=========================================================================")
        $repLines.Add(" 백업 일시       : $($backupJson.ExportedAt)")
        $repLines.Add(" 원본 PC (IP)    : $($env:COMPUTERNAME) ($PcIp)")
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
                                $backupNotes.Add([pscustomobject]@{ Level = 'Warning'; Target = 'USB 동시 복사'; Message = "USB ZIP 복사본 크기가 불일치합니다 ($candUsbZip) — 로컬 C:\_AsanPrtOffline ZIP을 사용하세요." })
                            }
                        } catch {
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
            try {
                if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $stageFull -Force | Out-Null
                $rc = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($localTemp, $stageFull, '/E', '/R:2', '/W:1')).ExitCode
                if ($rc -ge 8) { throw "서버 스테이징 업로드 중 robocopy 오류 발생 (ExitCode=$rc)" }

                $swapped = $false
                if (Test-Path -LiteralPath $targetFull) {
                    try {
                        if (Test-Path -LiteralPath $oldFull) { Remove-Item -LiteralPath $oldFull -Recurse -Force -ErrorAction SilentlyContinue }
                        [IO.Directory]::Move($targetFull, $oldFull)
                        try {
                            [IO.Directory]::Move($stageFull, $targetFull)
                            $swapped = $true
                        } catch {
                            try { if (-not (Test-Path -LiteralPath $targetFull) -and (Test-Path -LiteralPath $oldFull)) { [IO.Directory]::Move($oldFull, $targetFull) } } catch {}
                            throw
                        }
                    } catch {
                        # 대상 폴더가 타 PC 탐색기 등에 잠겨 Move 불가 시 폴백으로 직접 /MIR 동기화
                        $rcMir = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($localTemp, $targetFull, '/MIR', '/R:2', '/W:1')).ExitCode
                        if ($rcMir -ge 8) { throw "서버 덮어쓰기 업로드 중 robocopy 오류 발생 (ExitCode=$rcMir)" }
                        $swapped = $true
                    }
                } else {
                    [IO.Directory]::Move($stageFull, $targetFull)
                    $swapped = $true
                }
                if (-not $swapped) { throw '서버 백업 폴더 원자적 전환 실패' }
            }
            finally {
                if (Test-Path -LiteralPath $oldFull)   { Remove-Item -LiteralPath $oldFull   -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue }
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
                $liveReason = "[지연검증] $($chk.Reason)"
                if ($liveStatus -eq 'Healthy') { $liveStatusText = '정상' }
                elseif ($liveStatus -eq 'Ambiguous') { $liveStatusText = '애매함' }
                else { $liveStatusText = '비활성의심' }
            } elseif ($pKind -eq 'LOCAL_UNC' -or $pKind -eq 'SHARED_UNC') {
                $targetUnc = $port
                if ($p.ConnectionName) { $targetUnc = [string]$p.ConnectionName }
                $chk = Test-UncSharePrinterAlive -UncPath $targetUnc
                $liveStatus = $chk.Status
                $liveReason = "[지연검증] $($chk.Reason)"
                if ($liveStatus -eq 'Healthy') {
                    $liveStatusText = '정상'
                } elseif ($liveStatus -eq 'AuthOrSidConflict') {
                    $liveStatusText = '인증/SID의심'
                    if ($chk.HostName -and -not $seenAuthHost.ContainsKey($chk.HostName.ToLowerInvariant())) {
                        $seenAuthHost[$chk.HostName.ToLowerInvariant()] = $true
                        $authFailedHosts.Add([pscustomobject]@{ HostName = $chk.HostName; Reason = $chk.Reason })
                    }
                } else {
                    $liveStatusText = '비활성의심'
                }
            } elseif ($pKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$wsdIp)) {
                if ((Test-TcpPortFast -HostIp $wsdIp -Port 9100 -TimeoutMs 1200) -or (Test-TcpPortFast -HostIp $wsdIp -Port 515 -TimeoutMs 1000)) {
                    $wsdMode = 'TCPIP'; $wsdShare = $null; $liveStatus = 'WsdConvert'; $liveStatusText = 'WSD->TCP/IP'
                    $liveReason = "[지연검증] WSD IP($wsdIp) 인쇄 포트 정상 -> TCP/IP 전환 예정"
                } elseif (Test-TcpPortFast -HostIp $wsdIp -Port 445 -TimeoutMs 1200) {
                    $auth = Connect-SharedHostSmart -HostName $wsdIp
                    if ($auth.Success) {
                        $shs = @(Get-RemoteSharedPrinters -HostName $wsdIp)
                        if ($shs.Count -gt 0) {
                            $bestS = $shs[0]
                            $hintCombo = "$dName $wsdModel"
                            if ($hintCombo -match '(?i)Kyocera' -and ($shs -contains 'kyoceraf')) { $bestS = 'kyoceraf' }
                            elseif ($hintCombo -match '(?i)Samsung' -and ($shs -contains 'samsungm')) { $bestS = 'samsungm' }
                            $wsdMode = 'LOCAL_UNC'; $wsdShare = "\\$wsdIp\$bestS"; $liveStatus = 'WsdConvert'; $liveStatusText = 'WSD->LocalPort'
                            $liveReason = "[지연검증] WSD IP($wsdIp) 공유 프린터($bestS) 확인 -> Local Port 전환 예정"
                        } else {
                            $liveStatus = 'Ambiguous'; $liveStatusText = '애매함(WSD)'
                            $liveReason = "[지연검증] WSD IP($wsdIp) SMB 접속은 성공했으나 공유 프린터가 없음"
                        }
                    } elseif ($auth.Status -eq 'AuthOrSidConflict') {
                        $liveStatus = 'AuthOrSidConflict'; $liveStatusText = '인증/SID의심'
                        $liveReason = "[지연검증] WSD 호스트($wsdIp) $($auth.Reason)"
                        if (-not $seenAuthHost.ContainsKey($wsdIp.ToLowerInvariant())) {
                            $seenAuthHost[$wsdIp.ToLowerInvariant()] = $true
                            $authFailedHosts.Add([pscustomobject]@{ HostName = $wsdIp; Reason = $liveReason })
                        }
                    } else {
                        $liveStatus = 'Ambiguous'; $liveStatusText = '애매함(WSD)'
                        $liveReason = "[지연검증] WSD IP($wsdIp) SMB 연결 실패 ($($auth.Reason))"
                    }
                } else {
                    if ((Test-PingFast -HostIp $wsdIp -TimeoutMs 1000) -or (Test-TcpPortFast -HostIp $wsdIp -Port 80 -TimeoutMs 1000)) {
                        $liveStatus = 'Ambiguous'; $liveStatusText = '애매함(WSD)'
                        $liveReason = "[지연검증] WSD IP($wsdIp) 호스트 응답은 있으나 인쇄 포트(9100/515/445) 닫힘"
                    } else {
                        $liveStatus = 'SuspectedInactive'; $liveStatusText = '비활성의심'
                        $liveReason = "[지연검증] WSD IP($wsdIp) 무응답 (프린터 전원 꺼짐 또는 IP 변경 의심)"
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
            $liveStatusText = 'Win11수동설치'
        }
        if ($spec.NoDriverBackup) {
            $defaultCheck   = $false
            $liveStatusText = '무드라이버(LPT1확인)'
            $liveReason     = '[드라이버 설치 금지] LPT1 유선 직결 후 AMIS 직접 사용 장비 — 장치관리자 LPT1 인식 여부만 확인 (드라이버/에이전트 불필요)'
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
            $wmi = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $PrinterName }) | Select-Object -First 1
            if ($wmi) {
                Invoke-CimMethod -InputObject $wmi -MethodName SetDefaultPrinter | Out-Null
                return $true
            }
        } catch {}
    }
    return $false
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

    $exist = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $pName }) | Select-Object -First 1
    if ($exist) { return [pscustomobject]@{ Success = $true; PortName = [string]$exist.Name; Reason = $null; AuthFailedHost = $null } }

    $kind = 'LOCAL'
    if ($OverrideKind) { $kind = $OverrideKind }
    elseif ($PortObj -and $PortObj.Kind) { $kind = [string]$PortObj.Kind }
    elseif ($pName -match '^\\\\') { $kind = 'LOCAL_UNC' }

    try {
        if ($kind -eq 'TCPIP') {
            $hostIp = $pName
            if ($OverrideHostIp) { $hostIp = $OverrideHostIp }
            elseif ($PortObj -and $PortObj.HostAddress) { $hostIp = [string]$PortObj.HostAddress }

            if ($PortObj -and [string]$PortObj.Protocol -eq 'LPR' -and -not [string]::IsNullOrWhiteSpace([string]$PortObj.Queue)) {
                $params = @{ Name = $pName; LprHostAddress = $hostIp; LprQueueName = [string]$PortObj.Queue; SNMP = [uint32]0; ErrorAction = 'Stop' }
                if ($PortObj.ByteCount) { $params.LprByteCounting = $true }
                Add-PrinterPort @params
            } else {
                $params = @{ Name = $pName; PrinterHostAddress = $hostIp; SNMP = [uint32]0; ErrorAction = 'Stop' }
                if ($PortObj -and $PortObj.PortNumber -and [uint32]$PortObj.PortNumber -gt 0) { $params.PortNumber = [uint32]$PortObj.PortNumber }
                Add-PrinterPort @params
            }
            return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null }
        }
        elseif ($kind -eq 'USB') {
            $usbPorts  = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^USB\d+' } | Sort-Object Name)
            $usedPorts = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.PortName })
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
                $chk = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $pName }) | Select-Object -First 1
                if ($chk) { return [pscustomobject]@{ Success = $true; PortName = $pName; Reason = $null; AuthFailedHost = $null } }
                return [pscustomobject]@{ Success = $false; PortName = $pName; Reason = "UNC 로컬 포트 등록 실패: $($_.Exception.Message)"; AuthFailedHost = $hostName }
            }
        }
        else {
            Add-PrinterPort -Name $pName -ErrorAction Stop
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
            $tempRewrittenReg = Join-Path $global:AsanCtx.WorkBaseDir "Rewritten_$PID.reg"
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
        foreach ($p in @(Get-Printer -ErrorAction SilentlyContinue)) {
            $pName = [string]$p.Name
            if ($pName -eq 'Microsoft Print to PDF') { continue }
            if ($PreExistingPrinters -and $PreExistingPrinters.ContainsKey($pName.ToLowerInvariant())) { continue }
            if (Test-IsVirtualPrinter -PrinterName $pName -PortName $p.PortName) {
                Remove-Printer -InputObject $p -ErrorAction SilentlyContinue
            }
        }
    }

    $prtMap = @{}
    foreach ($p in @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)) {
        $prtMap[[string]$p.Name] = $p
    }

    [void](Stop-SpoolerSafe)

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
                $pInfo = $prtMap[$pName]
                if ($pInfo) {
                    $spec = Get-SpecialPrinterProfile -PrinterName $pName -DriverName ([string]$pInfo.DriverName) -PortName ([string]$pInfo.PortName)
                    if ($spec.IsSpecial -and ([string]$pInfo.PortName -match '(?i)^USB')) { return }
                }
                $attr = (Get-ItemProperty -LiteralPath $_.PSPath -Name 'Attributes' -ErrorAction SilentlyContinue).Attributes
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
                Write-ProgressSafe -Percent 88 -Message "[경고] 특수장비 레지스트리 설정(.reg) 주입 실패: $($regItem.PrinterName)"
            }
        }
    }
    finally {
        Ensure-SpoolerRunning
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
            DetectedSpecials  = @()
            SamFallbackNames  = @()
            RestoredScanCount = 0
        }
    }

    if (-not (Test-Path -LiteralPath $global:AsanCtx.WorkBaseDir)) { New-Item -ItemType Directory -Path $global:AsanCtx.WorkBaseDir -Force | Out-Null }

    $localTemp         = Join-Path $global:AsanCtx.WorkBaseDir "Work_Res_$PID"
    $isZip             = ($SourcePath -match '(?i)\.zip$')
    $restoreLog        = [System.Collections.Generic.List[object]]::new()
    $failures          = [System.Collections.Generic.List[object]]::new()
    $authHosts         = [System.Collections.Generic.List[object]]::new()
    $seenAuth          = @{}
    $offlineUncHosts   = @{}
    $detectedSpecials  = [System.Collections.Generic.List[object]]::new()
    $samFallbackList   = [System.Collections.Generic.List[string]]::new()
    $pendingRegImports = [System.Collections.Generic.List[object]]::new()
    $needsUsbReplug    = $false

    try {
        if (Test-Path -LiteralPath $localTemp) { Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $localTemp -Force | Out-Null

        $preExistingPrinters = @{}
        foreach ($ep in @(Get-Printer -ErrorAction SilentlyContinue)) {
            $preExistingPrinters[([string]$ep.Name).ToLowerInvariant()] = $true
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 10 -Message '[1/6] 백업 데이터 로컬 스테이징 준비 중...'
        if ($isZip) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($SourcePath, $localTemp)
        } else {
            $rc = (Invoke-NativeCommand -FilePath 'robocopy.exe' -Arguments @($SourcePath, $localTemp, '/E', '/R:2', '/W:1')).ExitCode
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
            if ($brmRestoreRes.ExitCode -ne 0) {
                $brmShort = ([string]$brmRestoreRes.Output -replace '\s+', ' ').Trim()
                if ($brmShort.Length -gt 200) { $brmShort = $brmShort.Substring(0, 200) + '...' }
                $restoreLog.Add([pscustomobject]@{ Level = 'Warning'; Target = 'PrintBrm'; Message = "PrintBrm 일부 경고/오류 (ExitCode=$($brmRestoreRes.ExitCode)) — 누락 항목은 5단계 정밀 복원으로 자동 보완됩니다. [$brmShort]" })
            }
        } else {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 36 -Message '[3/6] PrintBrm 없음 — 개별 드라이버 및 JSON 기반으로 복원 진행...'
        }

        # [4/6] 사후 정제 ([H1 Fix] -SkipPrintBrm 시 생략)
        if (-not $SkipPrintBrm) {
            Write-ProgressSafe -OnProgress $OnProgress -Percent 48 -Message '[4/6] 사후 정제 실행 중 (미선택/유입 가상/WSD원본/Win10 구형 세우테크 격리)...'
            $allBackupRowsByName = @{}
            foreach ($r in @($SelectedRows)) { $allBackupRowsByName[[string]$r.PrinterName] = $r }
            $sewooDriversToClean = [System.Collections.Generic.List[string]]::new()

            foreach ($curPrt in @(Get-Printer -ErrorAction SilentlyContinue)) {
                $cName = [string]$curPrt.Name
                if ($cName -eq 'Microsoft Print to PDF') { continue }

                $wasPreExisting = $preExistingPrinters.ContainsKey($cName.ToLowerInvariant())
                if (-not $wasPreExisting -and (Test-IsVirtualPrinter -PrinterName $cName -PortName $curPrt.PortName)) {
                    Remove-Printer -InputObject $curPrt -ErrorAction SilentlyContinue
                    continue
                }

                $specNow = Get-SpecialPrinterProfile -PrinterName $cName -DriverName $curPrt.DriverName -PortName $curPrt.PortName
                # 이미 새 Win 11 PC에 선설치된 정상 세우테크 큐는 보호($wasPreExisting 확인)
                if ((-not $wasPreExisting) -and ($specNow.Win11ReinstallOnly -or $specNow.NoDriverBackup)) {
                    $isoDrv = [string]$curPrt.DriverName
                    Remove-Printer -InputObject $curPrt -ErrorAction SilentlyContinue
                    if (-not [string]::IsNullOrWhiteSpace($isoDrv) -and -not $sewooDriversToClean.Contains($isoDrv)) {
                        $sewooDriversToClean.Add($isoDrv)
                    }
                    if ($specNow.NoDriverBackup) {
                        $restoreLog.Add([pscustomobject]@{ Level = 'Special'; Target = $cName; Message = 'EPSON TM-T88(LPT1 무드라이버) 유입 큐/드라이버 자동 격리 삭제 — 드라이버 설치 금지, 장치관리자 LPT1 인식만 확인' })
                    } else {
                        $restoreLog.Add([pscustomobject]@{ Level = 'Special'; Target = $cName; Message = 'Win 10 구형 세우테크 큐/드라이버 자동 격리 삭제 (Win 11 전용 설치 도우미 사용 필수)' })
                    }
                    continue
                }

                if ($allBackupRowsByName.ContainsKey($cName)) {
                    $rowRef = $allBackupRowsByName[$cName]
                    if (-not $rowRef.Selected -and -not $wasPreExisting) {
                        Remove-Printer -InputObject $curPrt -ErrorAction SilentlyContinue
                        $restoreLog.Add([pscustomobject]@{ Level = 'Info'; Target = $cName; Message = '사용자가 복원 제외(체크 해제)하여 사후 정제 삭제됨' })
                        continue
                    }
                    if ($rowRef.Selected -and $rowRef.PortKind -eq 'WSD' -and -not [string]::IsNullOrWhiteSpace([string]$rowRef.WsdTargetIp)) {
                        Remove-Printer -InputObject $curPrt -ErrorAction SilentlyContinue
                        continue
                    }
                }
            }

            if ($sewooDriversToClean.Count -gt 0) {
                $remainingDrvs = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.DriverName })
                foreach ($sdName in $sewooDriversToClean) {
                    if ($remainingDrvs -notcontains $sdName) {
                        foreach ($dObj in @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $sdName })) {
                            Remove-PrinterDriver -InputObject $dObj -ErrorAction SilentlyContinue
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
        $exportedIndex = @(Build-InfIndexCache -InfFiles $expInfs)
        if ($usbSpecialVendors.Count -gt 0) {
            foreach ($idxEntry in $exportedIndex) {
                if ($idxEntry.Vendors -contains 'SEWOO') { continue }
                $matchUsbVendor = $false
                foreach ($uv in $usbSpecialVendors) {
                    if ($idxEntry.Vendors -contains $uv) { $matchUsbVendor = $true; break }
                }
                if ($matchUsbVendor) {
                    [void](Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $idxEntry.Path, '/install'))
                }
            }
            if ($hasSelectedZt411Usb) {
                $ztInf = 'C:\ZD5-1-17-7412\ZBRN\ZBRN.inf'
                if (Test-Path -LiteralPath $ztInf) {
                    [void](Invoke-NativeCommand -FilePath 'pnputil.exe' -Arguments @('/add-driver', $ztInf, '/install'))
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

            $existing = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $pName }) | Select-Object -First 1

            # Case A: PrintBrm으로 이미 생성된 큐 검증 및 보강
            if ($existing) {
                $finalDrvName = [string]$existing.DriverName
                if (-not $spec.IsSpecial -and $finalDrvName -match $global:AsanCtx.MicrosoftInboxGenericRegex) {
                    $drvRes = Resolve-BestDriverForPrinter -PrinterName $pName -WantedDriverName $row.DriverName -ModelHint $row.WsdModelName -DriverIndexCache $driverIndexCache -ExcludeFromPcl6:$spec.ExcludeFromPcl6 -ForceUpgradeGeneric
                    if ($drvRes.Success -and $drvRes.DriverName -ne $finalDrvName) {
                        try {
                            Set-Printer -InputObject $existing -DriverName $drvRes.DriverName -ErrorAction Stop
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
                $isSharedConnection = (-not [string]::IsNullOrWhiteSpace([string]$row.ConnectionName)) -or $pName.StartsWith('\\') -or ($row.PortKind -eq 'SHARED_UNC')
                if ((-not $isSharedConnection) -and ($row.PortKind -eq 'USB' -or $existingPort -match '(?i)^USB\d+')) {
                    $curPortExists = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $existingPort }) | Select-Object -First 1
                    if (-not $curPortExists) {
                        $uRes = Ensure-RestoredPortSafe -PortObj $null -FallbackName $row.PortName -OverrideKind 'USB'
                        if ($uRes.Success) {
                            try {
                                Set-Printer -InputObject $existing -PortName $uRes.PortName -ErrorAction Stop
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
                if ($spec.IsSpecial) {
                    if ($row.SpecialDatFile) {
                        $dFull = Join-Path $localTemp $row.SpecialDatFile
                        if (Test-Path -LiteralPath $dFull) {
                            [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $pName, '/a', $dFull, 'd', 'g', 'u', 'r'))
                        }
                    }
                    if ($row.SpecialRegFile) {
                        $rFull = Join-Path $localTemp $row.SpecialRegFile
                        if (Test-Path -LiteralPath $rFull) {
                            $pendingRegImports.Add([pscustomobject]@{ PrinterName = $pName; OriginalPrinterName = $pName; RegFullPath = $rFull })
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
                    Add-Printer -ConnectionName $conn -ErrorAction Stop
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

            $drvRes = Resolve-BestDriverForPrinter -PrinterName $pName -WantedDriverName $row.DriverName -ModelHint $row.WsdModelName -DriverIndexCache $driverIndexCache -ExcludeFromPcl6:$spec.ExcludeFromPcl6
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

            try {
                Add-Printer -Name $pName -DriverName $drvRes.DriverName -PortName $pRes.PortName -ErrorAction Stop
                if ($spec.IsSpecial) {
                    if ($row.SpecialDatFile) {
                        $dFull = Join-Path $localTemp $row.SpecialDatFile
                        if (Test-Path -LiteralPath $dFull) {
                            [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $pName, '/a', $dFull, 'd', 'g', 'u', 'r'))
                        }
                    }
                    if ($row.SpecialRegFile) {
                        $rFull = Join-Path $localTemp $row.SpecialRegFile
                        if (Test-Path -LiteralPath $rFull) {
                            $pendingRegImports.Add([pscustomobject]@{ PrinterName = $pName; OriginalPrinterName = $pName; RegFullPath = $rFull })
                        }
                    }
                }
                $msg = "복원 완료 (드라이버: $($drvRes.DriverName) [$($drvRes.Source)] / 포트: $($pRes.PortName))"
                if ($row.PortKind -eq 'WSD') { $msg = "[WSD 전환 성공] $msg" }
                $restoreLog.Add([pscustomobject]@{ Level = 'Success'; Target = $pName; Message = $msg })

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
        if ($SkipPrintBrm) {
            Invoke-AsanStandardPolicyAtomic -PendingRegImports $pendingRegImports.ToArray()
        } else {
            Invoke-AsanStandardPolicyAtomic -PreExistingPrinters $preExistingPrinters -CleanMigratedVirtuals -PendingRegImports $pendingRegImports.ToArray()
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
            Copy-Item -LiteralPath $srcSpecDir -Destination $persistedSpecialDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-ProgressSafe -OnProgress $OnProgress -Percent 100 -Message '복원 파이프라인 완료!'
        return [pscustomobject]@{
            Success           = $true
            BlockedByWpp      = $false
            WppInfo           = $wppCheck
            RestoreLog        = $restoreLog.ToArray()
            Failures          = $failures.ToArray()
            AuthFailedHosts   = $authHosts.ToArray()
            DetectedSpecials  = $detectedSpecials.ToArray()
            SamFallbackNames  = $samFallbackList.ToArray()
            RestoredScanCount = $restoredScanCnt
            NeedsUsbReplug    = $needsUsbReplug
        }
    }
    finally {
        if (Test-Path -LiteralPath $localTemp) {
            Remove-Item -LiteralPath $localTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

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
        $ztSearchDirs = [System.Collections.Generic.List[string]]::new()
        foreach ($r in $baseRoots) {
            if (-not (Test-Path -LiteralPath $r)) { continue }
            foreach ($pat in @('*ZT411*', '*PRT*\*ZT411*', '*AMIS*\*ZT411*', '*Zebra*')) {
                foreach ($md in @(Get-ChildItem -Path (Join-Path $r $pat) -Directory -ErrorAction SilentlyContinue)) {
                    if (-not $ztSearchDirs.Contains($md.FullName)) { $ztSearchDirs.Add($md.FullName) }
                }
            }
        }
        # 사내 드라이버 서버(\\172.23.2.130)는 백그라운드 Runspace에서만 탐색 (-SkipRemoteProbe 시 UI 스레드 차단 방지)
        if (-not $SkipRemoteProbe) {
            if (Test-TcpPortFast -HostIp '172.23.2.130' -Port 445 -TimeoutMs 600) {
                $srvZtDir = '\\172.23.2.130\driver\기종별드라이버(PC,PRT)\PRT\ZT411 (약국용 신형 라벨 프린터)'
                if (Test-Path -LiteralPath $srvZtDir) { $ztSearchDirs.Add($srvZtDir) }
            }
        }

        $ztFolder  = $null
        $ztExePath = $null
        $ztDrsPath = $null
        $ztInfPath = $null
        # C:\ZD5-1-17-7412는 압축 해제 결과(ZBRN.inf) 확인 전용 (내부 PrnInst.exe 마법사 오인식 방지!)
        if (Test-Path -LiteralPath 'C:\ZD5-1-17-7412\ZBRN\ZBRN.inf') {
            $ztInfPath = 'C:\ZD5-1-17-7412\ZBRN\ZBRN.inf'
        }

        foreach ($sd in $ztSearchDirs) {
            if (-not $ztFolder) { $ztFolder = $sd }
            if (-not $ztExePath) {
                $allExes = @(Get-ChildItem -LiteralPath $sd -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '(?i)PrnInst' } |
                    Sort-Object FullName)
                $exeHit = $allExes | Where-Object { $_.Name -match '(?i)(zd51177412|certified|zd5)' } | Select-Object -First 1
                if (-not $exeHit) {
                    $exeHit = $allExes | Where-Object { $_.Name -match '(?i)(zebra|setup|driver)' } | Select-Object -First 1
                }
                if ($exeHit) { $ztExePath = $exeHit.FullName; $ztFolder = $exeHit.DirectoryName }
            }
            if (-not $ztDrsPath) {
                $drsHit = @(Get-ChildItem -LiteralPath $sd -Filter '*.drs' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName) | Select-Object -First 1
                if ($drsHit) { $ztDrsPath = $drsHit.FullName }
            }
            if (-not $ztInfPath) {
                $infHit = @(Get-ChildItem -LiteralPath $sd -Filter 'ZBRN.inf' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName) | Select-Object -First 1
                if ($infHit) { $ztInfPath = $infHit.FullName }
            }
        }
        if (-not $ztFolder -and (Test-Path -LiteralPath 'C:\ZD5-1-17-7412')) {
            $ztFolder = 'C:\ZD5-1-17-7412'
        }

        return [pscustomobject]@{
            Found   = ($null -ne $ztFolder -or $null -ne $ztExePath -or $null -ne $ztInfPath -or $null -ne $ztDrsPath)
            Folder  = $ztFolder
            ExePath = $ztExePath
            DrxPath = $null
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
                "[SIP-30M 진료카드 발급기 — 2단계 반자동 안내]",
                "1단계: [설치 실행] 클릭 -> '표준 로컬(USB) 설치' 선택 -> 장치 미연결 경고창에서 [아니오] -> [마침]",
                "2단계: [포트/이름/설정 자동 마무리] 클릭 -> TCP/IP($ipHint, SNMP OFF), 이름 'id카드', 4개 탭 설정 자동 주입",
                "3단계: 자동 팝업되는 인쇄 기본 설정(리본/코팅/농도/MS쓰기) 확인 후 담당자에게 AMIS 테스트 요청"
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'SIP30M_IDCARD'; TargetIp = $ipHint; Installer = $inst; HasStep2 = $true; Checklist = $chk }
        }
        'SEWOO_TE201' {
            $pHint = 'USB(USBPOS0)'
            if ($SpecialRow.PortName -match '(?i)LPT') { $pHint = 'Parallel(LPT1)' }
            $chk = @(
                "[Sewoo SLK-TE201 네임바코드 — Win 11 전용 필수 설치]",
                "1단계: [Win 11 설치 실행] 클릭 -> 모델 [SLK-TE201] 체크 -> [기본 프린터 설정] 해제 -> 포트 [$pHint] 선택",
                "2단계: AMIS 3.0 로그인 -> 개인환경설정 -> PC별 환경설정 -> 바코드 Agent '실행'",
                "3단계: 트레이 Barcode Print Agent 재실행 -> 자동 등록된 SLK-TE201(7.2x327.5) 삭제 -> 수동 등록(8.0 x 8.5) 추가"
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'SEWOO_TE201'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'ZEBRA_ZT411' {
            $isTcpLabel = ([string]$SpecialRow.PortKind -eq 'TCPIP') -or (-not [string]::IsNullOrWhiteSpace([string]$SpecialRow.HostAddress))
            $connHint   = 'USB 직결 — 셋업 종료 후 USB 연결 시 자동 설치(미인식 시 상단 [USB 재인식] 클릭)'
            if ($isTcpLabel) {
                $connHint = "TCP/IP 네트워크 연결($($SpecialRow.PortName)) — Standard TCP/IP(Generic Network Card, SNMP OFF) + ZDesigner ZT411-203dpi ZPL 자동 복원 대상"
            }
            $drsHint = '\\172.23.2.130\driver\기종별드라이버(PC,PRT)\PRT\ZT411 (약국용 신형 라벨 프린터)\ZebraDriver 설정.drs'
            if ($inst.DrsPath) { $drsHint = $inst.DrsPath }
            $infHint = 'C:\ZD5-1-17-7412\ZBRN\ZBRN.inf'
            if ($inst.InfPath) { $infHint = $inst.InfPath }

            $chk = @(
                "[Zebra ZT410/ZT411 약제팀 라벨 프린터 — 공식 설치·용지 설정(.drs) 안내]",
                "• 연결 방식: $connHint",
                "1. [드라이버 수동 재설치 필요 시] zd51177412-certified.exe 실행 -> C:\ZD5-1-17-7412 생성 후",
                "   ★ 주의: 마법사 화면에서 절대 프린터 설정하지 말고 반드시 [나가기] 버튼으로 종료하세요!",
                "   • USB 연결: 종료 후 케이블 연결 시 'ZDesigner ZT411-203dpi ZPL' 자동 설치",
                "   • IP 연결 : Standard TCP/IP(자동 검색 해제 / Generic Network Card) -> 디스크 있음 -> $infHint -> 'ZDesigner ZT411-203dpi ZPL'",
                "2. [용지 설정(필수)] 용지 값을 직접 손으로 입력하지 말고, 자동 복원(.dat/.reg) 미반영 시",
                "   프린터 속성 > 기본 설정 > [가져오기/내보내기 설정] > [가져오기...]에서 'ZebraDriver 설정.drs'를 불러오세요.",
                "   • 설정 파일(.drs): $drsHint"
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'ZEBRA_ZT411'; TargetIp = $SpecialRow.HostAddress; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'ZD410_411' {
            $drxHint = 'admin\드라이버(win10_x64)\AMIS3.0장비\ZD410(Zebra바코드)\*.drx'
            if ($inst.DrxPath) { $drxHint = $inst.DrxPath }
            $chk = @(
                "[Zebra ZD-410/411 검사·투약 바코드 확인 사항]",
                "1. USB 연결 장비가 [지정되지 않음]으로 보이면 상단 [USB 재인식] 버튼을 먼저 실행하세요 (실패 시에만 USB 1회 재연결).",
                "2. 프린터 속성 -> 드라이버 설정 -> [상태확인: 사용안함] 및 용지설정(.drx) 유지 확인 ($drxHint)",
                "3. 용지/상단 여백 확인: 검사바코드(5.5x3.0 / 2.6mm) | 투약바코드(5.5x6.0 / 1.0mm) -> AMIS Barcode Print Agent 확인"
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'ZD410_411'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'BIXOLON_TX220' {
            $chk = @(
                "[BIXOLON SLP-TX220 팔찌 바코드 확인 사항]",
                "1. USB 연결 장비가 [지정되지 않음]으로 보이면 상단 [USB 재인식] 버튼을 먼저 실행하세요 (실패 시에만 USB 1회 재연결).",
                "2. 기본 설정 -> Options: Darkness 11~12 (13이상 QR오류), mm, Landscape, Rotate 180, 20x250(성인)/20x150(소아)",
                "3. Advanced Setup: 감열지(Direct Thermal) / 리본(Thermal Transfer) 구분, Sensor: Black Mark -> AMIS Barcode Print Agent 확인"
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'BIXOLON_TX220'; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = $chk }
        }
        'EPSON_TMT88_LPT' {
            $lptsNow   = if ($null -ne $PreloadedLpts) { @($PreloadedLpts) } else { @(Get-DeviceManagerLptPorts) }
            $lpt1Now   = $lptsNow | Where-Object { $_.PortName -ieq 'LPT1' } | Select-Object -First 1
            $otherLpts = @($lptsNow | Where-Object { $_.PortName -ine 'LPT1' })
            $lptStatLine = '현재 PC 장치관리자 LPT1 상태: 미감지 (패럴렐 케이블 연결 및 PCIe LPT 포트 확인 필요)'
            if ($lpt1Now) {
                $lptStatLine = "현재 PC 장치관리자 LPT1 상태: 정상 감지됨 ($($lpt1Now.Name) / $($lpt1Now.Status))"
            } elseif ($otherLpts.Count -gt 0) {
                $otherDesc = ($otherLpts | ForEach-Object { "$($_.PortName)($($_.Name))" }) -join ', '
                $lptStatLine = "현재 PC 장치관리자 LPT1 미감지 — 대신 타 LPT 포트 감지됨: $otherDesc (장치관리자 포트 설정에서 LPT1으로 번호 변경 필요)"
            }
            $chk = @(
                "[EPSON TM-T88VI — LPT1 유선 직결 무드라이버 장비 (백업/설치 제외)]",
                "• $lptStatLine",
                "1. Windows 프린터 드라이버·별도 포트 설정·바코드 에이전트를 절대 설치하지 마세요.",
                "2. LPT 패럴렐 케이블 유선 연결 후 장치관리자(devmgmt.msc) > [포트(COM & LPT)]에 LPT1 인식 여부만 확인하세요.",
                "3. LPT1이 정상 인식된 상태에서 AMIS 3.0에서 별도 작업 없이 그대로 출력하여 확인하세요."
            ) -join "`r`n"
            return [pscustomobject]@{ Type = 'EPSON_TMT88_LPT'; TargetIp = $null; Installer = [pscustomobject]@{ Found = $false; Folder = $null; ExePath = $null; DrxPath = $null; DrsPath = $null; InfPath = $null }; HasStep2 = $false; Checklist = $chk }
        }
        default {
            return [pscustomobject]@{ Type = $SpecialRow.SpecialType; TargetIp = $null; Installer = $inst; HasStep2 = $false; Checklist = "특수 프린터($($SpecialRow.PrinterName)): 드라이버 및 용지 기본 설정을 확인한 뒤 AMIS에서 직접 테스트하세요." }
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

    if ([string]::IsNullOrWhiteSpace($TargetIp) -or $TargetIp -eq '백업 IP') {
        return [pscustomobject]@{ Success = $false; Message = 'SIP-30M 대상 TCP/IP 주소가 확인되지 않습니다.' }
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

    $settingsApplied = $false
    if ($datFile -and (Test-Path -LiteralPath $datFile)) {
        [void](Invoke-NativeCommand -FilePath 'rundll32.exe' -Arguments @('printui.dll,PrintUIEntry', '/Sr', '/q', '/n', $curName, '/a', $datFile, 'd', 'g', 'u', 'r'))
        $settingsApplied = $true
    }

    $pendingRegs = @()
    if ($regFile -and (Test-Path -LiteralPath $regFile)) {
        $pendingRegs = @([pscustomobject]@{ PrinterName = $curName; OriginalPrinterName = $OriginalPrinterName; RegFullPath = $regFile })
        $settingsApplied = $true
    }

    Invoke-AsanStandardPolicyAtomic -PendingRegImports $pendingRegs

    $safeCurName = ($curName -replace '"', '\"')
    Start-Process -FilePath 'rundll32.exe' -ArgumentList ('printui.dll,PrintUIEntry /e /n "' + $safeCurName + '"')

    $detail = '백업된 설정 파일이 없어 기본 설정 창에서 값을 직접 확인하세요.'
    if ($settingsApplied) { $detail = '백업된 4개 탭 인쇄 기본 설정(리본/코팅/농도/MS쓰기)이 자동 주입되었습니다.' }
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
            } catch {}
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
    if ([string]::IsNullOrWhiteSpace($PrtBakDir) -or -not (Test-Path -LiteralPath $PrtBakDir)) { return @() }

    foreach ($d in @(Get-ChildItem -LiteralPath $PrtBakDir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith('_')) { continue }
        $hasMarker = (Test-Path -LiteralPath (Join-Path $d.FullName 'PrinterBackup.json')) -or (Test-Path -LiteralPath (Join-Path $d.FullName 'PrinterBackup.printerExport'))
        if (-not $hasMarker) { continue }
        $effTime = Get-BackupEffectiveWriteTime -DirInfo $d
        if (($now - $effTime).TotalDays -lt [double]$DaysThreshold) { continue }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $d.FullName)) { $removed.Add($d.Name) }
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
    foreach ($s in ($secrets | Sort-Object { $_.Length } -Descending | Select-Object -Unique)) {
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
        $tcpKey    = Join-Path $tcpRegRoot $port
        if (Test-Path -LiteralPath $tcpKey) {
            $sv = (Get-ItemProperty -LiteralPath $tcpKey -Name 'SNMP Enabled' -ErrorAction SilentlyContinue).'SNMP Enabled'
            if ($null -ne $sv -and [int]$sv -ne 0) {
                $snmpState = 'ON'
                $snmpWarn  = $true
            } else {
                $snmpState = 'OFF'
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
