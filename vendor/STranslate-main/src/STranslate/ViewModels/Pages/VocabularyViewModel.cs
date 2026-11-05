using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using STranslate.Core;
using STranslate.Plugin;
using STranslate.Services;
using System.Collections.ObjectModel;
using System.IO;
using System.Text;
using System.Windows;

namespace STranslate.ViewModels.Pages;

/// <summary>
/// 生词本页面视图模型：列出内置生词本的全部词条，支持搜索、朗读、删除、导出。
/// </summary>
public partial class VocabularyViewModel : ObservableObject
{
    private readonly VocabularyStore _store;
    private readonly TtsService _tts;
    private readonly ISnackbar _snackbar;
    private readonly Internationalization _i18n;
    private readonly Settings _settings;
    private readonly StoryService _storyService;

    /// <summary>音标体系候选项。</summary>
    public PhoneticSystemOption[] PhoneticSystems { get; } =
    [
        new(PhoneticConverter.Kk, "KK（美式）"),
        new(PhoneticConverter.Ipa, "IPA（国际）"),
        new(PhoneticConverter.Both, "两者对照")
    ];

    /// <summary>当前音标体系，切换后立即刷新列表。</summary>
    public string PhoneticSystem
    {
        get => _settings.PhoneticSystem;
        set
        {
            if (string.Equals(_settings.PhoneticSystem, value, StringComparison.OrdinalIgnoreCase))
                return;

            _settings.PhoneticSystem = value ?? PhoneticConverter.Default;
            OnPropertyChanged();
            Fill();
        }
    }

    public VocabularyViewModel(
        VocabularyStore store,
        TtsService tts,
        ISnackbar snackbar,
        Internationalization i18n,
        Settings settings,
        StoryService storyService)
    {
        _store = store;
        _tts = tts;
        _snackbar = snackbar;
        _i18n = i18n;
        _settings = settings;
        _storyService = storyService;
        settings.PropertyChanged += OnSettingsPropertyChanged;
        Items = [];
        Refresh();
        _store.Changed += OnStoreChanged;
    }

    /// <summary>按当前搜索条件过滤后的词条。</summary>
    public ObservableCollection<VocabularyEntry> Items { get; }

    /// <summary>搜索关键词，匹配单词、释义与笔记。</summary>
    [ObservableProperty]
    public partial string SearchText { get; set; } = string.Empty;

    /// <summary>词条总数（不受搜索影响）。</summary>
    [ObservableProperty]
    public partial int TotalCount { get; set; }

    /// <summary>是否没有任何词条，用于空态提示。</summary>
    [ObservableProperty]
    public partial bool IsEmpty { get; set; } = true;

    /// <summary>是否有搜索结果，用于"无匹配"提示。</summary>
    [ObservableProperty]
    public partial bool HasResult { get; set; } = true;

    /// <summary>有词条但搜索不到匹配项。</summary>
    [ObservableProperty]
    public partial bool IsNoMatch { get; set; }

    /// <summary>当前选中的词条。</summary>
    [ObservableProperty]
    public partial VocabularyEntry? SelectedItem { get; set; }

    partial void OnSearchTextChanged(string value) => Fill();

    partial void OnTotalCountChanged(int value) => IsEmpty = value == 0;

    private void OnStoreChanged(object? sender, EventArgs e) => Refresh();

