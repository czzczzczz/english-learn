namespace STranslate.Plugin.Tts.Baidu;

/// <summary>
/// 朗读插件设置：词/句分别走不同的发音源，并允许选择口音与语速。
/// </summary>
public class Settings
{
    /// <summary>口音：US 美音 / UK 英音（仅影响单词朗读）。</summary>
    public string Accent { get; set; } = "US";

    /// <summary>句子朗读语速：0.5 / 0.75 / 1 / 1.25。</summary>
    public string Speed { get; set; } = "1";

    /// <summary>单词朗读音源：Youdao（真人录音）或 Baidu（合成）。</summary>
    public string WordEngine { get; set; } = "Youdao";
}
