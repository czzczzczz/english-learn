using Microsoft.Extensions.Logging;
using STranslate.Core;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace STranslate.Services;

/// <summary>
/// 用 AI 把生词串成小故事：走 OpenAI 兼容的 /chat/completions 接口，支持中转站地址。
/// 复用宿主的 IHttpService，自动套用系统的代理设置。
/// </summary>
public sealed class StoryService(Settings settings, ILogger<StoryService> logger)
{
    /// <summary>按需创建 HttpClient：配置了代理就走代理，否则直连。</summary>
    private HttpClient CreateClient()
    {
        var handler = new HttpClientHandler();

        var proxy = settings.LlmProxy?.Trim();
        if (!string.IsNullOrWhiteSpace(proxy))
        {
            handler.Proxy = new WebProxy(proxy);
            handler.UseProxy = true;
        }

        return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(90) };
    }

    /// <summary>是否已配置可用的 AI 参数。</summary>
    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(settings.LlmBaseUrl) &&
        !string.IsNullOrWhiteSpace(settings.LlmApiKey) &&
        !string.IsNullOrWhiteSpace(settings.LlmModel);

    /// <summary>
    /// 从中转站拉取可用模型列表。
    /// </summary>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>模型名列表（已排序）。</returns>
    public async Task<IReadOnlyList<string>> GetModelsAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(settings.LlmBaseUrl) || string.IsNullOrWhiteSpace(settings.LlmApiKey))
            throw new InvalidOperationException("请先填写中转站地址和密钥");

        var baseUrl = settings.LlmBaseUrl.Trim().TrimEnd('/');
        var endpoint = baseUrl.EndsWith("/models", StringComparison.OrdinalIgnoreCase)
            ? baseUrl
            : baseUrl + "/models";

        using var client = CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.LlmApiKey.Trim());

        using var response = await client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"接口返回 {(int)response.StatusCode}：{Truncate(body, 160)}");

        using var document = JsonDocument.Parse(body);

        // 兼容 { data: [{id}] } 与 { models: [{id}] } 两种形态
        var array = default(JsonElement);
        if (document.RootElement.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            array = data;
        else if (document.RootElement.TryGetProperty("models", out var models) && models.ValueKind == JsonValueKind.Array)
            array = models;
        else if (document.RootElement.ValueKind == JsonValueKind.Array)
            array = document.RootElement;

        if (array.ValueKind != JsonValueKind.Array)
            throw new InvalidOperationException("接口未返回模型列表");

        var result = new List<string>();
        foreach (var item in array.EnumerateArray())
        {
            if (item.ValueKind == JsonValueKind.String)
            {
                var name = item.GetString();
                if (!string.IsNullOrWhiteSpace(name))
                    result.Add(name.Trim());
                continue;
            }

            if (item.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String)
            {
                var name = id.GetString();
                if (!string.IsNullOrWhiteSpace(name))
                    result.Add(name.Trim());
            }
        }

        result.Sort(StringComparer.OrdinalIgnoreCase);
        logger.LogInformation("中转站返回 {Count} 个模型", result.Count);
        return result;
    }

    /// <summary>
    /// 根据给定生词生成一段英文小故事。
    /// </summary>
    /// <param name="words">要嵌入故事的单词。</param>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>生成的故事文本。</returns>
    public async Task<string> GenerateAsync(IReadOnlyList<string> words, CancellationToken cancellationToken = default)
    {
        if (words.Count == 0)
            throw new InvalidOperationException("生词本里还没有词");

        if (!IsConfigured)
            throw new InvalidOperationException("请先在「常规 → AI 故事」里填写中转站地址、密钥和模型名");

        var baseUrl = settings.LlmBaseUrl.Trim().TrimEnd('/');
        var endpoint = baseUrl.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase)
            ? baseUrl
            : baseUrl + "/chat/completions";

        var payload = new
        {
            model = settings.LlmModel.Trim(),
            temperature = 0.8,
            messages = new object[]
            {
                new { role = "system", content = "You are an English teacher who writes short, natural reading passages for Chinese learners." },
                new { role = "user", content = BuildPrompt(words) }
            }
        };

        using var client = CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.LlmApiKey.Trim());
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogWarning("生成故事失败 {Status}: {Body}", (int)response.StatusCode, Truncate(body, 300));
            throw new InvalidOperationException($"接口返回 {(int)response.StatusCode}：{Truncate(body, 160)}");
        }

        using var document = JsonDocument.Parse(body);
        if (!document.RootElement.TryGetProperty("choices", out var choices) ||
            choices.ValueKind != JsonValueKind.Array ||
            choices.GetArrayLength() == 0)
        {
            logger.LogWarning("生成故事失败，接口返回：{Body}", body.Length > 300 ? body[..300] : body);
            throw new InvalidOperationException("接口未返回内容：" + Truncate(body, 160));
        }

        var content = choices[0].GetProperty("message").GetProperty("content").GetString();
        if (string.IsNullOrWhiteSpace(content))
            throw new InvalidOperationException("接口返回空内容");

        return content.Trim();
    }

    /// <summary>构造提示词：目标词加粗、附中文对照、控制篇幅与难度。</summary>
    private static string BuildPrompt(IReadOnlyList<string> words)
    {
        var list = string.Join(", ", words);

        return $"""
            Write a short English story (150-220 words) that naturally uses ALL of these words: {list}.

            Requirements:
            1. Every target word must appear at least once, wrapped in **double asterisks** like **example**.
            2. Keep the rest of the vocabulary simple (roughly the 3000 most common English words), suitable for a Chinese learner.
            3. Use natural, everyday situations. Do not list the words mechanically.
            4. After the story, add a Chinese translation of the whole story under the heading "中文对照：".
            5. At the very end, add one line starting with "练习：" and two comprehension questions about the story.

            Output plain text only.
            """;
    }

    private static string Truncate(string text, int max) =>
        text.Length <= max ? text : text[..max] + "…";
}
