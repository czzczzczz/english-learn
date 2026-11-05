using Microsoft.Extensions.Logging;
using STranslate.Core;
using STranslate.Helpers;
using System.Drawing;

namespace STranslate.Services;

/// <summary>
/// 协调常驻鼠标划词和增量翻译对全局鼠标 Hook 的共享使用。
/// </summary>
public sealed class MouseSelectionService : IDisposable
{
    private readonly IMouseHookService _mouseHookService;
    private readonly Settings _settings;
    private readonly ILogger<MouseSelectionService> _logger;
    private readonly Func<int, Task<string?>> _getSelectedTextAsync;
    private readonly Func<int, Task<string?>> _getBubbleSelectedTextAsync;
    private readonly Lock _stateLock = new();
    private readonly SemaphoreSlim _captureLock = new(1, 1);
    private bool _directTranslationEnabled;
    private bool _bubbleEnabled;
    private bool _disposed;

    /// <summary>
    /// 初始化鼠标划词协调服务。
    /// </summary>
    /// <param name="mouseHookService">底层全局鼠标 Hook 服务。</param>
    /// <param name="settings">应用配置。</param>
    /// <param name="logger">日志记录器。</param>
    public MouseSelectionService(
        MouseHookService mouseHookService,
        Settings settings,
        ILogger<MouseSelectionService> logger)
        : this(mouseHookService, settings, logger,
              timeout => ClipboardHelper.GetSelectedTextAsync(timeout),
              timeout => SelectionReader.GetSelectedTextAsync(timeout))
    {
    }

    internal MouseSelectionService(
        IMouseHookService mouseHookService,
        Settings settings,
        ILogger<MouseSelectionService> logger,
        Func<int, Task<string?>> getSelectedTextAsync,
        Func<int, Task<string?>>? getBubbleSelectedTextAsync = null)
    {
        _mouseHookService = mouseHookService;
        _settings = settings;
        _logger = logger;
        _getSelectedTextAsync = getSelectedTextAsync;
        _getBubbleSelectedTextAsync = getBubbleSelectedTextAsync ?? getSelectedTextAsync;
        _mouseHookService.SelectionStarted += OnSelectionStarted;
        _mouseHookService.SelectionCompleted += OnSelectionCompleted;
        _mouseHookService.LongPressTriggered += OnLongPressTriggered;
    }

    /// <summary>
    /// 检测到直接翻译模式的选中文本时触发。
    /// </summary>
    public event EventHandler<string>? TextSelected;

    /// <summary>
    /// 鼠标左键开始操作时触发。
    /// </summary>
    public event EventHandler<Point>? SelectionStarted;

    /// <summary>
    /// 气泡模式下完成文本选中时触发，参数为鼠标的物理屏幕坐标。
    /// </summary>
    public event EventHandler<Point>? BubbleRequested;

    /// <summary>
    /// 需要隐藏当前划词气泡时触发。
    /// </summary>
    public event EventHandler? BubbleDismissRequested;

    /// <summary>
    /// 左键长按触发时发生，参数为按下时的物理屏幕坐标。
    /// </summary>
    public event EventHandler<Point>? LongPressTriggered;

    /// <summary>
    /// 常驻鼠标划词功能状态变化时触发。
    /// </summary>
    public event EventHandler? StateChanged;

    /// <summary>
    /// 同步常驻鼠标划词功能状态。
    /// </summary>
    /// <param name="directTranslationEnabled">是否启用划词后直接翻译。</param>
    /// <param name="iconEnabled">是否启用划词后悬浮图标。</param>
    /// <param name="bubbleEnabled">是否启用划词气泡（悬停触发翻译）。</param>
    /// <returns>底层 Hook 是否成功启动。</returns>
    public bool ApplyPersistentFeatures(bool directTranslationEnabled, bool bubbleEnabled = false)
    {
        lock (_stateLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_directTranslationEnabled == directTranslationEnabled
                && _bubbleEnabled == bubbleEnabled)
                return true;

            var shouldRun = directTranslationEnabled || bubbleEnabled;
            if (shouldRun && !_mouseHookService.IsRunning && !_mouseHookService.Start())
                return false;

            _directTranslationEnabled = directTranslationEnabled;
            _bubbleEnabled = bubbleEnabled;
            if (!shouldRun)
                StopHookWhenIdle();
        }

