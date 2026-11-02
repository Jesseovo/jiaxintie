using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

class PaintBenchmark
{
    [STAThread] static int Main(string[] args)
    {
        string app = Path.GetFullPath(args[0]); Assembly a = Assembly.LoadFrom(app);
        a.GetType("JiaXinTie.Native").GetMethod("EnableDpi").Invoke(null, null);
        Type overlayType = a.GetType("JiaXinTie.CaptureOverlay"), markType = a.GetType("JiaXinTie.Mark"), toolType = a.GetType("JiaXinTie.DrawTool");
        Bitmap source = new Bitmap(2560, 1440);
        using (Graphics g = Graphics.FromImage(source))
        using (LinearGradientBrush fill = new LinearGradientBrush(new Rectangle(0,0,2560,1440), Color.White, Color.SteelBlue, 25f)) g.FillRectangle(fill, 0,0,2560,1440);
        Stopwatch startup = Stopwatch.StartNew();
        using (Form overlay = (Form)Activator.CreateInstance(overlayType, new object[] {source, new Rectangle(0,0,2560,1440),false,Activator.CreateInstance(a.GetType("JiaXinTie.Settings")),null}))
        using (Bitmap target = new Bitmap(2560,1440))
        using (Graphics g = Graphics.FromImage(target))
        {
            startup.Stop(); Console.WriteLine("Constructor ms: " + startup.Elapsed.TotalMilliseconds.ToString("F2"));
            overlayType.GetField("selection",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(overlay,new Rectangle(100,100,2200,1200));
            IList marks = (IList)overlayType.GetField("marks",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(overlay);
            for (int i=0;i<24;i++)
            {
                object mark=Activator.CreateInstance(markType);
                markType.GetField("Tool").SetValue(mark,Enum.Parse(toolType,i<2?"Mosaic":"Rectangle"));
                markType.GetField("A").SetValue(mark,new Point(50+i*8,60+i*6));
                markType.GetField("B").SetValue(mark,new Point(1000+i*5,700+i*4)); marks.Add(mark);
            }
            object current=Activator.CreateInstance(markType); markType.GetField("Tool").SetValue(current,Enum.Parse(toolType,"Pen"));
            IList points=(IList)markType.GetField("Points").GetValue(current);
            for(int i=0;i<600;i++) points.Add(new Point(1100+i,800+(i%30)));
            markType.GetField("A").SetValue(current,new Point(1100,800)); markType.GetField("B").SetValue(current,new Point(1699,829));
            overlayType.GetField("current",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(overlay,current);
            MethodInfo paint=overlayType.GetMethod("OnPaint",BindingFlags.NonPublic|BindingFlags.Instance);
            foreach (bool full in new[]{true,false})
            {
                Rectangle clip=full?new Rectangle(0,0,2560,1440):new Rectangle(1180,880,300,100);
                List<double> samples=new List<double>();
                for(int i=0;i<33;i++)
                {
                    g.ResetClip();g.SetClip(clip); Stopwatch watch=Stopwatch.StartNew();
                    paint.Invoke(overlay,new object[]{new PaintEventArgs(g,clip)}); watch.Stop();
                    if(i>=3)samples.Add(watch.Elapsed.TotalMilliseconds);
                }
                samples.Sort(); Console.WriteLine((full?"Full":"Partial")+" paint ms: median="+samples[15].ToString("F2")+" p95="+samples[28].ToString("F2"));
            }
        }
        source.Dispose(); return 0;
    }
}
