using System.Text.Json.Serialization;

namespace STranslate.Core;

/// <summary>
/// 生词本词条：一个单词/短语一行，内置存储在 PortableConfig/Settings/Vocabulary.json。
/// </summary>
public class VocabularyEntry
{
    /// <summary>去重键：小写、去首尾空白，重复加入时只更新不新增。</summary>
    public string Key { get; set; } = string.Empty;

    /// <summary>原始形态，用于显示与朗读。</summary>
    public string Display { get; set; } = string.Empty;

    /// <summary>音标，可空。</summary>
    public string Phonetic { get; set; } = string.Empty;

    /// <summary>简短释义，可空。</summary>
    public string Meaning { get; set; } = string.Empty;

    /// <summary>译文/例句笔记，可空。</summary>
    public string Note { get; set; } = string.Empty;

    /// <summary>来源服务名，便于回溯。</summary>
    public string Source { get; set; } = string.Empty;

    /// <summary>加入时间。</summary>
    public DateTime CreatedAt { get; set; } = DateTime.Now;

    /// <summary>最近一次复习时间。</summary>
    public DateTime? LastReviewedAt { get; set; }

    /// <summary>复习次数。</summary>
    public int ReviewCount { get; set; }

    /// <summary>熟练度 0 到 5，数字越大下次复习间隔越长。</summary>
    public int Level { get; set; }

    /// <summary>下次该复习的时间，为空表示尚未安排。</summary>
    public DateTime? NextReviewAt { get; set; }

    /// <summary>界面展示用的时间文本。</summary>
    [JsonIgnore]
    public string CreatedAtText => CreatedAt.ToString("yyyy-MM-dd HH:mm");

    /// <summary>供无障碍读取与调试输出使用。</summary>
    public override string ToString() =>
        string.IsNullOrWhiteSpace(Meaning) ? Display : $"{Display} - {Meaning}";

    /// <summary>是否已到复习时间。</summary>
    [JsonIgnore]
    public bool IsDue => NextReviewAt is null || NextReviewAt <= DateTime.Now;
}
