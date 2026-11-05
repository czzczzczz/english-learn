using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace STranslate.Views;

/// <summary>
/// 全屏框选遮罩：左键长按或热键触发后显示，用户拖出区域即完成，返回物理像素矩形。
/// 粘滞模式：先显示遮罩，用户松手后仍在，需再次按住拖拽来框选。
/// </summary>
public partial class ScreenRegionOverlay : Window
{
    private const double MinSize = 8;

    private readonly TaskCompletionSource<Rectangle?> _completion =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private System.Windows.Point _start;
    private bool _dragging;
    private bool _finished;

    public ScreenRegionOverlay()
    {
        InitializeComponent();

        // 覆盖整个虚拟桌面（含多显示器）
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;

        Loaded += OnLoaded;
        SizeChanged += (_, _) => LayoutStaticElements();
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        MouseRightButtonDown += OnMouseRightButtonDown;
        KeyDown += OnKeyDown;
    }

    /// <summary>等待用户完成框选；取消时结果为 null。</summary>
    public Task<Rectangle?> Completion => _completion.Task;

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded;
        Activate();
        Focus();
        Keyboard.Focus(this);
        LayoutStaticElements();
        UpdateMask(null);
    }

    /// <summary>固定元素（遮罩、提示）铺满整个画布。</summary>
    private void LayoutStaticElements()
    {
        var width = Math.Max(1, PART_Canvas.ActualWidth);
        var height = Math.Max(1, PART_Canvas.ActualHeight);

        PART_Mask.Width = width;
        PART_Mask.Height = height;

        PART_Hint.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(PART_Hint, Math.Max(0, (width - PART_Hint.DesiredSize.Width) / 2));
        Canvas.SetTop(PART_Hint, 28);

        UpdateMask(null);
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _start = e.GetPosition(this);
        _dragging = true;
        CaptureMouse();
        PART_Hint.Visibility = Visibility.Collapsed;
        e.Handled = true;
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (!_dragging)
            return;

        var current = e.GetPosition(this);
        var rect = BuildRect(_start, current);
        UpdateMask(rect);
        e.Handled = true;
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging)
            return;

        _dragging = false;
        ReleaseMouseCapture();
        e.Handled = true;

        var current = e.GetPosition(this);
        var dipRect = BuildRect(_start, current);
        if (dipRect.Width < MinSize || dipRect.Height < MinSize)
        {
            // 太小当作误触，退回等待状态
            UpdateMask(null);
            PART_Hint.Visibility = Visibility.Visible;
            return;
        }

        // 转成物理像素：PointToScreen 直接给出屏幕设备坐标
        var topLeft = PointToScreen(new System.Windows.Point(dipRect.X, dipRect.Y));
        var bottomRight = PointToScreen(new System.Windows.Point(dipRect.Right, dipRect.Bottom));
        var physical = new Rectangle(
            (int)Math.Round(topLeft.X),
            (int)Math.Round(topLeft.Y),
            Math.Max(1, (int)Math.Round(bottomRight.X - topLeft.X)),
            Math.Max(1, (int)Math.Round(bottomRight.Y - topLeft.Y)));

        Finish(physical);
    }

    private void OnMouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        Cancel();
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            e.Handled = true;
            Cancel();
        }
    }

    /// <summary>取消框选。</summary>
    public void Cancel() => Finish(null);

    private void Finish(Rectangle? result)
    {
        if (_finished)
            return;

        _finished = true;
        if (IsMouseCaptured)
            ReleaseMouseCapture();

        try
        {
            Close();
        }
        catch
        {
            // 关闭失败不影响结果传递
        }

        _completion.TrySetResult(result);
    }

    /// <summary>整屏遮罩挖掉选区，边框与尺寸标签用 Canvas 定位，不做布局测量。</summary>
    private void UpdateMask(Rect? selection)
    {
        var width = Math.Max(1, PART_Canvas.ActualWidth);
        var height = Math.Max(1, PART_Canvas.ActualHeight);
        var full = new RectangleGeometry(new Rect(0, 0, width, height));

        if (selection is not { Width: > 0, Height: > 0 } rect)
        {
            PART_Mask.Data = full;
            PART_Selection.Visibility = Visibility.Collapsed;
            PART_SizeLabel.Visibility = Visibility.Collapsed;
            return;
        }

        PART_Mask.Data = new CombinedGeometry(GeometryCombineMode.Exclude, full, new RectangleGeometry(rect));

        PART_Selection.Visibility = Visibility.Visible;
        PART_Selection.Width = Math.Max(0, rect.Width);
        PART_Selection.Height = Math.Max(0, rect.Height);
        Canvas.SetLeft(PART_Selection, rect.X);
        Canvas.SetTop(PART_Selection, rect.Y);

        PART_SizeLabel.Visibility = Visibility.Visible;
        PART_SizeText.Text = $"{Math.Round(rect.Width)} × {Math.Round(rect.Height)}";

        // 标签位置按固定偏移计算，不做 Measure，避免每帧触发布局往返
        var labelTop = rect.Y - 26;
        if (labelTop < 0)
            labelTop = rect.Y + 6;

        Canvas.SetLeft(PART_SizeLabel, Math.Max(0, rect.X));
        Canvas.SetTop(PART_SizeLabel, labelTop);
    }

    private static Rect BuildRect(System.Windows.Point a, System.Windows.Point b)
    {
        var x = Math.Min(a.X, b.X);
        var y = Math.Min(a.Y, b.Y);
        return new Rect(x, y, Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
    }
}
