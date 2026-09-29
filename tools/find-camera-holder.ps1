#Requires -Version 5.1
<#
    用重启管理器 (rstrtmgr.dll) 查出谁占用了指定文件。
    比枚举模块更准，能看到只拿着文件句柄、没加载成模块的进程。
#>
[CmdletBinding()]
param(
    [string[]]$Path = @('C:\KinectCamV21\x64\BaseClassesNET.dll', 'C:\KinectCamV21\x64\KinectCam.dll'),
    [string]$LogPath = (Join-Path $env:TEMP 'who-locks-dll.log')
)

$ErrorActionPreference = 'Continue'

function Write-Log { param([string]$m) ; Write-Host $m; try { Add-Content -LiteralPath $LogPath -Value $m -Encoding UTF8 } catch { } }

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Elevated)) {
    $shell = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-LogPath',('"{0}"' -f $LogPath))
    foreach ($p in $Path) { $argList += @('-Path', ('"{0}"' -f $p)) }
    $proc = Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if (Test-Path -LiteralPath $LogPath) { Get-Content -LiteralPath $LogPath | Write-Host }
    exit $proc.ExitCode
}

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

$sig = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class RmQuery {
    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS { public int dwProcessId; public FILETIME ProcessStartTime; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
        public int ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames,
        uint nApplications, RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);
    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo,
        [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);

    public static string[] Who(string path) {
        uint session = 0;
        int rv = RmStartSession(out session, 0, Guid.NewGuid().ToString());
        if (rv != 0) return new string[] { "RmStartSession 0x" + rv.ToString("X8") };
        try {
            rv = RmRegisterResources(session, 1, new string[] { path }, 0, null, 0, null);
            if (rv != 0) return new string[] { "RmRegisterResources 0x" + rv.ToString("X8") };
            uint needed = 0, count = 0, reason = 0;
            rv = RmGetList(session, out needed, ref count, null, ref reason);
            if (needed == 0) return new string[] { "没有进程占用" };
            var arr = new RM_PROCESS_INFO[needed];
            count = needed;
            rv = RmGetList(session, out needed, ref count, arr, ref reason);
            if (rv != 0) return new string[] { "RmGetList 0x" + rv.ToString("X8") };
            var list = new List<string>();
            for (int i = 0; i < count; i++) {
                string t = arr[i].ApplicationType.ToString();
                list.Add(arr[i].strAppName + "  PID=" + arr[i].Process.dwProcessId +
                         "  type=" + t + "  svc=" + arr[i].strServiceShortName);
            }
            return list.ToArray();
        } finally { RmEndSession(session); }
    }
}
'@

try { Add-Type -TypeDefinition $sig -ErrorAction Stop } catch { Write-Log "Add-Type 失败: $($_.Exception.Message)"; exit 1 }

foreach ($p in $Path) {
    Write-Log "=== $p ==="
    if (-not (Test-Path -LiteralPath $p)) { Write-Log '  文件不存在'; continue }
    try {
        $fs = [IO.File]::Open($p, 'Open', 'ReadWrite', 'None')
        $fs.Close()
        Write-Log '  没有被占用（可以独占打开）'
    }
    catch {
        Write-Log '  被占用中，占用者：'
        [RmQuery]::Who($p) | ForEach-Object { Write-Log "    $_" }
    }
}
Write-Log '结束。'
