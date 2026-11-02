using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace JiaXinTie
{
    // Static screen pixels and finished annotations are rendered once. Mouse moves
    // only restore the damaged pixels and draw the annotation currently being edited.
    public sealed class CaptureRenderer : IDisposable
    {
        private readonly Bitmap desktop;
        private Bitmap dimmed, source, composition, mosaic;
        private Rectangle cachedSelection;
        private int cachedCount = -1;
        public CaptureRenderer(Bitmap desktop)
        {
            this.desktop = desktop;
            dimmed = new Bitmap(desktop.Width, desktop.Height, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(dimmed))
            {
                g.DrawImageUnscaled(desktop, 0, 0);
                using (Brush shade = new SolidBrush(Color.FromArgb(100, 0, 0, 0))) g.FillRectangle(shade, 0, 0, desktop.Width, desktop.Height);
            }
        }
        private static void Release(ref Bitmap bitmap) { if (bitmap != null) { bitmap.Dispose(); bitmap = null; } }
        private void Select(Rectangle selection)
        {
            if (selection == cachedSelection) return;
            cachedSelection = selection; Release(ref source); Release(ref mosaic); InvalidateAnnotations();
        }
        public void InvalidateAnnotations() { Release(ref composition); cachedCount = -1; }
        private Bitmap Source()
        {
            if (source == null) source = desktop.Clone(cachedSelection, PixelFormat.Format32bppPArgb);
            return source;
        }
        private Bitmap Mosaic()
        {
            if (mosaic == null)
            {
                Bitmap original = Source();
                int w = (original.Width + 11) / 12, h = (original.Height + 11) / 12;
                using (Bitmap small = new Bitmap(w, h, PixelFormat.Format32bppPArgb))
                {
                    using (Graphics g = Graphics.FromImage(small))
                    {
                        g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
                        g.DrawImage(original, new Rectangle(0, 0, w, h), new Rectangle(0, 0, original.Width, original.Height), GraphicsUnit.Pixel);
                    }
                    mosaic = new Bitmap(original.Width, original.Height, PixelFormat.Format32bppPArgb);
                    using (Graphics g = Graphics.FromImage(mosaic))
                    {
                        g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
                        g.DrawImage(small, new Rectangle(0, 0, w * 12, h * 12), new Rectangle(0, 0, w, h), GraphicsUnit.Pixel);
                    }
                }
            }
            return mosaic;
        }
        private Bitmap Finished(IList<Mark> marks)
        {
            if (composition == null || cachedCount != marks.Count)
            {
                Release(ref composition); composition = new Bitmap(Source());
                using (Graphics g = Graphics.FromImage(composition))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    foreach (Mark mark in marks) mark.Draw(g, source, mark.Tool == DrawTool.Mosaic ? Mosaic() : null);
                }
                cachedCount = marks.Count;
            }
            return composition;
        }
        public void Paint(Graphics g, Rectangle clip, Rectangle selection, IList<Mark> marks, Mark current)
        {
            clip.Intersect(new Rectangle(Point.Empty, desktop.Size));
            if (clip.IsEmpty) return;
            Select(selection);
            g.DrawImage(dimmed, clip, clip, GraphicsUnit.Pixel);
            Rectangle visible = Rectangle.Intersect(clip, selection);
            if (visible.Width < 1 || visible.Height < 1) return;
            Rectangle local = visible; local.Offset(-selection.X, -selection.Y);
            if (marks.Count > 0) g.DrawImage(Finished(marks), visible, local, GraphicsUnit.Pixel);
            else g.DrawImage(desktop, visible, visible, GraphicsUnit.Pixel);
            if (current != null && current.Tool != DrawTool.Text)
            {
                GraphicsState state = g.Save();
                g.SetClip(visible, CombineMode.Intersect); g.TranslateTransform(selection.X, selection.Y); g.SmoothingMode = SmoothingMode.AntiAlias;
                current.Draw(g, current.Tool == DrawTool.Mosaic ? Source() : desktop, current.Tool == DrawTool.Mosaic ? Mosaic() : null);
                g.Restore(state);
            }
        }
        public Bitmap Export(Rectangle selection, IList<Mark> marks)
        {
            Select(selection);
            return marks.Count == 0 ? desktop.Clone(selection, PixelFormat.Format32bppArgb) : new Bitmap(Finished(marks));
        }
        public void Dispose() { Release(ref dimmed); Release(ref source); Release(ref composition); Release(ref mosaic); }
    }
}
