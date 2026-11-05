using STranslate.Helpers;
using System.Drawing;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

using DrawingPoint = System.Drawing.Point;

namespace STranslate.Views;

/// <summary>
/// 划词气泡窗口：选中文本后在光标旁出现，鼠标悬停达到延迟后自动触发翻译。
/// 与悬浮图标窗口的区别是：气泡不需要点击，悬停即翻译，也不显示在任务栏与 Alt+Tab 中。
/// </summary>
public partial class MouseSelectionBubbleWindow : Window
{
    private const int BubbleOffset = 12;
    private const double InitialBubbleScale = 0.86;
    private static readonly Duration ShowAnimationDuration = TimeSpan.FromMilliseconds(140);
    private static readonly TimeSpan AutoHideDelay = TimeSpan.FromSeconds(4);

    private readonly DispatcherTimer _hideTimer;
    private readonly DispatcherTimer _hoverTimer;
    private int _showRequestId;

    /// <summary>
    /// 用户悬停达到延迟（或点击）后触发，表示可以执行取词与翻译。
    /// </summary>
    public event EventHandler? HoverCompleted;

    /// <summary>
    /// 悬停触发翻译的延迟，由调用方按用户设置同步。
    /// </summary>
    public int HoverDelayMs { get; set; } = 300;

    /// <summary>
    /// 初始化划词气泡窗口。
    /// </summary>
    public MouseSelectionBubbleWindow()
    {
        InitializeComponent();

        _hideTimer = new DispatcherTimer { Interval = AutoHideDelay };
        _hideTimer.Tick += (_, _) => HideWindow();

        _hoverTimer = new DispatcherTimer();
        _hoverTimer.Tick += OnHoverTimerTick;

        MouseEnter += OnBubbleMouseEnter;
        MouseLeave += OnBubbleMouseLeave;
        BubbleBody.MouseLeftButtonUp += OnBubbleMouseLeftButtonUp;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        // 关键：加上 WS_EX_NOACTIVATE，气泡出现与悬停都不抢焦点，用户在别的软件里继续打字不受影响
        var hwnd = new HWND(new WindowInteropHelper(this).Handle);
        var extendedStyle = (WINDOW_EX_STYLE)(uint)PInvoke.GetWindowLongPtr(
            hwnd,
            WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
        PInvoke.SetWindowLongPtr(
            hwnd,
            WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE,
            (nint)(extendedStyle | WINDOW_EX_STYLE.WS_EX_NOACTIVATE));
    }

    /// <summary>
    /// 在指定的物理屏幕坐标附近显示气泡，并自动避让屏幕边缘。
    /// </summary>
    /// <param name="point">鼠标的物理屏幕坐标。</param>
    public void ShowAt(System.Windows.Point point)
    {
        var physicalPoint = new DrawingPoint((int)Math.Round(point.X), (int)Math.Round(point.Y));
        var monitor = MonitorInfo.GetDisplayMonitors()
            .FirstOrDefault(item => item.Bounds.Contains(point)) ?? MonitorInfo.GetCursorDisplayMonitor();
        var dpi = Win32Helper.GetDpiScaleForPhysicalPoint(physicalPoint.X, physicalPoint.Y);
        var physicalWidth = Math.Max(1, (int)Math.Round(Width * dpi.DpiScaleX));
        var physicalHeight = Math.Max(1, (int)Math.Round(Height * dpi.DpiScaleY));
        var offsetX = (int)Math.Round(BubbleOffset * dpi.DpiScaleX);
        var offsetY = (int)Math.Round(BubbleOffset * dpi.DpiScaleY);
        var workArea = new Rectangle(
            (int)Math.Round(monitor.WorkingArea.Left),
            (int)Math.Round(monitor.WorkingArea.Top),
            (int)Math.Round(monitor.WorkingArea.Width),
            (int)Math.Round(monitor.WorkingArea.Height));

        var left = physicalPoint.X + offsetX;
        var top = physicalPoint.Y + offsetY;
        if (left + physicalWidth > workArea.Right)
            left = physicalPoint.X - physicalWidth - offsetX;
        if (top + physicalHeight > workArea.Bottom)
            top = physicalPoint.Y - physicalHeight - offsetY;

        left = Math.Clamp(left, workArea.Left, workArea.Right - physicalWidth);
        top = Math.Clamp(top, workArea.Top, workArea.Bottom - physicalHeight);

        var showRequestId = ++_showRequestId;
        StopShowAnimation();
        PrepareContentForShow();
        Win32Helper.SetWindowCloaked(this, cloaked: true);
        Left = left / dpi.DpiScaleX;
        Top = top / dpi.DpiScaleY;
        Win32Helper.SetWindowPhysicalBounds(this, left, top, physicalWidth, physicalHeight, showWindow: false);
        Show();
        RestartHideTimer();
        _ = Dispatcher.InvokeAsync(
            () => RevealAndAnimate(showRequestId),
            DispatcherPriority.Loaded);
    }

    /// <summary>
    /// 隐藏当前气泡。
    /// </summary>
    public void HideWindow()
    {
        _showRequestId++;
        _hideTimer.Stop();
        _hoverTimer.Stop();
        if (!IsVisible)
            return;

        Win32Helper.SetWindowCloaked(this, cloaked: true);
        StopShowAnimation();
        Hide();
    }

    /// <summary>
    /// 判断物理屏幕坐标是否位于当前气泡窗口内，用于区分"点气泡"和"点别处"。
    /// </summary>
    /// <param name="point">物理屏幕坐标。</param>
    /// <returns>窗口可见且坐标位于窗口内时返回 true。</returns>
    public bool ContainsPhysicalPoint(DrawingPoint point)
    {
        if (!IsVisible)
            return false;

        var hwnd = new HWND(new WindowInteropHelper(this).Handle);
        return PInvoke.GetWindowRect(hwnd, out var bounds) &&
               point.X >= bounds.left &&
               point.X < bounds.right &&
               point.Y >= bounds.top &&
               point.Y < bounds.bottom;
    }

    /// <summary>
    /// 鼠标进入气泡：停止自动隐藏，开始悬停计时。
    /// </summary>
    private void OnBubbleMouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _hideTimer.Stop();
        _hoverTimer.Stop();
        _hoverTimer.Interval = TimeSpan.FromMilliseconds(Math.Clamp(HoverDelayMs, 100, 2000));
        _hoverTimer.Start();
    }

