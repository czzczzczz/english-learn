using System.Windows.Controls;

namespace STranslate.Plugin.Translate.BingDict;

/// <summary>
/// 必应词典插件：无需密钥，直接查询 cn.bing.com/dict 页面并解析音标、释义和例句。
/// 适合单词查询；句子翻译请使用应用内其它翻译服务。
/// </summary>
public class Main : TranslatePluginBase, IPhoneticAware
{
    private const string DictUrl = "https://cn.bing.com/dict/search";

    private const string UserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36";

    private IPluginContext Context { get; set; } = null!;

    /// <inheritdoc />
    public string PhoneticSystem { get; set; } = PhoneticConverter.Default;

    public override Control GetSettingUI() => new ContentControl();

    public override string? GetSourceLanguage(LangEnum langEnum) => langEnum switch
    {
        LangEnum.Auto => "auto",
        LangEnum.ChineseSimplified => "zh-CN",
        LangEnum.English => "en",
        _ => "auto"
    };

    public override string? GetTargetLanguage(LangEnum langEnum) => langEnum switch
    {
        LangEnum.Auto => "auto",
        LangEnum.ChineseSimplified => "zh-CN",
        LangEnum.English => "en",
        _ => "auto"
    };

    public override void Init(IPluginContext context) => Context = context;

    public override void Dispose() { }

    public override async Task TranslateAsync(TranslateRequest request, TranslateResult result, CancellationToken cancellationToken = default)
    {
        var word = request.Text?.Trim();
        if (string.IsNullOrWhiteSpace(word))
        {
            result.Fail("查询内容为空");
            return;
        }

        try
        {
            var options = new Options
            {
                QueryParams = new Dictionary<string, string>
                {
                    { "q", word },
                    { "mkt", "zh-CN" },
                    { "setlang", "zh-Hans" }
                },
                Headers = new Dictionary<string, string>
                {
                    { "User-Agent", UserAgent },
                    { "Accept-Language", "zh-CN,zh;q=0.9" }
                }
            };

            var html = await Context.HttpService.GetAsync(DictUrl, options, cancellationToken);
            var parsed = BingDictParser.Parse(html, word);

            // 音标按用户选择的体系输出（默认 KK）
            parsed = PhoneticConverter.FormatInText(parsed, PhoneticSystem);
            if (string.IsNullOrWhiteSpace(parsed))
            {
                result.Fail($"必应词典未收录「{word}」，句子翻译请使用其它服务");
                return;
            }

            result.Success(parsed);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            result.Fail($"必应词典查询失败：{ex.Message}");
        }
    }
}
