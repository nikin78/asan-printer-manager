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
