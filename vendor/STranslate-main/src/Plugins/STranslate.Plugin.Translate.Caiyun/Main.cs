using STranslate.Plugin.Translate.Caiyun.View;
using STranslate.Plugin.Translate.Caiyun.ViewModel;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace STranslate.Plugin.Translate.Caiyun;

/// <summary>
/// 彩云小译插件：调用官方翻译接口，需要 token（默认内置一个测试 token，可在插件设置里替换）。
/// 接口：POST https://api.interpreter.caiyunai.com/v1/translator
/// 鉴权：请求头 x-authorization: token &lt;token&gt;
/// </summary>
public class Main : TranslatePluginBase
{
    private const string Endpoint = "https://api.interpreter.caiyunai.com/v1/translator";

    /// <summary>默认测试 token，可在设置里替换成自己的 token。</summary>
    private const string DefaultToken = "3975l6lr5pcbvidl6jl2";

    private IPluginContext Context { get; set; } = null!;
    private Settings Settings { get; set; } = null!;
    private Control? _settingUi;

    public override Control GetSettingUI()
    {
        if (_settingUi is not null)
            return _settingUi;

        try
        {
            _settingUi = new SettingsView { DataContext = new SettingsViewModel(Context, Settings) };
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

    public override string? GetSourceLanguage(LangEnum langEnum) => MapLang(langEnum, asSource: true);

    public override string? GetTargetLanguage(LangEnum langEnum) => MapLang(langEnum, asSource: false);

    public override void Init(IPluginContext context)
    {
        Context = context;
        Settings = context.LoadSettingStorage<Settings>();
    }

    public override void Dispose() { }

    public override async Task TranslateAsync(TranslateRequest request, TranslateResult result, CancellationToken cancellationToken = default)
    {
        var text = request.Text?.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            result.Fail("翻译内容为空");
            return;
        }

        var from = GetSourceLanguage(request.SourceLang) ?? "auto";
        var to = GetTargetLanguage(request.TargetLang) ?? "zh";
        var detect = from == "auto";
        var transType = detect ? $"auto2{to}" : $"{from}2{to}";

        try
        {
            var payload = new
            {
                source = text.Split('\n'),
                trans_type = transType,
                request_id = Guid.NewGuid().ToString("N"),
                detect
            };

            var options = new Options
            {
                Headers = new Dictionary<string, string>
                {
                    { "x-authorization", "token " + Settings.EffectiveToken },
                    { "Origin", "https://fanyi.caiyunapp.com" },
                    { "Referer", "https://fanyi.caiyunapp.com/" }
                }
            };

            var response = await Context.HttpService.PostAsync(Endpoint, payload, options, cancellationToken);
            using var json = JsonDocument.Parse(response);

            if (json.RootElement.TryGetProperty("target", out var targetElement)
                && targetElement.ValueKind == JsonValueKind.Array)
            {
                var lines = targetElement.EnumerateArray()
                    .Select(item => item.GetString())
                    .Where(item => !string.IsNullOrWhiteSpace(item))
                    .ToList();

                if (lines.Count > 0)
                {
                    result.Success(string.Join("\n", lines));
                    return;
                }
            }

            // 服务端可能返回错误信息
            var message = json.RootElement.TryGetProperty("message", out var msgElement)
                ? msgElement.GetString()
                : "彩云返回数据异常";
            result.Fail($"彩云小译：{message}");
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            result.Fail($"彩云小译请求失败：{ex.Message}");
        }
    }

    /// <summary>
    /// 把应用的语言枚举映射为彩云支持的代码（auto / zh / en / ja）。
    /// </summary>
    private static string? MapLang(LangEnum langEnum, bool asSource)
    {
        return langEnum switch
        {
            LangEnum.Auto => asSource ? "auto" : "zh",
            LangEnum.ChineseSimplified => "zh",
            LangEnum.ChineseTraditional => "zh",
            LangEnum.English => "en",
            LangEnum.Japanese => "ja",
            _ => asSource ? "auto" : "zh"
        };
    }
}
