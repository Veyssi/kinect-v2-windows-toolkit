using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace KinectCamTray
{
    /// <summary>
    /// Kinect v2 虚拟摄像头的独立设置程序。
    ///
    /// 上游的托盘图标是滤镜在宿主进程（会议软件 / OBS / ffmpeg …）里建出来的，
    /// 只在那个程序使用摄像头时才存在，退出就没，而且 Windows 11 默认还会把它折进
    /// "隐藏的图标"。这个程序改成常驻的独立进程，图标与任何宿主程序无关。
    ///
    /// 四个开关存在 HKCU\Software\KinectCamV2，滤镜侧每 300ms 轮询一次，
    /// 所以这里一改，正在出画面的程序下一个画面就生效，并且永久保存。
    /// </summary>
    static class Program
    {
        private const string MutexName = @"Global\KinectCamTray.SingleInstance";

        [STAThread]
        static void Main()
        {
            bool _createdNew;
            using (Mutex _mutex = new Mutex(true, MutexName, out _createdNew))
            {
                if (!_createdNew)
                {
                    MessageBox.Show("KinectCamTray 已经在运行了，看任务栏右下角（可能被折叠在 ^ 里）。",
                        "KinectCamTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayContext());
            }
        }
    }

    /// <summary>四个开关的读写（与滤镜共用同一份注册表键）。</summary>
    internal static class Settings
    {
        private const string KeyPath = @"Software\KinectCamV2";

        public static bool Mirrored
        {
            get { return Read("Mirrored"); }
            set { Write("Mirrored", value); }
        }

        public static bool Zoom
        {
            get { return Read("Zoom"); }
            set { Write("Zoom", value); }
        }

        public static bool TrackHead
        {
            get { return Read("TrackHead"); }
            set { Write("TrackHead", value); }
        }

        public static bool Desktop
        {
            get { return Read("Desktop"); }
            set { Write("Desktop", value); }
        }

        private static bool Read(string _name)
        {
            try
            {
                using (RegistryKey _key = Registry.CurrentUser.OpenSubKey(KeyPath))
                {
                    if (_key == null) return false;
                    object _value = _key.GetValue(_name);
                    return _value != null && Convert.ToInt32(_value) != 0;
                }
            }
            catch
            {
                return false;
            }
        }

        private static void Write(string _name, bool _value)
        {
            try
            {
                using (RegistryKey _key = Registry.CurrentUser.CreateSubKey(KeyPath))
                {
                    if (_key != null) _key.SetValue(_name, _value ? 1 : 0, RegistryValueKind.DWord);
                }
            }
            catch (Exception _ex)
            {
                MessageBox.Show("写注册表失败：" + _ex.Message, "KinectCamTray",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    internal sealed class TrayContext : ApplicationContext
    {
        private readonly NotifyIcon m_icon;
        private readonly ToolStripMenuItem m_mirrored;
        private readonly ToolStripMenuItem m_zoom;
        private readonly ToolStripMenuItem m_trackHead;
        private readonly ToolStripMenuItem m_desktop;
        private readonly ToolStripMenuItem m_state;

        public TrayContext()
        {
            m_mirrored = MakeItem("镜像（水平翻转）", delegate { Settings.Mirrored = !Settings.Mirrored; });
            m_zoom = MakeItem("缩放（2 倍中心裁剪）", delegate { Settings.Zoom = !Settings.Zoom; });
            m_trackHead = MakeItem("缩放置中跟随头部", delegate { Settings.TrackHead = !Settings.TrackHead; });
            m_desktop = MakeItem("桌面捕获（不输出摄像头画面）", delegate { Settings.Desktop = !Settings.Desktop; });
            m_state = new ToolStripMenuItem("—") { Enabled = false };

            ContextMenuStrip _menu = new ContextMenuStrip();
            _menu.Items.Add(m_state);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(m_mirrored);
            _menu.Items.Add(m_zoom);
            _menu.Items.Add(m_trackHead);
            _menu.Items.Add(m_desktop);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(new ToolStripMenuItem("关于 / 用法", null, ShowAbout));
            _menu.Items.Add(new ToolStripMenuItem("退出", null, delegate { ExitThread(); }));
            _menu.Opening += delegate { SyncFromSettings(); };

            m_icon = new NotifyIcon
            {
                Icon = LoadIcon(),
                Text = "KinectCam",
                ContextMenuStrip = _menu,
                Visible = true
            };
            m_icon.DoubleClick += ShowAbout;

            SyncFromSettings();
            TryPromoteToTaskbar();
        }

        private static ToolStripMenuItem MakeItem(string _text, EventHandler _click)
        {
            return new ToolStripMenuItem(_text, null, _click);
        }

        /// <summary>把菜单勾选状态和托盘提示刷成注册表里的当前值。</summary>
        private void SyncFromSettings()
        {
            m_mirrored.Checked = Settings.Mirrored;
            m_zoom.Checked = Settings.Zoom;
            m_trackHead.Checked = Settings.TrackHead;
            m_desktop.Checked = Settings.Desktop;

            System.Text.StringBuilder _on = new System.Text.StringBuilder();
            if (m_mirrored.Checked) _on.Append("镜像 ");
            if (m_zoom.Checked) _on.Append("缩放 ");
            if (m_trackHead.Checked) _on.Append("跟随头部 ");
            if (m_desktop.Checked) _on.Append("桌面捕获 ");

            string _stateText = _on.Length == 0 ? "全部关闭" : _on.ToString().Trim();
            m_state.Text = "当前：" + _stateText;
            m_icon.Text = "KinectCam · " + _stateText;

            // NotifyIcon.Text 有 63 字符上限
            if (m_icon.Text.Length > 63) m_icon.Text = m_icon.Text.Substring(0, 63);
        }

        private void ShowAbout(object sender, EventArgs e)
        {
            SyncFromSettings();
            MessageBox.Show(
                "KinectCamTray —— Kinect v2 虚拟摄像头的设置\n\n" +
                "这里的选项对 \"Kinect Camera V2\" 这个虚拟摄像头生效，改完立即生效，并且会记住。\n\n" +
                "· 镜像：画面左右翻转，视频通话里常需要\n" +
                "· 缩放：取画面中心 2 倍\n" +
                "· 缩放置中跟随头部：配合\"缩放\"，画面跟着你的头移动\n" +
                "· 桌面捕获：输出显示器画面而不是摄像头画面\n\n" +
                "当前设置：" + m_state.Text + "\n\n" +
                "如果任务栏看不到这个图标，点右下角的 ^ 展开，或到\n" +
                "设置 → 个性化 → 任务栏 → 其他系统托盘图标 里把 KinectCamTray 打开。",
                "KinectCamTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        /// <summary>从 shell32.dll 取一个摄像头样子的图标，失败就用系统默认图标。</summary>
        private static Icon LoadIcon()
        {
            try
            {
                IntPtr _large, _small;
                string _shell32 = System.IO.Path.Combine(Environment.SystemDirectory, "shell32.dll");
                if (ExtractIconEx(_shell32, 117, out _large, out _small, 1) > 0 && _small != IntPtr.Zero)
                {
                    return Icon.FromHandle(_small);
                }
            }
            catch
            {
            }
            return SystemIcons.Application;
        }

        [DllImport("Shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode,
            ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
        private static extern int ExtractIconEx(string _file, int _index, out IntPtr _large, out IntPtr _small, int _count);

        /// <summary>
        /// 让图标显示在任务栏上而不是折叠区。
        /// Windows 11 把新图标默认折叠，设置项在 HKCU\Control Panel\NotifyIconSettings\*
        /// 的 IsPromoted；这条在下次启动时生效，所以第一次运行后重启一次就固定住了。
        /// </summary>
        private static void TryPromoteToTaskbar()
        {
            try
            {
                string _self = Application.ExecutablePath;
                using (RegistryKey _root = Registry.CurrentUser.OpenSubKey(@"Control Panel\NotifyIconSettings", true))
                {
                    if (_root == null) return;
                    foreach (string _sub in _root.GetSubKeyNames())
                    {
                        using (RegistryKey _entry = _root.OpenSubKey(_sub, true))
                        {
                            if (_entry == null) continue;
                            string _exe = _entry.GetValue("ExecutablePath") as string;
                            if (_exe != null && string.Equals(_exe, _self, StringComparison.OrdinalIgnoreCase))
                            {
                                _entry.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
                            }
                        }
                    }
                }
            }
            catch
            {
            }
        }

        protected override void Dispose(bool _disposing)
        {
            if (_disposing && m_icon != null)
            {
                m_icon.Visible = false;
                m_icon.Dispose();
            }
            base.Dispose(_disposing);
        }
    }
}
