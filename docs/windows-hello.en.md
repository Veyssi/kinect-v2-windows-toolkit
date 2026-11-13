# Windows Hello Face Sign-in with Kinect v2 — Research and Local Verification

中文版本：[windows-hello.md](windows-hello.md)

> **Note:** Enabling Windows Hello is now included in the one-click installer
> [`../install.ps1`](../install.ps1) (`-WindowsHello Yes`, or choose it when prompted).
> The original notes also refer to a standalone `install-kinect-driver.ps1`; that script is not present
> in this repository.

## 1. About the original post

The original Channel 9 Coding4Fun post at `channel9.msdn.com/coding4fun/kinect/Windows-Hello-with-the-Kinect-v2`
went offline when Channel 9 was folded into Microsoft Learn at the end of 2021. Its URL now redirects (HTTP 302) to
`learn.microsoft.com/en-us/shows/`, and the article text is no longer available. On the local network used for this
investigation, neither `web.archive.org` nor `archive.ph` was reachable, so a Wayback snapshot could not be retrieved.

A **Chinese mirror of the same article is still available**, and provides a complete account of its instructions:

- [Configure Windows 10 to use Kinect 2.0 for Windows Hello authentication](https://blog.csdn.net/qq_22033759/article/details/50181923)
  (CSDN, published 2015-12-04, around the same time as the Coding4Fun original, with matching steps)

This is not a source-code project; the procedure consists of **a registry setting and a driver update**:

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DriverFlighting\Partner]
"TargetRing"="Drivers"
```

Then, in Device Manager, choose **Update driver → Search automatically** for `WDF KinectSensor Interface 0`.
After restarting, open **Settings → Accounts → Sign-in options** to enable Windows Hello face sign-in (a PIN must
be set up first).

## 2. What the registry setting does

`DriverFlighting\Partner\TargetRing = Drivers` was used in 2015 to put the computer in a **driver distribution
preview ring**, allowing Windows Update to deliver the then-not-yet-generally-available Kinect driver early.

**This setting is no longer needed:** Windows Update now distributes the driver as a regular release (see the local
test in section 4). In addition, this key puts the entire computer in the driver preview ring, so other hardware
may also receive preview drivers. The side effects outweigh any benefit.

## 3. Driver package contents (authoritative details extracted from the Windows Update CAB)

Update title: `Microsoft - KinectSensor - 5/16/2019 - 2.2.1905.16000`; package size: 70.1 MB.

| File | Purpose |
| --- | --- |
| `kinectsensor.inf` | Driver installation description |
| `KinectSensor.sys` | KMDF 1.11 kernel driver, `BootCritical=1` |
| `KinectMFMediaSource.dll` | **Media Foundation camera source** (the key component) |
| `KinectRuntime-x64.msi` | Kinect v2 runtime (`Kinect20.dll`, `Microsoft.Kinect.dll`, `KinectService.exe`, `KinectMonitor.exe`, `FernsModel.bin`, and 15 other files) |
| `K4WRuntimeInstallService.exe` | Runtime installation service |
| `vcredist/vc_redist` | Visual C++ runtime |

The most important lines in `kinectsensor.inf` are:

```inf
DriverVer=05/16/2019,2.2.1905.16000

[KinectSensor.Dev.NT.Interfaces]
AddInterface = %KSCATEGORY_VIDEO_CAMERA%, ...   ; {E5323777-F976-4f5b-9B55-B94699C46E44}
AddInterface = %KSCATEGORY_CAPTURE%, ...
AddInterface = %KSCATEGORY_VIDEO%, ...

