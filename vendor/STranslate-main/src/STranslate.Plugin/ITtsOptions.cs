namespace STranslate.Plugin;

/// <summary>
/// 朗读参数读写接口。
/// <para>宿主设置页直接绑定本接口暴露的选项，插件负责持久化，避免依赖插件自绘的设置面板。</para>
/// </summary>
public interface ITtsOptions
{
    /// <summary>单词发音源：Youdao（有道真人录音）或 Baidu（百度合成）。</summary>
    string WordEngine { get; set; }

    /// <summary>口音：US 美音 / UK 英音，仅影响单词朗读。</summary>
    string Accent { get; set; }

    /// <summary>整句语速：0.5 / 0.75 / 1 / 1.25。</summary>
    string Speed { get; set; }

    /// <summary>把当前参数写回插件设置文件。</summary>
    void Save();
}
