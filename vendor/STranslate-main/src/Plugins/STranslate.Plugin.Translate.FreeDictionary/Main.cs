using System.Text;
using System.Text.Json;
using System.Windows.Controls;

namespace STranslate.Plugin.Translate.FreeDictionary;

/// <summary>
/// Free Dictionary 插件：免密钥调用 dictionaryapi.dev，返回音标、词性与英文释义。
/// 适合单词语境；整句翻译请交给其它服务。
/// </summary>
public class Main : TranslatePluginBase, IPhoneticAware
{
    private const string Endpoint = "https://api.dictionaryapi.dev/api/v2/entries/en/";

    private const string UserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36";

    private IPluginContext Context { get; set; } = null!;

    /// <inheritdoc />
    public string PhoneticSystem { get; set; } = PhoneticConverter.Default;

    public override Control GetSettingUI() => new ContentControl();

    public override string? GetSourceLanguage(LangEnum langEnum) => "en";

    public override string? GetTargetLanguage(LangEnum langEnum) => "en";

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

        // 只查单词或短语，整句直接交给别的服务
        if (word.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length > 3 || word.Length > 60)
        {
            result.Fail("Free Dictionary 只收录单词与短语，整句请使用其它服务");
            return;
        }

        try
        {
            var url = Endpoint + Uri.EscapeDataString(word.ToLowerInvariant());
            var options = new Options
            {
                Headers = new Dictionary<string, string> { { "User-Agent", UserAgent } }
            };

            var json = await Context.HttpService.GetAsync(url, options, cancellationToken);
            var parsed = Parse(json, word, PhoneticSystem);
            if (string.IsNullOrWhiteSpace(parsed))
            {
                result.Fail($"Free Dictionary 未收录「{word}」");
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
            result.Fail($"Free Dictionary 查询失败：{ex.Message}");
        }
    }

    /// <summary>把词典 JSON 转成「单词 + 音标 + 词性释义」文本。</summary>
    internal static string? Parse(string json, string word, string phoneticSystem)
    {
        if (string.IsNullOrWhiteSpace(json))
            return null;

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Array || document.RootElement.GetArrayLength() == 0)
            return null;

        var entry = document.RootElement[0];

        var phonetic = ReadPhonetic(entry);
        var builder = new StringBuilder();

        builder.Append(word);
        if (!string.IsNullOrWhiteSpace(phonetic))
        {
            builder.Append("  ");
            builder.Append(PhoneticConverter.Format(phonetic, phoneticSystem));
        }

        var meanings = ReadMeanings(entry);
        if (meanings.Count == 0 && phonetic.Length == 0)
            return null;

        foreach (var line in meanings)
        {
            builder.Append('\n');
            builder.Append(line);
        }

        return builder.ToString().Trim();
    }

    private static string ReadPhonetic(JsonElement entry)
    {
        if (entry.TryGetProperty("phonetic", out var direct) && direct.ValueKind == JsonValueKind.String)
        {
            var text = direct.GetString();
            if (!string.IsNullOrWhiteSpace(text))
                return text.Trim();
        }

        if (entry.TryGetProperty("phonetics", out var list) && list.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in list.EnumerateArray())
            {
                if (item.TryGetProperty("text", out var t) && t.ValueKind == JsonValueKind.String)
                {
                    var text = t.GetString();
                    if (!string.IsNullOrWhiteSpace(text))
                        return text.Trim();
                }
            }
        }

        return string.Empty;
    }

    /// <summary>每个词性取前两条释义，最多三个词性。</summary>
    private static List<string> ReadMeanings(JsonElement entry)
    {
        var lines = new List<string>();
        if (!entry.TryGetProperty("meanings", out var meanings) || meanings.ValueKind != JsonValueKind.Array)
            return lines;

        var posCount = 0;
        foreach (var meaning in meanings.EnumerateArray())
        {
            var pos = meaning.TryGetProperty("partOfSpeech", out var p) && p.ValueKind == JsonValueKind.String
                ? p.GetString() ?? string.Empty
                : string.Empty;

            if (!meaning.TryGetProperty("definitions", out var definitions) ||
                definitions.ValueKind != JsonValueKind.Array)
                continue;

            var added = 0;
            foreach (var definition in definitions.EnumerateArray())
            {
                if (!definition.TryGetProperty("definition", out var d) || d.ValueKind != JsonValueKind.String)
                    continue;

                var text = (d.GetString() ?? string.Empty).Trim();
                if (text.Length == 0)
                    continue;

                lines.Add(pos.Length > 0 ? $"{pos}. {text}" : text);
                added++;

                if (added >= 2)
                    break;
            }

            if (added > 0)
            {
                posCount++;
                if (posCount >= 3)
                    break;
            }
        }

        return lines;
    }
}