[KinectMFMediaSourceInterface.AddReg]
HKR,,CLSID,,%ProxyVCap.CLSID%                       ; {17CCA71B-ECD7-11D0-B908-00A0C9223196}
HKR,,CustomCaptureSourceClsid,,%KinectMFMediaSource.CLSID%  ; {F2C6892D-006F-463D-ACCC-837A055C7A98}
HKR,,FriendlyName,,%KinectMFMediaSource.Desc%       ; "Kinect V2 Video Sensor"
```

Conclusion: this driver registers Kinect v2 as a **standard Windows camera device** (device name
`Kinect V2 Video Sensor`, using the Media Foundation / FrameServer path). Windows Hello face recognition runs on
this path. That is the underlying reason the original post says Kinect can be used for face sign-in; it is a
completely different path from the KinectCamV2 DirectShow filter.

Note that the INF contains **no** Biometric device class or WBF registration. Windows downloads the Windows Hello
face components as needed when it detects a compatible IR camera. This computer has
`System32\WinBioPlugIns\FaceBootstrapAdapter.dll`, the bootstrap adapter for this process.

## 4. Local verification results

| Item | Status |
| --- | --- |
| System | Windows 11 Pro for Workstations, build 26200 |
| Kinect device | `USB\VID_045E&PID_02C4&MI_00`, status OK |
| Driver installed before testing | `2.0.1410.18000` (2014-10-18, `oem68.inf`) — **the older 2014 driver** |
| Windows Update | **Directly offers** `Microsoft - KinectSensor - 5/16/2019 - 2.2.1905.16000` |
| `DriverFlighting` key | Absent and **not needed** (Windows Update offers the driver directly) |
| Biometric-class device | None |
| Windows Biometric Service | `WbioSrvc` stopped / manual |
| Windows Hello face sign-in | Not yet available |

The driver package had been downloaded to the Windows Update cache (70.1 MB), but **had not yet been installed** at
the time of this check.

## 5. Execution status

### Completed (2026-09-29)

- [x] Installed driver `2.2.1905.16000`
      (script: `install-kinect-driver.ps1`; result `ResultCode=2`, success)
- [x] Device switched to the new driver: `WDF KinectSensor Interface 0` → `2.2.1905.16000`; service: `KinectSensor`
- [x] `C:\Windows\System32\Kinect\KinectMFMediaSource.dll` is in place
- [x] **`Kinect V2 Video Sensor` now appears in Windows' camera enumeration** (Media Foundation path)
- [x] KinectCamV2's DirectShow virtual camera `Kinect Camera V2` remains visible and unaffected

### Completed (after restart and face enrollment)

- [x] Restarted the computer; the driver took effect fully
- [x] **Face Recognition (Windows Hello)** appeared under **Settings → Accounts → Sign-in options**, and enrollment completed
- [x] New biometric device detected: `Facial Recognition (Windows Hello) Software Device`
      (`ROOT\WINDOWSHELLOFACESOFTWAREDRIVER\0000`, Class=Biometric, Status=OK, driver `10.0.26100.9444`)
- [x] Biometric event logs confirmed successful enrollment five times:
      `Windows Biometric Service successfully used sensor Facial Recognition (Windows Hello) Software Device
       (\FacialFeatures\Virtual Sensors\{063436EF-2F27-4B5F-9192-A31BE552253B}) to register <current user>`
- [x] `KinectSensor` service remains at `Start=3` (start on demand, as requested)

### Why `verify.ps1` still reports zero facial biometric units

That count uses `WinBioEnumBiometricUnits(FACIAL_FEATURES)`. This computer uses the **Virtual Sensors** architecture
for Kinect (`\FacialFeatures\Virtual Sensors\{...}`), which is not exposed through the user-mode enumeration API.
Therefore, this metric **does not apply here**. To determine whether Hello is ready, check:

1. Biometric event log event 1010 (successful registration)
2. The `Facial Recognition (Windows Hello) Software Device` in Plug and Play
3. Whether face recognition is set up under **Settings → Accounts → Sign-in options**

### About ESS (Enhanced Sign-in Security)

VBS is **running** on this computer (`VirtualizationBasedSecurityStatus = 2`, with HVCI and other features enabled),
but the event log contains `1600 / 0x80070032`: the Biometric Service could not start its security component.
**This is expected.** ESS requires the camera to use a hardware-level secure channel; Kinect is exposed through a
Media Foundation software source and does not meet that requirement. Windows Hello therefore runs in standard
mode. Recognition works, but it does not get ESS's additional anti-spoofing protection.

### Baseline before restarting (for comparison)

| Check | Before restart |
| --- | --- |
| Driver version | `2.2.1905.16000` ✅ |
| Windows camera list | `Kinect V2 Video Sensor` ✅ |
| DirectShow `Kinect Camera V2` | Visible ✅ |
| `WbioSrvc` | Stopped / Manual |
| Facial biometric units | 0 |

## 6. The two steps to complete

1. Install the driver (administrator privileges and a restart are required; the kernel driver is boot-critical).
2. After restarting, check whether **Face Recognition (Windows Hello)** appears under **Settings → Accounts → Sign-in options**; set up a PIN first if needed.

To roll back: **Device Manager → WDF KinectSensor Interface 0 → Properties → Driver → Roll Back Driver**.

## 7. Optional: reduce lock-screen wake-up delay

If face sign-in works after restarting but Kinect takes a few seconds to turn on at the lock screen, configure the
Kinect driver service to start automatically:

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\KinectSensor]
"Start"=dword:00000002
```

(`3` = start on demand; `2` = automatic start. The service key can be confirmed only after the driver is installed.)
