using System.Text;
using System.Text.RegularExpressions;

namespace STranslate.Plugin;

/// <summary>
/// 音标体系转换：词典数据统一存 IPA，显示时按用户选择转成 KK 或两套对照。
/// KK 仅适用于美式发音，英式音标保持原样。
/// </summary>
public static partial class PhoneticConverter
{
    /// <summary>IPA（国际音标）。</summary>
    public const string Ipa = "ipa";

    /// <summary>KK（美式音标）。</summary>
    public const string Kk = "kk";

    /// <summary>两者对照。</summary>
    public const string Both = "both";

    /// <summary>默认体系：KK。</summary>
    public const string Default = Kk;

    /// <summary>是否 KK 体系。</summary>
    public static bool IsKk(string? system) =>
        string.Equals(system, Kk, StringComparison.OrdinalIgnoreCase);

    /// <summary>是否对照显示。</summary>
    public static bool IsBoth(string? system) =>
        string.Equals(system, Both, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// 把一段 IPA 音标转成 KK 写法。保留原有定界符（/.../、[...]）。
    /// </summary>
    public static string ToKk(string? ipa)
    {
        if (string.IsNullOrWhiteSpace(ipa))
            return ipa ?? string.Empty;

        var text = ipa;

        // 组合优先，避免被单字符规则拆开
        text = text.Replace("ɜːr", "ɝ", StringComparison.Ordinal)
                   .Replace("ɝː", "ɝ", StringComparison.Ordinal)
                   .Replace("ər", "ɚ", StringComparison.Ordinal)
                   .Replace("ɚː", "ɚ", StringComparison.Ordinal)
                   .Replace("eɪ", "e", StringComparison.Ordinal)
                   .Replace("oʊ", "o", StringComparison.Ordinal)
                   .Replace("əʊ", "o", StringComparison.Ordinal)
                   .Replace("iː", "i", StringComparison.Ordinal)
                   .Replace("uː", "u", StringComparison.Ordinal)
                   .Replace("ɑː", "ɑ", StringComparison.Ordinal)
                   .Replace("ɔː", "ɔ", StringComparison.Ordinal)
                   .Replace("ɜː", "ɜ", StringComparison.Ordinal);

        // 其余长音符号 KK 不用
        return text.Replace("ː", string.Empty, StringComparison.Ordinal);
    }

    /// <summary>按用户选择格式化单个音标。</summary>
    public static string Format(string? ipa, string? system)
    {
        if (string.IsNullOrWhiteSpace(ipa))
            return ipa ?? string.Empty;

        if (IsKk(system))
            return ToKk(ipa);

        if (IsBoth(system))
        {
            var kk = ToKk(ipa);
            return string.Equals(kk, ipa, StringComparison.Ordinal)
                ? ipa
                : $"{kk} · IPA {ipa}";
        }

        return ipa;
    }

    /// <summary>
    /// 在整段文本里查找音标片段并转换。只有形如 /.../ 或 [...] 且含音标字符的片段会被处理，
    /// 避免误伤正文中的斜杠路径。
    /// </summary>
    public static string FormatInText(string? text, string? system)
    {
        if (string.IsNullOrWhiteSpace(text))
            return text ?? string.Empty;

        if (string.IsNullOrEmpty(system) || string.Equals(system, Ipa, StringComparison.OrdinalIgnoreCase))
            return text;

        return PhoneticPattern().Replace(text, match =>
        {
            var token = match.Value;
            if (!ContainsPhoneticChar(token))
                return token;

            // KK 只用于美式：紧跟在「英」标记后的音标保持 IPA
            if (IsBritishPhonetic(text, match.Index))
                return token;

            return Format(token, system);
        });
    }

    /// <summary>判断该音标前是否紧邻「英」标记（英式音标不做 KK 转换）。</summary>
    private static bool IsBritishPhonetic(string text, int index)
    {
        var i = index - 1;
        while (i >= 0 && char.IsWhiteSpace(text[i]))
            i--;

        if (i < 0)
            return false;

        // 向前最多取三个字符，覆盖「英」「英国」「英式」这几种标记
        var start = Math.Max(0, i - 2);
        for (var k = i; k >= start; k--)
        {
            if (text[k] == '英')
                return true;

            // 只在这种短前缀里找，遇到非中文立即停止，避免误判正文
            if (text[k] is not ('国' or '式' or '音' or '：' or ':'))
                break;
        }

        return false;
    }

    /// <summary>判断文本里是否出现音标专用字符。</summary>
    private static bool ContainsPhoneticChar(string token)
    {
        foreach (var c in token)
        {
            if (PhoneticChars.IndexOf(c) >= 0)
                return true;
        }

        return false;
    }

    private const string PhoneticChars =
        "æɑɔəɜɪʊʌθðʃʒŋɝɚːˈˌˈ";

    [GeneratedRegex(@"(\/[^\/\r\n]{1,40}\/|\[[^\]\r\n]{1,40}\])", RegexOptions.Compiled)]
    private static partial Regex PhoneticPattern();
}
