using System;
using System.IO;
using System.Reflection;
using System.Drawing;
using System.Windows.Forms;
class UiHarness
{
    [STAThread] static void Main()
    {
        string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
        string version = File.ReadAllText(Path.Combine(root, "VERSION")).Trim();
        Assembly a = Assembly.LoadFrom(Path.Combine(root, "dist", version, "夹心贴.exe"));
        string modeFile = Path.Combine(root, "tests", "ui-mode.txt");
        string mode = File.Exists(modeFile) ? File.ReadAllText(modeFile).Trim() : "demo";
        if (mode == "settings" || mode == "pin")
        {
            a.GetType("JiaXinTie.Native").GetMethod("EnableDpi").Invoke(null, null);
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            a.GetType("JiaXinTie.Settings").GetField("ProfileDirectory").SetValue(null, Path.Combine(root, "tests", "ui-profile"));
            object settings = a.GetType("JiaXinTie.Settings").GetMethod("Load").Invoke(null, null);
            if (mode == "settings")
                using (Form form = (Form)Activator.CreateInstance(a.GetType("JiaXinTie.SettingsWindow"), new object[] { settings, false, null })) form.ShowDialog();
            else
                using (Bitmap image = (Bitmap)a.GetType("JiaXinTie.TrayHost").GetMethod("DemoImage").Invoke(null, new object[] {new Size(960,640)}))
                using (Form form = (Form)Activator.CreateInstance(a.GetType("JiaXinTie.PinWindow"), new object[] { image, settings }))
                { form.ShowInTaskbar = true; Application.Run(form); }
        }
        else a.GetType("JiaXinTie.Program").GetMethod("Main", BindingFlags.Public | BindingFlags.Static).Invoke(null,
            new object[] { new[] { mode == "real" ? "--capture" : "--demo", "--profile", Path.Combine(root, "tests", "ui-profile") } });
    }
}
