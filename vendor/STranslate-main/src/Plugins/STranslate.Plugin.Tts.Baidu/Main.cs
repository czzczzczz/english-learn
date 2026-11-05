using Microsoft.Extensions.Logging;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;

namespace STranslate.Plugin.Tts.Baidu;

/// <summary>
/// 朗读插件：单词走有道真人发音，整句走 Google / 百度合成，自动降级。
/// 相比单纯调用百度 gettts，单词发音更自然、句子语速可调。
/// </summary>
public class Main : ITtsPlugin, ITtsOptions
{
    private const string YoudaoTtsUrl = "https://dict.youdao.com/dictvoice";
    private const string BaiduTtsUrl = "https://fanyi.baidu.com/gettts";

    private const string UserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36";

    /// <summary>判断是否为"单词级"文本：不含句末标点且词数较少。</summary>
    private static readonly Regex SentenceHint = new(@"[.!?;:。！？；：]", RegexOptions.Compiled);

    private IPluginContext Context { get; set; } = null!;
    private Settings Settings { get; set; } = null!;
    private Control? _settingUi;

    public Control GetSettingUI()
    {
        if (_settingUi is not null)
            return _settingUi;

        try
        {
            _settingUi = new View.SettingsView { DataContext = new ViewModel.SettingsViewModel(Context, Settings) };
        }
        catch (Exception ex)
        {
            _settingUi = new ContentControl
            {
                Content = new TextBlock
                {
                    Text = "设置界面加载失败：" + ex.Message,
                    TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(12),
                    Foreground = System.Windows.Media.Brushes.OrangeRed
                }
            };
        }

        return _settingUi;
    }

    public void Init(IPluginContext context)
    {
        Context = context;
        Settings = context.LoadSettingStorage<Settings>();
    }

    public void Dispose() { }

    #region ITtsOptions 宿主设置页直接用这三个属性读写

    /// <summary>单词发音源：Youdao / Baidu。</summary>
    public string WordEngine
    {
        get => Settings.WordEngine;
        set => Settings.WordEngine = value;
    }

    /// <summary>口音：US / UK。</summary>
    public string Accent
    {
        get => Settings.Accent;
        set => Settings.Accent = value;
    }

    /// <summary>整句语速：0.5 / 0.75 / 1 / 1.25。</summary>
    public string Speed
    {
        get => Settings.Speed;
        set => Settings.Speed = value;
    }

    /// <summary>把当前参数落盘。</summary>
    public void Save()
    {
        try
        {
            Context.SaveSettingStorage<Settings>();
        }
        catch (Exception ex)
        {
            Context.Logger.LogWarning(ex, "保存朗读设置失败");
        }
    }

    #endregion

    public async Task PlayAudioAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        var content = text.Trim();
        if (content.Length > 800)
            content = content[..800];

        var audio = IsWord(content)
            ? await TryWordAudioAsync(NormalizeWord(content), cancellationToken)
            : await TrySentenceAudioAsync(content, cancellationToken);

        if (audio is null || audio.Length == 0)
            throw new InvalidOperationException("朗读失败：所有发音源均未返回音频");

