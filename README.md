# Kinect v2 Windows Toolkit

把 Xbox One 的 **Kinect v2** 接进 Windows：一个脚本装完，程序里就能当摄像头用，还能开 **Windows Hello** 刷脸登录。

> One-click installer for **Xbox One Kinect (v2) on Windows**. It registers Kinect as a DirectShow virtual
> camera and — optionally — installs the Media Foundation driver so Windows sees it as a real system camera
> that can be used for **Windows Hello face sign-in**.

## 装完能做什么

一个脚本做两件事，第二件可选：

| 步骤 | 内容 | 程序里出现 |
| --- | --- | --- |
| 1 | KinectCamV2 DirectShow 虚拟摄像头（默认总是装） | `Kinect Camera V2` |
| 2（可选） | Kinect 的 Media Foundation 驱动 | `Kinect V2 Video Sensor` + Windows Hello 刷脸 |

两个设备名对应两条不同的链路，各管一摊：

- `Kinect Camera V2` —— DirectShow 链路。OBS、ffmpeg、VLC、老一点的通话软件认它。
- `Kinect V2 Video Sensor` —— Media Foundation 链路。Windows 相机 App、Teams、浏览器认它，**Windows Hello 人脸也走这条**。

两条可以同时存在，互不冲突。

## 环境要求

- Windows 10 / 11（x64），管理员权限
- **Kinect for Windows SDK 2.0**（实测 v2.0_1409）
- Kinect v2 本体 + Xbox One Kinect 的 PC 转接器（USB 3.0）

## 用法

```powershell
# 交互：会问你一句要不要开 Windows Hello
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 直接都装
powershell -ExecutionPolicy Bypass -File .\install.ps1 -WindowsHello Yes

# 只装 DirectShow 虚拟摄像头，不碰 Kinect 驱动
powershell -ExecutionPolicy Bypass -File .\install.ps1 -WindowsHello No
```

脚本会自动弹 UAC 提权（要写注册表 / 装驱动）。**提问放在提权之前** —— 提权后的进程窗口是隐藏的，提问放里面就看不见了。

开 Windows Hello 的分支会从 Windows Update 取 `Microsoft - KinectSensor` 驱动（约 70MB），装完**必须重启**；
重启后进 `设置 → 账户 → 登录选项`，先设 PIN 再录人脸。

核查脚本（只读，不需要管理员）：

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

## 卸载

```powershell
# 只注销 DirectShow 滤镜
.\uninstall.ps1

# 连 C:\KinectCamV21 一起删
.\uninstall.ps1 -RemoveFiles

# 把 Windows Hello 用的驱动也卸掉（回到旧驱动，需重启）
.\uninstall.ps1 -RemoveFiles -RemoveKinectDriver
```

驱动也可以随时手动回退：设备管理器 → `WDF KinectSensor Interface 0` → 属性 → 驱动程序 → 回退驱动程序。

## 原理速览

1. **DirectShow 滤镜**：把 `KinectCam.dll` 注册成 COM 组件，再挂到 DirectShow 的「视频采集设备」分类下。
   x86 / x64 两个位数的注册表视图都写，所以 32 位和 64 位程序都能看到。

2. **Media Foundation 驱动**：MS 在 2019 年发布的 Kinect 驱动（`2.2.1905.16000`）里带了一个
   `KinectMFMediaSource.dll`，把 Kinect 注册成标准 Windows 摄像头
   （`KSCATEGORY_VIDEO_CAMERA`，设备名 `Kinect V2 Video Sensor`）。
   Windows Hello 人脸就是在检测到兼容 IR 摄像头后按需拉取组件、走这条链路完成识别的。

   顺带一提：早年那篇 Channel 9 Coding4Fun 教程（《Windows Hello with the Kinect v2》）教人用
   `HKLM\SOFTWARE\Microsoft\DriverFlighting\Partner\TargetRing=Drivers` 把机器加进驱动预览环来提前拿到驱动。
   **现在不需要了**，Windows Update 直接就把这版作为正式驱动下发。那段历史见 [docs/windows-hello.md](docs/windows-hello.md)。

## 已知限制

- Kinect 的 IR/深度流经 Media Foundation 软件源暴露，不满足 **ESS（增强登录安全）** 的硬件通道要求，
  所以 Hello 以标准模式运行 —— 识别正常，只是少了 ESS 那层额外防伪。
- `KinectSensor` 驱动服务是按需启动（`Start=3`），锁屏后首次刷脸可能要等 1~2 秒才亮灯。
  想消除这个延迟，把该服务改成开机自启（`Start=2`）即可。
- 滤镜第一次被调用时才打开 Kinect，**前 2～4 秒是黑屏**（Kinect 本体预热），属正常。
- 更新系统或让 Windows Update 换掉 Kinect 驱动后，可能需要重跑一次脚本。

