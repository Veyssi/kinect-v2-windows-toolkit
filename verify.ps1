#Requires -Version 5.1
<#
    重启后运行，核对 Kinect 摄像头 / Windows Hello 是否就位。
    只读检查，不修改任何东西。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# ---------- 1. 驱动 ----------
Section '1. Kinect 驱动'
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'KinectSpeaker|KinectSensor|WDF KinectSensor' } | Select-Object -First 1
if ($dev) {
    "设备: $($dev.FriendlyName)  [$($dev.Status)]"
    foreach ($k in 'DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverDate', 'DEVPKEY_Device_Service') {
        try { "  {0} = {1}" -f $k, (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName $k -ErrorAction Stop).Data } catch { }
    }
}
else {
    '没找到 Kinect 设备'
}

# ---------- 2. Windows 自己的摄像头枚举（MF / WinRT，和 Teams、相机 App、Hello 用同一条链） ----------
Section '2. Windows 摄像头列表 (Media Foundation)'
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                       $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Await($op, $type) {
        $m = $asTaskGeneric.MakeGenericMethod($type)
        $t = $m.Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
    }
    [void][Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    $op = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync(
        [Windows.Devices.Enumeration.DeviceClass]::VideoCapture)
    $devs = Await $op ([Windows.Devices.Enumeration.DeviceInformationCollection])
    "共 $($devs.Count) 个:"
    foreach ($d in $devs) { "  - $($d.Name)" }
    if (-not ($devs | Where-Object { $_.Name -match 'Kinect' })) {
        '  !! 列表里没有 Kinect 摄像头'
    }
}
catch { "  枚举失败: $($_.Exception.Message.Split([char]10)[0])" }

# ---------- 3. DirectShow（KinectCamV2 那条路） ----------
Section '3. DirectShow 虚拟摄像头 (KinectCamV2)'
$clsid = 'HKLM:\SOFTWARE\Classes\CLSID\{E48ECF1A-A5E7-4EB0-8BF7-E15185D66FA4}\InprocServer32'
if (Test-Path $clsid) {
    "  滤镜已注册: $((Get-ItemProperty $clsid).'(default)')"
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ff) {
        $out = & ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Out-String
        if ($out -match 'Kinect Camera V2') { '  DirectShow 枚举: 可见 "Kinect Camera V2"' }
        else { '  DirectShow 枚举: 没看到 "Kinect Camera V2"' }
    }
}
else { '  KinectCamV2 滤镜未注册' }

# ---------- 4. Windows 生物识别 ----------
Section '4. Windows Hello 生物识别'
Get-Service WbioSrvc -ErrorAction SilentlyContinue | ForEach-Object { "  WbioSrvc: $($_.Status) / $($_.StartType)" }

$sig = @'
using System;
using System.Runtime.InteropServices;
public static class WinBio {
    [DllImport("winbio.dll", ExactSpelling = true)]
    public static extern int WinBioEnumBiometricUnits(uint Factor, out IntPtr Units, out UIntPtr Count);
    [DllImport("winbio.dll", ExactSpelling = true)]
    public static extern int WinBioFree(IntPtr Address);
    public static string FaceUnits() {
        IntPtr units; UIntPtr count;
        int hr = WinBioEnumBiometricUnits(0x08, out units, out count); // 0x08 = FACIAL_FEATURES
        if (hr != 0) return "WinBioEnumBiometricUnits 返回 0x" + hr.ToString("X8");
        var n = count.ToUInt64();
        if (units != IntPtr.Zero) WinBioFree(units);
        return "人脸生物识别单元数量: " + n;
    }
}
'@
try {
    Add-Type -TypeDefinition $sig -ErrorAction Stop
    '  ' + [WinBio]::FaceUnits()
}
catch { "  查询失败: $($_.Exception.Message.Split([char]10)[0])" }

Section '结论'
'如果第 2 节能看到 "Kinect V2 Video Sensor"，说明 Kinect 已经是系统摄像头。'
'接着看 设置 -> 账户 -> 登录选项 有没有"人脸识别 (Windows Hello)"（需要先设 PIN）。'
'第 4 节人脸单元数量 > 0 表示 Hello 人脸已经装好。'
