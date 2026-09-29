# Kinect v2 做 Windows Hello 人脸登录 —— 资料 + 本机核查

> **提示**：启用 Windows Hello 这一步现在已经并进一键安装脚本
> [`../KinectCamV2-install/install.ps1`](../KinectCamV2-install/install.ps1)
> （`-WindowsHello Yes`，或运行时交互选择）。本目录的 `install-kinect-driver.ps1`
> 作为单独版本保留，两者做的是同一件事。

## 1. 原帖情况

原 Channel 9 Coding4Fun 帖 `channel9.msdn.com/coding4fun/kinect/Windows-Hello-with-the-Kinect-v2`
已随 Channel 9 于 2021 年底并入 Microsoft Learn 而下线，原 URL 现在 302 到
`learn.microsoft.com/en-us/shows/`，正文不可恢复（本机网络下 `web.archive.org` / `archive.ph`
均无法连通，Wayback 快照取不到）。

但同内容的**中文镜像还在**，可以完整还原这篇帖子的做法：

- [在 win10 下配置，用 Kinect2.0 来实现 Windows Hello 验证身份](https://blog.csdn.net/qq_22033759/article/details/50181923)
  （CSDN，发布于 2015-12-04，与 Coding4Fun 原帖同期，步骤一致）

它不是一个源码项目，而是**一段注册表 + 一次驱动更新**：

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DriverFlighting\Partner]
"TargetRing"="Drivers"
```

然后到设备管理器里对 `WDF KinectSensor Interface 0` 执行「更新驱动程序 → 自动搜索」，
重启后进 `设置 → 账户 → 登录选项` 就会多出 Windows Hello 人脸（需先设置 PIN）。

## 2. 那个注册表到底在干什么

`DriverFlighting\Partner\TargetRing = Drivers` 是 2015 年用来把本机**加入驱动分发预览环**，
好让 Windows Update 提前下发当时还没 GA 的 Kinect 新驱动。

**现在这一条已经没用了**：Windows Update 直接就把该驱动作为正式版下发（见第 4 节实测）。
而且这个键会把整机都拉进驱动预览环（其它硬件也会提前收到预览驱动），副作用大于收益。

## 3. 驱动包内容（从 Windows Update 下发的 cab 里解出来的权威信息）

更新标题：`Microsoft - KinectSensor - 5/16/2019 - 2.2.1905.16000`，包体 70.1 MB。

| 文件 | 作用 |
| --- | --- |
| `kinectsensor.inf` | 驱动安装描述 |
| `KinectSensor.sys` | KMDF 1.11 内核驱动，`BootCritical=1` |
| `KinectMFMediaSource.dll` | **Media Foundation 摄像头源**（关键） |
| `KinectRuntime-x64.msi` | Kinect v2 运行时（Kinect20.dll / Microsoft.Kinect.dll / KinectService.exe / KinectMonitor.exe / FernsModel.bin 等 15 个文件） |
| `K4WRuntimeInstallService.exe` | 运行时安装服务 |
| `vcredist/vc_redist` | VC++ 运行库 |

`kinectsensor.inf` 里最关键的几行：

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

结论：这个驱动把 Kinect v2 注册成**标准 Windows 摄像头设备**
（设备名 `Kinect V2 Video Sensor`，走 Media Foundation / FrameServer 这条链）。
Windows Hello 人脸识别正是跑在这条链上的 —— 这才是原帖说「能刷脸」的根本原因，
和 DirectShow 的 KinectCamV2 是两条完全不同的路。

注意 INF 里**没有** Biometric 设备类或 WBF 注册项：Hello 人脸组件是 Windows 在检测到
兼容的 IR 摄像头后按需拉取的（本机存在 `System32\WinBioPlugIns\FaceBootstrapAdapter.dll`，
就是这个引导适配器）。

## 4. 本机核查结果

| 项目 | 现状 |
| --- | --- |
| 系统 | Windows 11 专业工作站版 build 26200 |
| Kinect 设备 | `USB\VID_045E&PID_02C4&MI_00`，状态 OK |
| 已装驱动 | `2.0.1410.18000`（2014-10-18，oem68.inf）——**2014 年的老驱动** |
| Windows Update | **直接提供** `Microsoft - KinectSensor - 5/16/2019 - 2.2.1905.16000` |
| `DriverFlighting` 键 | 不存在，且**不需要**（WU 已直接下发） |
| Biometric 类设备 | 无 |
| Windows 生物识别服务 | `WbioSrvc` 停止 / 手动 |
| Windows Hello 人脸 | 目前不可用 |

驱动包已下载到 Windows Update 缓存（70.1 MB），**尚未安装**。

## 5. 执行状态

### 已完成（2026-09-29）

- [x] 安装驱动 `2.2.1905.16000`
      （脚本：[install-kinect-driver.ps1](./install-kinect-driver.ps1)，结果 `ResultCode=2` 成功）
- [x] 设备已切换到新驱动：`WDF KinectSensor Interface 0` → `2.2.1905.16000`，服务 `KinectSensor`
- [x] `C:\Windows\System32\Kinect\KinectMFMediaSource.dll` 已就位
- [x] **Windows 自己的摄像头枚举里已经出现 `Kinect V2 Video Sensor`**（Media Foundation 链）
- [x] KinectCamV2 的 DirectShow 虚拟摄像头 `Kinect Camera V2` 未受影响，仍然可见

### 已完成（重启 + 录入人脸之后）

- [x] 重启电脑，驱动完全生效
- [x] `设置 → 账户 → 登录选项` 出现「人脸识别 (Windows Hello)」并完成录入
- [x] 新增生物识别设备：`Facial Recognition (Windows Hello) Software Device`
      （`ROOT\WINDOWSHELLOFACESOFTWAREDRIVER\0000`，Class=Biometric，Status=OK，驱动 `10.0.26100.9444`）
- [x] 生物识别事件日志确认录入成功，共 5 次：
      `Windows 生物识别服务成功使用传感器 Facial Recognition (Windows Hello) Software Device
       (\FacialFeatures\Virtual Sensors\{063436EF-2F27-4B5F-9192-A31BE552253B}) 注册 <当前用户>`
- [x] `KinectSensor` 服务保持 `Start=3`（按需启动，按用户要求）

### 说明：为什么 verify.ps1 里「人脸生物识别单元数量」仍是 0

那个数字用的是 `WinBioEnumBiometricUnits(FACIAL_FEATURES)`。这台机器上 Kinect 走的是
**Virtual Sensors** 架构（`\FacialFeatures\Virtual Sensors\{...}`），用户态枚举拿不到这些虚拟传感器，
所以这个指标在这里**不适用**。判断 Hello 是否就绪请看：

1. 生物识别事件日志的 1010 事件（注册成功）
2. PnP 里的 `Facial Recognition (Windows Hello) Software Device`
3. `设置 → 账户 → 登录选项` 里人脸识别是否显示已设置

### 关于 ESS（增强登录安全）

VBS 在本机是**运行中**（`VirtualizationBasedSecurityStatus = 2`，HVCI 等已开），
但事件日志里有 `1600 / 0x80070032`：生物识别服务无法启动其安全组件。
这是**预期行为**——ESS 要求摄像头走硬件级安全通道，Kinect 经 Media Foundation 软件源暴露，
不满足该条件，因此 Hello 以标准模式运行。识别本身正常，只是不享受 ESS 增加的那层防伪。

### 重启前的基线（供对比）

| 检查项 | 重启前 |
| --- | --- |
| 驱动版本 | `2.2.1905.16000` ✅ |
| Windows 摄像头列表 | `Kinect V2 Video Sensor` ✅ |
| DirectShow `Kinect Camera V2` | 可见 ✅ |
| `WbioSrvc` | Stopped / Manual |
| 人脸生物识别单元 | 0 |

## 6. 要做的两步

1. 安装驱动（管理员 + 重启；内核驱动是 boot-critical，必须重启）
2. 重启后看 `设置 → 账户 → 登录选项` 是否出现「人脸识别 (Windows Hello)」，需要先设 PIN

回滚：设备管理器 → `WDF KinectSensor Interface 0` → 属性 → 驱动程序 → 回退驱动程序。

## 7. 可选：锁屏唤醒慢的补丁

如果重启后刷脸正常、但锁屏要等几秒 Kinect 才亮灯，把 Kinect 驱动服务改成开机自启：

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\KinectSensor]
"Start"=dword:00000002
```

（`3` = 按需启动，`2` = 自动启动。装完驱动后才能确认这个服务键名是否存在。）
