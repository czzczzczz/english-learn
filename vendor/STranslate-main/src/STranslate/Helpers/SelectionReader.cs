using System.Windows.Automation;

namespace STranslate.Helpers;

/// <summary>
/// 选中文本读取器：优先通过 UI Automation 直接读取当前选区，失败时回退到模拟复制。
/// 这样日常在浏览器、Word、记事本等支持 UIA 的软件中划词时不会改写用户剪贴板。
/// </summary>
public static class SelectionReader
{
    /// <summary>
    /// 读取当前选中的文本。
    /// </summary>
    /// <param name="timeoutMs">回退到模拟复制时的等待超时（毫秒）。</param>
    /// <returns>选中的文本；两种方式都取不到时返回 null。</returns>
    public static async Task<string?> GetSelectedTextAsync(int timeoutMs)
    {
        var uiaText = await TryGetTextFromUiaAsync();
        if (!string.IsNullOrWhiteSpace(uiaText))
            return uiaText.Trim();

        // UIA 取不到（游戏、自绘控件、远程桌面等）才回退到模拟 Ctrl+C，
        // 回退前先做剪贴板快照，取词后立刻恢复，避免覆盖用户原有剪贴板内容
        var snapshot = ClipboardSnapshot.Capture();
        try
        {
            return await ClipboardHelper.GetSelectedTextAsync(timeoutMs);
        }
        finally
        {
            snapshot.Restore();
        }
    }

    /// <summary>
    /// 尝试用 UI Automation 读取焦点控件的文本选区。
    /// </summary>
    /// <returns>选区文本；不支持或读取失败时返回 null。</returns>
    private static async Task<string?> TryGetTextFromUiaAsync()
    {
        // UIA 调用是跨进程 COM 操作，可能阻塞，放到线程池执行，避免卡住 UI 线程
        return await Task.Run(() =>
        {
            try
            {
                var element = AutomationElement.FocusedElement;
                if (element is null)
                    return null;

                if (!element.TryGetCurrentPattern(TextPattern.Pattern, out var patternObj)
                    || patternObj is not TextPattern textPattern)
                    return null;

                var ranges = textPattern.GetSelection();
                if (ranges.Length == 0)
                    return null;

                var text = ranges[0].GetText(-1);
                return string.IsNullOrWhiteSpace(text) ? null : text;
            }
            catch (Exception)
            {
                // UIA 在部分进程（受保护进程、已退出进程）会抛异常，视为不支持，交由调用方回退
                return null;
            }
        });
    }
}
