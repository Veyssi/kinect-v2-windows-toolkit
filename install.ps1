#Requires -Version 5.1
<#
    Kinect v2 一键安装脚本

    做两件事，第二件可选：

    [1] 装 KinectCamV2 的 DirectShow 虚拟摄像头（默认总是装）
        装完系统里会多出摄像头设备 "Kinect Camera V2"，x86/x64 两个位数都注册，
        OBS / ffmpeg / 老一点的程序都能选它。

    [2] 装 Kinect 的 Media Foundation 驱动，启用 Windows Hello 人脸登录（可选）
        从 Windows Update 拿 Microsoft - KinectSensor 驱动（约 70MB），装完 Kinect 会以
        "Kinect V2 Video Sensor" 的身份成为系统摄像头（Teams / 相机 App / 浏览器 / Hello 走这条链），
        之后就能在 设置 → 账户 → 登录选项 里录入人脸。
        注意：会替换现有 Kinect 驱动，装完必须重启；可在设备管理器回退。

    用法：
        .\install.ps1                     交互询问是否启用 Windows Hello
        .\install.ps1 -WindowsHello Yes   直接装（不询问）
        .\install.ps1 -WindowsHello No    只装 DirectShow 滤镜

    需要管理员权限（写注册表 / 装驱动），脚本会自动请求提权。
#>
[CmdletBinding()]
param(
    # 是否启用 Windows Hello 人脸登录: Ask(运行时询问) / Yes / No
    [ValidateSet('Ask', 'Yes', 'No')]
    [string]$WindowsHello = 'Ask',

    [string]$InstallDir = 'C:\KinectCamV21',
    [string]$LogPath    = (Join-Path $env:TEMP 'KinectCamV2-install.log')
)

$ErrorActionPreference = 'Stop'
$payloadRoot        = $PSScriptRoot
$filterClsid        = '{E48ECF1A-A5E7-4EB0-8BF7-E15185D66FA4}'   # VirtualCamFilter
$videoInputCategory = '{860BB310-5D01-11d0-BD3B-00A0C911CE86}'
$frameworks         = @{ x86 = 'Framework'; x64 = 'Framework64' }

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch { }
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-HelloChoice {
    param([string]$Choice)
    if ($Choice -ne 'Ask') { return $Choice }
    Write-Host ''
    Write-Host '是否同时启用 Windows Hello 人脸登录？' -ForegroundColor Yellow
    Write-Host '  y   = 装 Kinect 的 MF 驱动（从 Windows Update 下，约 70MB），之后可刷脸登录，需要重启'
    Write-Host '  回车 = 只装 DirectShow 虚拟摄像头，不动现有 Kinect 驱动'
    $answer = Read-Host '启用请输入 y'
    if ($answer -match '^\s*(y|yes)\s*$') { return 'Yes' }
    return 'No'
}

# 找出谁占用了某个文件（提权后连 SYSTEM 进程的模块也能枚举）
function Get-FileHolder {
    param([string]$Path)
    $holders = @()
    foreach ($proc in Get-Process -ErrorAction SilentlyContinue) {
        try {
            foreach ($mod in $proc.Modules) {
                if ($mod.FileName -eq $Path) {
                    $holders += "$($proc.ProcessName) (PID $($proc.Id))"
                    break
                }
            }
        }
        catch { }
    }
    return $holders
}

# ============ 提权（提问必须在提权之前，否则新窗口里看不见） ============
if (-not (Test-Elevated)) {
    if ($env:KINECTCAM_NO_ELEVATE) {
        throw '安装需要管理员权限（写注册表 / 装驱动）。'
    }
    $WindowsHello = Resolve-HelloChoice $WindowsHello
    Write-Host '需要管理员权限，正在弹出 UAC，请点"是"...'
    $shell = (Get-Process -Id $PID).Path
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File',         ('"{0}"' -f $PSCommandPath),
        '-WindowsHello', $WindowsHello,
        '-InstallDir',   ('"{0}"' -f $InstallDir),
        '-LogPath',      ('"{0}"' -f $LogPath)
    )
    try {
        $proc = Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs `
                              -WindowStyle Hidden -Wait -PassThru
    }
    catch {
        # 某些系统上 RunAs 不接受 -WindowStyle
        $proc = Start-Process -FilePath $shell -ArgumentList $argList -Verb RunAs `
                              -Wait -PassThru
    }
    if (Test-Path -LiteralPath $LogPath) { Get-Content -LiteralPath $LogPath | Write-Host }
    exit $proc.ExitCode
}

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

