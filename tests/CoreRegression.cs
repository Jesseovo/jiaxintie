using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Linq;
using System.Windows.Forms;
using JiaXinTie;

class CoreRegression
{
    static int passed;
    static void Check(bool result, string name)
    { if (!result) throw new Exception(name); passed++; Console.WriteLine("PASS " + name); }
    static bool Same(Bitmap a, Bitmap b)
    {
        if(a.Size != b.Size) return false;
        for(int y=0;y<a.Height;y++) for(int x=0;x<a.Width;x++) if(a.GetPixel(x,y)!=b.GetPixel(x,y)) return false;
        return true;
    }
    static object Invoke(object target,string method,params object[] args)
    { return target.GetType().GetMethod(method,BindingFlags.NonPublic|BindingFlags.Instance).Invoke(target,args); }
    static void RenderingChecks()
    {
        using(Bitmap source = new Bitmap(320,240))
        {
            using(Graphics g=Graphics.FromImage(source)) g.Clear(Color.FromArgb(250,245,235));
            for(int x=40;x<90;x++) for(int y=45;y<95;y++) source.SetPixel(x,y,Color.FromArgb(x*2,y*2,100));
            Rectangle selection=new Rectangle(20,30,260,180);
            List<Mark> marks=new List<Mark>{new Mark{Tool=DrawTool.Rectangle,A=new Point(10,10),B=new Point(90,100),Color=Color.Red},new Mark{Tool=DrawTool.Mosaic,A=new Point(20,15),B=new Point(65,65)}};
            using(CaptureRenderer renderer=new CaptureRenderer(source))
            using(Bitmap preview=new Bitmap(320,240))
            using(Graphics g=Graphics.FromImage(preview))
            {
                renderer.Paint(g,new Rectangle(0,0,320,240),selection,marks,null);
                using(Bitmap exported=renderer.Export(selection,marks))
                using(Bitmap inside=preview.Clone(selection,PixelFormat.Format32bppArgb)) Check(Same(exported,inside),"cached preview matches exported annotation pixels");
                Check(preview.GetPixel(5,5).R < source.GetPixel(5,5).R && preview.GetPixel(160,170)==source.GetPixel(160,170),"mask darkens only outside selection");
                marks.RemoveAt(0); renderer.InvalidateAnnotations();
                using(Bitmap result=renderer.Export(selection,marks)) Check(result.GetPixel(10,60)==source.GetPixel(30,90),"cache invalidation removes old annotation pixels");
                Rectangle moved=new Rectangle(25,35,200,160);
                using(Bitmap expected=source.Clone(moved,PixelFormat.Format32bppArgb))
                using(Bitmap actual=renderer.Export(moved,new List<Mark>())) Check(Same(expected,actual),"selection resize invalidates source cache");
            }
            using(CaptureOverlay overlay=new CaptureOverlay(new Bitmap(source),new Rectangle(0,0,320,240),false,new Settings(),null))
            {
                typeof(CaptureOverlay).GetField("selection",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(overlay,selection);
                Mark rectangle=new Mark{Tool=DrawTool.Rectangle,A=new Point(10,10),B=new Point(90,100),Color=Color.Red};
                rectangle.Points.Add(rectangle.A);
                Check(rectangle.VisualBounds.Contains(rectangle.B),"shape dirty bounds include endpoint despite initial point");
                Mark line=new Mark{Tool=DrawTool.Line,A=new Point(5,130),B=new Point(200,130),Color=Color.Blue};
                Invoke(overlay,"AddMark",rectangle); Invoke(overlay,"AddMark",line);
                using(Bitmap before=overlay.RenderSelection())
                {
                    Invoke(overlay,"EraseAt",new Point(50,130));
                    using(Bitmap erased=overlay.RenderSelection()) Check(erased.GetPixel(50,130)==source.GetPixel(70,160),"eraser restores original pixels");
                    Invoke(overlay,"Undo"); using(Bitmap undone=overlay.RenderSelection()) Check(Same(before,undone),"undo eraser restores exact layer order");
                    Invoke(overlay,"Redo"); using(Bitmap redone=overlay.RenderSelection()) Check(redone.GetPixel(50,130)==source.GetPixel(70,160),"redo eraser removes annotation again");
                }
                Check(rectangle.HitTest(new Point(10,40),5) && !rectangle.HitTest(new Point(50,50),5),"eraser hits shape outline instead of empty center");
                Invoke(overlay,"SetTool",DrawTool.Eraser);
                Invoke(overlay,"OnMouseDown",new MouseEventArgs(MouseButtons.Left,1,5,5,0));
                Invoke(overlay,"OnMouseMove",new MouseEventArgs(MouseButtons.Left,0,100,100,0));
                Invoke(overlay,"OnMouseUp",new MouseEventArgs(MouseButtons.Left,1,150,120,0));
                Rectangle reselected=(Rectangle)typeof(CaptureOverlay).GetField("selection",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(overlay);
                Check(reselected == new Rectangle(5,5,145,115),"eraser selected outside region still completes fresh selection");
            }
        }
    }
    [STAThread] static int Main()
    {
        Native.EnableDpi();
        string tests = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        string root = Path.GetFullPath(Path.Combine(tests, "runtime-" + Guid.NewGuid().ToString("N")));
        if (!root.StartsWith(tests, StringComparison.OrdinalIgnoreCase)) return 2;
        Directory.CreateDirectory(root);
        try
        {
            // Exercise the real screen path that failed in 1.0.0, without retaining desktop pixels.
            for (int i = 0; i < 3; i++)
            {
                Rectangle bounds;
                using (Bitmap screen = Native.CaptureDesktop(out bounds))
                using (MemoryStream png = new MemoryStream())
                {
                    Check(bounds == SystemInformation.VirtualScreen && screen.Size == bounds.Size, "real desktop capture " + (i + 1));
                    screen.Save(png, ImageFormat.Png); png.Position = 0;
                    using (Bitmap decoded = new Bitmap(png)) Check(decoded.GetPixel(decoded.Width / 2, decoded.Height / 2).A == 255, "desktop PNG opaque " + (i + 1));
                }
            }
            string shots = Path.Combine(root, "中文 空格截图");
            ShotStore store = new ShotStore(shots);
            ShotStore.ValidateWritable(shots);
            using (Bitmap image = new Bitmap(61, 39))
            {
                using (Graphics g = Graphics.FromImage(image)) g.Clear(Color.FromArgb(255, 25, 130, 205));
                string permanent = store.SavePermanent(image);
                string unrelated = Path.Combine(store.Cache, "用户保留.png");
                image.Save(unrelated, ImageFormat.Png);
                string nearMatch = Path.Combine(store.Cache, "jxt-cache-用户图片.png");
                image.Save(nearMatch, ImageFormat.Png);
                string oldest = store.AddCache(image);
                File.SetLastWriteTimeUtc(oldest, DateTime.UtcNow.AddMinutes(-1));
                for (int i = 0; i < 5; i++) store.AddCache(image);
                Check(store.Recent().Count == 3 && !File.Exists(oldest), "cache rotates to latest three");
                Check(File.Exists(permanent) && File.Exists(unrelated) && File.Exists(nearMatch), "permanent and unrelated files preserved");
                using (Bitmap decoded = ShotStore.LoadUnlocked(permanent))
                    Check(decoded.Size == image.Size && decoded.GetPixel(5, 5).ToArgb() == image.GetPixel(5, 5).ToArgb(), "PNG dimensions and pixels preserved");
                using (Bitmap unlocked = ShotStore.LoadUnlocked(store.Recent()[0]))
                { foreach (string path in store.Recent()) File.Delete(path); Check(unlocked.Width == 61, "loaded cache does not lock files"); }
                Check(!Directory.GetFiles(shots, "*.part", SearchOption.AllDirectories).Any(), "no partial PNG files");
            }
            Settings.ProfileDirectory = Path.Combine(root, "profile");
            Settings custom = new Settings { SaveDirectory = shots, CaptureKey = (int)Keys.F8, CopyKey = (int)Keys.F8, SaveKey = (int)(Keys.Control | Keys.S) };
            Shortcuts.Validate(custom); custom.Save(); Settings loaded = Settings.Load();
            Check(loaded.CaptureKey == (int)Keys.F8 && loaded.CopyKey == (int)Keys.F8 && loaded.SaveKey == (int)(Keys.Control | Keys.S), "custom shortcuts persist");
            bool conflict = false; loaded.PinKey = loaded.CaptureKey;
            try { Shortcuts.Validate(loaded); } catch (ArgumentException) { conflict = true; }
            Check(conflict, "duplicate global shortcuts rejected");
            string changed = Path.Combine(root, "安装后 目录");
            string exe = Path.Combine(tests, "..", "dist", "1.0.2", "夹心贴.exe");
            using (Process p = Process.Start(new ProcessStartInfo(exe, "--configure \"" + changed + "\" --profile \"" + Settings.ProfileDirectory + "\"") { UseShellExecute = false, CreateNoWindow = true }))
            { if (!p.WaitForExit(10000)) throw new Exception("configure timeout"); Check(p.ExitCode == 0, "installer configure exits successfully"); }
            loaded = Settings.Load();
            Check(loaded.SaveDirectory == changed && loaded.CaptureKey == custom.CaptureKey && loaded.SaveKey == custom.SaveKey, "installer preserves custom shortcuts");
            File.WriteAllText(Settings.ConfigFile, "{\"SaveDirectory\":\"C:\\\\shots\"}"); loaded = Settings.Load();
            Check(loaded.CopyKey == (int)Keys.F1 && loaded.SaveKey == (int)Keys.S && loaded.CacheLimit == 3, "older settings receive shortcut defaults");
            using (Bitmap logo = new Bitmap(Theme.Logo()))
            {
                Check(logo.GetPixel(0, 0).A == 0 && logo.GetPixel(logo.Width - 1, logo.Height - 1).A == 0 && logo.GetPixel(logo.Width / 2, logo.Height / 2).A == 255, "logo transparent background and intact face");
            }
            RenderingChecks();
            using(Bitmap image=new Bitmap(20,20))
            {
                ShotStore recorded=new ShotStore(Path.Combine(root,"record")); recorded.Record(image,true);
                Check(Directory.GetFiles(recorded.Root,"*.png").Length==1 && recorded.Recent().Count==1 && File.ReadAllBytes(Directory.GetFiles(recorded.Root,"*.png")[0]).SequenceEqual(File.ReadAllBytes(recorded.Recent()[0])),"manual PNG and cache share identical encoded bytes");
            }
            Console.WriteLine("RESULT " + passed + " checks passed"); return 0;
        }
        catch (Exception e) { Console.Error.WriteLine("FAIL " + e); return 1; }
        finally { Directory.Delete(root, true); }
    }
}
