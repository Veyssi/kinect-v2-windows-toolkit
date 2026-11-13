# Kinect v2 Windows Toolkit

中文版本：[README.md](README.md)

Connect an **Xbox One Kinect v2** to Windows: install it with one script, use it as a camera in your applications, and optionally enable **Windows Hello** face sign-in.

> One-click installer for **Xbox One Kinect (v2) on Windows**. It registers Kinect as a DirectShow virtual
> camera and — optionally — installs the Media Foundation driver so Windows sees it as a real system camera
> that can be used for **Windows Hello face sign-in**.

## What you get

The script performs two steps; the second is optional:

| Step | What it does | How it appears to applications |
| --- | --- | --- |
| 1 | Installs the KinectCamV2 DirectShow virtual camera (always installed by default) | `Kinect Camera V2` |
| 2 (optional) | Installs the Kinect Media Foundation driver | `Kinect V2 Video Sensor` + Windows Hello face sign-in |

These device names represent two different camera paths, each serving a different purpose:

- `Kinect Camera V2` — the DirectShow path. OBS, ffmpeg, VLC, and some older conferencing software recognize it.
- `Kinect V2 Video Sensor` — the Media Foundation path. The Windows Camera app, Teams, and browsers recognize it; **Windows Hello face sign-in also uses this path**.

Both devices can be present at the same time without conflicting.

## Requirements

- Windows 10 / 11 (x64), with administrator privileges
- **Kinect for Windows SDK 2.0** (tested with v2.0_1409)
- Kinect v2 hardware and the Xbox One Kinect PC adapter (USB 3.0)

## Usage

```powershell
# Interactive: asks whether to enable Windows Hello
powershell -ExecutionPolicy Bypass -File .\install.ps1

# Install both components directly
powershell -ExecutionPolicy Bypass -File .\install.ps1 -WindowsHello Yes

# Install only the DirectShow virtual camera; leave the Kinect driver unchanged
powershell -ExecutionPolicy Bypass -File .\install.ps1 -WindowsHello No
```

The script automatically requests elevation through UAC (it needs to write to the registry and install drivers). **The prompt is shown before elevation** because the elevated process window is hidden; a prompt inside it would not be visible.

The Windows Hello path downloads the `Microsoft - KinectSensor` driver from Windows Update (about 70 MB). You **must restart** after installation. After restarting, go to **Settings → Accounts → Sign-in options**, set up a PIN, and then enroll your face.

Run the verification script (read-only; administrator privileges are not required):

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

## Uninstall

```powershell
# Unregister only the DirectShow filter
.\uninstall.ps1

# Also delete C:\KinectCamV21
.\uninstall.ps1 -RemoveFiles

# Also remove the Windows Hello driver (reverts to the previous driver; restart required)
.\uninstall.ps1 -RemoveFiles -RemoveKinectDriver
```

You can also roll back the driver manually at any time: **Device Manager → WDF KinectSensor Interface 0 → Properties → Driver → Roll Back Driver**.

## How it works

1. **DirectShow filter**: registers `KinectCam.dll` as a COM component and adds it to the DirectShow video capture device category.
   Both the x86 and x64 registry views are written so 32-bit and 64-bit applications can see it.

2. **Media Foundation driver**: Microsoft's Kinect driver (version `2.2.1905.16000`, released in 2019) includes
   `KinectMFMediaSource.dll`, which registers Kinect as a standard Windows camera
   (`KSCATEGORY_VIDEO_CAMERA`, device name `Kinect V2 Video Sensor`).
   When Windows Hello detects a compatible IR camera, it retrieves the required components as needed and uses this path for face recognition.

   For historical context, an old Channel 9 Coding4Fun tutorial ("Windows Hello with the Kinect v2") instructed users
   to set `HKLM\SOFTWARE\Microsoft\DriverFlighting\Partner\TargetRing=Drivers` to join a driver preview ring.
   **That is no longer necessary**: Windows Update now distributes this driver as a regular release.
   See [docs/windows-hello.en.md](docs/windows-hello.en.md) for the investigation.

## Known limitations

- Kinect's IR/depth streams are exposed through a Media Foundation software source and do not meet the hardware-channel requirement for **ESS (Enhanced Sign-in Security)**. Windows Hello therefore runs in standard mode: recognition works, but without ESS's additional anti-spoofing protection.
- The `KinectSensor` driver service starts on demand (`Start=3`), so the first face sign-in after the lock screen may take 1–2 seconds to turn on the sensor. To remove the delay, set the service to start automatically (`Start=2`).
- The filter opens Kinect only when first called. The screen may be black for the first **2–4 seconds** while the Kinect warms up; this is normal.
- After a system update or if Windows Update replaces the Kinect driver, you may need to run the script again.

## FAQ

### An application says the camera is in use or cannot start

There are two possible causes; check the second one as well.

