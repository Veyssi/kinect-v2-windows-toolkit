#Requires -Version 5.1
<#
    卸载脚本。

    默认只注销 DirectShow 滤镜（对应 install.ps1 的第 1 步）。

    参数：
        -RemoveFiles          连同 C:\KinectCamV21 目录一起删掉
        -RemoveKinectDriver   同时卸掉 Windows Hello 用的那个 2019 版 Kinect 驱动
                              （设备会退回 DriverStore 里的旧驱动，需要重启）

    用法：
        .\uninstall.ps1
        .\uninstall.ps1 -RemoveFiles
        .\uninstall.ps1 -RemoveFiles -RemoveKinectDriver
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\KinectCamV21',
    [switch]$RemoveFiles,
    [switch]$RemoveKinectDriver
)

$ErrorActionPreference = 'Stop'
$frameworks = @{ x86 = 'Framework'; x64 = 'Framework64' }

function Write-Log {
    param([string]$Message, [string]$EnglishMessage)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$timestamp] $Message"
    if ($PSBoundParameters.ContainsKey('EnglishMessage')) {
        Write-Host "[$timestamp] $EnglishMessage"
    }
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Elevated)) {
    $shell = (Get-Process -Id $PID).Path
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File',       ('"{0}"' -f $PSCommandPath),
        '-InstallDir', ('"{0}"' -f $InstallDir)
    )
    if ($RemoveFiles)          { $argList += '-RemoveFiles' }
    if ($RemoveKinectDriver)   { $argList += '-RemoveKinectDriver' }
    $proc = Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

# ---------- 1. 注销 DirectShow 滤镜 ----------
foreach ($arch in 'x64', 'x86') {
    $target = Join-Path $InstallDir $arch
    $regasm = Join-Path $env:WINDIR "Microsoft.NET\$($frameworks[$arch])\v4.0.30319\RegAsm.exe"
    $ngen   = Join-Path $env:WINDIR "Microsoft.NET\$($frameworks[$arch])\v4.0.30319\ngen.exe"
    if (-not (Test-Path -LiteralPath $target)) { continue }

    foreach ($dll in 'KinectCam.dll', 'BaseClassesNET.dll') {
        $path = Join-Path $target $dll
        if (-not (Test-Path -LiteralPath $path)) { continue }
        & $regasm /nologo /unregister $path
        Write-Log "[$arch] 已注销 $dll (退出码 $LASTEXITCODE)" "[$arch] Unregistered $dll (exit code $LASTEXITCODE)"
        try { & $ngen uninstall $path | Out-Null } catch { }
    }
}

# ---------- 2. 卸掉 Windows Hello 用的 Kinect 驱动（可选） ----------
if ($RemoveKinectDriver) {
    Write-Log '--- 移除 Kinect 的 2019 版驱动（Windows Hello 相关） ---' '--- Removing the 2019 Kinect driver (used by Windows Hello) ---'
    $pkg = $null
    try {
        $pkg = Get-WindowsDriver -Online -ErrorAction Stop |
            Where-Object { $_.ClassName -eq 'KinectSensor' -and $_.Version -like '*2.2.1905*' } |
            Select-Object -First 1
    }
    catch {
        Write-Log "Get-WindowsDriver 失败: $($_.Exception.Message)" "Get-WindowsDriver failed: $($_.Exception.Message)"
    }

    if (-not $pkg) {
        Write-Log '没找到 2.2.1905.16000 版驱动包，可能已经移除过了。' 'Driver package version 2.2.1905.16000 was not found; it may already have been removed.'
    }
    else {
        Write-Log "删除驱动包: $($pkg.Driver)  [$($pkg.Version)]" "Removing driver package: $($pkg.Driver)  [$($pkg.Version)]"
        & pnputil /delete-driver $pkg.Driver /uninstall /force
        Write-Log "pnputil 退出码: $LASTEXITCODE" "pnputil exit code: $LASTEXITCODE"
        Start-Sleep -Seconds 2
        & pnputil /scan-devices | Out-Null
        Write-Log '已重新扫描设备（设备会退回 DriverStore 里的旧驱动）。' 'Devices rescanned (they will revert to the older driver in the DriverStore).'
        Write-Log '>> 请重启电脑。设备管理器里也可以随时用「回退驱动程序」做同样的事。' '>> Restart the computer. You can also use "Roll Back Driver" in Device Manager at any time.'
    }
}

# ---------- 3. 删文件 ----------
if ($RemoveFiles -and (Test-Path -LiteralPath $InstallDir)) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Log "已删除 $InstallDir" "Removed $InstallDir"
}

Write-Log '卸载完成。' 'Uninstallation complete.'
