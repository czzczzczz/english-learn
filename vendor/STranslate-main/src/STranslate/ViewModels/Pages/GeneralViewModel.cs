using CommunityToolkit.Mvvm.Input;
using STranslate.Core;
using STranslate.Helpers;
using STranslate.Plugin;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows;
using System.Windows.Threading;

namespace STranslate.ViewModels.Pages;

public partial class GeneralViewModel : SearchViewModelBase
{
    public GeneralViewModel(
        Settings settings,
        DataProvider dataProvider,
        HotkeySettings hotkeySettings,
        Internationalization i18n,
        STranslate.Services.StoryService storyService,
        STranslate.Plugin.ISnackbar snackbar) : base(i18n, "General_")
    {
        Settings = settings;
        _storyService = storyService;
        _snackbar = snackbar;
        LongPressDurations = [300, 450, 600, 800, 1200];
        DataProvider = dataProvider;
        HotkeySettings = hotkeySettings;
        Languages = i18n.LoadAvailableLanguages();

        InitializeMainHeaderActions();

        VisibleHeaderActions.CollectionChanged += OnMainHeaderActionsChanged;
        AvailableHeaderActions.CollectionChanged += OnMainHeaderActionsChanged;
        Settings.PropertyChanged += OnSettingsPropertyChanged;
    }

    private bool _isSyncingMainHeaderActions;
    private bool _isMainHeaderSyncPending;

    /// <summary>热键配置，用于展示「方式一」的当前按键。</summary>
    public HotkeySettings HotkeySettings { get; }

    public ObservableCollection<string> VisibleHeaderActions { get; } = [];

    public ObservableCollection<string> AvailableHeaderActions { get; } = [];

    [RelayCommand]
    private void ResetFontFamily() => Settings.FontFamily = Win32Helper.GetSystemDefaultFont();

    [RelayCommand]
    private void ResetAutoTransDelay() => Settings.AutoTranslateDelayMs = 500;

    [RelayCommand]
    private void ResetFontSize() => Settings.FontSize = 14;

    [RelayCommand]
    private void ResetMainWindowMaxHeightRatio() => Settings.MainWindowMaxHeightRatio = 0.85;

    [RelayCommand]
    private void ShowAllHeaderActions()
    {
        _isSyncingMainHeaderActions = true;
        try
        {
            ReplaceItems(VisibleHeaderActions, MainHeaderActions.DefaultOrder);
            ReplaceItems(AvailableHeaderActions, []);
        }
        finally
        {
            _isSyncingMainHeaderActions = false;
        }

        SyncMainHeaderActions();
    }

    [RelayCommand]
    private void HideAllHeaderActions()
    {
        _isSyncingMainHeaderActions = true;
        try
        {
            ReplaceItems(VisibleHeaderActions, []);
            ReplaceItems(AvailableHeaderActions, MainHeaderActions.DefaultOrder);
        }
        finally
        {
            _isSyncingMainHeaderActions = false;
        }

        SyncMainHeaderActions();
    }

    public List<int> ScreenNumbers
    {
        get
        {
            var screens = MonitorInfo.GetDisplayMonitors();
            var screenNumbers = new List<int>();
            for (int i = 1; i <= screens.Count; i++)
            {
                screenNumbers.Add(i);
            }

            return screenNumbers;
        }
    }
    private readonly STranslate.Services.StoryService _storyService;
    private readonly STranslate.Plugin.ISnackbar _snackbar;

    /// <summary>中转站可用模型列表。</summary>
    public ObservableCollection<string> LlmModels { get; } = [];

    /// <summary>从中转站拉取模型列表。</summary>
    [RelayCommand]
    private async Task RefreshModelsAsync()
    {
        try
        {
            var models = await _storyService.GetModelsAsync();
            LlmModels.Clear();
            foreach (var model in models)
                LlmModels.Add(model);

            if (models.Count > 0 && string.IsNullOrWhiteSpace(Settings.LlmModel))
                Settings.LlmModel = models[0];
        }
        catch (Exception ex)
        {
            _snackbar.ShowError(ex.Message);
        }
    }

    /// <summary>音标体系候选项。</summary>
    public PhoneticSystemOption[] PhoneticSystems { get; } =
    [
        new(PhoneticConverter.Kk, "KK（美式）"),
        new(PhoneticConverter.Ipa, "IPA（国际）"),
        new(PhoneticConverter.Both, "两者对照")
    ];

    /// <summary>左键长按进入框选的时长候选（毫秒）。</summary>
    public int[] LongPressDurations { get; }

    public Settings Settings { get; }
    public DataProvider DataProvider { get; }

    public List<I18nPair> Languages { get; }

    public bool IsTextSeparatorMouseSelectionScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.MouseSelection);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.MouseSelection, value);
    }

    public bool IsTextSeparatorCrosswordScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.Crossword);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.Crossword, value);
    }

    public bool IsTextSeparatorIncrementalScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.Incremental);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.Incremental, value);
    }

    public bool IsTextSeparatorClipboardMonitorScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.ClipboardMonitor);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.ClipboardMonitor, value);
    }

    public bool IsTextSeparatorScreenshotTranslateScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.ScreenshotTranslate);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.ScreenshotTranslate, value);
    }

    public bool IsTextSeparatorSilentOcrScopeEnabled
    {
        get => IsTextSeparatorScopeEnabled(TextSeparatorHandleScope.SilentOcr);
        set => SetTextSeparatorScope(TextSeparatorHandleScope.SilentOcr, value);
    }

    private bool IsTextSeparatorScopeEnabled(TextSeparatorHandleScope scope)
        => (Settings.TextSeparatorHandleScopes & scope) == scope;

    private void SetTextSeparatorScope(TextSeparatorHandleScope scope, bool isEnabled)
    {
        var current = Settings.TextSeparatorHandleScopes;
        var updated = isEnabled ? current | scope : current & ~scope;
        if (updated == current)
            return;

        Settings.TextSeparatorHandleScopes = updated;
    }

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(Settings.TextSeparatorHandleScopes))
        {
            OnTextSeparatorScopePropertiesChanged();
        }
    }

    private void OnTextSeparatorScopePropertiesChanged()
    {
        OnPropertyChanged(nameof(IsTextSeparatorMouseSelectionScopeEnabled));
        OnPropertyChanged(nameof(IsTextSeparatorCrosswordScopeEnabled));
        OnPropertyChanged(nameof(IsTextSeparatorIncrementalScopeEnabled));
        OnPropertyChanged(nameof(IsTextSeparatorClipboardMonitorScopeEnabled));
        OnPropertyChanged(nameof(IsTextSeparatorScreenshotTranslateScopeEnabled));
        OnPropertyChanged(nameof(IsTextSeparatorSilentOcrScopeEnabled));
    }

    private void InitializeMainHeaderActions()
    {
        Settings.EnsureMainHeaderVisibleActionsInitialized();

        var normalizedVisible = MainHeaderActions.Normalize(Settings.MainHeaderVisibleActions);

        _isSyncingMainHeaderActions = true;
        try
        {
            ReplaceItems(VisibleHeaderActions, normalizedVisible);

            var visibleSet = normalizedVisible.ToHashSet(StringComparer.OrdinalIgnoreCase);
            var availableActions = MainHeaderActions.DefaultOrder
                .Where(action => !visibleSet.Contains(action))
                .ToList();

            ReplaceItems(AvailableHeaderActions, availableActions);
        }
        finally
        {
            _isSyncingMainHeaderActions = false;
        }

        Settings.ApplyMainHeaderVisibleActions(normalizedVisible);
    }

    private void OnMainHeaderActionsChanged(object? _, NotifyCollectionChangedEventArgs __)
    {
        if (_isSyncingMainHeaderActions || _isMainHeaderSyncPending)
        {
            return;
        }

        _isMainHeaderSyncPending = true;

        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher == null)
        {
            _isMainHeaderSyncPending = false;
            SyncMainHeaderActions();
            return;
        }

        dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
        {
            _isMainHeaderSyncPending = false;
            SyncMainHeaderActions();
        }));
    }

    private void SyncMainHeaderActions()
    {
        if (_isSyncingMainHeaderActions)
        {
            return;
        }

        _isSyncingMainHeaderActions = true;
        try
        {
            var normalizedVisible = MainHeaderActions.Normalize(VisibleHeaderActions);
            ReplaceItemsIfDifferent(VisibleHeaderActions, normalizedVisible);

            var visibleSet = normalizedVisible.ToHashSet(StringComparer.OrdinalIgnoreCase);
            var availableActions = MainHeaderActions.DefaultOrder
                .Where(action => !visibleSet.Contains(action))
                .ToList();
            ReplaceItemsIfDifferent(AvailableHeaderActions, availableActions);

            Settings.ApplyMainHeaderVisibleActions(normalizedVisible);
        }
        finally
        {
            _isSyncingMainHeaderActions = false;
        }
    }

    private static void ReplaceItems(ObservableCollection<string> target, IEnumerable<string> source)
    {
        target.Clear();
        foreach (var item in source)
        {
            target.Add(item);
        }
    }

    private static void ReplaceItemsIfDifferent(ObservableCollection<string> target, IReadOnlyList<string> source)
    {
        if (target.Count == source.Count && target.SequenceEqual(source))
        {
            return;
        }

        ReplaceItems(target, source);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Settings.PropertyChanged -= OnSettingsPropertyChanged;
        }

        base.Dispose(disposing);
    }
}