    /// <summary>
    /// 鼠标离开气泡：取消悬停计时并重新开始自动隐藏倒计时。
    /// </summary>
    private void OnBubbleMouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _hoverTimer.Stop();
        RestartHideTimer();
    }

    /// <summary>
    /// 悬停计时结束：视为用户确认翻译，先收起气泡再通知外部取词。
    /// </summary>
    private void OnHoverTimerTick(object? sender, EventArgs e)
    {
        _hoverTimer.Stop();
        HideWindow();
        HoverCompleted?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// 点击气泡：立即翻译，不等悬停延迟。
    /// </summary>
    private void OnBubbleMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        _hoverTimer.Stop();
        HideWindow();
        HoverCompleted?.Invoke(this, EventArgs.Empty);
    }

    private void RestartHideTimer()
    {
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    private void RevealAndAnimate(int showRequestId)
    {
        if (showRequestId != _showRequestId || !IsVisible)
            return;

        Win32Helper.FlushDesktopComposition();
        StartShowAnimation();
        Win32Helper.SetWindowCloaked(this, cloaked: false);
    }

    private void PrepareContentForShow()
    {
        BubbleRoot.Opacity = 0;
        BubbleScaleTransform.ScaleX = InitialBubbleScale;
        BubbleScaleTransform.ScaleY = InitialBubbleScale;
    }

    private void StartShowAnimation()
    {
        var showRequestId = _showRequestId;
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
        var opacityAnimation = CreateShowAnimation(0, 1, easing);
        opacityAnimation.Completed += (_, _) =>
        {
            if (showRequestId == _showRequestId && IsVisible)
            {
                BubbleRoot.Opacity = 1;
                BubbleScaleTransform.ScaleX = 1;
                BubbleScaleTransform.ScaleY = 1;
                StopShowAnimation();
            }
        };

        BubbleRoot.BeginAnimation(OpacityProperty, opacityAnimation, HandoffBehavior.SnapshotAndReplace);
        BubbleScaleTransform.BeginAnimation(
            ScaleTransform.ScaleXProperty,
            CreateShowAnimation(InitialBubbleScale, 1, easing),
            HandoffBehavior.SnapshotAndReplace);
        BubbleScaleTransform.BeginAnimation(
            ScaleTransform.ScaleYProperty,
            CreateShowAnimation(InitialBubbleScale, 1, easing),
            HandoffBehavior.SnapshotAndReplace);
    }

    private void StopShowAnimation()
    {
        BubbleRoot.BeginAnimation(OpacityProperty, null);
        BubbleScaleTransform.BeginAnimation(ScaleTransform.ScaleXProperty, null);
        BubbleScaleTransform.BeginAnimation(ScaleTransform.ScaleYProperty, null);
    }

    private static DoubleAnimation CreateShowAnimation(double from, double to, IEasingFunction easing)
        => new(from, to, ShowAnimationDuration)
        {
            EasingFunction = easing,
            FillBehavior = FillBehavior.HoldEnd
        };
}
