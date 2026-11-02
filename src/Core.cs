using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace JiaXinTie
{
    [DataContract]
    public sealed class Settings
    {
        [DataMember] public string SaveDirectory;
        [DataMember] public int CacheLimit = 3;
        [DataMember] public int CaptureKey = (int)Keys.F1;
        [DataMember] public int CopyKey = (int)Keys.F1;
        [DataMember] public int SaveKey = (int)Keys.S;
        [DataMember] public int PinKey = (int)Keys.F3;
        [DataMember] public int TogglePinsKey = (int)(Keys.Shift | Keys.F3);
        [DataMember] public int AutoCopyKey = (int)(Keys.Control | Keys.F1);
        [DataMember] public int CancelKey = (int)Keys.Escape;
        [DataMember] public int UndoKey = (int)(Keys.Control | Keys.Z);
        [DataMember] public int RedoKey = (int)(Keys.Control | Keys.Y);
        [DataMember] public int ResetZoomKey = (int)Keys.D0;
        [OnDeserializing] private void Defaults(StreamingContext context)
        {
            CaptureKey = CopyKey = (int)Keys.F1; SaveKey = (int)Keys.S; PinKey = (int)Keys.F3;
            TogglePinsKey = (int)(Keys.Shift | Keys.F3); AutoCopyKey = (int)(Keys.Control | Keys.F1);
            CancelKey = (int)Keys.Escape; UndoKey = (int)(Keys.Control | Keys.Z);
            RedoKey = (int)(Keys.Control | Keys.Y); ResetZoomKey = (int)Keys.D0;
        }
        public static string ProfileDirectory;
        public static string ConfigFile { get { return Path.Combine(ProfileDirectory, "settings.json"); } }
        public static Settings Load()
        {
            try
            {
                using (FileStream s = File.OpenRead(ConfigFile))
                {
                    Settings result = (Settings)new DataContractJsonSerializer(typeof(Settings)).ReadObject(s);
                    result.CacheLimit = 3;
                    return result;
                }
            }
            catch (FileNotFoundException) { return new Settings(); }
            catch (DirectoryNotFoundException) { return new Settings(); }
        }
        public void Save()
        {
            Directory.CreateDirectory(ProfileDirectory);
            string temp = ConfigFile + ".tmp";
            using (FileStream s = File.Create(temp))
                new DataContractJsonSerializer(typeof(Settings)).WriteObject(s, this);
            if (File.Exists(ConfigFile)) File.Replace(temp, ConfigFile, null);
            else File.Move(temp, ConfigFile);
        }
    }

    public static class Shortcuts
    {
        public static string Label(int key)
        {
            Keys keys = (Keys)key; List<string> parts = new List<string>();
            if ((keys & Keys.Control) != 0) parts.Add("Ctrl");
            if ((keys & Keys.Alt) != 0) parts.Add("Alt");
            if ((keys & Keys.Shift) != 0) parts.Add("Shift");
            Keys code = keys & Keys.KeyCode;
            string name = code == Keys.Escape ? "Esc" : code == Keys.Return ? "Enter" : code.ToString();
            if (code >= Keys.D0 && code <= Keys.D9) name = ((int)code - (int)Keys.D0).ToString();
            parts.Add(name); return String.Join("+", parts);
        }
        public static bool Usable(Keys value)
        {
            Keys code = value & Keys.KeyCode;
            return code != Keys.None && code != Keys.ControlKey && code != Keys.ShiftKey && code != Keys.Menu &&
                code != Keys.LWin && code != Keys.RWin && code != Keys.Tab && code != Keys.ProcessKey && code != Keys.Packet;
        }
        public static void Validate(Settings s)
        {
            int[] global = { s.CaptureKey, s.PinKey, s.TogglePinsKey, s.AutoCopyKey };
            int[] editor = { s.CopyKey, s.SaveKey, s.PinKey, s.CancelKey, s.UndoKey, s.RedoKey };
            if (global.Concat(editor).Concat(new[] { s.ResetZoomKey }).Any(k => !Usable((Keys)k)))
                throw new ArgumentException("请为每个操作选择有效的快捷键。");
            if (global.Distinct().Count() != global.Length) throw new ArgumentException("全局快捷键之间不能重复。");
            if (editor.Distinct().Count() != editor.Length) throw new ArgumentException("截图编辑快捷键之间不能重复。");
            if (new[] { s.SaveKey, s.CopyKey, s.CancelKey }.Contains(s.ResetZoomKey)) throw new ArgumentException("原始大小快捷键与贴图的复制、保存或关闭键重复。");
        }
        public static bool Register(IntPtr handle, int id, int key)
        {
            Keys k = (Keys)key; uint modifiers = 0x4000;
            if ((k & Keys.Control) != 0) modifiers |= 2;
            if ((k & Keys.Alt) != 0) modifiers |= 1;
            if ((k & Keys.Shift) != 0) modifiers |= 4;
            return Native.RegisterHotKey(handle, id, modifiers, (uint)(k & Keys.KeyCode));
        }
    }

    public sealed class ShotStore
    {
        public const int Limit = 3;
        public string Root { get; private set; }
        public string Cache { get { return Path.Combine(Root, "缓存"); } }
        // Only app-owned filenames can be rotated. Unrelated files are never deleted.
        private static readonly Regex Owned = new Regex(@"^jxt-cache-\d{8}-\d{9}-[a-f0-9]{12}\.png$", RegexOptions.CultureInvariant);
        public ShotStore(string root)
        {
            if (String.IsNullOrWhiteSpace(root) || !Path.IsPathRooted(root))
                throw new ArgumentException("请选择完整的截图保存路径。");
            Root = Path.GetFullPath(root);
            Directory.CreateDirectory(Root);
            Directory.CreateDirectory(Cache);
        }
        public static void ValidateWritable(string root)
        {
            ShotStore store = new ShotStore(root);
            string probe = Path.Combine(store.Root, ".jiaxintie-write-" + Guid.NewGuid().ToString("N"));
            using (FileStream s = new FileStream(probe, FileMode.CreateNew, FileAccess.Write, FileShare.None)) s.WriteByte(1);
            File.Delete(probe);
        }
        private static string Stamp() { return DateTime.Now.ToString("yyyyMMdd-HHmmssfff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 12); }
        public string AddCache(Bitmap bitmap)
        {
            string path = Path.Combine(Cache, "jxt-cache-" + Stamp() + ".png");
            SaveAtomic(bitmap, path);
            Trim();
            return path;
        }
        public string SavePermanent(Bitmap bitmap)
        {
            string path = Path.Combine(Root, "夹心贴-" + Stamp() + ".png");
            SaveAtomic(bitmap, path);
            return path;
        }
        public void Record(Bitmap bitmap, bool permanent)
        {
            using (MemoryStream buffer = new MemoryStream())
            {
                bitmap.Save(buffer, ImageFormat.Png); byte[] png = buffer.ToArray(); string stamp = Stamp();
                if (permanent) SaveAtomic(png, Path.Combine(Root, "夹心贴-" + stamp + ".png"));
                SaveAtomic(png, Path.Combine(Cache, "jxt-cache-" + stamp + ".png"));
            }
            Trim();
        }
        private static void SaveAtomic(byte[] png, string path)
        {
            string temp = path + ".part";
            try { File.WriteAllBytes(temp, png); File.Move(temp, path); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        private static void SaveAtomic(Bitmap bitmap, string path)
        {
            string temp = path + ".part";
            try { bitmap.Save(temp, ImageFormat.Png); File.Move(temp, path); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        public List<string> Recent()
        {
            return Directory.GetFiles(Cache, "jxt-cache-*.png")
                .Where(p => Owned.IsMatch(Path.GetFileName(p)))
                .OrderByDescending(p => File.GetLastWriteTimeUtc(p)).ThenByDescending(p => p, StringComparer.Ordinal).ToList();
        }
        public void Trim()
        {
            foreach (string path in Recent().Skip(Limit)) File.Delete(path);
        }
        public static Bitmap LoadUnlocked(string path)
        {
            using (Image image = Image.FromFile(path)) return new Bitmap(image);
        }
    }

    public static class Native
    {
        [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetDC(IntPtr window);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern bool BitBlt(IntPtr target, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);
        public static void EnableDpi()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { }
            SetProcessDPIAware();
        }
        public static Bitmap CaptureDesktop(out Rectangle bounds)
        {
            bounds = SystemInformation.VirtualScreen;
            Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppRgb);
            try
            {
                // Graphics.CopyFromScreen rejects combined CopyPixelOperation values on
                // .NET Framework. Pass SRCCOPY | CAPTUREBLT to the native API instead.
                using (Graphics g = Graphics.FromImage(bitmap))
                {
                    IntPtr source = GetDC(IntPtr.Zero);
                    if (source == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                    try
                    {
                        IntPtr target = g.GetHdc();
                        try
                        {
                            if (!BitBlt(target, 0, 0, bounds.Width, bounds.Height, source, bounds.Left, bounds.Top, 0x40CC0020))
                                throw new Win32Exception(Marshal.GetLastWin32Error());
                        }
                        finally { g.ReleaseHdc(target); }
                    }
                    finally { ReleaseDC(IntPtr.Zero, source); }
                }
                return bitmap;
            }
            catch { bitmap.Dispose(); throw; }
        }
        public static void CopyImage(Bitmap image)
        {
            // PNG preserves alpha in supporting apps; Bitmap covers standard Windows paste targets.
            using (MemoryStream png = new MemoryStream())
            {
                image.Save(png, ImageFormat.Png);
                png.Position = 0;
                DataObject data = new DataObject();
                data.SetData(DataFormats.Bitmap, true, image);
                data.SetData("PNG", false, png);
                Clipboard.SetDataObject(data, true, 8, 70);
            }
        }
    }

    public enum DrawTool { Move, Rectangle, Ellipse, Arrow, Pen, Text, Mosaic, Line, Highlighter, Eraser }
    public sealed class Mark
    {
        public DrawTool Tool;
        public Point A, B;
        public List<Point> Points = new List<Point>();
        public Color Color = Color.FromArgb(244, 89, 122);
        public float Width = 3;
        public string Text;
        public Rectangle Bounds { get { return Normalize(A, B); } }
        public static Rectangle Normalize(Point a, Point b)
        { return Rectangle.FromLTRB(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y)); }
        public Rectangle VisualBounds
        {
            get
            {
                Rectangle r = Bounds;
                if ((Tool == DrawTool.Pen || Tool == DrawTool.Highlighter) && Points.Count > 0)
                    r = Rectangle.FromLTRB(Points.Min(p => p.X), Points.Min(p => p.Y), Points.Max(p => p.X), Points.Max(p => p.Y));
                if (Tool == DrawTool.Text)
                    using (Font font = new Font("Microsoft YaHei UI", 18, FontStyle.Bold, GraphicsUnit.Pixel)) r = new Rectangle(A, TextRenderer.MeasureText(Text ?? "", font));
                r.Inflate((int)Math.Ceiling(Width) + (Tool == DrawTool.Arrow ? 24 : 5), (int)Math.Ceiling(Width) + (Tool == DrawTool.Arrow ? 24 : 5));
                return r;
            }
        }
        private static double Distance(Point p, Point a, Point b)
        {
            double dx = b.X - a.X, dy = b.Y - a.Y;
            double t = dx == 0 && dy == 0 ? 0 : Math.Max(0, Math.Min(1, ((p.X-a.X)*dx+(p.Y-a.Y)*dy)/(dx*dx+dy*dy)));
            dx = p.X - a.X - t * dx; dy = p.Y - a.Y - t * dy; return Math.Sqrt(dx * dx + dy * dy);
        }
        public bool HitTest(Point point, float radius)
        {
            if (!Rectangle.Inflate(VisualBounds, (int)Math.Ceiling(radius), (int)Math.Ceiling(radius)).Contains(point)) return false;
            float tolerance = radius + Width / 2;
            Rectangle r = Bounds;
            if (Tool == DrawTool.Mosaic) return Rectangle.Inflate(r, (int)radius, (int)radius).Contains(point);
            if (Tool == DrawTool.Text) return VisualBounds.Contains(point);
            if (Tool == DrawTool.Line || Tool == DrawTool.Arrow) return Distance(point, A, B) <= tolerance;
            if (Tool == DrawTool.Pen || Tool == DrawTool.Highlighter)
            {
                if (Points.Count == 1) return Distance(point, Points[0], Points[0]) <= tolerance;
                for (int i = 1; i < Points.Count; i++) if (Distance(point, Points[i-1], Points[i]) <= tolerance) return true;
                return false;
            }
            if (Tool == DrawTool.Ellipse && r.Width > 0 && r.Height > 0)
            {
                double x = (point.X-r.Left-r.Width/2.0)/(r.Width/2.0), y = (point.Y-r.Top-r.Height/2.0)/(r.Height/2.0);
                return Math.Abs(Math.Sqrt(x*x+y*y)-1) * Math.Min(r.Width,r.Height)/2 <= tolerance;
            }
            return Distance(point, new Point(r.Left,r.Top),new Point(r.Right,r.Top)) <= tolerance || Distance(point,new Point(r.Right,r.Top),new Point(r.Right,r.Bottom)) <= tolerance || Distance(point,new Point(r.Right,r.Bottom),new Point(r.Left,r.Bottom)) <= tolerance || Distance(point,new Point(r.Left,r.Bottom),new Point(r.Left,r.Top)) <= tolerance;
        }
        public void Draw(Graphics g, Bitmap source, Bitmap pixelated = null)
        {
            using (Pen pen = new Pen(Color, Width))
            {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                switch (Tool)
                {
                    case DrawTool.Rectangle: if (Bounds.Width > 0 && Bounds.Height > 0) g.DrawRectangle(pen, Bounds); break;
                    case DrawTool.Ellipse: if (Bounds.Width > 0 && Bounds.Height > 0) g.DrawEllipse(pen, Bounds); break;
                    case DrawTool.Line: g.DrawLine(pen, A, B); break;
                    case DrawTool.Arrow:
                        using (AdjustableArrowCap cap = new AdjustableArrowCap(5, 6, true))
                        { pen.CustomEndCap = cap; g.DrawLine(pen, A, B); } break;
                    case DrawTool.Highlighter:
                        pen.Color = Color.FromArgb(90, Color); pen.StartCap = pen.EndCap = LineCap.Square;
                        goto case DrawTool.Pen;
                    case DrawTool.Pen:
                        if (Points.Count > 1) g.DrawLines(pen, Points.ToArray());
                        else g.DrawEllipse(pen, A.X, A.Y, 1, 1); break;
                    case DrawTool.Text:
                        using (Font font = new Font("Microsoft YaHei UI", 18, FontStyle.Bold, GraphicsUnit.Pixel))
                        using (Brush brush = new SolidBrush(Color)) g.DrawString(Text ?? "", font, brush, A); break;
                    case DrawTool.Mosaic:
                        Rectangle r = Rectangle.Intersect(new Rectangle(Point.Empty, source.Size), Bounds);
                        if (pixelated != null) { g.DrawImage(pixelated, r, r, GraphicsUnit.Pixel); break; }
                        for (int y = r.Top; y < r.Bottom; y += 12)
                            for (int x = r.Left; x < r.Right; x += 12)
                            {
                                int w = Math.Min(12, r.Right - x), h = Math.Min(12, r.Bottom - y);
                                using (Brush block = new SolidBrush(source.GetPixel(x + w / 2, y + h / 2)))
                                    g.FillRectangle(block, x, y, w, h);
                            }
                        break;
                }
            }
        }
    }

    public static class Theme
    {
        public static readonly Color Ink = Color.FromArgb(46, 49, 54);
        public static readonly Color Accent = Color.FromArgb(0, 120, 215);
        public static readonly Color Paper = Color.White;
        public static Icon Icon()
        { using (Stream s = typeof(Theme).Assembly.GetManifestResourceStream("app.ico")) return new Icon(s); }
        public static Image Logo()
        { using (Stream s = typeof(Theme).Assembly.GetManifestResourceStream("logo.png")) using (Image i = Image.FromStream(s)) return new Bitmap(i); }
        public static Button Button(string title, bool primary)
        {
            Button b = new Button { Text = title, FlatStyle = FlatStyle.Flat, Height = 38,
                BackColor = primary ? Accent : Color.White, ForeColor = primary ? Color.White : Ink, Cursor = Cursors.Hand };
            b.FlatAppearance.BorderColor = primary ? Accent : Color.FromArgb(221, 224, 229);
            b.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(0, 103, 190) : Color.FromArgb(242, 244, 247);
            b.FlatAppearance.MouseDownBackColor = primary ? Color.FromArgb(0, 88, 168) : Color.FromArgb(230, 233, 238);
            return b;
        }
        public static Bitmap ToolIcon(string kind, Color color)
        {
            Bitmap b = new Bitmap(24, 24, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            using (Pen p = new Pen(color, 1.8f))
            using (Brush brush = new SolidBrush(color))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; p.StartCap = p.EndCap = LineCap.Round;
                if (kind == "矩形") g.DrawRectangle(p, 4, 5, 16, 14);
                else if (kind == "圆形") g.DrawEllipse(p, 4, 4, 16, 16);
                else if (kind == "箭头") { g.DrawLine(p, 5, 19, 19, 5); g.DrawLines(p, new[] { new Point(10, 5), new Point(19, 5), new Point(19, 14) }); }
                else if (kind == "直线") g.DrawLines(p, new[] { new Point(4,18),new Point(11,7),new Point(20,13) });
                else if (kind == "荧光笔") { g.DrawPolygon(p,new[] {new Point(6,14),new Point(14,4),new Point(20,9),new Point(12,18)}); g.DrawLine(p,5,20,13,20); g.DrawLine(p,5,15,9,19); }
                else if (kind == "橡皮擦") { g.DrawPolygon(p,new[] {new Point(4,14),new Point(13,4),new Point(21,11),new Point(13,20),new Point(10,20)});g.DrawLine(p,9,9,17,16); }
                else if (kind == "完成") { p.Width=2.2f;g.DrawLines(p,new[] {new Point(4,12),new Point(10,18),new Point(21,6)}); }
                else if (kind == "调色板") { g.DrawEllipse(p,4,4,16,16); using(Brush red=new SolidBrush(Color.IndianRed))g.FillEllipse(red,7,7,4,4);using(Brush blue=new SolidBrush(Color.SteelBlue))g.FillEllipse(blue,13,7,4,4);using(Brush green=new SolidBrush(Color.ForestGreen))g.FillEllipse(green,9,13,4,4); }
                else if (kind == "画笔") { g.DrawLines(p, new[] { new Point(5, 16), new Point(15, 4), new Point(20, 8), new Point(9, 20), new Point(4, 21), new Point(5, 16) }); g.DrawLine(p, 13, 7, 17, 11); }
                else if (kind == "文字") { g.DrawLine(p, 5, 5, 19, 5); g.DrawLine(p, 12, 5, 12, 20); g.DrawLine(p, 8, 20, 16, 20); }
                else if (kind == "马赛克") { for (int y = 4; y < 20; y += 5) for (int x = 4; x < 20; x += 5) if ((x / 5 + y / 5) % 2 == 0) g.FillRectangle(brush, x, y, 4, 4); else g.DrawRectangle(p, x, y, 3, 3); }
                else if (kind == "移动") { g.DrawLine(p, 3, 12, 21, 12); g.DrawLine(p, 12, 3, 12, 21); g.DrawLines(p, new[] {new Point(8,7),new Point(12,3),new Point(16,7)}); g.DrawLines(p,new[] {new Point(7,8),new Point(3,12),new Point(7,16)}); g.DrawLines(p,new[] {new Point(17,8),new Point(21,12),new Point(17,16)}); g.DrawLines(p,new[] {new Point(8,17),new Point(12,21),new Point(16,17)}); }
                else if (kind == "颜色") { g.FillEllipse(brush, 4, 4, 16, 16); using (Pen white = new Pen(Color.White, 2)) g.DrawArc(white, 7, 7, 10, 10, 190, 80); }
                else if (kind == "撤销" || kind == "重做") { if (kind == "重做") { g.TranslateTransform(24,0);g.ScaleTransform(-1,1); } g.DrawArc(p, 5, 7, 15, 13, 200, 250); g.DrawLines(p, new[] { new Point(4, 4), new Point(4, 11), new Point(11, 11) }); }
                else if (kind == "保存") { g.DrawRectangle(p, 4, 3, 16, 18); g.DrawRectangle(p, 8, 3, 8, 6); g.DrawRectangle(p, 8, 14, 8, 7); }
                else if (kind == "贴图") { g.DrawLines(p,new[] {new Point(7,3),new Point(17,3),new Point(16,11),new Point(20,15),new Point(4,15),new Point(8,11),new Point(7,3)});g.DrawLine(p,12,15,12,22); }
                else if (kind == "复制") { g.DrawRectangle(p, 8, 7, 12, 14); g.DrawLines(p, new[] { new Point(5,17), new Point(3,17), new Point(3,3), new Point(15,3), new Point(15,4) }); }
                else { g.DrawLine(p, 6, 6, 18, 18); g.DrawLine(p, 6, 18, 18, 6); }
            }
            return b;
        }
        public static Bitmap DotIcon(int diameter, Color color)
        {
            Bitmap b = new Bitmap(20,20);
            using(Graphics g=Graphics.FromImage(b)) using(Brush brush=new SolidBrush(color)) { g.SmoothingMode=SmoothingMode.AntiAlias;g.FillEllipse(brush,(20-diameter)/2f,(20-diameter)/2f,diameter,diameter); }
            return b;
        }
        public static void Form(Form form)
        {
            form.Font = new Font("Microsoft YaHei UI", 9F);
            form.BackColor = Paper; form.ForeColor = Ink; form.Icon = Icon();
            form.AutoScaleMode = AutoScaleMode.Dpi;
        }
    }
}