        await Context.AudioPlayer.PlayAsync(audio, cancellationToken);
    }

    /// <summary>单词优先用有道真人录音，失败再退回整句引擎。</summary>
    private async Task<byte[]?> TryWordAudioAsync(string word, CancellationToken cancellationToken)
    {
        if (!string.Equals(Settings.WordEngine, "Baidu", StringComparison.OrdinalIgnoreCase))
        {
            var accent = string.Equals(Settings.Accent, "UK", StringComparison.OrdinalIgnoreCase) ? 1 : 2;
            var url = $"{YoudaoTtsUrl}?audio={Uri.EscapeDataString(word)}&type={accent}";
            var youdao = await TryDownloadAsync(url, cancellationToken);
            if (LooksLikeAudio(youdao))
                return youdao;
        }

        return await TrySentenceAudioAsync(word, cancellationToken);
    }

    /// <summary>
    /// 整句发音：先试有道（词库命中短句时是真人录音），未命中再用百度合成。
    /// 有道已无公开的整句合成接口，<c>dictvoice</c> 只返回词库里已有的录音，
    /// 所以长句必然走到百度这一步；Google 那条路国内网络下取不到音频，已移除。
    /// </summary>
    private async Task<byte[]?> TrySentenceAudioAsync(string text, CancellationToken cancellationToken)
    {
        var accent = string.Equals(Settings.Accent, "UK", StringComparison.OrdinalIgnoreCase) ? 1 : 2;
        var youdaoUrl = $"{YoudaoTtsUrl}?audio={Uri.EscapeDataString(text)}&type={accent}";
        var youdao = await TryDownloadAsync(youdaoUrl, cancellationToken);
        if (LooksLikeAudio(youdao))
            return youdao;

        var language = ContainsChinese(text) ? "zh" : "en";
        var speed = ToBaiduSpeed(Settings.Speed);
        var baiduUrl = $"{BaiduTtsUrl}?lan={language}&text={Uri.EscapeDataString(text)}&spd={speed}&source=web";
        var baidu = await TryDownloadAsync(baiduUrl, cancellationToken, referer: "https://fanyi.baidu.com/");
        return LooksLikeAudio(baidu) ? baidu : null;
    }

    /// <summary>把界面上的 0.5 / 0.75 / 1 / 1.25 语速映射为百度接口的 1-9 档。</summary>
    private static string ToBaiduSpeed(string? speed)
    {
        var value = double.TryParse(speed, out var parsed) ? parsed : 1.0;
        return value switch
        {
            <= 0.6 => "2",
            <= 0.85 => "3",
            <= 1.05 => "5",
            <= 1.15 => "6",
            _ => "7"
        };
    }

    /// <summary>
    /// 判断返回的字节是不是真的音频。
    /// 有道对查不到的整句会返回 120 字节的 JSON 错误体，只看长度会被误判成音频。
    /// </summary>
    private static bool LooksLikeAudio(byte[]? data)
    {
        if (data is not { Length: > 512 })
            return false;

        // ID3 头 / MPEG 帧同步 / RIFF(WAV) / OggS / ftyp(M4A)
        if (data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33)
            return true;
        if (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0)
            return true;
        if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46)
            return true;
        if (data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53)
            return true;

        return false;
    }

    /// <summary>下载音频字节，失败返回 null（由调用方降级）。</summary>
    private async Task<byte[]?> TryDownloadAsync(string url, CancellationToken cancellationToken, string? referer = null)
    {
        try
        {
            var headers = new Dictionary<string, string> { { "User-Agent", UserAgent } };
            if (referer is not null)
                headers["Referer"] = referer;

            var options = new Options { Headers = headers };
            var data = await Context.HttpService.GetAsBytesAsync(url, options, cancellationToken);
            return data is { Length: > 0 } ? data : null;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>单词两端需要剔除的标点。</summary>
    private static readonly char[] WordPunctuation =
        [',', '.', ';', ':', '!', '?', '"', '(', ')', '[', ']', '{', '}', '。', '，', '！', '？', '；', '：'];

    /// <summary>去掉单词两端的标点，避免取词带逗号/句号导致发音源查不到。</summary>
    private static string NormalizeWord(string text)
    {
        var trimmed = text.Trim().Trim(WordPunctuation);
        return string.IsNullOrWhiteSpace(trimmed) ? text.Trim() : trimmed;
    }

    /// <summary>词数 ≤ 3 且没有句末标点，视为单词发音。</summary>
    private static bool IsWord(string text)
    {
        if (SentenceHint.IsMatch(text))
            return false;

        var parts = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length <= 3 && text.Length <= 40;
    }

    private static bool ContainsChinese(string text)
    {
        foreach (var ch in text)
        {
            if (ch >= 0x4E00 && ch <= 0x9FFF)
                return true;
        }

        return false;
    }
}