## 常见问题

### 程序报「摄像头被占用 / 无法启动摄像头」

分两种，先看第二种。

**1) 真的有别的程序拿着它。** 用 `tools/find-camera-holder.ps1` 查，它会用重启管理器（rStrtmgr）
把占用进程直接列出来 —— 包括只拿着文件句柄、或带保护看不见模块的进程：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\find-camera-holder.ps1
```

查出来是谁就关掉谁，再重跑 `install.ps1`（否则那个位数还是旧版本的滤镜 —— 安装脚本会明确提示）。

**2) 格式谈不拢，被程序笼统报成"被占用"。** 上游原版滤镜只提供 **1920×1080 及以上** 且 **只有 RGB24**，
而大多数会议 / IM 客户端默认要 640×480、1280×720，或者只认 YUY2 —— 协商失败就报"占用"。
本仓库 `bin\` 里的 DLL **已经修好这一点**（见下面的变更记录）：

| 请求 | 上游原版 | 本仓库 |
| --- | --- | --- |
| 640×480 RGB24 | ❌ | ✅ |
| 1280×720 RGB24 | ❌ | ✅ |
| 640×480 YUY2 | ❌ | ✅ |
| 1920×1080 RGB24 | ✅ | ✅ |

自己确认设备到底提供什么格式，可以用 ffmpeg 列一下：

```powershell
ffmpeg -f dshow -list_options true -i "video=Kinect Camera V2"
```

### 滤镜装不上 / x64 更新不了

被程序加载过的 DLL 无法覆盖。安装脚本会查出占用者并提示，关掉对应程序后重跑即可。

## 变更记录

### v2：修复分辨率与像素格式（当前 `bin\` 里的版本）

上游原版只支持 1920×1080 及以上的 RGB24，这是"三方软件连不上/报被占用"的主因。本版在原版基础上补了：

- **分辨率阶梯**：320×240 / 640×480 / 800×600 / 960×540 / 1024×768 / 1280×720 / 1600×900 /
  1920×1080 / 2560×1440 / 3840×2160，内部把 Kinect 的 1920×1080 画面做面积平均缩放后输出。
- **YUY2 输出**：除 RGB24 外额外提供 4:2:2（内部做 RGB→YUY2 转换），兼容只认 YUY2 的客户端。
- **帧率范围**：30～60fps 放宽到 5～60fps。
- 保留了上游「`GetMediaType(0)` 返回当前已设置格式」的协商逻辑 —— 少了它，应用请求 640×480 也会被按
  列表第一项连上（开发时踩过这个坑，已修正）。

改动以补丁形式提供：[src/kinectcamv2-multires-yuy2.patch](src/kinectcamv2-multires-yuy2.patch)

```powershell
git clone https://github.com/DavidObando/KinectCamV2.git
cd KinectCamV2
git apply ..\kinectcamv2-multires-yuy2.patch
# 再用 Visual Studio / MSBuild 编译（见下方致谢里的三处工程改动）
```

### v1：让原版能在本机编译

`Microsoft.Kinect.dll` 的 HintPath 指向 `v2.0_1409`、目标框架 `v4.5` → `v4.8`、
x64 配置补 `AllowUnsafeBlocks`（这三处也包含在上面的补丁里）。

## 目录

```
install.ps1                 一键安装（滤镜 + 可选 Hello）
uninstall.ps1               卸载
verify.ps1                  只读状态核查
bin\x86, bin\x64            KinectCam.dll / BaseClassesNET.dll / Microsoft.Kinect.dll
tools\find-camera-holder.ps1 查是谁占用了摄像头 DLL（重启管理器实现）
src\*.patch                 相对上游 KinectCamV2 的源码改动
docs\installer-readme.md    安装脚本的详细说明
docs\windows-hello.md       Windows Hello 部分的考证与实测记录
```

## 实测环境

- Windows 11 专业工作站版 build 26200
- Kinect v2（`USB\VID_045E&PID_02C4`）+ Kinect for Windows SDK 2.0_1409
- 结果：`Kinect Camera V2` 与 `Kinect V2 Video Sensor` 均正常枚举，Windows Hello 人脸录入并成功解锁

## 授权与致谢

- `bin\` 里的 DLL 编译自 [DavidObando/KinectCamV2](https://github.com/DavidObando/KinectCamV2)（MIT），
  原始代码出自 Piotr Sowa（codingbytodesign.net）。
- 源码改动见 [变更记录](#变更记录) 与 `src\` 下的补丁。
- 本仓库的安装/卸载/核查脚本为新增内容，同样以 MIT 发布，见 [LICENSE](LICENSE)。
