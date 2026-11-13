#Requires -Version 5.1
<#
    重启后运行，核对 Kinect 摄像头 / Windows Hello 是否就位。
    只读检查，不修改任何东西。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Bilingual($Chinese, $English) {
    Write-Host $Chinese
    Write-Host $English
}

function Section($Chinese, $English) {
    Write-Host "`n=== $Chinese ===" -ForegroundColor Cyan
    Write-Host "=== $English ===" -ForegroundColor Cyan
}

# ---------- 1. 驱动 ----------
Section '1. Kinect 驱动' '1. Kinect driver'
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'KinectSpeaker|KinectSensor|WDF KinectSensor' } | Select-Object -First 1
if ($dev) {
    Bilingual "设备: $($dev.FriendlyName)  [$($dev.Status)]" "Device: $($dev.FriendlyName)  [$($dev.Status)]"
    foreach ($k in 'DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverDate', 'DEVPKEY_Device_Service') {
        try { "  {0} = {1}" -f $k, (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName $k -ErrorAction Stop).Data } catch { }
    }
}
else {
    Bilingual '没找到 Kinect 设备' 'No Kinect device found'
}

# ---------- 2. Windows 自己的摄像头枚举（MF / WinRT，和 Teams、相机 App、Hello 用同一条链） ----------
Section '2. Windows 摄像头列表 (Media Foundation)' '2. Windows camera list (Media Foundation)'
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
    Bilingual "共 $($devs.Count) 个:" "$($devs.Count) device(s) found:"
    foreach ($d in $devs) { Bilingual "  - $($d.Name)" "  - $($d.Name)" }
    if (-not ($devs | Where-Object { $_.Name -match 'Kinect' })) {
        Bilingual '  !! 列表里没有 Kinect 摄像头' '  !! No Kinect camera is listed'
    }
}
catch { Bilingual "  枚举失败: $($_.Exception.Message.Split([char]10)[0])" "  Enumeration failed: $($_.Exception.Message.Split([char]10)[0])" }

# ---------- 3. DirectShow（KinectCamV2 那条路） ----------
Section '3. DirectShow 虚拟摄像头 (KinectCamV2)' '3. DirectShow virtual camera (KinectCamV2)'
$clsid = 'HKLM:\SOFTWARE\Classes\CLSID\{E48ECF1A-A5E7-4EB0-8BF7-E15185D66FA4}\InprocServer32'
if (Test-Path $clsid) {
    Bilingual "  滤镜已注册: $((Get-ItemProperty $clsid).'(default)')" "  Filter registered: $((Get-ItemProperty $clsid).'(default)')"
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ff) {
        $out = & ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Out-String
        if ($out -match 'Kinect Camera V2') { Bilingual '  DirectShow 枚举: 可见 "Kinect Camera V2"' '  DirectShow enumeration: "Kinect Camera V2" is visible' }
        else { Bilingual '  DirectShow 枚举: 没看到 "Kinect Camera V2"' '  DirectShow enumeration: "Kinect Camera V2" was not found' }
    }
}
else { Bilingual '  KinectCamV2 滤镜未注册' '  KinectCamV2 filter is not registered' }

# ---------- 4. Windows 生物识别 ----------
Section '4. Windows Hello 生物识别' '4. Windows Hello biometrics'
Get-Service WbioSrvc -ErrorAction SilentlyContinue | ForEach-Object { Bilingual "  WbioSrvc: $($_.Status) / $($_.StartType)" "  WbioSrvc: $($_.Status) / $($_.StartType)" }

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
        if (hr != 0) return "WinBioEnumBiometricUnits returned 0x" + hr.ToString("X8");
        var n = count.ToUInt64();
        if (units != IntPtr.Zero) WinBioFree(units);
        return "人脸生物识别单元数量: " + n + "\nFace biometric unit count: " + n;
    }
}
'@
try {
    Add-Type -TypeDefinition $sig -ErrorAction Stop
    [WinBio]::FaceUnits() -split "`n" | ForEach-Object { Write-Host "  $_" }
}
catch { Bilingual "  查询失败: $($_.Exception.Message.Split([char]10)[0])" "  Query failed: $($_.Exception.Message.Split([char]10)[0])" }

Section '结论' 'Conclusion'
Bilingual '如果第 2 节能看到 "Kinect V2 Video Sensor"，说明 Kinect 已经是系统摄像头。' 'If section 2 lists "Kinect V2 Video Sensor", Kinect is available as a system camera.'
Bilingual '接着看 设置 -> 账户 -> 登录选项 有没有"人脸识别 (Windows Hello)"（需要先设 PIN）。' 'Then check Settings -> Accounts -> Sign-in options for "Face Recognition (Windows Hello)" (a PIN must be set first).'
Bilingual '第 4 节人脸单元数量 > 0 表示 Hello 人脸已经装好。' 'A face biometric unit count greater than 0 in section 4 means Windows Hello facial recognition is installed.'
