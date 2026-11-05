using System.Net;
using System.Text.RegularExpressions;

namespace STranslate.Plugin.Translate.BingDict;

/// <summary>
/// 必应词典页面解析器：从 cn.bing.com/dict/search 的 HTML 中提取音标、释义与例句。
/// 页面为服务端渲染，无需登录令牌；音频地址在 data-mp3link 属性里，本插件不取音频，
/// 朗读统一交给应用内的语音合成服务处理。
/// </summary>
public static class BingDictParser
{
    /// <summary>音标块，例如 “美 [ˈsæləd]”。</summary>
    private static readonly Regex PronRegex = new(
        @"<div class=""hd_pr[^""]*""[^>]*>(.*?)</div>",
        RegexOptions.Singleline | RegexOptions.Compiled);

    /// <summary>词性 + 释义行（释义内含嵌套标签，取到 li 结束）。</summary>
    private static readonly Regex PosDefRegex = new(
        @"<li>\s*<span class=""pos"">(.*?)</span>\s*<span class=""def[^""]*"">(.*?)</li>",
        RegexOptions.Singleline | RegexOptions.Compiled);

    /// <summary>英文例句。</summary>
    private static readonly Regex SenEnRegex = new(
        @"<div class=""sen_en[^""]*"">(.*?)</div>",
        RegexOptions.Singleline | RegexOptions.Compiled);

    /// <summary>中文例句译文。</summary>
    private static readonly Regex SenCnRegex = new(
        @"<div class=""sen_cn[^""]*"">(.*?)</div>",
        RegexOptions.Singleline | RegexOptions.Compiled);

    /// <summary>词形变化（复数、过去式等）。</summary>
    private static readonly Regex InflectionRegex = new(
        @"<div class=""df_div2"">\s*<span[^>]*>词形</span>\s*<span[^>]*>(.*?)</span>",
        RegexOptions.Singleline | RegexOptions.Compiled);

    /// <summary>
    /// 解析必应词典页面。
    /// </summary>
    /// <param name="html">页面 HTML。</param>
    /// <param name="word">查询词。</param>
    /// <returns>格式化后的释义文本；页面没有词条时返回 null。</returns>
    public static string? Parse(string html, string word)
    {
        if (string.IsNullOrWhiteSpace(html))
            return null;

        var pron = PronRegex.Matches(html)
            .Select(m => Clean(m.Groups[1].Value))
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct()
            .ToList();

        var defs = PosDefRegex.Matches(html)
            .Select(m => (Pos: Clean(m.Groups[1].Value), Def: Clean(m.Groups[2].Value)))
            .Where(x => !string.IsNullOrWhiteSpace(x.Def))
            .ToList();

        if (defs.Count == 0)
            return null;

        var senEn = SenEnRegex.Matches(html).Select(m => Clean(m.Groups[1].Value)).Where(s => s.Length > 0).Take(3).ToList();
        var senCn = SenCnRegex.Matches(html).Select(m => Clean(m.Groups[1].Value)).Where(s => s.Length > 0).Take(3).ToList();

        var sb = new System.Text.StringBuilder();
        sb.AppendLine(word.Trim());
        if (pron.Count > 0)
            sb.AppendLine(string.Join("  ", pron));
        sb.AppendLine();

        foreach (var (pos, def) in defs)
            sb.AppendLine($"{pos} {def}");

        var inflection = InflectionRegex.Match(html);
        if (inflection.Success)
        {
            var text = Clean(inflection.Groups[1].Value);
            if (text.Length > 0)
                sb.AppendLine($"词形：{text}");
        }

        if (senEn.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("例句：");
            for (var i = 0; i < senEn.Count; i++)
            {
                sb.AppendLine(senEn[i]);
                if (i < senCn.Count)
                    sb.AppendLine(senCn[i]);
            }
        }

        return sb.ToString().TrimEnd();
    }

    /// <summary>
    /// 去掉 HTML 标签并还原实体字符。
    /// </summary>
    private static string Clean(string html)
    {
        var text = Regex.Replace(html, "<[^>]+>", string.Empty);
        text = WebUtility.HtmlDecode(text);
        return Regex.Replace(text, @"\s+", " ").Trim();
    }
}
