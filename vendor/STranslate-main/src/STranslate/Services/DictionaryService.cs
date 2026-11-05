using Microsoft.Extensions.Logging;
using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace STranslate.Services;

/// <summary>
/// 免密钥词典查询（dictionaryapi.dev）：给生词本补音标与英文释义。
/// </summary>
public sealed class DictionaryService(ILogger<DictionaryService> logger)
{
    private const string Endpoint = "https://api.dictionaryapi.dev/api/v2/entries/en/";

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36");
        return client;
    }

    /// <summary>
    /// 查询单词的音标与释义。
    /// </summary>
    /// <param name="word">待查单词或短语。</param>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>查到返回结果，查不到或失败返回 null。</returns>
    public async Task<DictionaryInfo?> LookupAsync(string word, CancellationToken cancellationToken = default)
    {
        var query = (word ?? string.Empty).Trim();
        if (query.Length == 0 || query.Length > 60)
            return null;

        // 整句不查词典，避免无意义请求
        if (query.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length > 3)
            return null;

        try
        {
            var url = Endpoint + Uri.EscapeDataString(query.ToLowerInvariant());
            using var response = await Http.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode)
                return null;

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

            if (document.RootElement.ValueKind != JsonValueKind.Array || document.RootElement.GetArrayLength() == 0)
                return null;

            var first = document.RootElement[0];

            var phonetic = ReadPhonetic(first);
            var meaning = ReadMeaning(first);

            if (phonetic.Length == 0 && meaning.Length == 0)
                return null;

            logger.LogDebug("词典命中 {Word}: 音标='{Phonetic}' 释义长度={Len}", query, phonetic, meaning.Length);
            return new DictionaryInfo(phonetic, meaning);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "查询词典失败：{Word}", query);
            return null;
        }
    }

    /// <summary>优先取顶层 phonetic，其次取 phonetics 数组里的首个文本。</summary>
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

    /// <summary>取前两条释义，拼成「词性. 解释」的多行文本。</summary>
    private static string ReadMeaning(JsonElement entry)
    {
        if (!entry.TryGetProperty("meanings", out var meanings) || meanings.ValueKind != JsonValueKind.Array)
            return string.Empty;

        var lines = new List<string>();
        foreach (var meaning in meanings.EnumerateArray())
        {
            var pos = meaning.TryGetProperty("partOfSpeech", out var p) && p.ValueKind == JsonValueKind.String
                ? p.GetString() ?? string.Empty
                : string.Empty;

            if (!meaning.TryGetProperty("definitions", out var definitions) ||
                definitions.ValueKind != JsonValueKind.Array)
                continue;

            foreach (var definition in definitions.EnumerateArray())
            {
                if (!definition.TryGetProperty("definition", out var d) || d.ValueKind != JsonValueKind.String)
                    continue;

                var text = (d.GetString() ?? string.Empty).Trim();
                if (text.Length == 0)
                    continue;

                lines.Add(pos.Length > 0 ? $"{pos}. {text}" : text);
                break;
            }

            if (lines.Count >= 2)
                break;
        }

        return string.Join('\n', lines);
    }
}

/// <summary>词典查询结果。</summary>
/// <param name="Phonetic">音标，可能为空。</param>
/// <param name="Meaning">英文释义，可能为空。</param>
public sealed record DictionaryInfo(string Phonetic, string Meaning);