# 提权后的进程窗口是隐藏的，出错必须写进日志，否则只看到一个退出码
trap {
    Write-Log ("!! 出错: {0}" -f $_.Exception.Message)
    Write-Log ($_.ScriptStackTrace)
    exit 1
}

Write-Log "安装目录: $InstallDir"
Write-Log "Windows Hello: $WindowsHello"

$rebootNeeded = $false

# ============ 第 1 步：DirectShow 虚拟摄像头 ============
Write-Log '--- [1/2] DirectShow 虚拟摄像头 (KinectCamV2) ---'

foreach ($arch in 'x86', 'x64') {
    $source = Join-Path $payloadRoot "bin\$arch"
    if (-not (Test-Path -LiteralPath $source)) { throw "安装包不完整，缺少 $source" }

    $regasm = Join-Path $env:WINDIR "Microsoft.NET\$($frameworks[$arch])\v4.0.30319\RegAsm.exe"
    $ngen   = Join-Path $env:WINDIR "Microsoft.NET\$($frameworks[$arch])\v4.0.30319\ngen.exe"
    if (-not (Test-Path -LiteralPath $regasm)) { throw "找不到 RegAsm: $regasm" }

    $target = Join-Path $InstallDir $arch
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    # 逐个文件复制：某个文件被占用时（常见是相机/生物识别相关服务），
    # 只要目标已存在旧文件就沿用，不让整个安装失败。
    $copied = 0
    $locked = @()
    foreach ($file in Get-ChildItem -LiteralPath $source -File) {
        $dest = Join-Path $target $file.Name
        try {
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force -ErrorAction Stop
            $copied++
        }
        catch {
            if (Test-Path -LiteralPath $dest) {
                $locked += $file.Name
            }
            else {
                throw
            }
        }
    }
    Write-Log "[$arch] 文件已就绪: $copied 个已复制 -> $target"
    if ($locked.Count -gt 0) {
        Write-Log "[$arch] $($locked -join ', ') 正被占用，沿用目录里的已有文件（内容相同）"
        foreach ($name in $locked) {
            $who = Get-FileHolder (Join-Path $target $name)
            if ($who.Count -gt 0) { Write-Log "[$arch]   占用者: $($who -join ', ')" }
        }
    }

    # 先注册 BaseClassesNET.dll（滤镜的基类库），再注册 KinectCam.dll
    foreach ($dll in 'BaseClassesNET.dll', 'KinectCam.dll') {
        $path = Join-Path $target $dll
        $extra = @()
        if ($dll -eq 'KinectCam.dll') {
            $extra = @('/tlb:' + (Join-Path $target 'KinectCam.tlb'))
        }
        & $regasm /nologo /codebase $path @extra
        if ($LASTEXITCODE -ne 0) { throw "RegAsm 注册失败 ($arch / $dll)，退出码 $LASTEXITCODE" }
        Write-Log "[$arch] 已注册 $dll"
    }

    try {
        & $ngen install (Join-Path $target 'BaseClassesNET.dll') | Out-Null
        & $ngen install (Join-Path $target 'KinectCam.dll') | Out-Null
        Write-Log "[$arch] ngen 完成"
    }
    catch {
        Write-Log "[$arch] ngen 跳过: $($_.Exception.Message)"
    }
}

# 校验注册结果
$ok = 0
foreach ($view in 'Registry64', 'Registry32') {
    $base = if ($view -eq 'Registry64') { 'HKLM:\SOFTWARE\Classes' } else { 'HKLM:\SOFTWARE\WOW6432Node\Classes' }
    $inproc   = "$base\CLSID\$filterClsid\InprocServer32"
    $instance = "$base\CLSID\$videoInputCategory\Instance\$filterClsid"
    $hasServer   = Test-Path -LiteralPath $inproc
    $hasCategory = Test-Path -LiteralPath $instance
    if ($hasServer -and $hasCategory) {
        $ok++
        $friendly = (Get-ItemProperty -LiteralPath $instance -ErrorAction SilentlyContinue).FriendlyName
        Write-Log "校验通过 [$view] 设备名: $friendly"
    }
    else {
        Write-Log "校验失败 [$view] COM组件=$hasServer 视频采集分类=$hasCategory"
    }
}
if ($ok -eq 0) { throw 'DirectShow 滤镜注册表校验失败。' }