**1) Another application really is using it.** Run `tools/find-camera-holder.ps1`. It uses Restart Manager (`rstrtmgr`) to list processes holding the camera, including processes that only hold a file handle or whose modules are hidden by protection:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\find-camera-holder.ps1
```

Close the process it identifies, then run `install.ps1` again (otherwise that architecture will still use the old filter; the installer will tell you).

**2) The requested video format is unsupported, but the application reports it as "in use."** The upstream filter only provides **1920×1080 or higher, and RGB24 only**. Most meeting and IM clients request 640×480 or 1280×720 by default, or only support YUY2; negotiation fails and the application reports the camera as busy.
The DLLs in this repository's `bin\` directory **already include the fix** (see the change log below):

| Request | Upstream version | This repository |
| --- | --- | --- |
| 640×480 RGB24 | ❌ | ✅ |
| 1280×720 RGB24 | ❌ | ✅ |
| 640×480 YUY2 | ❌ | ✅ |
| NV12 (common in modern capture / encoding pipelines) | ❌ | ✅ |
| 1920×1080 RGB24 | ✅ | ✅ |

To see which formats the device provides, list them with ffmpeg:

```powershell
ffmpeg -f dshow -list_options true -i "video=Kinect Camera V2"
```

### You may not need this filter

After installing the Kinect **Media Foundation driver** (the `install.ps1 -WindowsHello Yes` option installs it), Windows adds a camera device named **`Kinect V2 Video Sensor`**. In testing, it appeared in both the DirectShow and Media Foundation APIs: the Camera app, Teams, browsers, Windows Hello, and ffmpeg could all use it **without this filter**.

That makes this repository's filter more of a **fallback**. It is useful in two cases:

1. **More formats and resolutions.** The system source provides only `YUY2 1920×1080` and `YUY2/NV12 512×424`; the filter provides 10 resolutions (320×240 to 3840×2160) × 3 pixel formats (RGB24 / YUY2 / NV12). Applications that require 640×480 or RGB24 can use the filter when the system source cannot provide those formats.
2. **Image flipping.** Right-click the filter's tray icon to toggle mirroring (the setting is per host process, so processes do not affect one another). The system source's image is **always mirrored** and has no toggle. For that reason, the filter **does not mirror by default**, avoiding a double mirror when an application also mirrors its preview.

Choose based on your application: **use the system source if it works** to avoid an extra virtual camera; use the filter if the application requires a format or resolution the system source does not provide.

### The filter will not install / the x64 version will not update

A DLL that has been loaded by an application cannot be overwritten. The installer checks for processes using it and reports them. Close the corresponding application and run the installer again.

## Change log

### v2.1: Add NV12 and clarify the default mirroring behavior (current version in `bin\`)

- **Add NV12 output.** The system source provides `YUY2/NV12`, and modern capture / encoding pipelines (such as browsers and hardware encoders) commonly request NV12. This was the system source's only pixel format advantage; adding NV12 gives the filter complete coverage of the available pixel formats.
- **Keep mirroring off by default** (matching upstream behavior). During development, the default was briefly changed to mirrored to match the system source's orientation. However, the system source already outputs a mirrored image, and most video software mirrors its preview too. If the filter also mirrored by default, the preview would be double-mirrored (and appear unmirrored), while the remote feed would be reversed. The usual practice is to output the camera's unmodified image and let the application handle preview mirroring; use **Mirrored** in the tray icon for the occasional case that needs it.
- Tested: RGB24, YUY2, and NV12 all produce a live image. The default orientation is opposite to the system source, meaning the filter outputs the unmirrored image.

Patch: [src/kinectcamv2.patch](src/kinectcamv2.patch) (apply with `--ignore-whitespace`; upstream files use CRLF)

```powershell
git clone https://github.com/DavidObando/KinectCamV2.git
cd KinectCamV2
git apply --ignore-whitespace ..\kinectcamv2.patch
```

### v2: Add resolution tiers and YUY2

The upstream filter supports only RGB24 at 1920×1080 or higher, which is the main reason third-party software cannot connect or reports the camera as busy. This version adds:

- **Resolution tiers**: 320×240 / 640×480 / 800×600 / 960×540 / 1024×768 / 1280×720 / 1600×900 /
  1920×1080 / 2560×1440 / 3840×2160. The Kinect's 1920×1080 image is downscaled using area averaging.
- **YUY2 output**: in addition to RGB24, provides 4:2:2 YUY2 through internal RGB-to-YUY2 conversion, for clients that support only YUY2.
- **Frame-rate range**: expanded from 30–60 fps to 5–60 fps.
- Preserves upstream's negotiation behavior in which `GetMediaType(0)` returns the currently configured format. Without it, an application requesting 640×480 could connect using the first format in the list instead (a development issue that has since been fixed).

### v1: Make the upstream version compile locally

The `Microsoft.Kinect.dll` HintPath now targets `v2.0_1409`, the target framework is upgraded from `v4.5` to `v4.8`, and the x64 configuration enables `AllowUnsafeBlocks`. All three changes are also included in the patch above.

## Repository layout

```
install.ps1                  One-click install (filter + optional Hello support)
uninstall.ps1                Uninstall
verify.ps1                   Read-only status check
bin\x86, bin\x64             KinectCam.dll / BaseClassesNET.dll / Microsoft.Kinect.dll
tools\find-camera-holder.ps1 Identify processes using the camera DLL (Restart Manager)
src\kinectcamv2.patch        All source changes relative to upstream KinectCamV2
docs\windows-hello.md        Research and test notes for Windows Hello
docs\windows-hello.en.md     English translation of the Windows Hello notes
```

## Tested environment

- Windows 11 Pro for Workstations, build 26200
- Kinect v2 (`USB\VID_045E&PID_02C4`) + Kinect for Windows SDK 2.0_1409
- Result: `Kinect Camera V2` and `Kinect V2 Video Sensor` both enumerate correctly; Windows Hello face enrollment and unlock both succeeded.

## License and acknowledgments

- The DLLs in `bin\` are compiled from [DavidObando/KinectCamV2](https://github.com/DavidObando/KinectCamV2) (MIT); the original code is by Piotr Sowa (codingbytodesign.net).
- Source changes are described in the [change log](#change-log) and the patch under `src\`.
- The install, uninstall, and verification scripts in this repository are new and also released under the MIT license; see [LICENSE](LICENSE).
