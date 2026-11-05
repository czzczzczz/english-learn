using Microsoft.Extensions.Logging;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace STranslate.Services;

/// <summary>
/// 图像文字识别：优先用系统内置 OCR（离线、免密钥），识别不到时做反色与放大重试。
/// </summary>
public sealed class OcrService(ILogger<OcrService> logger)
{
    /// <summary>
    /// 识别图片中的文字。原图失败时依次尝试反色、放大。
    /// </summary>
    /// <param name="bitmap">待识别的位图。</param>
    /// <param name="preferChinese">是否优先用中文引擎（中英混排更稳）。</param>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>识别到的文本；全部失败返回空字符串。</returns>
    public async Task<string> RecognizeAsync(Bitmap bitmap, bool preferChinese = true, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(bitmap);

        var original = await TryRecognizeWithSystemAsync(bitmap, preferChinese, cancellationToken);
        if (!string.IsNullOrWhiteSpace(original))
            return original;

        // 深色背景白字：反色后重试
        using (var inverted = Invert(bitmap))
        {
            var text = await TryRecognizeWithSystemAsync(inverted, preferChinese, cancellationToken);
            if (!string.IsNullOrWhiteSpace(text))
            {
                logger.LogInformation("OCR 反色重试成功（{Chars} 字符）。", text.Length);
                return text;
            }
        }

        // 小字：放大 2 倍后重试
        using (var scaled = Scale(bitmap, 2.0))
        {
            var text = await TryRecognizeWithSystemAsync(scaled, preferChinese, cancellationToken);
            if (!string.IsNullOrWhiteSpace(text))
            {
                logger.LogInformation("OCR 放大重试成功（{Chars} 字符）。", text.Length);
                return text;
            }
        }

        logger.LogWarning("OCR 三次尝试均未识别到文字（{W}x{H}）。", bitmap.Width, bitmap.Height);
        return string.Empty;
    }

    /// <summary>用 Windows 内置 OCR 引擎识别一次。</summary>
    private async Task<string?> TryRecognizeWithSystemAsync(Bitmap bitmap, bool preferChinese, CancellationToken cancellationToken)
    {
        try
        {
            var language = ResolveLanguage(preferChinese);
            var engine = (language is null ? null : OcrEngine.TryCreateFromLanguage(language))
                         ?? OcrEngine.TryCreateFromUserProfileLanguages();

            if (engine is null)
            {
                logger.LogWarning("系统 OCR 引擎不可用（缺少识别语言包）。");
                return null;
            }

            using var buffer = new MemoryStream();
            bitmap.Save(buffer, ImageFormat.Png);
            buffer.Position = 0;

            using var randomAccessStream = buffer.AsRandomAccessStream();
            var decoder = await BitmapDecoder.CreateAsync(randomAccessStream).AsTask(cancellationToken);
            using var softwareBitmap = await decoder.GetSoftwareBitmapAsync().AsTask(cancellationToken);

            var result = await engine.RecognizeAsync(softwareBitmap).AsTask(cancellationToken);
            var text = result.Text;

            if (string.IsNullOrWhiteSpace(text))
                return null;

            logger.LogDebug("系统 OCR 识别 {Chars} 字符，语言 {Lang}。", text.Length, engine.RecognizerLanguage.LanguageTag);
            return text;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "系统 OCR 识别失败。");
            return null;
        }
    }

    /// <summary>按偏好挑选已安装的识别语言。</summary>
    private static Windows.Globalization.Language? ResolveLanguage(bool preferChinese)
    {
        var available = OcrEngine.AvailableRecognizerLanguages;
        if (available.Count == 0)
            return null;

        var wantedPrefix = preferChinese ? "zh" : "en";

        foreach (var language in available)
        {
            if (language.LanguageTag.StartsWith(wantedPrefix, StringComparison.OrdinalIgnoreCase))
                return language;
        }

        return available[0];
    }

    /// <summary>生成反色副本（深色背景转白底黑字）。</summary>
    private static Bitmap Invert(Bitmap source)
    {
        var result = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(result);
        using var attributes = new ImageAttributes();
        attributes.SetColorMatrix(new ColorMatrix([
            [-1, 0, 0, 0, 0],
            [0, -1, 0, 0, 0],
            [0, 0, -1, 0, 0],
            [0, 0, 0, 1, 0],
            [1, 1, 1, 0, 1]
        ]));
        graphics.DrawImage(source,
            new Rectangle(0, 0, source.Width, source.Height),
            0, 0, source.Width, source.Height, GraphicsUnit.Pixel, attributes);
        return result;
    }

    /// <summary>等比放大，用高质量插值减少锯齿。</summary>
    private static Bitmap Scale(Bitmap source, double factor)
    {
        var width = Math.Max(1, (int)Math.Round(source.Width * factor));
        var height = Math.Max(1, (int)Math.Round(source.Height * factor));
        var result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(result);
        graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        graphics.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        graphics.DrawImage(source, new Rectangle(0, 0, width, height));
        return result;
    }

    /// <summary>当前系统可用的 OCR 语言标签，便于设置页展示。</summary>
    public static IReadOnlyList<string> GetAvailableLanguages()
    {
        try
        {
            return [.. OcrEngine.AvailableRecognizerLanguages.Select(l => l.LanguageTag)];
        }
        catch
        {
            return [];
        }
    }
}
