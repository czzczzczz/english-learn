using System.Windows;

namespace STranslate.Helpers;

/// <summary>
/// 剪贴板快照：在模拟复制取词前记录剪贴板内容，取词完成后恢复，避免污染用户剪贴板。
/// WPF 剪贴板 API 需要 STA 线程，因此内部用独立 STA 线程执行读写。
/// </summary>
public sealed class ClipboardSnapshot
{
    private readonly Dictionary<string, object> _values;
    private readonly bool _captured;

    private ClipboardSnapshot(Dictionary<string, object> values, bool captured)
    {
        _values = values;
        _captured = captured;
    }

    /// <summary>
    ///     记录当前剪贴板内容。
    /// </summary>
    /// <returns>剪贴板快照；读取失败时返回空快照（<see cref="Restore"/> 不做任何事）。</returns>
    public static ClipboardSnapshot Capture()
    {
        try
        {
            var values = RunOnStaThread(() =>
            {
                var result = new Dictionary<string, object>();
                var dataObject = Clipboard.GetDataObject();
                if (dataObject is null)
                    return result;

                foreach (var format in dataObject.GetFormats(autoConvert: false))
                {
                    try
                    {
                        var value = dataObject.GetData(format, autoConvert: false);
                        if (value is not null)
                            result[format] = value;
                    }
                    catch (Exception)
                    {
                        // 单个格式读取失败不影响其它格式
                    }
                }

                return result;
            });

            return new ClipboardSnapshot(values, values.Count > 0);
        }
        catch (Exception)
        {
            return new ClipboardSnapshot([], false);
        }
    }

    /// <summary>
    ///     把快照内容写回剪贴板；没有可恢复内容时静默跳过。
    /// </summary>
    public void Restore()
    {
        if (!_captured || _values.Count == 0)
            return;

        try
        {
            RunOnStaThread(() =>
            {
                var dataObject = new DataObject();
                foreach (var (format, value) in _values)
                {
                    try
                    {
                        dataObject.SetData(format, value);
                    }
                    catch (Exception)
                    {
                        // 单个格式写回失败不影响其它格式
                    }
                }

                Clipboard.SetDataObject(dataObject, copy: true);
                return true;
            });
        }
        catch (Exception)
        {
            // 恢复失败不阻塞取词链路，最坏情况是剪贴板停留在选中的文本
        }
    }

    /// <summary>
    ///     在独立 STA 线程上执行剪贴板操作。
    /// </summary>
    /// <param name="func">要执行的剪贴板操作。</param>
    /// <returns>操作返回值。</returns>
    private static T RunOnStaThread<T>(Func<T> func)
    {
        T result = default!;
        Exception? error = null;
        var thread = new Thread(() =>
        {
            try
            {
                result = func();
            }
            catch (Exception ex)
            {
                error = ex;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
        thread.Join(3000);

        if (error is not null)
            throw error;

        return result;
    }
}
