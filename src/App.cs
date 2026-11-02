using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using Timer = System.Windows.Forms.Timer;

namespace JiaXinTie
{
    internal static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            Native.EnableDpi();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Settings.ProfileDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JiaXinTie");
            int profile = Array.IndexOf(args, "--profile");
            if (profile >= 0 && profile + 1 < args.Length) Settings.ProfileDirectory = Path.GetFullPath(args[profile + 1]);
            if (args.Length > 1 && args[0] == "--configure")
            {
                try { ShotStore.ValidateWritable(args[1]); Settings configured = Settings.Load(); configured.SaveDirectory = Path.GetFullPath(args[1]); configured.Save(); return 0; }
                catch (Exception e) { MessageBox.Show(e.Message, "夹心贴 · 保存目录不可用"); return 1; }
            }
            bool demo = args.Contains("--demo");
            bool first;
            string suffix = demo ? ".Demo" : "";
            using (Mutex mutex = new Mutex(true, @"Local\JiaXinTie.Singleton.v1" + suffix, out first))
            {
                if (!first) { MessageBox.Show("夹心贴已经在运行，可以在系统托盘找到它。", "夹心贴"); return 0; }
                try
                {
                    Settings settings = Settings.Load();
                    if (String.IsNullOrWhiteSpace(settings.SaveDirectory) || !Directory.Exists(settings.SaveDirectory))
                    {
                        using (SettingsWindow setup = new SettingsWindow(settings, true, null))
                            if (setup.ShowDialog() != DialogResult.OK) return 0;
                    }
                    Application.ThreadException += delegate(object sender, ThreadExceptionEventArgs e) { ShowError(e.Exception); };
                    using (TrayHost host = new TrayHost(settings, demo, args.Contains("--capture"))) Application.Run(host);
                    return 0;
                }
                catch (Exception e) { ShowError(e); return 1; }
            }
        }
        public static void ShowError(Exception e)
        { MessageBox.Show("操作没有完成：" + e.Message, "夹心贴", MessageBoxButtons.OK, MessageBoxIcon.Information); }
    }

    public sealed class SettingsWindow : Form
    {
        private TextBox folder;
        private Settings settings;
        private Dictionary<string, HotkeyBox> hotkeys = new Dictionary<string, HotkeyBox>();
        public SettingsWindow(Settings current, bool firstRun, string hotkeyStatus)
        {
            settings = current; Theme.Form(this);
            Text = firstRun ? "夹心贴 · 首次设置" : "夹心贴 · 设置";
            ClientSize = new Size(560, 650); FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen; MaximizeBox = false; MinimizeBox = false;
            PictureBox logo = new PictureBox { Image = Theme.Logo(), SizeMode = PictureBoxSizeMode.Zoom, Bounds = new Rectangle(28, 24, 40, 44) };
            Controls.Add(logo);
            Controls.Add(new Label { Text = "夹心贴", Font = new Font(Font.FontFamily, 16, FontStyle.Regular), AutoSize = true, Location = new Point(82, 29) });
            Controls.Add(new Label { Text = "保存位置", AutoSize = true, Location = new Point(28, 102) });
            folder = new TextBox { Bounds = new Rectangle(28, 130, 408, 28), Text = current.SaveDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "夹心贴"), AccessibleName = "截图保存文件夹" };
            Controls.Add(folder);
            Button browse = Theme.Button("浏览…", false); browse.Bounds = new Rectangle(448, 126, 84, 32);
            browse.Click += delegate { using (FolderBrowserDialog d = new FolderBrowserDialog { Description = "选择夹心贴的截图保存文件夹", SelectedPath = folder.Text, ShowNewFolderButton = true }) if (d.ShowDialog(this) == DialogResult.OK) folder.Text = d.SelectedPath; };
            Controls.Add(browse);
            Controls.Add(new Label { Bounds = new Rectangle(28, 170, 504, 24), Text = "按保存键直接存入此处；「缓存」子文件夹保留最近 3 张。", ForeColor = Color.DimGray });
            Controls.Add(new Label { Text = "快捷键", AutoSize = true, Location = new Point(28, 210) });
            string[] fields = { "CaptureKey", "CopyKey", "SaveKey", "PinKey", "TogglePinsKey", "AutoCopyKey", "CancelKey", "UndoKey", "RedoKey", "ResetZoomKey" };
            string[] names = { "开始截图（全局）", "框选后复制", "直接保存", "贴图（全局）", "显隐贴图（全局）", "框选即复制（全局）", "取消 / 删除贴图", "撤销标注", "重做标注", "贴图原始大小" };
            for (int i = 0; i < fields.Length; i++)
            {
                int y = 241 + i * 29;
                Controls.Add(new Label { Text = names[i], Location = new Point(28, y + 3), Size = new Size(330, 24) });
                HotkeyBox key = new HotkeyBox { Location = new Point(388, y), Size = new Size(144, 25), AccessibleName = names[i] + "快捷键" };
                key.KeyValue = (int)typeof(Settings).GetField(fields[i]).GetValue(settings); hotkeys[fields[i]] = key; Controls.Add(key);
            }
            Label status = new Label { Bounds = new Rectangle(28, 540, 504, 44), Text = hotkeyStatus ?? "点击按键框后按下新快捷键。\n输入标注文字时，快捷键暂停，文字输入优先。", ForeColor = String.IsNullOrEmpty(hotkeyStatus) ? Color.DimGray : Color.FromArgb(172, 72, 57) };
            Controls.Add(status);
            Button save = Theme.Button(firstRun ? "完成" : "保存", true); save.Bounds = new Rectangle(432, 602, 100, 34);
            save.Click += delegate
            {
                try
                {
                    ShotStore.ValidateWritable(folder.Text.Trim());
                    Settings candidate = new Settings { SaveDirectory = Path.GetFullPath(folder.Text.Trim()) };
                    foreach (KeyValuePair<string, HotkeyBox> pair in hotkeys) typeof(Settings).GetField(pair.Key).SetValue(candidate, pair.Value.KeyValue);
                    Shortcuts.Validate(candidate); candidate.Save();
                    foreach (System.Reflection.FieldInfo field in typeof(Settings).GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public)) field.SetValue(settings, field.GetValue(candidate));
                    DialogResult = DialogResult.OK; Close();
                }
                catch (Exception e) { Program.ShowError(e); }
            };
            Controls.Add(save);
            Button cancel = Theme.Button("取消", false); cancel.Bounds = new Rectangle(334, 602, 86, 34); cancel.DialogResult = DialogResult.Cancel;
            Controls.Add(cancel); CancelButton = cancel; AcceptButton = save;
            Button reset = Theme.Button("恢复默认按键", false); reset.Bounds = new Rectangle(18, 602, 134, 34); reset.FlatAppearance.BorderSize = 0; reset.ForeColor = Color.DimGray;
            reset.Click += delegate { Settings defaults = new Settings(); foreach (KeyValuePair<string, HotkeyBox> pair in hotkeys) pair.Value.KeyValue = (int)typeof(Settings).GetField(pair.Key).GetValue(defaults); };
            Controls.Add(reset);
            FormClosed += delegate { logo.Image.Dispose(); };
        }
    }

    public sealed class HotkeyBox : TextBox
    {
        private int value;
        public int KeyValue { get { return value; } set { this.value = value; Text = Shortcuts.Label(value); } }
        public HotkeyBox() { ReadOnly = true; BackColor = Color.FromArgb(247, 248, 250); BorderStyle = BorderStyle.FixedSingle; TextAlign = HorizontalAlignment.Center; Cursor = Cursors.Hand; }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if ((keyData & Keys.KeyCode) == Keys.Tab) return base.ProcessCmdKey(ref msg, keyData);
            if (Shortcuts.Usable(keyData)) KeyValue = (int)keyData;
            return true;
        }
    }

    public sealed class TrayHost : Form
    {
        private readonly Settings settings;
        private ShotStore store;
        private NotifyIcon tray;
        private CaptureOverlay overlay;
        private List<PinWindow> pins = new List<PinWindow>();
        private Bitmap lastImage;
        private bool pinsHidden;
        private bool demo;
        private bool closing;
        private string hotkeyStatus;
        private ToolStripMenuItem recent;
        public TrayHost(Settings settings, bool demo, bool immediateCapture = false)
        {
            this.settings = settings; this.demo = demo;
            store = new ShotStore(settings.SaveDirectory); store.Trim();
            ShowInTaskbar = false; FormBorderStyle = FormBorderStyle.FixedToolWindow;
            WindowState = FormWindowState.Minimized; Opacity = 0; Text = "夹心贴 · 托盘";
            ContextMenuStrip menu = new ContextMenuStrip { Font = new Font("Microsoft YaHei UI", 9.5F), ShowImageMargin = false };
            Add(menu, "截图", Shortcuts.Label(settings.CaptureKey), delegate { BeginCapture(false, true); });
            Add(menu, "贴图", Shortcuts.Label(settings.PinKey), Paste);
            Add(menu, "隐藏 / 显示贴图", Shortcuts.Label(settings.TogglePinsKey), TogglePins);
            menu.Items.Add(new ToolStripSeparator());
            recent = new ToolStripMenuItem("最近截图"); menu.Items.Add(recent);
            Add(menu, "打开保存文件夹", "", delegate { Process.Start("explorer.exe", Quote(store.Root)); });
            menu.Items.Add(new ToolStripSeparator());
            Add(menu, "设置…", "", ShowSettings);
            Add(menu, "退出", "", Close);
            menu.Opening += delegate { RefreshRecent(); ((ToolStripMenuItem)menu.Items[0]).ShortcutKeyDisplayString = Shortcuts.Label(settings.CaptureKey); ((ToolStripMenuItem)menu.Items[1]).ShortcutKeyDisplayString = Shortcuts.Label(settings.PinKey); ((ToolStripMenuItem)menu.Items[2]).ShortcutKeyDisplayString = Shortcuts.Label(settings.TogglePinsKey); };
            tray = new NotifyIcon { Icon = Theme.Icon(), Text = "夹心贴", ContextMenuStrip = menu, Visible = true };
            tray.DoubleClick += delegate { BeginCapture(false); };
            Timer startup = new Timer { Interval = 180 };
            startup.Tick += delegate
            {
                startup.Stop(); startup.Dispose();
                Hide();
                if (!demo) RegisterKeys();
                if (demo || immediateCapture) BeginCapture(false);
            };
            startup.Start();
            FormClosed += delegate
            {
                closing = true;
                for (int i = 1; i <= 4; i++) Native.UnregisterHotKey(Handle, i);
                if (overlay != null) overlay.Close();
                foreach (PinWindow pin in pins.ToArray()) pin.Close();
                if (lastImage != null) lastImage.Dispose();
                tray.Visible = false; tray.Icon.Dispose(); tray.Dispose(); menu.Dispose();
            };
        }
        private static string Quote(string s) { return "\"" + s + "\""; }
        private static void Add(ContextMenuStrip menu, string text, string key, Action action)
        { ToolStripMenuItem i = new ToolStripMenuItem(text) { ShortcutKeyDisplayString = key }; i.Click += delegate { action(); }; menu.Items.Add(i); }
        private void RegisterKeys()
        {
            if (closing) return;
            PauseKeys();
            List<string> conflicts = new List<string>();
            if (!Shortcuts.Register(Handle, 1, settings.CaptureKey)) conflicts.Add(Shortcuts.Label(settings.CaptureKey));
            if (!Shortcuts.Register(Handle, 2, settings.PinKey)) conflicts.Add(Shortcuts.Label(settings.PinKey));
            if (!Shortcuts.Register(Handle, 3, settings.TogglePinsKey)) conflicts.Add(Shortcuts.Label(settings.TogglePinsKey));
            if (!Shortcuts.Register(Handle, 4, settings.AutoCopyKey)) conflicts.Add(Shortcuts.Label(settings.AutoCopyKey));
            hotkeyStatus = conflicts.Count == 0 ? null : "快捷键被其他软件占用：" + String.Join("、", conflicts) + "。请退出使用相同快捷键的软件，然后重启夹心贴。也可以双击托盘图标开始截图。";
            if (hotkeyStatus != null) Notify("快捷键未全部启用", hotkeyStatus);
        }
        private void PauseKeys() { for (int i = 1; i <= 4; i++) Native.UnregisterHotKey(Handle, i); }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312)
            {
                int id = m.WParam.ToInt32();
                int key = id == 1 ? settings.CaptureKey : id == 2 ? settings.PinKey : id == 3 ? settings.TogglePinsKey : settings.AutoCopyKey;
                PinWindow activePin = Form.ActiveForm as PinWindow;
                if (activePin != null && activePin.TryShortcut(key)) return;
                if (id == 1 || id == 4)
                {
                    if (overlay == null) BeginCapture(id == 4);
                }
                else if (id == 2) { if (overlay == null) Paste(); }
                else if (id == 3) TogglePins();
            }
            base.WndProc(ref m);
        }
        private void Notify(string title, string message)
        { tray.BalloonTipTitle = title; tray.BalloonTipText = message; tray.ShowBalloonTip(2200); }
        private bool captureScheduled;
        private void BeginCapture(bool autoCopy, bool waitForMenu = false)
        {
            if (captureScheduled) return;
            if (!waitForMenu) { CaptureNow(autoCopy); return; }
            captureScheduled = true;
            Timer timer = new Timer { Interval = 140 };
            timer.Tick += delegate { timer.Stop(); timer.Dispose(); captureScheduled = false; CaptureNow(autoCopy); };
            timer.Start();
        }
        private void CaptureNow(bool autoCopy)
        {
            if (overlay != null) { overlay.Activate(); return; }
            try
            {
                Rectangle bounds;
                Bitmap desktop;
                if (demo)
                {
                    bounds = Screen.PrimaryScreen.Bounds;
                    desktop = DemoImage(bounds.Size);
                }
                else desktop = Native.CaptureDesktop(out bounds);
                PauseKeys();
                overlay = new CaptureOverlay(desktop, bounds, autoCopy, settings, CompleteCapture);
                overlay.FormClosed += delegate { overlay = null; if (!demo && !closing) RegisterKeys(); };
                overlay.Show(); overlay.Activate();
            }
            catch (Exception e) { if (overlay == null && !demo) RegisterKeys(); Program.ShowError(e); }
        }
        public static Bitmap DemoImage(Size size)
        {
            Bitmap b = new Bitmap(size.Width, size.Height);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.Clear(Color.FromArgb(245, 239, 232));
                using (Brush card = new SolidBrush(Color.White)) g.FillRectangle(card, 100, 120, Math.Min(840, size.Width - 160), 500);
                using (Font title = new Font("Microsoft YaHei UI", 30, FontStyle.Bold))
                using (Brush ink = new SolidBrush(Theme.Ink)) g.DrawString("留住这一刻的灵感", title, ink, 145, 180);
                using (Font font = new Font("Microsoft YaHei UI", 16))
                using (Brush ink = new SolidBrush(Color.FromArgb(123, 106, 115))) g.DrawString("夹心贴 · 截图与贴图\n\n框选区域后：F1 复制   S 保存   F3 贴图", font, ink, 150, 280);
                using (Image logo = Theme.Logo()) g.DrawImage(logo, 650, 365, 180, 180);
                using (Brush pink = new SolidBrush(Theme.Accent)) g.FillRectangle(pink, 150, 430, 360, 8);
            }
            return b;
        }
        private void CompleteCapture(Bitmap image, CaptureAction action)
        {
            // Keep editor open on I/O failure so the selected content remains recoverable.
            if (action == CaptureAction.Copy) Native.CopyImage(image);
            store.Record(image, action == CaptureAction.Save);
            if (lastImage != null) lastImage.Dispose();
            lastImage = new Bitmap(image);
            if (action == CaptureAction.Pin) CreatePin(image);
        }
        private void RefreshRecent()
        {
            foreach (ToolStripItem item in recent.DropDownItems) if (item.Image != null) item.Image.Dispose();
            recent.DropDownItems.Clear();
            try
            {
                foreach (string path in store.Recent())
                {
                    string captured = path;
                    using (Bitmap b = ShotStore.LoadUnlocked(path))
                    {
                        ToolStripMenuItem i = new ToolStripMenuItem(File.GetLastWriteTime(path).ToString("MM-dd HH:mm:ss") + "  ·  点击贴图");
                        i.Image = new Bitmap(b, new Size(36, 24));
                        i.Click += delegate { try { using (Bitmap image = ShotStore.LoadUnlocked(captured)) CreatePin(image); } catch (Exception e) { Program.ShowError(e); } };
                        recent.DropDownItems.Add(i);
                    }
                }
                if (recent.DropDownItems.Count == 0) recent.DropDownItems.Add(new ToolStripMenuItem("还没有截图") { Enabled = false });
            }
            catch (Exception e) { recent.DropDownItems.Add(new ToolStripMenuItem(e.Message) { Enabled = false }); }
        }
        private void Paste()
        {
            try
            {
                if (Clipboard.ContainsImage()) { using (Image image = Clipboard.GetImage()) using (Bitmap b = new Bitmap(image)) CreatePin(b); }
                else if (lastImage != null) CreatePin(lastImage);
                else
                {
                    string path = store.Recent().FirstOrDefault();
                    if (path != null) { using (Bitmap b = ShotStore.LoadUnlocked(path)) CreatePin(b); }
                    else Notify("还没有可贴的图片", "先截图并复制，或复制一张图片，再按 " + Shortcuts.Label(settings.PinKey) + "。");
                }
            }
            catch (Exception e) { Program.ShowError(e); }
        }
        private void CreatePin(Bitmap image)
        {
            PinWindow pin = new PinWindow(image, settings);
            pin.FormClosed += delegate { pins.Remove(pin); };
            pins.Add(pin); pinsHidden = false; pin.Show();
        }
        private void TogglePins()
        { pinsHidden = !pinsHidden; foreach (PinWindow pin in pins) { if (pinsHidden) pin.Hide(); else pin.Show(); } }
        private void ShowSettings()
        {
            PauseKeys();
            using (SettingsWindow window = new SettingsWindow(settings, false, hotkeyStatus))
                if (window.ShowDialog() == DialogResult.OK) { store = new ShotStore(settings.SaveDirectory); store.Trim(); }
            if (!demo) RegisterKeys();
        }
    }

    public enum CaptureAction { Copy, Save, Pin }

    internal sealed class CaptureToolbar : FlowLayoutPanel
    {
        public CaptureToolbar()
        {
            DoubleBuffered = true; BackColor = Color.White;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen border = new Pen(Color.FromArgb(136, 174, 220))) e.Graphics.DrawRectangle(border, 0, 0, Width - 1, Height - 1);
        }
    }

    public sealed class CaptureOverlay : Form
    {
        private Bitmap desktop;
        private Rectangle selection;
        private List<Mark> marks = new List<Mark>();
        private sealed class AnnotationEdit { public Mark Mark; public int Index; public bool Added; }
        private Stack<AnnotationEdit> history = new Stack<AnnotationEdit>(), undone = new Stack<AnnotationEdit>();
        private CaptureRenderer renderer;
        private Mark current;
        private DrawTool tool = DrawTool.Move;
        private Point anchor, selectionStart;
        private Rectangle beforeMove;
        private bool dragging, moving, resizing, erasing, completing;
        private int resizeHandle = -1;
        private bool autoCopy;
        private Action<Bitmap, CaptureAction> complete;
        private FlowLayoutPanel toolbar;
        private FlowLayoutPanel toolOptions;
        private Dictionary<DrawTool, Button> toolButtons = new Dictionary<DrawTool, Button>();
        private TextBox textEntry;
        private Color color = Color.FromArgb(242, 65, 65);
        private float strokeWidth = 3;
        private ToolTip toolbarTips = new ToolTip { InitialDelay = 350, ReshowDelay = 100 };
        private Rectangle virtualBounds;
        private Settings shortcuts;
        public CaptureOverlay(Bitmap desktop, Rectangle bounds, bool autoCopy, Settings shortcuts, Action<Bitmap, CaptureAction> complete)
        {
            Theme.Form(this); AutoScaleMode = AutoScaleMode.None;
            this.desktop = desktop; virtualBounds = bounds; this.autoCopy = autoCopy; this.complete = complete; this.shortcuts = shortcuts;
            renderer = new CaptureRenderer(desktop);
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual; Bounds = bounds; Text = "夹心贴 · 截图"; KeyPreview = true;
            DoubleBuffered = true; Cursor = Cursors.Cross;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
            BuildToolbar();
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && desktop != null)
            {
                renderer.Dispose(); desktop.Dispose(); desktop = null; toolbarTips.Dispose();
                foreach (Control panel in new Control[] { toolbar, toolOptions }) if (panel != null)
                    foreach (Control c in panel.Controls) { Button b = c as Button; if (b != null && b.Image != null) b.Image.Dispose(); }
            }
            base.Dispose(disposing);
        }
        private void BuildToolbar()
        {
            toolbar = new CaptureToolbar { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Padding = new Padding(3), WrapContents = false, Visible = false, AccessibleName = "截图工具栏" };
            Controls.Add(toolbar);
            AddTool("矩形", DrawTool.Rectangle); AddTool("圆形", DrawTool.Ellipse); AddTool("直线", DrawTool.Line);
            AddTool("箭头", DrawTool.Arrow); AddTool("画笔", DrawTool.Pen); AddTool("荧光笔", DrawTool.Highlighter);
            AddTool("马赛克", DrawTool.Mosaic); AddTool("文字", DrawTool.Text); AddTool("橡皮擦", DrawTool.Eraser);
            BarSeparator();
            Button undo = BarButton("撤销", "撤销 " + Shortcuts.Label(shortcuts.UndoKey)); undo.Click += delegate { Undo(); };
            Button redo = BarButton("重做", "重做 " + Shortcuts.Label(shortcuts.RedoKey)); redo.Click += delegate { Redo(); };
            BarSeparator();
            Button save = BarButton("保存", "保存 " + Shortcuts.Label(shortcuts.SaveKey)); save.Click += delegate { Finish(CaptureAction.Save); };
            Button pin = BarButton("贴图", "贴图 " + Shortcuts.Label(shortcuts.PinKey)); pin.Click += delegate { Finish(CaptureAction.Pin); };
            Button cancel = BarButton("取消", "取消 " + Shortcuts.Label(shortcuts.CancelKey)); cancel.Click += delegate { Close(); };
            Button copy = BarButton("完成", "复制 " + Shortcuts.Label(shortcuts.CopyKey)); copy.Click += delegate { Finish(CaptureAction.Copy); };
            BuildOptions();
            SetTool(DrawTool.Move);
        }
        private Button BarButton(string icon, string hint)
        {
            Button b = Theme.Button("", false); b.Size = new Size(30, 28); b.Image = Theme.ToolIcon(icon, Theme.Ink); b.FlatAppearance.BorderSize = 0;
            b.AccessibleName = hint; toolbarTips.SetToolTip(b, hint);
            b.Padding = new Padding(1); b.Margin = new Padding(0); b.TabStop = false;
            toolbar.Controls.Add(b); return b;
        }
        private void BarSeparator()
        { toolbar.Controls.Add(new Panel { Width = 1, Height = 18, BackColor = Color.FromArgb(205, 209, 214), Margin = new Padding(4, 5, 4, 0) }); }
        private void AddTool(string label, DrawTool value)
        { Button b = BarButton(label, value == DrawTool.Eraser ? "橡皮擦 · 擦除标注" : label); b.Tag = label; b.Click += delegate { CommitText(); SetTool(tool == value ? DrawTool.Move : value); }; toolButtons[value] = b; }
        private void BuildOptions()
        {
            toolOptions = new CaptureToolbar { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Padding = new Padding(3), WrapContents = false, Visible = false, AccessibleName = "标注选项" };
            Controls.Add(toolOptions);
            foreach (int size in new[] { 2, 4, 7 })
            {
                int chosen = size; Button b = OptionButton("粗细 " + size, "粗细", Color.FromArgb(70, 75, 81), size);
                b.Click += delegate { strokeWidth = chosen; };
            }
            toolOptions.Controls.Add(new Panel { Width = 1, Height = 16, BackColor = Color.LightGray, Margin = new Padding(4,4,4,0) });
            foreach (Color swatch in new[] { Color.FromArgb(242,65,65), Color.FromArgb(255,192,0), Color.FromArgb(82,176,57), Color.FromArgb(0,120,215), Color.FromArgb(153,76,209), Color.FromArgb(40,42,45), Color.White })
            {
                Color chosen = swatch; Button b = OptionButton("颜色 " + swatch.ToArgb().ToString("X8"), "颜色", swatch, 0);
                b.Click += delegate { CommitText(); color = chosen; };
            }
            Button custom = OptionButton("自定义颜色", "调色板", Theme.Ink, 0);
            custom.Click += delegate { CommitText(); using (ColorDialog dialog = new ColorDialog { Color = color, FullOpen = true }) if (dialog.ShowDialog(this) == DialogResult.OK) color = dialog.Color; };
        }
        private Button OptionButton(string hint, string icon, Color ink, int diameter)
        {
            Button b = Theme.Button("", false); b.Size = new Size(22,24); b.Margin = new Padding(0); b.TabStop = false; b.FlatAppearance.BorderSize = 0;
            b.Image = diameter == 0 ? Theme.ToolIcon(icon, ink) : Theme.DotIcon(diameter, ink); b.AccessibleName = hint; toolbarTips.SetToolTip(b, hint); toolOptions.Controls.Add(b); return b;
        }
        private void SetTool(DrawTool value)
        {
            tool = value; Cursor = tool == DrawTool.Move ? Cursors.SizeAll : Cursors.Cross;
            foreach (KeyValuePair<DrawTool, Button> pair in toolButtons)
            {
                bool selected = pair.Key == tool; pair.Value.BackColor = selected ? Theme.Accent : Color.White;
                pair.Value.FlatAppearance.MouseOverBackColor = selected ? Theme.Accent : Color.FromArgb(229, 239, 252);
                pair.Value.Image.Dispose(); pair.Value.Image = Theme.ToolIcon((string)pair.Value.Tag, selected ? Color.White : Theme.Ink);
            }
            if (!selection.IsEmpty) PlaceToolbar();
            Focus();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; renderer.Paint(g, e.ClipRectangle, selection, marks, current);
            if (!selection.IsEmpty)
            {
                using (Pen border = new Pen(Theme.Accent, 1))
                {
                    g.DrawRectangle(border, selection);
                    foreach (Rectangle handle in Handles()) { g.FillRectangle(Brushes.White, handle); g.DrawRectangle(border, handle); }
                }
                string dimensions = selection.Width + " × " + selection.Height;
                DrawBadge(g, dimensions, new Point(selection.Left, Math.Max(8, selection.Top - 32)));
            }
            if (selection.IsEmpty)
            {
                Rectangle active = Screen.FromPoint(Cursor.Position).Bounds;
                string hint = "拖动选择区域 · " + Shortcuts.Label(shortcuts.CancelKey) + " 取消";
                int width = TextRenderer.MeasureText(hint, Font).Width + 20;
                DrawBadge(g, hint, new Point(active.Left - virtualBounds.Left + (active.Width - width) / 2, active.Top - virtualBounds.Top + 28));
            }
        }
        private void DrawBadge(Graphics g, string text, Point at)
        {
            Size size = TextRenderer.MeasureText(text, Font);
            using (Brush back = new SolidBrush(Color.FromArgb(232, 35, 38, 42))) g.FillRectangle(back, at.X, at.Y, size.Width + 20, size.Height + 12);
            TextRenderer.DrawText(g, text, Font, new Point(at.X + 10, at.Y + 6), Color.White, TextFormatFlags.NoPadding);
        }
        private List<Rectangle> Handles()
        {
            int l = selection.Left, r = selection.Right, t = selection.Top, b = selection.Bottom, x = l + selection.Width / 2, y = t + selection.Height / 2;
            return new[] { new Point(l,t),new Point(x,t),new Point(r,t),new Point(r,y),new Point(r,b),new Point(x,b),new Point(l,b),new Point(l,y) }
                .Select(p => new Rectangle(p.X - 3, p.Y - 3, 6, 6)).ToList();
        }
        private Point Clamp(Point p)
        { return new Point(Math.Max(0, Math.Min(desktop.Width, p.X)), Math.Max(0, Math.Min(desktop.Height, p.Y))); }
        private void InvalidateMark(Rectangle local)
        { local.Offset(selection.Location); Invalidate(Rectangle.Intersect(Rectangle.Inflate(local, 3, 3), ClientRectangle)); }
        private void InvalidateSelection(Rectangle previous)
        {
            if (previous.IsEmpty || selection.IsEmpty) { Invalidate(); return; }
            using (Region dirty = new Region(previous))
            {
                if (marks.Count == 0) dirty.Xor(selection); else dirty.Union(selection);
                foreach (Rectangle rect in new[] { previous, selection })
                {
                    dirty.Union(new Rectangle(rect.Left-5,rect.Top-5,rect.Width+10,10));
                    dirty.Union(new Rectangle(rect.Left-5,rect.Bottom-5,rect.Width+10,10));
                    dirty.Union(new Rectangle(rect.Left-5,rect.Top-5,10,rect.Height+10));
                    dirty.Union(new Rectangle(rect.Right-5,rect.Top-5,10,rect.Height+10));
                    dirty.Union(new Rectangle(rect.Left-3,Math.Max(8,rect.Top-32),170,32));
                }
                Invalidate(dirty);
            }
        }
        private void AddMark(Mark mark)
        {
            history.Push(new AnnotationEdit { Mark = mark, Index = marks.Count, Added = true });
            marks.Add(mark); undone.Clear(); renderer.InvalidateAnnotations(); InvalidateMark(mark.VisualBounds);
        }
        private void EraseAt(Point point)
        {
            for (int i = marks.Count - 1; i >= 0; i--)
                if (marks[i].HitTest(point, Math.Max(5, strokeWidth * 2)))
                {
                    Mark mark = marks[i]; history.Push(new AnnotationEdit { Mark = mark, Index = i, Added = false }); marks.RemoveAt(i); undone.Clear(); renderer.InvalidateAnnotations(); InvalidateMark(mark.VisualBounds); return;
                }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e); if (e.Button != MouseButtons.Left) return;
            CommitText(); Focus(); anchor = Clamp(e.Location); Capture = true; toolbar.Visible = false; toolOptions.Visible = false;
            resizing = false; moving = false; erasing = false;
            if (!selection.IsEmpty && tool == DrawTool.Move && marks.Count == 0)
            {
                resizeHandle = Handles().FindIndex(r => Rectangle.Inflate(r, 5, 5).Contains(e.Location));
                if (resizeHandle >= 0) { resizing = true; beforeMove = selection; dragging = true; return; }
            }
            if (!selection.IsEmpty && selection.Contains(e.Location))
            {
                if (tool == DrawTool.Move) { moving = true; beforeMove = selection; dragging = true; return; }
                Point local = new Point(anchor.X - selection.X, anchor.Y - selection.Y);
                if (tool == DrawTool.Text) { BeginText(local); Capture = false; PlaceToolbar(); return; }
                if (tool == DrawTool.Eraser) { dragging = true; erasing = true; EraseAt(local); return; }
                current = new Mark { Tool = tool, A = local, B = local, Color = color, Width = tool == DrawTool.Highlighter ? strokeWidth * 5 : strokeWidth }; current.Points.Add(local); dragging = true; return;
            }
            marks.Clear(); history.Clear(); undone.Clear(); renderer.InvalidateAnnotations(); selectionStart = anchor; selection = Rectangle.Empty; dragging = true; Invalidate();
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e); if (!dragging) return;
            Point p = Clamp(e.Location);
            Rectangle previous = selection;
            if (erasing) { EraseAt(new Point(p.X-selection.X,p.Y-selection.Y)); return; }
            if (current != null)
            {
                Rectangle oldBounds = current.Tool == DrawTool.Pen || current.Tool == DrawTool.Highlighter ? Rectangle.Empty : current.VisualBounds;
                p = new Point(Math.Max(0, Math.Min(selection.Width - 1, p.X - selection.X)), Math.Max(0, Math.Min(selection.Height - 1, p.Y - selection.Y)));
                current.B = p;
                if (current.Tool == DrawTool.Pen || current.Tool == DrawTool.Highlighter)
                {
                    Point last = current.Points[current.Points.Count - 1];
                    if (last == p) return; current.Points.Add(p);
                    oldBounds = Mark.Normalize(last, p); oldBounds.Inflate((int)current.Width + 5, (int)current.Width + 5); InvalidateMark(oldBounds);
                }
                else InvalidateMark(Rectangle.Union(oldBounds, current.VisualBounds));
                return;
            }
            else if (moving)
            {
                int x = Math.Max(0, Math.Min(desktop.Width - selection.Width, beforeMove.X + p.X - anchor.X));
                int y = Math.Max(0, Math.Min(desktop.Height - selection.Height, beforeMove.Y + p.Y - anchor.Y));
                selection.Location = new Point(x, y);
            }
            else if (resizing)
            {
                int l = beforeMove.Left, t = beforeMove.Top, r = beforeMove.Right, b = beforeMove.Bottom;
                if (resizeHandle == 0 || resizeHandle == 6 || resizeHandle == 7) l = p.X;
                if (resizeHandle == 0 || resizeHandle == 1 || resizeHandle == 2) t = p.Y;
                if (resizeHandle == 2 || resizeHandle == 3 || resizeHandle == 4) r = p.X;
                if (resizeHandle == 4 || resizeHandle == 5 || resizeHandle == 6) b = p.Y;
                selection = Mark.Normalize(new Point(l, t), new Point(r, b));
            }
            else selection = Mark.Normalize(selectionStart, p);
            if (previous != selection) InvalidateSelection(previous);
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e); if (e.Button != MouseButtons.Left || !dragging) return;
            // The final mouse position must be committed even when a move event was coalesced.
            OnMouseMove(e); dragging = false; erasing = false; Capture = false;
            if (current != null) { Mark finished = current; current = null; AddMark(finished); }
            if (selection.Width < 2 || selection.Height < 2) selection = Rectangle.Empty;
            if (!selection.IsEmpty) { if (autoCopy) { CopySelection(); return; } PlaceToolbar(); }
            if (selection.IsEmpty) Invalidate();
        }
        protected override void OnMouseDoubleClick(MouseEventArgs e)
        { base.OnMouseDoubleClick(e); if (e.Button == MouseButtons.Left && tool == DrawTool.Move && selection.Contains(e.Location)) CopySelection(); }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            if (e.Button == MouseButtons.Right) { if (tool != DrawTool.Move) { CommitText(); SetTool(DrawTool.Move); } else Close(); }
        }
        private void PlaceToolbar()
        {
            if (selection.IsEmpty) return;
            Rectangle monitor = Screen.FromPoint(new Point(selection.X + virtualBounds.X, selection.Y + virtualBounds.Y)).WorkingArea;
            monitor.Offset(-virtualBounds.X, -virtualBounds.Y);
            int maxWidth = Math.Max(300, monitor.Width - 16);
            toolbar.MaximumSize = new Size(maxWidth, 0); toolbar.WrapContents = toolbar.PreferredSize.Width > maxWidth;
            toolbar.Visible = true; toolbar.PerformLayout();
            bool options = tool != DrawTool.Move && tool != DrawTool.Eraser;
            int combinedHeight = toolbar.Height + (options ? toolOptions.Height + 2 : 0);
            int x = Math.Max(monitor.Left + 8, Math.Min(selection.Right - toolbar.Width, monitor.Right - toolbar.Width - 8));
            int y = selection.Bottom + 12;
            if (y + combinedHeight > monitor.Bottom - 8) y = selection.Top - combinedHeight - 12;
            if (y < monitor.Top + 8) y = Math.Min(monitor.Bottom - combinedHeight - 8, selection.Bottom - combinedHeight - 8);
            toolbar.Location = new Point(x, Math.Max(monitor.Top + 8, y)); toolbar.BringToFront();
            toolOptions.Visible = options; toolOptions.Location = new Point(toolbar.Left, toolbar.Bottom + 2); toolOptions.BringToFront();
        }
        private void BeginText(Point point)
        {
            current = new Mark { Tool = DrawTool.Text, A = point, Color = color };
            textEntry = new TextBox { Location = new Point(selection.X + point.X, selection.Y + point.Y), Width = Math.Max(80, Math.Min(300, selection.Width - point.X)), Font = new Font("Microsoft YaHei UI", 14), AccessibleName = "标注文字" };
            textEntry.KeyDown += delegate(object sender, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { CommitText(); e.SuppressKeyPress = true; } };
            Controls.Add(textEntry); textEntry.BringToFront(); textEntry.Focus();
        }
        private void CommitText()
        {
            if (textEntry == null) return;
            string text = textEntry.Text; Controls.Remove(textEntry); textEntry.Dispose(); textEntry = null;
            if (current != null && !String.IsNullOrWhiteSpace(text)) { current.Text = text; AddMark(current); }
            current = null; Focus();
        }
        private void Undo()
        {
            CommitText(); if (history.Count == 0) return; AnnotationEdit edit = history.Pop();
            if (edit.Added) marks.RemoveAt(edit.Index); else marks.Insert(edit.Index, edit.Mark);
            undone.Push(edit); renderer.InvalidateAnnotations(); InvalidateMark(edit.Mark.VisualBounds);
        }
        private void Redo()
        {
            if (undone.Count == 0) return; AnnotationEdit edit = undone.Pop();
            if (edit.Added) marks.Insert(edit.Index, edit.Mark); else marks.RemoveAt(edit.Index);
            history.Push(edit); renderer.InvalidateAnnotations(); InvalidateMark(edit.Mark.VisualBounds);
        }
        public Bitmap RenderSelection()
        {
            return renderer.Export(selection, marks);
        }
        public void CopySelection() { Finish(CaptureAction.Copy); }
        public void PinSelection() { Finish(CaptureAction.Pin); }
        private void Finish(CaptureAction action)
        {
            if (completing || dragging || selection.Width < 2 || selection.Height < 2) return;
            completing = true;
            try
            {
                CommitText(); using (Bitmap b = RenderSelection()) complete(b, action); Close();
            }
            catch (Exception e) { Program.ShowError(e); }
            finally { completing = false; }
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            // Text owns all keys while editing. Global registrations are paused for the
            // entire overlay lifetime, including customized Ctrl+C/Ctrl+Z combinations.
            if (textEntry != null && textEntry.Focused) return base.ProcessCmdKey(ref msg, keyData);
            if ((int)keyData == shortcuts.CancelKey) { Close(); return true; }
            if ((int)keyData == shortcuts.CopyKey) { CopySelection(); return true; }
            if ((int)keyData == shortcuts.SaveKey) { Finish(CaptureAction.Save); return true; }
            if ((int)keyData == shortcuts.PinKey) { PinSelection(); return true; }
            if ((int)keyData == shortcuts.UndoKey) { Undo(); return true; }
            if ((int)keyData == shortcuts.RedoKey) { Redo(); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }
    }

    public sealed class PinWindow : Form
    {
        private Bitmap image;
        private Point dragAnchor;
        private bool dragging;
        private Bitmap scaledPreview;
        private Timer previewTimer;
        private double zoom = 1;
        private Settings shortcuts;
        public PinWindow(Bitmap image, Settings shortcuts)
        {
            Theme.Form(this); AutoScaleMode = AutoScaleMode.None; this.image = new Bitmap(image); this.shortcuts = shortcuts;
            previewTimer = new Timer { Interval = 120 }; previewTimer.Tick += delegate { previewTimer.Stop(); BuildPreview(); Invalidate(); };
            Text = "夹心贴 · 贴图"; FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            DoubleBuffered = true; StartPosition = FormStartPosition.Manual; KeyPreview = true;
            Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea;
            zoom = Math.Min(1, Math.Min((area.Width - 60.0) / image.Width, (area.Height - 60.0) / image.Height));
            ResizeImage(); Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
            ContextMenuStrip menu = new ContextMenuStrip { Font = Font, ShowImageMargin = false };
            Add(menu, "复制", Shortcuts.Label(shortcuts.CopyKey), delegate { Native.CopyImage(this.image); });
            Add(menu, "保存", Shortcuts.Label(shortcuts.SaveKey), SaveImage);
            Add(menu, "原始大小", Shortcuts.Label(shortcuts.ResetZoomKey), delegate { SetZoom(1); });
            menu.Items.Add(new ToolStripSeparator());
            Add(menu, "删除", Shortcuts.Label(shortcuts.CancelKey), Close); ContextMenuStrip = menu;
            menu.Opening += delegate
            {
                ((ToolStripMenuItem)menu.Items[0]).ShortcutKeyDisplayString = Shortcuts.Label(shortcuts.CopyKey);
                ((ToolStripMenuItem)menu.Items[1]).ShortcutKeyDisplayString = Shortcuts.Label(shortcuts.SaveKey);
                ((ToolStripMenuItem)menu.Items[2]).ShortcutKeyDisplayString = Shortcuts.Label(shortcuts.ResetZoomKey);
                ((ToolStripMenuItem)menu.Items[4]).ShortcutKeyDisplayString = Shortcuts.Label(shortcuts.CancelKey);
            };
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && image != null)
            {
                previewTimer.Dispose(); if (scaledPreview != null) scaledPreview.Dispose(); image.Dispose(); image = null;
                if (ContextMenuStrip != null) ContextMenuStrip.Dispose();
            }
            base.Dispose(disposing);
        }
        private static void Add(ContextMenuStrip menu, string text, string key, Action action)
        { ToolStripMenuItem item = new ToolStripMenuItem(text) { ShortcutKeyDisplayString = key }; item.Click += delegate { try { action(); } catch (Exception e) { Program.ShowError(e); } }; menu.Items.Add(item); }
        private void BuildPreview()
        {
            if (scaledPreview != null) { scaledPreview.Dispose(); scaledPreview = null; }
            int w = ClientSize.Width - 2, h = ClientSize.Height - 2;
            if (w == image.Width && h == image.Height || (long)w * h > 16000000) return;
            scaledPreview = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(scaledPreview)) { g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.DrawImage(image, new Rectangle(0,0,w,h)); }
        }
        private void ResizeImage()
        {
            ClientSize = new Size(Math.Max(30, (int)Math.Round(image.Width * zoom)) + 2, Math.Max(30, (int)Math.Round(image.Height * zoom)) + 2);
            if (scaledPreview != null) { scaledPreview.Dispose(); scaledPreview = null; }
            previewTimer.Stop(); previewTimer.Start(); Invalidate();
        }
        private void SetZoom(double value)
        {
            Point center = new Point(Left + Width / 2, Top + Height / 2); zoom = Math.Max(0.1, Math.Min(4, value)); ResizeImage(); Location = new Point(center.X - Width / 2, center.Y - Height / 2);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (scaledPreview != null) e.Graphics.DrawImageUnscaled(scaledPreview, 1, 1);
            else if (ClientSize.Width - 2 == image.Width && ClientSize.Height - 2 == image.Height) e.Graphics.DrawImageUnscaled(image, 1, 1);
            else { e.Graphics.InterpolationMode = InterpolationMode.Bilinear; e.Graphics.DrawImage(image, new Rectangle(1, 1, Width - 2, Height - 2)); }
            using (Pen p = new Pen(Theme.Accent)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
        protected override void OnMouseDown(MouseEventArgs e)
        { base.OnMouseDown(e); if (e.Button == MouseButtons.Left) { dragging = true; dragAnchor = e.Location; Capture = true; } }
        protected override void OnMouseMove(MouseEventArgs e)
        { base.OnMouseMove(e); if (dragging) Location = new Point(Left + e.X - dragAnchor.X, Top + e.Y - dragAnchor.Y); }
        protected override void OnMouseUp(MouseEventArgs e)
        { base.OnMouseUp(e); dragging = false; Capture = false; }
        protected override void OnMouseDoubleClick(MouseEventArgs e)
        { base.OnMouseDoubleClick(e); if (e.Button == MouseButtons.Left) Close(); }
        protected override void OnMouseWheel(MouseEventArgs e)
        { base.OnMouseWheel(e); if ((ModifierKeys & Keys.Control) != 0) Opacity = Math.Max(0.1, Math.Min(1, Opacity + (e.Delta > 0 ? .05 : -.05))); else SetZoom(zoom * (e.Delta > 0 ? 1.1 : 1 / 1.1)); }
        private void SaveImage()
        {
            string path = new ShotStore(shortcuts.SaveDirectory).SavePermanent(image);
            Text = "夹心贴 · 已保存";
            ToolTip tip = new ToolTip(); tip.Show("已保存到 " + path, this, 10, 10, 2200);
            Timer timer = new Timer { Interval = 2500 }; timer.Tick += delegate { timer.Dispose(); tip.Dispose(); }; timer.Start();
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (TryShortcut((int)keyData)) return true;
            return base.ProcessCmdKey(ref msg, keyData);
        }
        public bool TryShortcut(int keyData)
        {
            try
            {
                if (keyData == shortcuts.CancelKey) { Close(); return true; }
                if (keyData == shortcuts.SaveKey) { SaveImage(); return true; }
                if (keyData == shortcuts.CopyKey) { Native.CopyImage(image); return true; }
                if (keyData == shortcuts.ResetZoomKey) { SetZoom(1); return true; }
            }
            catch (Exception e) { Program.ShowError(e); return true; }
            return false;
        }
    }
}