        BubbleDismissRequested?.Invoke(this, EventArgs.Empty);
        StateChanged?.Invoke(this, EventArgs.Empty);
        return true;
    }



    /// <summary>
    /// 用户悬停划词气泡后获取当前选中文本。
    /// 优先走 UI Automation 直接读取选区（不改写剪贴板），失败时回退到模拟复制。
    /// </summary>
    /// <returns>选中的文本；取词失败时返回 null。</returns>
    public async Task<string?> CaptureBubbleSelectedTextAsync()
    {
        if (!CanTranslateFromBubble())
            return null;

        await _captureLock.WaitAsync();
        try
        {
            if (!CanTranslateFromBubble())
                return null;

            var timeout = Math.Max(1, _settings.SelectedTextFetchTimeoutMs);
            var text = await _getBubbleSelectedTextAsync(timeout);
            return CanTranslateFromBubble() ? text?.Trim() : null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to capture selected text for the mouse selection bubble.");
            return null;
        }
        finally
        {
            _captureLock.Release();
        }
    }

    private async Task<string?> CaptureSelectedTextAsync()
    {
        await _captureLock.WaitAsync();
        try
        {
            var timeout = Math.Max(1, _settings.SelectedTextFetchTimeoutMs);
            return await _getSelectedTextAsync(timeout);
        }
        finally
        {
            _captureLock.Release();
        }
    }

    private void OnLongPressTriggered(object? sender, Point point) => LongPressTriggered?.Invoke(this, point);

    private void OnSelectionStarted(object? sender, Point point)
        => SelectionStarted?.Invoke(this, point);

    private void OnSelectionCompleted(object? sender, MouseSelectionCompletedEventArgs e)
    {
        bool directTranslationEnabled;
        bool bubbleEnabled;

        lock (_stateLock)
        {
            directTranslationEnabled = _directTranslationEnabled;
            bubbleEnabled = _bubbleEnabled;
        }

        if (directTranslationEnabled)
        {
            _ = CaptureAndPublishAsync(TextSelected);
            return;
        }

        if (bubbleEnabled)
        {
            // 气泡模式只负责显示气泡，取词与翻译延迟到用户悬停时进行
            _logger.LogDebug("Selection completed in bubble mode at {Point}, requesting bubble.", e.ScreenPoint);
            BubbleRequested?.Invoke(this, e.ScreenPoint);
            return;
        }

    }

    private async Task CaptureAndPublishAsync(EventHandler<string>? handler)
    {
        try
        {
            var text = await CaptureSelectedTextAsync();
            if (!string.IsNullOrWhiteSpace(text))
                handler?.Invoke(this, text);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to capture selected text from the mouse selection workflow.");
        }
    }

    private void StopHookWhenIdle()
    {
        if (!_directTranslationEnabled && !_bubbleEnabled)
            _mouseHookService.Stop();
    }

    private bool CanTranslateFromBubble()
    {
        lock (_stateLock)
            return !_directTranslationEnabled && _bubbleEnabled;
    }

    /// <inheritdoc />
    public void Dispose()
    {
        lock (_stateLock)
        {
            if (_disposed)
                return;

            _disposed = true;
            _directTranslationEnabled = false;
            _bubbleEnabled = false;
        }

        _mouseHookService.SelectionStarted -= OnSelectionStarted;
        _mouseHookService.LongPressTriggered -= OnLongPressTriggered;
        _mouseHookService.SelectionCompleted -= OnSelectionCompleted;
        _mouseHookService.Dispose();
    }
}