    private void OnSettingsPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(Core.Settings.PhoneticSystem))
            return;

        OnPropertyChanged(nameof(PhoneticSystem));
        Fill();
    }

    /// <summary>重新读取全部词条并应用过滤。</summary>
    public void Refresh()
    {
        TotalCount = _store.Count;
        Fill();
    }

    /// <summary>按关键词过滤。</summary>
    private void Fill()
    {
        var keyword = SearchText?.Trim() ?? string.Empty;

        Items.Clear();
        foreach (var entry in _store.Entries)
        {
            if (keyword.Length > 0 &&
                entry.Display.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) < 0 &&
                entry.Meaning.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) < 0 &&
                entry.Note.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) < 0)
                continue;

            Items.Add(new VocabularyEntry
            {
                Key = entry.Key,
                Display = entry.Display,
                Phonetic = PhoneticConverter.Format(entry.Phonetic, _settings.PhoneticSystem),
                Meaning = entry.Meaning,
                Note = entry.Note,
                Source = entry.Source,
                CreatedAt = entry.CreatedAt,
                ReviewCount = entry.ReviewCount,
                Level = entry.Level,
                NextReviewAt = entry.NextReviewAt
            });
        }

        IsEmpty = _store.Count == 0;
        HasResult = Items.Count > 0;
        IsNoMatch = !IsEmpty && !HasResult;
    }

    /// <summary>朗读词条。</summary>
    [RelayCommand]
    private async Task SpeakAsync(VocabularyEntry? entry)
    {
        if (entry is null)
            return;

        var plugin = _tts.GetActiveSvc<ITtsPlugin>();
        if (plugin is null)
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("TtsServiceNotFound"));
            return;
        }

        try
        {
            await plugin.PlayAudioAsync(entry.Display);
        }
        catch (Exception ex)
        {
            _snackbar.ShowError(ex.Message);
        }
    }

    /// <summary>删除词条。</summary>
    [RelayCommand]
    private void Remove(VocabularyEntry? entry)
    {
        if (entry is null)
            return;

        // 列表里是显示副本，删除时按 key 找原始记录
        var original = _store.Entries.FirstOrDefault(e => string.Equals(e.Key, entry.Key, StringComparison.Ordinal));
        _store.Remove(original);
        SelectedItem = null;
    }

    /// <summary>清空生词本。</summary>
    [RelayCommand]
    private void Clear()
    {
        if (_store.Count == 0)
            return;

        _store.Clear();
        SelectedItem = null;
    }

    /// <summary>用当前生词生成一段 AI 小故事。</summary>
    [RelayCommand]
    private void GenerateStory()
    {
        if (_store.Count == 0)
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("VocabularyEmpty"));
            return;
        }

        if (!_storyService.IsConfigured)
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("Vocabulary_StoryNotConfigured"));
            return;
        }

        // 优先取还没熟练的词，最多 12 个
        var words = _store.Entries
            .OrderBy(e => e.Level)
            .ThenByDescending(e => e.CreatedAt)
            .Select(e => e.Display)
            .Take(12)
            .ToList();

        var window = new Views.StoryWindow(_storyService, _tts)
        {
            Owner = Application.Current.MainWindow
        };
        window.Show();
        _ = window.LoadAsync(words);
    }

    /// <summary>导出为 CSV 到桌面。</summary>
    [RelayCommand]
    private void Export()
    {
        if (_store.Count == 0)
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("VocabularyEmpty"));
            return;
        }

        try
        {
            var path = Path.Combine(
                DataLocation.DesktopPath,
                $"生词本_{DateTime.Now:yyyyMMdd_HHmmss}.csv");

            var sb = new StringBuilder();
            sb.AppendLine("单词,音标,释义,笔记,来源,加入时间,复习次数");
            foreach (var e in _store.Entries)
            {
                sb.AppendLine(string.Join(',',
                    Csv(e.Display), Csv(e.Phonetic), Csv(e.Meaning), Csv(e.Note),
                    Csv(e.Source), Csv(e.CreatedAtText), e.ReviewCount.ToString()));
            }

            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(true));
            _snackbar.ShowSuccess(path);
        }
        catch (Exception ex)
        {
            _snackbar.ShowError(ex.Message);
        }
    }

    /// <summary>CSV 字段转义。</summary>
    private static string Csv(string value)
    {
        if (string.IsNullOrEmpty(value))
            return string.Empty;

        var escaped = value.Replace("\"", "\"\"").Replace("\r", " ").Replace("\n", " ");
        return "\"" + escaped + "\"";
    }
}

/// <summary>音标体系下拉项。</summary>
/// <param name="Value">写入设置的值。</param>
/// <param name="Display">界面显示名。</param>
public sealed record PhoneticSystemOption(string Value, string Display)
{
    /// <inheritdoc />
    public override string ToString() => Display;
}