# ============ 第 2 步：Windows Hello（可选） ============
if ($WindowsHello -eq 'Yes') {
    Write-Log '--- [2/2] Windows Hello 人脸登录 ---'

    # 只认驱动 INF 里声明的这两个硬件 ID（Petra / Metra 的 Interface 0）。
    # 注意别用 PID_02D* 之类的宽匹配：Kinect 内置 USB Hub 是 PID_02D9，会被误命中。
    $dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InstanceId -like 'USB\VID_045E&PID_02C4&MI_00*' -or
            $_.InstanceId -like 'USB\VID_045E&PID_02D8&MI_00*'
        } |
        Select-Object -First 1

    if (-not $dev) {
        Write-Log '未检测到 Kinect v2 设备（USB\VID_045E&PID_02C4 / 02D8），跳过 Windows Hello 部分。'
    }
    else {
        try {
            $ver = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction Stop).Data
            Write-Log "当前 Kinect 驱动版本: $ver"
        }
        catch { }

        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and Type='Driver'")
        $update   = $found.Updates | Where-Object { $_.Title -like '*KinectSensor*' } | Select-Object -First 1

        if (-not $update) {
            Write-Log 'Windows Update 没有可用的 KinectSensor 驱动更新 —— 当前已是支持 Windows Hello 的驱动。'
        }
        else {
            Write-Log "找到驱动更新: $($update.Title)"
            $coll = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$coll.Add($update)
            $update.AcceptEula()

            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $coll
            $downloader.Priority = 3
            $dl = $downloader.Download()
            Write-Log ("下载 ResultCode={0} HResult=0x{1:X8}" -f $dl.ResultCode, $dl.HResult)

            if ($dl.ResultCode -eq 2 -or $dl.ResultCode -eq 3) {
                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $coll
                $installer.AllowSourcePrompts = $false
                $ins = $installer.Install()
                Write-Log ("安装 ResultCode={0} HResult=0x{1:X8} RebootRequired={2}" -f `
                    $ins.ResultCode, $ins.HResult, $ins.RebootRequired)
                if ($ins.ResultCode -eq 2 -or $ins.ResultCode -eq 3) {
                    $rebootNeeded = $true
                    Write-Log 'Kinect 驱动已安装。'
                }
                else {
                    Write-Log "驱动安装失败 (ResultCode=$($ins.ResultCode))，Windows Hello 部分未完成。"
                }
            }
            else {
                Write-Log "驱动下载失败 (ResultCode=$($dl.ResultCode))，Windows Hello 部分未完成。"
            }
        }
    }
}
else {
    Write-Log '--- [2/2] Windows Hello: 按选择跳过 ---'
}

# ============ 收尾 ============
Write-Log ''
Write-Log 'DirectShow 虚拟摄像头就绪，在任何程序里把摄像头切成 "Kinect Camera V2" 即可。'
if ($WindowsHello -eq 'Yes') {
    Write-Log 'Windows Hello 部分:'
    Write-Log '  · 需要重启后生效；重启完进 设置 → 账户 → 登录选项，先设 PIN 再录入人脸。'
    Write-Log '  · Kinect 也会以 "Kinect V2 Video Sensor" 出现在系统摄像头列表（Teams / 相机 App 可用）。'
    Write-Log '  · 想撤销: 设备管理器 → WDF KinectSensor Interface 0 → 属性 → 驱动程序 → 回退驱动程序。'
    Write-Log '  · 核查脚本: ..\kinect-windows-hello\verify.ps1'
}
if ($rebootNeeded) {
    Write-Log '>> 请重启电脑，驱动才会完全生效。'
}
Write-Log '安装脚本执行完毕。'
