using Microsoft.Extensions.Logging;
using STranslate.Core;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;

namespace STranslate.Services;

/// <summary>
/// 生词本内置存储：单文件 JSON + 内存集合，替代原来的生词本插件链路。
/// </summary>
public class VocabularyStore
{
    private const int MaxEntries = 20000;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly ILogger<VocabularyStore> _logger;
    private readonly object _gate = new();

    public VocabularyStore(ILogger<VocabularyStore> logger)
    {
        _logger = logger;
        Entries = [];
        FilePath = Path.Combine(DataLocation.SettingsDirectory, "Vocabulary.json");
        Load();
    }

    /// <summary>存储文件路径。</summary>
    public string FilePath { get; }

    /// <summary>全部词条，按加入时间倒序排列。</summary>
    public ObservableCollection<VocabularyEntry> Entries { get; }

    /// <summary>词条数量变化时触发，供界面与统计刷新。</summary>
    public event EventHandler? Changed;

    /// <summary>词条总数。</summary>
    public int Count => Entries.Count;

    /// <summary>
    /// 加入一个词条；已存在时只补全空白字段，不产生重复行。
    /// </summary>
    /// <param name="text">单词或短语。</param>
    /// <param name="note">译文/例句笔记。</param>
    /// <param name="phonetic">音标。</param>
    /// <param name="meaning">简短释义。</param>
    /// <param name="source">来源服务。</param>
    /// <returns>新增返回 true；已存在被更新返回 false。</returns>
    public bool Add(string text, string note = "", string phonetic = "", string meaning = "", string source = "")
    {
        var display = (text ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(display))
            return false;

        if (display.Length > 200)
            display = display[..200];

        var key = display.ToLowerInvariant();

        lock (_gate)
        {
            var existing = Entries.FirstOrDefault(e => string.Equals(e.Key, key, StringComparison.Ordinal));
            if (existing is not null)
            {
                if (!string.IsNullOrWhiteSpace(note) && string.IsNullOrWhiteSpace(existing.Note))
                    existing.Note = note;
                if (!string.IsNullOrWhiteSpace(phonetic) && string.IsNullOrWhiteSpace(existing.Phonetic))
                    existing.Phonetic = phonetic;
                if (!string.IsNullOrWhiteSpace(meaning) && string.IsNullOrWhiteSpace(existing.Meaning))
                    existing.Meaning = meaning;
                // 触发一次属性刷新，让列表内的笔记更新可见
                OnChanged();
                Save();
                return false;
            }

            if (Entries.Count >= MaxEntries)
                Entries.RemoveAt(Entries.Count - 1);

            Entries.Insert(0, new VocabularyEntry
            {
                Key = key,
                Display = display,
                Note = note ?? string.Empty,
                Phonetic = phonetic ?? string.Empty,
                Meaning = meaning ?? string.Empty,
                Source = source ?? string.Empty,
                CreatedAt = DateTime.Now
            });

            OnChanged();
            Save();
            return true;
        }
    }

    /// <summary>
    /// 用词典结果补全词条：音标填空位，笔记为空时填英文释义。
    /// </summary>
    /// <param name="key">词条键（小写）。</param>
    /// <param name="phonetic">音标。</param>
    /// <param name="meaning">英文释义。</param>
    /// <returns>是否有字段被更新。</returns>
    public bool Enrich(string key, string phonetic, string meaning)
    {
        if (string.IsNullOrWhiteSpace(key))
            return false;

        lock (_gate)
        {
            var entry = Entries.FirstOrDefault(e => string.Equals(e.Key, key, StringComparison.Ordinal));
            if (entry is null)
                return false;

            var changed = false;
            if (!string.IsNullOrWhiteSpace(phonetic) && string.IsNullOrWhiteSpace(entry.Phonetic))
            {
                entry.Phonetic = phonetic;
                changed = true;
            }

            if (!string.IsNullOrWhiteSpace(meaning) && string.IsNullOrWhiteSpace(entry.Note))
            {
                entry.Note = meaning;
                changed = true;
            }

            if (!changed)
                return false;

            OnChanged();
            Save();
            return true;
        }
    }

    /// <summary>删除一个词条。</summary>
    public bool Remove(VocabularyEntry? entry)
    {
        if (entry is null)
            return false;

        lock (_gate)
        {
            if (!Entries.Remove(entry))
                return false;

            OnChanged();
            Save();
            return true;
        }
    }

    /// <summary>清空全部词条。</summary>
    public void Clear()
    {
        lock (_gate)
        {
            if (Entries.Count == 0)
                return;

            Entries.Clear();
            OnChanged();
            Save();
        }
    }

    /// <summary>更新熟练度并安排下次复习（1/3/7/15/30/60 天）。</summary>
    public void MarkReviewed(VocabularyEntry? entry, bool remembered)
    {
        if (entry is null)
            return;

        lock (_gate)
        {
            var intervals = new[] { 1, 3, 7, 15, 30, 60 };
            entry.Level = remembered ? Math.Min(entry.Level + 1, intervals.Length - 1) : 0;
            entry.ReviewCount++;
            entry.LastReviewedAt = DateTime.Now;
            entry.NextReviewAt = DateTime.Now.Date.AddDays(intervals[entry.Level]);
            OnChanged();
            Save();
        }
    }

    /// <summary>把当前集合写回磁盘；先写临时文件再替换，避免半截文件。</summary>
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            List<VocabularyEntry> snapshot;
            lock (_gate)
            {
                snapshot = [.. Entries];
            }

            var json = JsonSerializer.Serialize(snapshot, JsonOptions);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "保存生词本失败");
        }
    }

    /// <summary>从磁盘读取；文件不存在或损坏时以空列表启动。</summary>
    private void Load()
    {
        try
        {
            if (!File.Exists(FilePath))
                return;

            var json = File.ReadAllText(FilePath);
            if (string.IsNullOrWhiteSpace(json))
                return;

            var items = JsonSerializer.Deserialize<List<VocabularyEntry>>(json, JsonOptions);
            if (items is null)
                return;

            foreach (var item in items)
            {
                if (string.IsNullOrWhiteSpace(item.Display))
                    continue;

                if (string.IsNullOrWhiteSpace(item.Key))
                    item.Key = item.Display.ToLowerInvariant();

                Entries.Add(item);
            }

            _logger.LogInformation("生词本已加载 {Count} 条", Entries.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "读取生词本失败，按空列表启动");
        }
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);
}
