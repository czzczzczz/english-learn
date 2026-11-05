using CommunityToolkit.Mvvm.ComponentModel;
using System.IO;
using CommunityToolkit.Mvvm.Input;
using iNKORE.UI.WPF.Modern;
using Microsoft.Extensions.Logging;
using STranslate.Core;
using STranslate.Helpers;
using STranslate.Plugin;
using STranslate.Resources;
using STranslate.Services;
using STranslate.Views;
using STranslate.Views.Pages;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Windows.Win32;

namespace STranslate.ViewModels;

public partial class MainWindowViewModel : ObservableObject, IDisposable
{
    #region Constructor & DI

    private readonly ILogger<MainWindowViewModel> _logger;
    private readonly Internationalization _i18n;
    private readonly IAudioPlayer _audioPlayer;
    private readonly IScreenshot _screenshot;
    private readonly ISnackbar _snackbar;
    private readonly INotification _notification;
    private readonly MouseSelectionService _mouseSelectionService;
    private readonly MouseSelectionBubbleWindow _mouseSelectionBubbleWindow = new();
    private bool _mouseSelectionTranslationHasTopmostLease;
    private bool _bubbleTranslateHasTopmostLease;

    /// <summary>
    ///     用户手动置顶（钉子按钮）状态。
    ///     钉子图标绑定这个值，气泡翻译申请的临时置顶不会点亮钉子。
    /// </summary>
    [ObservableProperty]
    public partial bool IsUserTopmost { get; private set; }

    private int _managedTopmostLeaseCount;
    private bool _isApplyingManagedTopmost;
    private double _cacheLeft;
    private double _cacheTop;
    private bool _isAdjustingWindowPositionForContent;

    public TranslateService TranslateService { get; }
    public TtsService TtsService { get; }
    public VocabularyService VocabularyService { get; }

    /// <summary>内置生词本存储（不再依赖生词本插件）。</summary>
    public VocabularyStore VocabularyStore { get; }

    /// <summary>是否可以回到上一条历史。</summary>
    [ObservableProperty]
    public partial bool CanGoHistoryBack { get; set; }

    /// <summary>是否可以前进到下一条历史。</summary>
    [ObservableProperty]
    public partial bool CanGoHistoryForward { get; set; }

    /// <summary>生词本是否可用：内置存储常驻，恒为 true。</summary>
    public bool HasVocabulary => true;
    public ObservableCollection<ServiceQuickAccessItem> QuickServiceItems { get; } = [];

    private const int TranslationHistoryLimit = 20;

    private readonly List<HistoryEntry> _translationHistory = [];
    private int _historyIndex = -1;
    private bool _isReplayingHistory;

    private readonly OcrService _ocrService;
    private readonly DictionaryService _dictionaryService;
    private bool _isCapturingRegion;
    private readonly DebounceExecutor _debounceExecutor;
    private ClipboardMonitor? _clipboardMonitor;
    private bool _forceShowInputForInputTranslate;
    private bool _skipShowForNextTranslate;
    private bool _disposed;
    private readonly object _manualTranslationTaskLock = new();
    private readonly Dictionary<string, CancellationTokenSource> _manualTranslationTaskTokens = [];
    private readonly SemaphoreSlim _manualTranslationHistoryLock = new(1, 1);
    private readonly TranslationResultCoordinator _translationCoordinator;

    public Settings Settings { get; }
    public HotkeySettings HotkeySettings { get; }

    public MainWindowViewModel(
        DataProvider dataProvider,
        ILogger<MainWindowViewModel> logger,
        Internationalization i18n,
        IAudioPlayer audioPlayer,
        IScreenshot screenshot,
        ISnackbar snackbar,
        INotification notification,
        TranslateService translateService,
        TtsService ttsService,
        VocabularyService vocabularyService,
        VocabularyStore vocabularyStore,
        OcrService ocrService,
        DictionaryService dictionaryService,
        Settings settings,
        HotkeySettings hotkeySettings,
        MouseSelectionService mouseSelectionService)
    {
        DataProvider = dataProvider;
        IdentifiedLanguageOptions = DataProvider.LangEnums
            .Where(x => x.Value != LangEnum.Auto)
            .Cast<DropdownDataGeneric<LangEnum>>()
            .ToList();
        _logger = logger;
        _i18n = i18n;
        _translationCoordinator = new(i18n.GetTranslation);
        _audioPlayer = audioPlayer;
        _screenshot = screenshot;
        _snackbar = snackbar;
        _notification = notification;
        TranslateService = translateService;
        TtsService = ttsService;
        VocabularyService = vocabularyService;
        VocabularyStore = vocabularyStore;
        _ocrService = ocrService;
        _dictionaryService = dictionaryService;
        Settings = settings;
        HotkeySettings = hotkeySettings;
        _mouseSelectionService = mouseSelectionService;
        _mouseSelectionService.TextSelected += OnMouseSelectionTextSelected;
        _mouseSelectionService.SelectionStarted += OnMouseSelectionStarted;
        _mouseSelectionService.BubbleRequested += OnMouseSelectionBubbleRequested;
        _mouseSelectionService.BubbleDismissRequested += OnMouseSelectionBubbleDismissRequested;
        _mouseSelectionService.LongPressTriggered += OnLongPressTriggered;
        _mouseSelectionService.StateChanged += OnMouseSelectionStateChanged;
        _mouseSelectionBubbleWindow.HoverCompleted += OnMouseSelectionBubbleHoverCompleted;

        TranslateService.Services.CollectionChanged += OnQuickServiceCollectionChanged;
        ApplyPhoneticSystem();
        Settings.PropertyChanged += OnSettingsChangedForPhonetic;
        TtsService.Services.CollectionChanged += OnQuickServiceCollectionChanged;
        VocabularyService.Services.CollectionChanged += OnQuickServiceCollectionChanged;
        RebuildQuickServiceItems();

        _debounceExecutor = new();
        _i18n.OnLanguageChanged += OnLanguageChanged;
        Settings.PropertyChanged += OnSettingsPropertyChanged;
    }

    private void OnLanguageChanged()
    {
        ApplyIdentifiedLanguageState(_identifiedLanguageState);

        if (!UACHelper.IsUserAdministrator())
            return;

        TrayToolTip = $"{Constant.AppName} # {_i18n.GetTranslation("Administrator")}";
    }

    #endregion

    #region Quick Service Switcher

    private void OnQuickServiceCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
        => RebuildQuickServiceItems();

    private void RebuildQuickServiceItems()
    {
        QuickServiceItems.Clear();

        var hasPreviousGroup = false;
        AddQuickServiceGroup(TranslateService.Services, ref hasPreviousGroup);
        AddQuickServiceGroup(TtsService.Services, ref hasPreviousGroup);
        AddQuickServiceGroup(VocabularyService.Services, ref hasPreviousGroup);
    }

    private void AddQuickServiceGroup(IEnumerable<Service> services, ref bool hasPreviousGroup)
    {
        var isFirstItem = true;
        foreach (var service in services)
        {
            QuickServiceItems.Add(new ServiceQuickAccessItem(
                service,
                ShowSeparatorBefore: isFirstItem && hasPreviousGroup));
            isFirstItem = false;
        }

        if (!isFirstItem)
            hasPreviousGroup = true;
    }

    [RelayCommand]
    private void ToggleQuickService(Service service) => service.IsEnabled = !service.IsEnabled;

    #endregion

    #region Properties

    private MainWindow MainWindow => (Application.Current.MainWindow as MainWindow)!;
    private bool IsMainWindowVisible => MainWindow.Visibility == Visibility.Visible;

    public DataProvider DataProvider { get; }

    /// <summary>
    /// 等待ContextMenu关闭动画完成的延迟时间（毫秒）
    /// </summary>
    private const int ContextMenuCloseAnimationDelay = 150;

    private sealed record IdentifiedLanguageState(IdentifiedLanguageStateKind Kind, LangEnum? Language = null)
    {
        public static IdentifiedLanguageState Empty { get; } = new(IdentifiedLanguageStateKind.None);
    }

    private sealed record TranslationLanguageContext(
        LangEnum CacheSource,
        LangEnum CacheTarget,
        LangEnum EffectiveSource,
        LangEnum EffectiveTarget);

    [ObservableProperty]
    public partial ImageSource TrayIcon { get; set; } = BitmapImageLoc.AppIcon;

    [ObservableProperty]
    public partial string TrayToolTip { get; set; } = Constant.AppName;

    [ObservableProperty]
    public partial bool IsIdentifyProcessing { get; set; } = false;

    [ObservableProperty]
    public partial bool IsClipboardMonitoring { get; set; } = false;

    [ObservableProperty]
    public partial double MainWindowEffectiveMaxHeight { get; set; } = 800;

    public bool IsInputActuallyHidden
    {
        get => Settings.HideInput && !_forceShowInputForInputTranslate;
        set
        {
            if (value == IsInputActuallyHidden)
                return;

            ExitInputTranslateMode();
            Settings.HideInput = value;
        }
    }

    public bool IsInputBoxVisible => !IsInputActuallyHidden;

    public bool IsLanguageSelectControlVisible =>
        !IsInputActuallyHidden || !Settings.HideInputWithLangSelectControl;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SingleTranslateCommand))]
    [NotifyCanExecuteChangedFor(nameof(SingleTransBackCommand))]
    [NotifyCanExecuteChangedFor(nameof(TranslateCommand))]
    [NotifyCanExecuteChangedFor(nameof(SelectIdentifiedLanguageCommand))]
    [NotifyCanExecuteChangedFor(nameof(SelectLanguageDetectorCommand))]
    public partial string InputText { get; set; } = string.Empty;

    [ObservableProperty]
    public partial string IdentifiedLanguage { get; set; } = string.Empty;

    [ObservableProperty]
    public partial LangEnum SelectedIdentifiedLanguage { get; set; } = LangEnum.Auto;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(SelectIdentifiedLanguageCommand))]
    public partial bool CanSelectIdentifiedLanguage { get; set; } = false;

    public IReadOnlyList<DropdownDataGeneric<LangEnum>> IdentifiedLanguageOptions { get; }

    private IdentifiedLanguageState _identifiedLanguageState = IdentifiedLanguageState.Empty;

    public IdentifiedLanguageStateKind CurrentIdentifiedLanguageState => _identifiedLanguageState.Kind;

    public bool IsTopmost
    {
        get => field;
        set
        {
            if (!_isApplyingManagedTopmost)
                IsUserTopmost = value;

            SetProperty(ref field, value);

            // 手动切换置顶时同步 Win32 层：置顶走 HWND_TOPMOST，取消走 HWND_NOTOPMOST
            if (!_isApplyingManagedTopmost && MainWindow is not null)
            {
                try
                {
                    if (value)
                        Win32Helper.RaiseWindowWithoutActivation(MainWindow, showWindow: false);
                    else
                        Win32Helper.LowerWindowFromTopmost(MainWindow);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Apply topmost window failed.");
                }
            }
        }
    }

    public bool CanTranslate => !string.IsNullOrWhiteSpace(InputText);

    #endregion

    #region Translation Commands

    /// <summary>
    /// 执行翻译
    /// </summary>
    /// <param name="text"></param>
    /// <param name="force">不为空则跳过缓存</param>
    public void ExecuteTranslate(string text, string? force = null)
    {
        ExitInputTranslateMode();
        CancelAllOperations();
        ResetTranslationLanguageState();
        InputText = text;
        TranslateCommand.Execute(force);

        var skipShow = _skipShowForNextTranslate;
        _skipShowForNextTranslate = false;

        if (skipShow)
            return;

        Show();
        UpdateCaret();
    }

    [RelayCommand(IncludeCancelCommand = true, CanExecute = nameof(CanTranslate))]
    private async Task TranslateAsync(object? force, CancellationToken cancellationToken)
    {
        try
        {
            RecordHistory(InputText);
            await ExecuteAutomaticTranslationAsync(force, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // 用户取消属于正常控制流，不应让取消异常越过命令边界。
        }
    }

    private async Task ExecuteAutomaticTranslationAsync(object? force, CancellationToken cancellationToken)
    {
        // 取消防抖执行器中的待执行任务
        _debounceExecutor.Cancel();
        var operation = _translationCoordinator.BeginAutomaticOperation(
            InputText,
            Settings.SourceLang,
            Settings.TargetLang,
            cancellationToken);

        LangEnum? forcedSourceLanguage = force is LangEnum language && language != LangEnum.Auto
            ? language
            : null;

        ResetAllServices(operation);
        ApplyIdentifiedLanguageState(forcedSourceLanguage.HasValue
            ? CreateDetectedIdentifiedLanguageState(forcedSourceLanguage.Value)
            : IdentifiedLanguageState.Empty);

        // force 空则优先检查缓存
        var checkCacheFirst = force == null;

        var history = await ExecuteTranslateAsync(
            operation,
            checkCacheFirst,
            forcedSourceLanguage);

        operation.CancellationToken.ThrowIfCancellationRequested();
        if (!operation.IsLatestAutomatic)
            return;

        // 翻译后自动复制
        if (Settings.CopyAfterTranslation != CopyAfterTranslation.NoAction)
        {
            var serviceList = TranslateService.Services.Where(x => x.IsEnabled && x.Options?.ExecMode == ExecutionMode.Automatic);
            var service = Settings.CopyAfterTranslation == CopyAfterTranslation.Last ?
                serviceList.LastOrDefault() :
                serviceList.ElementAtOrDefault((int)Settings.CopyAfterTranslation - 1);
            if (service == null)
            {
                _snackbar.ShowWarning(string.Format(_i18n.GetTranslation("CopyServiceNotFound"), Settings.CopyAfterTranslation));
            }
            else
            {
                var data = history?.GetData(service);
                if (data != null)
                {
                    var textToCopy = data.TransResult?.Text ?? data.DictResult?.Text;
                    if (!string.IsNullOrWhiteSpace(textToCopy))
                    {
                        operation.TryPublishAutomatic(
                            () =>
                            {
                                ClipboardHelper.SetText(textToCopy);
                                _snackbar.ShowSuccess(string.Format(
                                    _i18n.GetTranslation("CopiedToClipboard"),
                                    service.DisplayName));
                            });
                    }
                }
            }
        }

    }

    [RelayCommand]
    private void TemporaryTranslate(Service service)
    {
        if (string.IsNullOrWhiteSpace(InputText))
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("InputContentIsEmpty"));
            return;
        }

        if (!SingleTranslateCommand.CanExecute(service))
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("WaitingForPreviousExecution"));
            return;
        }
        service.Options?.TemporaryDisplay = true;

        SingleTranslateCommand.Execute(service);
    }

    [RelayCommand(AllowConcurrentExecutions = true, CanExecute = nameof(CanSingleTranslate))]
    private async Task SingleTranslateAsync(Service service)
    {
        if (!TryStartManualTranslation(service, out var cancellationTokenSource))
            return;

        var operation = _translationCoordinator.BeginOperation(
            InputText,
            Settings.SourceLang,
            Settings.TargetLang,
            cancellationTokenSource.Token);
        try
        {
            await ExecuteSingleTranslateAsync(
                service,
                operation).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationTokenSource.IsCancellationRequested)
        {
            // Ignore
        }
        finally
        {
            FinishManualTranslation(service, cancellationTokenSource);
        }
    }

    private async Task ExecuteSingleTranslateAsync(
        Service service,
        TranslationOperation operation)
    {
        if (string.IsNullOrWhiteSpace(operation.Text))
            return;

        switch (service.Plugin)
        {
            case IDictionaryPlugin dictionaryPlugin:
                if (!operation.TryPrepare(dictionaryPlugin))
                    return;

                var result = await operation.LookupAsync(dictionaryPlugin).ConfigureAwait(false);
                if (result.ResultType == DictionaryResultType.Error ||
                    !operation.IsCurrent(dictionaryPlugin.DictionaryResult))
                    return;

                if (Settings.CopyAfterTranslationNotAutomatic)
                {
                    var copied = operation.TryPublish(
                        dictionaryPlugin.DictionaryResult,
                        () =>
                        {
                            ClipboardHelper.SetText(result.Text);
                            _snackbar.ShowSuccess(string.Format(
                                _i18n.GetTranslation("CopiedToClipboard"),
                                service.DisplayName));
                        });
                    if (!copied)
                        return;
                }

                var history = GetFromMemoryCache(
                    operation.Text,
                    operation.SourceLang.ToString(),
                    operation.TargetLang.ToString());
                history ??= CreateHistoryModel(
                    operation.Text,
                    operation.SourceLang,
                    operation.TargetLang);
                // 词典手动执行保持现有历史语义：仅更新内存对象，不额外落盘。
                history.Data.Add(new(service) { DictResult = result });
                return;

            case ITranslatePlugin plugin:
                if (plugin.TransResult.IsProcessing)
                    return;

                operation.ActivateIdentifiedLanguage();
                var context = await ResolveTranslationLanguageContextAsync(
                    operation,
                    null).ConfigureAwait(false);
                if (!operation.TryPrepare(plugin))
                    return;

                var translateResult = await operation.TranslateAsync(
                    plugin,
                    context.EffectiveSource,
                    context.EffectiveTarget).ConfigureAwait(false);
                if (!translateResult.IsSuccess ||
                    !operation.IsCurrent(plugin.TransResult))
                    return;

                if (Settings.CopyAfterTranslationNotAutomatic)
                {
                    var copied = operation.TryPublish(
                        plugin.TransResult,
                        () =>
                        {
                            ClipboardHelper.SetText(translateResult.Text);
                            _snackbar.ShowSuccess(string.Format(
                                _i18n.GetTranslation("CopiedToClipboard"),
                                service.DisplayName));
                        });
                    if (!copied)
                        return;
                }

                var historyData = new HistoryData(service)
                {
                    TransResult = CloneTranslateResult(translateResult)
                };

                if (service.Options?.AutoBackTranslation ?? false)
                {
                    var backResult = await operation.BackTranslateAsync(
                        plugin,
                        translateResult.Text,
                        context.EffectiveTarget,
                        context.EffectiveSource).ConfigureAwait(false);
                    if (backResult.IsSuccess &&
                        operation.IsCurrent(plugin.TransBackResult))
                    {
                        historyData.TransBackResult = CloneTranslateResult(backResult);
                    }
                }

                await MergeManualHistoryDataAsync(
                    operation,
                    context,
                    service,
                    historyData,
                    plugin.TransResult,
                    createIfMissing: true).ConfigureAwait(false);
                return;
        }
    }

    [RelayCommand(AllowConcurrentExecutions = true, CanExecute = nameof(CanSingleTransBack))]
    private async Task SingleTransBackAsync(Service service)
    {
        if (!TryStartManualTranslation(service, out var cancellationTokenSource))
            return;

        var operation = _translationCoordinator.BeginOperation(
            InputText,
            Settings.SourceLang,
            Settings.TargetLang,
            cancellationTokenSource.Token);
        try
        {
            await ExecuteSingleTransBackAsync(
                service,
                operation).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationTokenSource.IsCancellationRequested)
        {
            // Ignore
        }
        finally
        {
            FinishManualTranslation(service, cancellationTokenSource);
        }
    }

    private async Task ExecuteSingleTransBackAsync(
        Service service,
        TranslationOperation operation)
    {
        if (string.IsNullOrWhiteSpace(operation.Text) ||
            service.Plugin is not ITranslatePlugin plugin ||
            plugin.TransBackResult.IsProcessing)
            return;

        var sourceText = plugin.TransResult.Text;
        operation.ActivateIdentifiedLanguage();
        var context = await ResolveTranslationLanguageContextAsync(
            operation,
            null).ConfigureAwait(false);
        if (!operation.TryPrepareBack(plugin))
            return;

        var backResult = await operation.BackTranslateAsync(
            plugin,
            sourceText,
            context.EffectiveTarget,
            context.EffectiveSource).ConfigureAwait(false);
        if (!backResult.IsSuccess ||
            !operation.IsCurrent(plugin.TransBackResult))
            return;

        var historyData = new HistoryData(service)
        {
            TransBackResult = CloneTranslateResult(backResult)
        };

        await MergeManualHistoryDataAsync(
            operation,
            context,
            service,
            historyData,
            plugin.TransBackResult,
            createIfMissing: false).ConfigureAwait(false);
    }

    private bool CanSingleTranslate(Service? service) =>
        CanRunManualTranslation(service) &&
        service?.Plugin is ITranslatePlugin or IDictionaryPlugin;

    private bool CanSingleTransBack(Service? service) =>
        CanRunManualTranslation(service) &&
        service?.Plugin is ITranslatePlugin;

    private bool CanRunManualTranslation(Service? service) =>
        service != null &&
        CanTranslate &&
        !IsManualTranslationRunning(service);

    private bool TryStartManualTranslation(Service service, out CancellationTokenSource cancellationTokenSource)
    {
        var key = GetManualTranslationTaskKey(service);
        lock (_manualTranslationTaskLock)
        {
            if (_manualTranslationTaskTokens.ContainsKey(key))
            {
                cancellationTokenSource = null!;
                return false;
            }

            cancellationTokenSource = new CancellationTokenSource();
            _manualTranslationTaskTokens[key] = cancellationTokenSource;
        }

        NotifyManualTranslationCanExecuteChanged();
        return true;
    }

    private void FinishManualTranslation(Service service, CancellationTokenSource cancellationTokenSource)
    {
        var key = GetManualTranslationTaskKey(service);
        lock (_manualTranslationTaskLock)
        {
            if (_manualTranslationTaskTokens.TryGetValue(key, out var current) &&
                ReferenceEquals(current, cancellationTokenSource))
            {
                _manualTranslationTaskTokens.Remove(key);
            }
        }

        cancellationTokenSource.Dispose();
        NotifyManualTranslationCanExecuteChanged();
    }

    private void CancelSingleTranslationTasks()
    {
        List<CancellationTokenSource> cancellationTokenSources;
        lock (_manualTranslationTaskLock)
        {
            cancellationTokenSources = [.. _manualTranslationTaskTokens.Values];
        }

        foreach (var cancellationTokenSource in cancellationTokenSources)
        {
            if (!cancellationTokenSource.IsCancellationRequested)
                cancellationTokenSource.Cancel();
        }
    }

    private bool IsManualTranslationRunning(Service service)
    {
        lock (_manualTranslationTaskLock)
        {
            return _manualTranslationTaskTokens.ContainsKey(GetManualTranslationTaskKey(service));
        }
    }

    private void NotifyManualTranslationCanExecuteChanged()
    {
        void Notify()
        {
            SingleTranslateCommand.NotifyCanExecuteChanged();
            SingleTransBackCommand.NotifyCanExecuteChanged();
        }

        if (Application.Current.Dispatcher.CheckAccess())
            Notify();
        else
            Application.Current.Dispatcher.Invoke(Notify);
    }

    private static string GetManualTranslationTaskKey(Service service) =>
        $"{service.MetaData.PluginID}:{service.ServiceID}";

    [RelayCommand]
    private void SwapLanguage()
    {
        if (string.IsNullOrWhiteSpace(InputText) ||
            (Settings.SourceLang == Settings.TargetLang && Settings.SourceLang == LangEnum.Auto))
            return;

        CancelAllOperations();
        (Settings.SourceLang, Settings.TargetLang) = (Settings.TargetLang, Settings.SourceLang);
        TranslateCommand.Execute(null);
    }

    [RelayCommand]
    private void Explain(string text)
    {
        ExecuteTranslate(text);
    }

    [RelayCommand(CanExecute = nameof(CanSelectIdentifiedLanguageForCurrentText))]
    private async Task SelectIdentifiedLanguageAsync(LangEnum language)
    {
        CancelAllOperations();

        TranslateCommand.Execute(language);
        Show();
        UpdateCaret();
        await Task.CompletedTask;
    }

    [RelayCommand(CanExecute = nameof(CanSelectLanguageDetectorForCurrentText))]
    private void SelectLanguageDetector(LanguageDetectorType detector)
    {
        Settings.LanguageDetector = detector;
        CancelAllOperations();

        TranslateCommand.Execute("force");
        Show();
        UpdateCaret();
    }

    #region Translation Execution Logic

    private async Task<HistoryModel?> ExecuteTranslateAsync(
        TranslationOperation operation,
        bool checkCacheFirst,
        LangEnum? forcedSourceLanguage)
    {
        var enabledSvcs = TranslateService.Services
            .Where(x => x.IsEnabled && x.Options?.ExecMode == ExecutionMode.Automatic)
            .ToList();
        if (enabledSvcs.Count == 0)
            return null;

        HistoryModel? history = null;
        var uncachedSvcs = new List<Service>(enabledSvcs);

        // 尝试从缓存加载
        if (checkCacheFirst)
        {
            history = GetFromMemoryCache(
                operation.Text,
                operation.SourceLang.ToString(),
                operation.TargetLang.ToString());
            operation.CancellationToken.ThrowIfCancellationRequested();

            if (history != null)
            {
                operation.PublishIdentifiedLanguage(
                    () => ApplyIdentifiedLanguageState(CreateCacheIdentifiedLanguageState(history)));
                uncachedSvcs = PopulateResultsFromCache(
                    history,
                    enabledSvcs,
                    operation);
            }
        }

        if (uncachedSvcs.Count == 0)
            return history;

        var context = await ResolveTranslationLanguageContextAsync(
            operation,
            forcedSourceLanguage);

        history ??= CreateHistoryModel(operation.Text, context.CacheSource, context.CacheTarget);
        ApplyEffectiveLanguages(history, context.EffectiveSource, context.EffectiveTarget);

        await ExecuteTranslationForServicesAsync(
            uncachedSvcs,
            context.EffectiveSource,
            context.EffectiveTarget,
            history,
            operation);

        return history;
    }

    private HistoryModel CreateHistoryModel(string sourceText, LangEnum source, LangEnum target)
    {
        return new HistoryModel
        {
            Time = DateTime.Now,
            SourceText = sourceText,
            SourceLang = source.ToString(),
            TargetLang = target.ToString(),
            Data = []
        };
    }

    private static void ApplyEffectiveLanguages(HistoryModel history, LangEnum source, LangEnum target)
    {
        history.EffectiveSourceLang = source.ToString();
        history.EffectiveTargetLang = target.ToString();
    }

    /// <summary>
    /// 统一维护历史记录里的服务名称快照，确保历史展示和导出不依赖当前服务配置。
    /// </summary>
    private static void UpdateHistoryServiceSnapshot(HistoryData historyData, Service service)
    {
        historyData.ServiceDisplayName = service.DisplayName;
    }

    private async Task MergeManualHistoryDataAsync(
        TranslationOperation operation,
        TranslationLanguageContext context,
        Service service,
        HistoryData incomingData,
        object resultChannel,
        bool createIfMissing)
    {
        if (!operation.IsCurrent(resultChannel))
            return;

        await _manualTranslationHistoryLock.WaitAsync(operation.CancellationToken).ConfigureAwait(false);
        try
        {
            operation.CancellationToken.ThrowIfCancellationRequested();
            if (!operation.IsCurrent(resultChannel))
                return;

            var history = GetFromMemoryCache(
                operation.Text,
                operation.SourceLang.ToString(),
                operation.TargetLang.ToString());
            operation.CancellationToken.ThrowIfCancellationRequested();
            if (!operation.IsCurrent(resultChannel))
                return;

            if (history == null)
            {
                if (!createIfMissing)
                    return;

                history = CreateHistoryModel(operation.Text, context.CacheSource, context.CacheTarget);
            }

            ApplyEffectiveLanguages(history, context.EffectiveSource, context.EffectiveTarget);

            var existingData = history.GetData(service);
            if (existingData == null)
            {
                if (!createIfMissing)
                    return;

                history.Data.Add(incomingData);
            }
            else
            {
                MergeHistoryData(existingData, incomingData);
            }

            var enabledServices = TranslateService.Services.Where(x => x.IsEnabled).ToList();
            history.Data = [.. history.Data.OrderBy(data => enabledServices.FindIndex(svc => svc.ServiceID.Equals(data.ServiceID)))];
            if (!operation.IsCurrent(resultChannel))
                return;

            SaveToMemoryCache(history);
        }
        finally
        {
            _manualTranslationHistoryLock.Release();
        }
    }

    private static void MergeHistoryData(HistoryData existingData, HistoryData incomingData)
    {
        existingData.ServiceDisplayName = incomingData.ServiceDisplayName ?? existingData.ServiceDisplayName;
        existingData.TransResult = incomingData.TransResult ?? existingData.TransResult;
        existingData.TransBackResult = incomingData.TransBackResult ?? existingData.TransBackResult;
        existingData.DictResult = incomingData.DictResult ?? existingData.DictResult;
    }

    private static TranslateResult CloneTranslateResult(TranslateResult result) =>
        new()
        {
            IsSuccess = result.IsSuccess,
            Text = result.Text,
            Duration = result.Duration
        };

    /// <summary>
    /// 从缓存填充翻译结果，并返回未缓存的服务列表
    /// </summary>
    private List<Service> PopulateResultsFromCache(
        HistoryModel history,
        List<Service> services,
        TranslationOperation operation)
    {
        var uncachedServices = new List<Service>();
        foreach (var service in services)
        {
            operation.CancellationToken.ThrowIfCancellationRequested();
            if (history.GetData(service) is { } data)
            {
                PopulateServiceResultFromData(service, data, operation);
                if (!history.HasData(service))
                    uncachedServices.Add(service);
            }
            else
            {
                uncachedServices.Add(service);
            }
        }

        return uncachedServices;
    }

    /// <summary>
    /// 根据历史数据填充单个服务的结果
    /// </summary>
    private static void PopulateServiceResultFromData(
        Service svc,
        HistoryData data,
        TranslationOperation operation)
    {
        if (svc.Plugin is ITranslatePlugin tPlugin)
        {
            if (data.TransResult != null && data.TransResult.IsSuccess && !string.IsNullOrWhiteSpace(data.TransResult.Text))
            {
                operation.TryPublish(
                    tPlugin.TransResult,
                    () => tPlugin.TransResult.Update(data.TransResult));
            }

            if ((svc.Options?.AutoBackTranslation ?? false) && data.TransBackResult != null && data.TransBackResult.IsSuccess && !string.IsNullOrWhiteSpace(data.TransBackResult.Text))
            {
                operation.TryPublish(
                    tPlugin.TransBackResult,
                    () => tPlugin.TransBackResult.Update(data.TransBackResult));
            }
        }
        else if (svc.Plugin is IDictionaryPlugin dPlugin)
        {
            if (data.DictResult != null && data.DictResult.ResultType != DictionaryResultType.Error && data.DictResult.ResultType != DictionaryResultType.None)
                operation.PublishDictionary(
                    data.DictResult,
                    dPlugin.DictionaryResult);
        }
    }

    /// <summary>
    /// 为指定的服务列表执行翻译
    /// </summary>
    private async Task ExecuteTranslationForServicesAsync(
        IEnumerable<Service> services,
        LangEnum source,
        LangEnum target,
        HistoryModel history,
        TranslationOperation operation)
    {
        var maxConcurrency = Math.Min(services.Count(), Environment.ProcessorCount * 10);
        using var semaphore = new SemaphoreSlim(maxConcurrency, maxConcurrency);

        var translateTasks = services.Select(svc =>
            ExecuteTranslationHandlerAsync(
                svc,
                source,
                target,
                semaphore,
                history,
                operation));

        try
        {
            await Task.WhenAll(translateTasks).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Ignore
        }
    }

    private async Task ExecuteTranslationHandlerAsync(
        Service svc,
        LangEnum source,
        LangEnum target,
        SemaphoreSlim semaphore,
        HistoryModel history,
        TranslationOperation operation)
    {
        await semaphore.WaitAsync(operation.CancellationToken).ConfigureAwait(false);
        try
        {
            switch (svc.Plugin)
            {
                case ITranslatePlugin translatePlugin:
                    await ProcessTranslatePluginAsync(
                        svc,
                        translatePlugin,
                        source,
                        target,
                        history,
                        operation).ConfigureAwait(false);
                    break;
                case IDictionaryPlugin dictionaryPlugin:
                    await ProcessDictionaryPluginAsync(
                        svc,
                        dictionaryPlugin,
                        history,
                        operation).ConfigureAwait(false);
                    break;
            }
        }
        finally
        {
            semaphore.Release();
        }
    }

    private async Task ProcessTranslatePluginAsync(
        Service service,
        ITranslatePlugin plugin,
        LangEnum source,
        LangEnum target,
        HistoryModel history,
        TranslationOperation operation)
    {
        // 如果历史记录中没有该服务的数据，则执行全新翻译
        if (history.GetData(service) == null)
        {
            await ExecuteNewTranslationAsync(
                service,
                plugin,
                source,
                target,
                history,
                operation).ConfigureAwait(false);
        }
        // 否则，只执行反向翻译（如果需要）
        else if ((service.Options?.AutoBackTranslation ?? false) && history.GetData(service)?.TransBackResult == null)
        {
            await ExecuteBackTranslationOnlyAsync(
                service,
                plugin,
                target,
                source,
                history,
                operation).ConfigureAwait(false);
        }
    }

    private async Task ExecuteNewTranslationAsync(
        Service service,
        ITranslatePlugin plugin,
        LangEnum source,
        LangEnum target,
        HistoryModel history,
        TranslationOperation operation)
    {
        var translateResult = await operation.TranslateAsync(
            plugin,
            source,
            target).ConfigureAwait(false);
        if (!translateResult.IsSuccess ||
            !operation.IsCurrent(plugin.TransResult))
            return;

        var historyData = new HistoryData(service);
        history.Data.Add(historyData);
        UpdateHistoryServiceSnapshot(historyData, service);
        historyData.TransResult = translateResult;

        if (service.Options?.AutoBackTranslation ?? false)
        {
            var backResult = await operation.BackTranslateAsync(
                plugin,
                translateResult.Text,
                target,
                source).ConfigureAwait(false);
            if (operation.IsCurrent(plugin.TransBackResult))
                historyData.TransBackResult = backResult;
        }
    }

    private async Task ExecuteBackTranslationOnlyAsync(
        Service service,
        ITranslatePlugin plugin,
        LangEnum target,
        LangEnum source,
        HistoryModel history,
        TranslationOperation operation)
    {
        if (history.GetData(service) is not { } historyData ||
            string.IsNullOrWhiteSpace(historyData.TransResult?.Text))
            return;

        var backResult = await operation.BackTranslateAsync(
            plugin,
            historyData.TransResult.Text,
            target,
            source).ConfigureAwait(false);
        if (!operation.IsCurrent(plugin.TransBackResult))
            return;

        UpdateHistoryServiceSnapshot(historyData, service);
        historyData.TransBackResult = backResult;
    }

    private async Task ProcessDictionaryPluginAsync(
        Service service,
        IDictionaryPlugin plugin,
        HistoryModel history,
        TranslationOperation operation)
    {
        // 如果缓存中已存在数据则跳过
        if (history.HasData(service))
            return;

        var result = await operation.LookupAsync(plugin).ConfigureAwait(false);
        if (result.ResultType == DictionaryResultType.Error ||
            !operation.IsCurrent(plugin.DictionaryResult))
            return;

        var historyData = new HistoryData(service);
        history.Data.Add(historyData);
        UpdateHistoryServiceSnapshot(historyData, service);
        historyData.DictResult = result;
    }

    #endregion

    #region Auto Translate

    [RelayCommand]
    private void ToggleAutoTranslate()
    {
        Settings.AutoTranslate = !Settings.AutoTranslate;
        if (Settings.AutoTranslate)
            _snackbar.ShowSuccess(_i18n.GetTranslation("AutoTranslateEnabled"));
        else
            _snackbar.ShowInfo(_i18n.GetTranslation("AutoTranslateDisabled"));
    }
    
    #endregion

    #endregion


    #region TTS & Audio Commands

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task PlayAudioAsync(string text, CancellationToken cancellationToken)
    {
        var ttsSvc = TtsService.GetActiveSvc<ITtsPlugin>();
        if (ttsSvc == null)
        {
            Helper.PromptConfigureService(
                _i18n.GetTranslation("Prompt"),
                _i18n.GetTranslation("TtsServiceNotFound"),
                nameof(TtsPage));
            return;
        }

        try
        {
            await ttsSvc.PlayAudioAsync(text, cancellationToken);
        }
        catch (TaskCanceledException)
        {
            _snackbar.ShowInfo(_i18n.GetTranslation("TtsCancelled"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "TTS播放失败");
            _snackbar.ShowError(_i18n.GetTranslation("TtsFailed"));
        }
    }

    /// <summary>
    /// 划词翻译触发后自动朗读原文。
    /// 未启用自动朗读、文本为空或超长、没有可用的语音合成服务时静默跳过，不打断翻译流程。
    /// </summary>
    /// <param name="text">待朗读的原文。</param>
    private async void TryAutoSpeak(string? text)
    {
        try
        {
            if (!Settings.IsAutoSpeakEnabled || string.IsNullOrWhiteSpace(text))
                return;

            var content = text.Trim();
            if (content.Length > Math.Max(1, Settings.AutoSpeakMaxLength))
                return;

            var ttsSvc = TtsService.GetActiveSvc<ITtsPlugin>();
            if (ttsSvc is null)
                return;

            _logger.LogDebug("Auto speak {Length} chars.", content.Length);
            await ttsSvc.PlayAudioAsync(content, CancellationToken.None);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Auto speak failed.");
        }
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task PlayAudioUrlAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            await _audioPlayer.PlayAsync(url, cancellationToken);
        }
        catch (TaskCanceledException)
        {
            _snackbar.ShowInfo(_i18n.GetTranslation("TtsCancelled"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "音频播放失败");
            _snackbar.ShowError(_i18n.GetTranslation("TtsFailed"));
        }
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task SilentTtsAsync(CancellationToken cancellationToken)
    {
        var (success, text) = await GetTextAsync();
        if (!success || string.IsNullOrWhiteSpace(text))
            return;
        await SilentTtsHandlerAsync(text, default, cancellationToken);
    }

    public async Task SilentTtsHandlerAsync(string text, ITtsPlugin? ttsSvc = default, CancellationToken cancellationToken = default)
    {
        ttsSvc ??= TtsService.GetActiveSvc<ITtsPlugin>();
        if (ttsSvc == null)
        {
            Helper.PromptConfigureService(
                _i18n.GetTranslation("Prompt"),
                _i18n.GetTranslation("TtsServiceNotFound"),
                nameof(TtsPage));
            return;
        }

        try
        {
            CursorHelper.Execute();
            await ttsSvc.PlayAudioAsync(text, cancellationToken);
        }
        catch (TaskCanceledException)
        {
            // Ignore
        }
        finally
        {
            CursorHelper.Restore();
        }
    }

    #endregion

    #region Voculary Commands

    /// <summary>记录一次翻译过的文本，供左右箭头回看。</summary>
    private void RecordHistory(string? text)
    {
        if (_isReplayingHistory)
            return;

        var word = (text ?? string.Empty).Trim();
        if (word.Length == 0)
            return;

        // 同一个词不重复追加
        if (_translationHistory.Any(entry => string.Equals(entry.Text, word, StringComparison.Ordinal)))
        {
            _historyIndex = _translationHistory.Count - 1;
            UpdateHistoryState();
            return;
        }

        _translationHistory.Add(new HistoryEntry(word, DateTime.Now));

        if (_translationHistory.Count > TranslationHistoryLimit)
            _translationHistory.RemoveAt(0);

        _historyIndex = _translationHistory.Count - 1;
        UpdateHistoryState();
        _logger.LogDebug("历史 {Count} 条，当前索引 {Index}，可回看={Back}，可前进={Forward}",
            _translationHistory.Count, _historyIndex, CanGoHistoryBack, CanGoHistoryForward);
    }

    /// <summary>上一个翻译过的词。</summary>
    [RelayCommand]
    private void HistoryBack() => NavigateHistory(-1);

    /// <summary>下一个翻译过的词。</summary>
    [RelayCommand]
    private void HistoryForward() => NavigateHistory(1);

    private void NavigateHistory(int offset)
    {
        if (_translationHistory.Count == 0)
            return;

        var target = _historyIndex + offset;
        if (target < 0 || target >= _translationHistory.Count)
            return;

        _historyIndex = target;
        var entry = _translationHistory[target];

        _isReplayingHistory = true;
        try
        {
            InputText = entry.Text;
            ExecuteTranslate(entry.Text);
        }
        finally
        {
            _isReplayingHistory = false;
        }

        UpdateHistoryState();
    }

    private void UpdateHistoryState()
    {
        CanGoHistoryBack = _historyIndex > 0;
        CanGoHistoryForward = _historyIndex >= 0 && _historyIndex < _translationHistory.Count - 1;
    }

    /// <summary>设置变化时，音标体系需要重新下发。</summary>
    private void OnSettingsChangedForPhonetic(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(Settings.PhoneticSystem))
            ApplyPhoneticSystem();
    }

    /// <summary>把当前音标体系下发给支持该偏好的插件。</summary>
    private void ApplyPhoneticSystem()
    {
        var applied = 0;
        foreach (var service in TranslateService.Services)
        {
            if (service.Plugin is IPhoneticAware aware)
            {
                aware.PhoneticSystem = Settings.PhoneticSystem;
                applied++;
            }
        }

        _logger.LogInformation("音标体系下发 {System}：命中 {Applied}/{Total} 个翻译服务。",
            Settings.PhoneticSystem, applied, TranslateService.Services.Count);
    }

    /// <summary>后台查词典补全音标与英文释义，失败静默跳过。</summary>
    private void EnrichVocabularyInBackground(string word)
    {
        var key = (word ?? string.Empty).Trim().ToLowerInvariant();
        if (key.Length == 0)
            return;

        _ = Task.Run(async () =>
        {
            try
            {
                var info = await _dictionaryService.LookupAsync(key).ConfigureAwait(false);
                if (info is null)
                    return;

                // Enrich 会触发集合变更通知，必须回到 UI 线程执行
                await Application.Current.Dispatcher.InvokeAsync(
                    () => VocabularyStore.Enrich(key, info.Phonetic, info.Meaning));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "补充生词信息失败：{Word}", key);
            }
        });
    }

    /// <summary>取当前翻译结果首行，作为生词本的简短释义。</summary>
    private string TakeCurrentMeaning()
    {
        var text = TranslateService.GetActiveSvc<ITranslatePlugin>()?.TransResult?.Text;
        if (string.IsNullOrWhiteSpace(text))
            return string.Empty;

        var lines = text
            .Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0)
            .ToList();

        // 译文过长或行数多说明是整段翻译，不适合当词条释义，直接留空
        if (lines.Count != 1 || lines[0].Length > 60)
            return string.Empty;

        return lines[0];
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private Task SaveToVocabularyAsync(string text, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("InputContentIsEmpty"));
            return Task.CompletedTask;
        }

        var added = VocabularyStore.Add(text, meaning: TakeCurrentMeaning());
        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));
        EnrichVocabularyInBackground(text);
        return Task.CompletedTask;
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task SaveToVocabularyWithNoteAsync(Service service, CancellationToken cancellationToken)
    {
        if (service.Plugin is not ITranslatePlugin plugin || plugin.TransResult.IsProcessing)
            return;

        var word = InputText;
        var note = plugin.TransResult.IsSuccess ? plugin.TransResult.Text : string.Empty;

        if (string.IsNullOrWhiteSpace(word))
        {
            _snackbar.ShowWarning(_i18n.GetTranslation("InputContentIsEmpty"));
            return;
        }

        if (cancellationToken.IsCancellationRequested)
            return;

        var added = VocabularyStore.Add(word, note: note, source: service.DisplayName);
        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));
        EnrichVocabularyInBackground(word);
    }

    #endregion


    #region Mouse Selection Feature

    [RelayCommand]
    private void ToggleMouseSelectionTranslation() =>
        Settings.IsMouseSelectionTranslationEnabled = !Settings.IsMouseSelectionTranslationEnabled;



    private async void OnMouseSelectionStarted(object? sender, System.Drawing.Point point)
    {
        try
        {
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                // 用户点到气泡以外的地方（选区随之消失）时，气泡立即收起
                if (!_mouseSelectionBubbleWindow.ContainsPhysicalPoint(point))
                    _mouseSelectionBubbleWindow.HideWindow();

                // 窗口有时拿不到前台焦点，失焦隐藏不会触发；
                // 这里用全局鼠标钩子兜底：点在主窗口之外就收起。
                // 但用户手动钉住的窗口、以及「直接翻译」强制置顶的窗口要保持显示，不能被点走。
                var visible = MainWindow is { IsVisible: true };
                var inside = IsPointInsideMainWindow(point);
                _logger.LogDebug("Outside click: pinned={0} visible={1} inside={2}", IsUserTopmost, visible, inside);

                if (!IsUserTopmost && visible && !inside)
                    Hide();
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process mouse selection start.");
        }
    }

    /// <summary>
    /// 判断物理屏幕坐标是否落在主窗口内（用于区分"点窗口"和"点别处"）。
    /// </summary>
    /// <param name="point">物理屏幕坐标。</param>
    private bool IsPointInsideMainWindow(System.Drawing.Point point)
    {
        try
        {
            if (MainWindow is null)
                return false;

            var hwnd = new System.Windows.Interop.WindowInteropHelper(MainWindow).Handle;
            if (hwnd == IntPtr.Zero)
                return false;

            if (!PInvoke.GetWindowRect(new Windows.Win32.Foundation.HWND(hwnd), out var bounds))
                return false;

            return point.X >= bounds.left && point.X < bounds.right &&
                   point.Y >= bounds.top && point.Y < bounds.bottom;
        }
        catch (Exception)
        {
            return false;
        }
    }



    /// <summary>
    /// 划词气泡模式下选中文本后，在光标旁显示气泡（此时不取词、不翻译）。
    /// </summary>
    /// <param name="drawingPoint">鼠标的物理屏幕坐标。</param>
    private async void OnMouseSelectionBubbleRequested(object? sender, System.Drawing.Point drawingPoint)
    {
        try
        {
            _logger.LogDebug("Mouse selection bubble requested at {X},{Y}.", drawingPoint.X, drawingPoint.Y);
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                var point = new System.Windows.Point(drawingPoint.X, drawingPoint.Y);
                _mouseSelectionBubbleWindow.HoverDelayMs = Settings.BubbleHoverDelayMs;
                _mouseSelectionBubbleWindow.ShowAt(point);
                _logger.LogDebug("Mouse selection bubble shown: visible={Visible}, left={Left}, top={Top}.",
                    _mouseSelectionBubbleWindow.IsVisible, _mouseSelectionBubbleWindow.Left, _mouseSelectionBubbleWindow.Top);
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to show the mouse selection bubble.");
        }
    }

    /// <summary>
    /// 用户悬停达到延迟（或点击气泡）后取词并翻译。
    /// 取词优先走 UI Automation，失败才回退模拟复制并恢复剪贴板。
    /// </summary>
    private async void OnMouseSelectionBubbleHoverCompleted(object? sender, EventArgs e)
    {
        try
        {
            var text = await _mouseSelectionService.CaptureBubbleSelectedTextAsync();
            if (string.IsNullOrWhiteSpace(text))
            {
                _logger.LogWarning("Mouse selection bubble captured empty text, translation skipped.");
                return;
            }

            _ = Application.Current.Dispatcher.InvokeAsync(() =>
            {
                // 气泡由鼠标悬停触发，此时本进程通常不是前台，必须强制置前；
                // 否则窗口显示后拿不到焦点，用户点击别处时不会触发失焦隐藏，窗口会一直挂着
                using var _ = WindowActivationContext.Push(WindowActivationMode.ForceForeground);
                // 置顶租约保证窗口一定浮在最上层；窗口隐藏时在 Hide() 中释放
                AcquireManagedTopmost(ref _bubbleTranslateHasTopmostLease);
                TryAutoSpeak(text);
                ExecuteTranslate(HandleCapturedText(text, TextSeparatorHandleScope.MouseSelection));
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to translate from the mouse selection bubble.");
        }
    }

    /// <summary>
    /// 左键长按：弹出全屏遮罩让用户框选区域，识别文字后直接翻译。
    /// </summary>
    private void OnLongPressTriggered(object? sender, System.Drawing.Point point)
    {
        if (!Settings.IsLongPressOcrEnabled)
            return;

        StartRegionOcr();
    }

    /// <summary>热键触发的框选识别。</summary>
    [RelayCommand]
    private void RegionOcr() => StartRegionOcr();

    /// <summary>
    /// 弹出全屏遮罩让用户框选区域，识别文字后直接翻译。长按与热键共用。
    /// </summary>
    private void StartRegionOcr()
    {
        if (_isCapturingRegion)
            return;

        _ = Application.Current.Dispatcher.InvokeAsync(async () =>
        {
            if (_isCapturingRegion)
                return;

            _isCapturingRegion = true;
            try
            {
                if (MainWindow is { IsVisible: true })
                    MainWindow.Visibility = Visibility.Collapsed;

                var overlay = new ScreenRegionOverlay();
                overlay.Show();
                var region = await overlay.Completion;

                await Task.Delay(250);
                if (region is not { Width: > 4, Height: > 4 } rect)
                {
                    _logger.LogDebug("Region capture cancelled.");
                    return;
                }

                using var bitmap = CaptureRegion(rect);
                _logger.LogInformation("Region capture: {X},{Y} {W}x{H}", rect.X, rect.Y, rect.Width, rect.Height);

                var text = await _ocrService.RecognizeAsync(bitmap);
                if (string.IsNullOrWhiteSpace(text))
                {
                    SaveOcrDebugImage(bitmap, rect);

                    // 窗口为了截图已经隐藏，没识别到内容也要拉回来，否则用户以为程序退出了
                    if (MainWindow is { IsVisible: false })
                        Show();

                    _snackbar.ShowWarning(_i18n.GetTranslation("OcrNoTextFound"));
                    return;
                }

                var normalized = NormalizeOcrText(text);
                _logger.LogInformation("OCR captured {Chars} chars from {W}x{H} region.", normalized.Length, rect.Width, rect.Height);

                // 框选期间主窗口让开了位置，识别完成后要拉回来再翻译
                if (MainWindow is { IsVisible: false })
                    Show();

                InputText = normalized;
                TryAutoSpeak(normalized);
                ExecuteTranslate(normalized);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Region OCR failed.");
                _snackbar.ShowError(_i18n.GetTranslation("OperationFailed"));
            }
            finally
            {
                _isCapturingRegion = false;
            }
        });
    }

    /// <summary>识别失败时保留截图，便于排查（只留最近 5 张）。</summary>
    private void SaveOcrDebugImage(System.Drawing.Bitmap bitmap, System.Drawing.Rectangle rect)
    {
        try
        {
            var dir = Path.Combine(@"D:\dsh\downloads", "ocr-debug");
            Directory.CreateDirectory(dir);

            var files = Directory.GetFiles(dir, "*.png")
                .OrderByDescending(File.GetLastWriteTime)
                .Skip(4)
                .ToList();
            foreach (var old in files)
                File.Delete(old);

            var path = Path.Combine(dir, $"ocr-{DateTime.Now:yyyyMMdd_HHmmss_fff}_{rect.Width}x{rect.Height}.png");
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            _logger.LogWarning("OCR 未识别到文字，截图已保存：{Path}", path);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "保存 OCR 调试截图失败。");
        }
    }

    /// <summary>把屏幕选区抓成位图。</summary>
    private static System.Drawing.Bitmap CaptureRegion(System.Drawing.Rectangle rect)
    {
        var bitmap = new System.Drawing.Bitmap(rect.Width, rect.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var graphics = System.Drawing.Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(rect.Location, System.Drawing.Point.Empty, rect.Size);
        return bitmap;
    }

    /// <summary>整理 OCR 结果：去掉空行与行首尾空白。</summary>
    private static string NormalizeOcrText(string text)
    {
        var lines = text
            .Replace("\r\n", "\n")
            .Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.Length > 0);

        return string.Join('\n', lines);
    }

    private void OnMouseSelectionBubbleDismissRequested(object? sender, EventArgs e)
        => _ = Application.Current.Dispatcher.InvokeAsync(_mouseSelectionBubbleWindow.HideWindow);

    private void OnMouseSelectionTextSelected(object? sender, string text)
    {
        _ = Application.Current.Dispatcher.InvokeAsync(() =>
        {
            TryAutoSpeak(text);
            ExecuteTranslate(HandleCapturedText(text, TextSeparatorHandleScope.MouseSelection));
        });
    }

    private void OnMouseSelectionStateChanged(object? sender, EventArgs e)
        => _ = Application.Current.Dispatcher.InvokeAsync(ApplyMouseSelectionWindowMode);

    private void ApplyMouseSelectionWindowMode()
    {
        // 置顶完全交给左上角钉子按钮，划词模式不再强制置顶
        ReleaseManagedTopmost(ref _mouseSelectionTranslationHasTopmostLease);
    }

    private void AcquireManagedTopmost(ref bool lease)
    {
        if (lease)
            return;

        lease = true;
        _managedTopmostLeaseCount++;
        SetTopmostInternally(true);
    }

    private void ReleaseManagedTopmost(ref bool lease)
    {
        if (!lease)
            return;

        lease = false;
        _managedTopmostLeaseCount--;
        if (_managedTopmostLeaseCount == 0)
            SetTopmostInternally(IsUserTopmost);
    }

    private void SetTopmostInternally(bool value)
    {
        _isApplyingManagedTopmost = true;
        try
        {
            IsTopmost = value;
        }
        finally
        {
            _isApplyingManagedTopmost = false;
        }
    }

    [RelayCommand]
    private async Task CrosswordTranslateAsync()
    {
        var (success, text) = await GetTextAsync(showFailureFeedback: false);
        if (!success || string.IsNullOrWhiteSpace(text))
        {
            HandleCrosswordFetchFailed();
            return;
        }

        TryAutoSpeak(text);
        ExecuteTranslate(HandleCapturedText(text, TextSeparatorHandleScope.Crossword));
    }

    public void CrosswordTranslateByCtrlSameCHandler()
    {
        _ = Application.Current.Dispatcher.InvokeAsync(() =>
        {
            // Ctrl+C+C 由其他前台应用触发，需要越过前台锁确保翻译窗口可见。
            using var _ = WindowActivationContext.Push(WindowActivationMode.ForceForeground);

            var text = ClipboardHelper.GetText()?.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                HandleCrosswordFetchFailed();
                return;
            }

            TryAutoSpeak(text);
            ExecuteTranslate(HandleCapturedText(text, TextSeparatorHandleScope.Crossword));
        });
    }

    [RelayCommand]
    private void ToggleClipboardMonitor() => IsClipboardMonitoring = !IsClipboardMonitoring;

    partial void OnIsClipboardMonitoringChanged(bool value) => ToggleClipboardMonitorHandler(value);

    private void ToggleClipboardMonitorHandler(bool value)
    {
        if (value)
        {
            StartClipboardMonitor();
        }
        else
        {
            StopClipboardMonitor();
        }
    }

    private void StartClipboardMonitor()
    {
        _clipboardMonitor ??= new ClipboardMonitor(MainWindow);
        _clipboardMonitor.OnClipboardTextChanged += OnClipboardTextChanged;
        _clipboardMonitor.Start();
        _notification.Show(
            _i18n.GetTranslation("Hotkey_ClipboardMonitor"),
            _i18n.GetTranslation("ClipboardMonitorStarted"));
    }

    private void StopClipboardMonitor()
    {
        if (_clipboardMonitor != null)
        {
            _clipboardMonitor.OnClipboardTextChanged -= OnClipboardTextChanged;
            _clipboardMonitor.Stop();
        }
        _notification.Show(
            _i18n.GetTranslation("Hotkey_ClipboardMonitor"),
            _i18n.GetTranslation("ClipboardMonitorStopped"));
    }

    private void OnClipboardTextChanged(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;

        App.Current.Dispatcher.Invoke(() =>
            ExecuteTranslate(HandleCapturedText(text, TextSeparatorHandleScope.ClipboardMonitor)));
    }


    /// <summary>
    /// 初始化主窗口布局约束，避免窗口首次显示时沿用过期的高度上限。
    /// </summary>
    public void InitializeWindowLayoutConstraints() => UpdateMainWindowMaxHeightConstraint();

    public void Show()
    {
        MainWindow.PrepareShowAnimation();
        if (Settings.MainWindowLeft <= -18000 && Settings.MainWindowTop <= -18000)
        {
            Settings.MainWindowLeft = _cacheLeft;
            Settings.MainWindowTop = _cacheTop;
        }
        MainWindow.Visibility = Visibility.Visible;
        UpdateMainWindowMaxHeightConstraint();
        UpdatePosition();
        UpdateMainWindowMaxHeightConstraint();

        MainWindow.StartShowAnimation(() =>
        {
            ActivateMainWindow();

            // 用户钉住窗口时，重新声明置顶，防止被后弹出的窗口覆盖
            if (IsUserTopmost)
            {
                // 走内部方法而不是直接给窗口属性赋值：本地赋值会打断 Topmost 的单向绑定
                SetTopmostInternally(true);
                try
                {
                    Win32Helper.RaiseWindowWithoutActivation(MainWindow, showWindow: false);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Raise pinned window failed.");
                }
            }
        });
    }

    private void ActivateMainWindow()
    {
        Win32Helper.ActivateForegroundWindow(MainWindow);

        MainWindow.Activate();

        if (IsInputBoxVisible)
        {
            MainWindow.PART_Input.Focus();
            Keyboard.Focus(MainWindow.PART_Input);
        }
    }

    public void Hide()
    {
        // 用户钉住的窗口不隐藏：外面点一下、失焦回退等路径都被这里拦住
        if (IsUserTopmost)
        {
            _logger.LogDebug("Hide skipped: window is pinned.");
            return;
        }

        // 窗口隐藏即释放气泡翻译申请的置顶，避免影响后续普通窗口的层级行为
        ReleaseManagedTopmost(ref _bubbleTranslateHasTopmostLease);
        ExitInputTranslateMode();
        MainWindow.Visibility = Visibility.Collapsed;
        MainWindow.StopShowAnimation();
    }

    [RelayCommand]
    private void DoubleClick()
    {
        switch (Settings.DoubleClickTrayFunction)
        {
            case DoubleClickTrayFunction.InputTranslate:
                InputClear();
                break;
            case DoubleClickTrayFunction.OpenSettingsWindow:
                OpenSettingsCommand.Execute(null);
                break;
            case DoubleClickTrayFunction.ToggleMouseSelectionTranslation:
                ToggleMouseSelectionTranslationCommand.Execute(null);
                break;
            case DoubleClickTrayFunction.ToggleGlobalHotkeys:
                ToggleGlobalHotkey();
                break;
            case DoubleClickTrayFunction.Exit:
                Exit(AppShutdownReason.TrayDoubleClick);
                break;
            default:
                break;
        }
    }

    [RelayCommand]
    private void LeftClick()
    {
        // 开启后单击托盘功能禁用
        if (Settings.DoubleClickTrayFunction != DoubleClickTrayFunction.None)
            return;

        ToggleApp();
    }

    [RelayCommand]
    private void ToggleApp()
    {
        if (IsMainWindowVisible && !IsTopmost)
            Hide();
        else
            Show();
    }

    [RelayCommand]
    private void Cancel(Window window)
    {
        if (!Settings.IsMouseSelectionTranslationEnabled)
        {
            if (IsTopmost) IsTopmost = false;
            ExitInputTranslateMode();
            window.Visibility = Visibility.Collapsed;
        }
        CancelAllOperations();
    }

    [RelayCommand]
    private async Task OpenSettingsAsync(object? parameter)
    {
        await OpenSettingsAndNavigateAsync(parameter);
    }

    internal async Task OpenSettingsAndNavigateAsync(object? parameter)
    {
        var isAlreadyOpen = Application.Current.Windows.OfType<SettingsWindow>().Any();
        var window = await OpenSettingsInternalAsync(parameter);

        if (!isAlreadyOpen)
            window.Navigate(nameof(GeneralPage));
    }

    internal async Task<SettingsWindow> OpenSettingsInternalAsync(object? parameter)
    {
        // 如果由 ContextMenu 触发，等待关闭动画完成
        if (parameter is not null)
            await Task.Delay(ContextMenuCloseAnimationDelay);

        // 如果从主窗口打开设置，主动隐藏主窗口
        if (MainWindow.IsActive && IsMainWindowVisible && !IsTopmost)
            Hide();

        return await SingletonWindowOpener.OpenAsync<SettingsWindow>();
    }

    [RelayCommand]
    private async Task OpenHistoryAsync()
    {
        await OpenHistoryInternalAsync();
    }

    internal async Task OpenHistoryInternalAsync()
    {
        var window = await OpenSettingsInternalAsync(null);
        window.Navigate("HistoryPage");
    }

    [RelayCommand]
    private async Task NavigateAsync(Service service)
    {
        var window = await OpenSettingsInternalAsync(string.Empty);
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            window.Navigate(nameof(TranslatePage), selectedService: service);
        }, DispatcherPriority.Normal);
    }

    [RelayCommand]
    private void CloseService(Service service) => service.IsEnabled = false;

    [RelayCommand]
    /// <summary>
    ///     切换钉住状态：以"用户是否钉住"取反，而不是以窗口当前层级取反。
    ///     否则气泡翻译的临时置顶会让切换方向反掉（开=不钉、关=钉）。
    /// </summary>
    private void ToggleTopmost() => IsTopmost = !IsUserTopmost;

    [RelayCommand]
    private void ToggleHideInput() => IsInputActuallyHidden = !IsInputActuallyHidden;

    [RelayCommand]
    private void ChangeColorScheme()
    {
        var current = Settings.ColorScheme;
        var next = current + 1;
        if (next > ElementTheme.Dark) next = 0;
        Settings.ColorScheme = next;
    }

    [RelayCommand]
    private void Exit(AppShutdownReason reason) => App.RequestShutdown(reason);

    #endregion

    #region Text & Clipboard Manipulation

    [RelayCommand]
    private void InputClear()
    {
        CancelAllOperations();
        ResetTranslationLanguageState();
        InputText = string.Empty;

        var operation = _translationCoordinator.BeginAutomaticOperation(
            InputText,
            Settings.SourceLang,
            Settings.TargetLang,
            CancellationToken.None);
        ResetAllServices(operation);
        EnterInputTranslateMode();
        Show();
    }

    [RelayCommand]
    private void Copy(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        ClipboardHelper.SetText(text);
        _snackbar.ShowSuccess(_i18n.GetTranslation("CopySuccess"));
    }

    [RelayCommand]
    private void CopyPascalCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var pascalCaseText = Utilities.ToPascalCase(text);
        ClipboardHelper.SetText(pascalCaseText);
        _snackbar.ShowSuccess(_i18n.GetTranslation("CopySuccess"));
    }

    [RelayCommand]
    private void CopyCamelCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var pascalCaseText = Utilities.ToCamelCase(text);
        ClipboardHelper.SetText(pascalCaseText);
        _snackbar.ShowSuccess(_i18n.GetTranslation("CopySuccess"));
    }

    [RelayCommand]
    private void CopySnakeCase(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var pascalCaseText = Utilities.ToSnakeCase(text);
        ClipboardHelper.SetText(pascalCaseText);
        _snackbar.ShowSuccess(_i18n.GetTranslation("CopySuccess"));
    }

    [RelayCommand]
    private async Task InsertAsync(string text)
    {
        if (string.IsNullOrEmpty(text)) return;

        // 如果按住Shift则使用小写
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift))
            text = text.ToLower();

        if (IsTopmost) IsTopmost = false;
        Hide();
        await Task.Delay(150);
        InputHelper.PrintText(text);
    }

    private void RestartTranslation()
    {
        CancelAllOperations();
        TranslateCommand.Execute(null);
    }

    [RelayCommand]
    private void CleanTransBack(ITranslatePlugin plugin)
    {
        var operation = _translationCoordinator.BeginOperation(
            InputText,
            Settings.SourceLang,
            Settings.TargetLang,
            CancellationToken.None);
        operation.TryPrepareBack(plugin);
    }

    #endregion

    #region Window Position

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(Settings.SourceLang) ||
            e.PropertyName == nameof(Settings.TargetLang))
        {
            ResetTranslationLanguageState();
        }

        if (e.PropertyName == nameof(Settings.HideInput) ||
            e.PropertyName == nameof(Settings.HideInputWithLangSelectControl))
        {
            NotifyInputVisibilityProperties();
        }

        if (e.PropertyName != nameof(Settings.MainWindowMaxHeightRatio) &&
            e.PropertyName != nameof(Settings.WindowScreen) &&
            e.PropertyName != nameof(Settings.CustomScreenNumber))
            return;

        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher == null)
            return;

        void RefreshWindowHeightConstraint()
        {
            UpdateMainWindowMaxHeightConstraint();
            if (IsMainWindowVisible)
                AdjustPositionForContentSizeChanged();
        }

        if (dispatcher.CheckAccess())
        {
            RefreshWindowHeightConstraint();
            return;
        }

        dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(RefreshWindowHeightConstraint));
    }

    /// <summary>
    /// 根据当前屏幕工作区和用户配置比例刷新主窗口最大高度约束。
    /// </summary>
    /// <param name="monitor">可选。指定目标显示器，避免跟随鼠标场景下读取到旧屏幕。</param>
    private void UpdateMainWindowMaxHeightConstraint(MonitorInfo? monitor = null)
    {
        if (Application.Current?.MainWindow is not MainWindow window)
            return;

        var ratio = Math.Clamp(Settings.MainWindowMaxHeightRatio, 0.6, 1.0);
        if (Math.Abs(ratio - Settings.MainWindowMaxHeightRatio) > double.Epsilon)
        {
            // 统一写回归一化后的比例，确保各入口读取到一致约束。
            Settings.MainWindowMaxHeightRatio = ratio;
        }

        var targetMonitor = monitor ?? GetWindowMonitor();
        var workAreaTopLeft = Win32Helper.TransformPixelsToDIP(window, targetMonitor.WorkingArea.X, targetMonitor.WorkingArea.Y);
        var workAreaBottomRight = Win32Helper.TransformPixelsToDIP(
            window,
            targetMonitor.WorkingArea.X + targetMonitor.WorkingArea.Width,
            targetMonitor.WorkingArea.Y + targetMonitor.WorkingArea.Height);

        var workAreaHeight = Math.Max(0, workAreaBottomRight.Y - workAreaTopLeft.Y - 8 * 2);
        var effectiveMaxHeight = Math.Max(window.MinHeight, workAreaHeight * ratio);
        MainWindowEffectiveMaxHeight = Math.Max(window.MinHeight, effectiveMaxHeight);
    }

    private MonitorInfo GetWindowMonitor()
    {
        try
        {
            var windowHelper = new WindowInteropHelper(MainWindow);
            windowHelper.EnsureHandle();
            return MonitorInfo.GetNearestDisplayMonitor(windowHelper.Handle);
        }
        catch
        {
            return SelectedScreen();
        }
    }

    public void UpdatePosition(bool hideOnStartup = false)
    {
        if (IsTopmost) return;

        InternalUpdatePosition(hideOnStartup);
        InternalUpdatePosition(hideOnStartup);

        void InternalUpdatePosition(bool hideOnStartup)
        {
            if (hideOnStartup)
            {
                // 隐藏时缓存位置，第一次打开时恢复位置
                if (Settings.WindowScreen == WindowScreenType.RememberLastLaunchLocation &&
                    _cacheLeft == 0 && _cacheTop == 0)
                {
                    _cacheLeft = Settings.MainWindowLeft;
                    _cacheTop = Settings.MainWindowTop;
                }
                Settings.MainWindowLeft = -18000;
                Settings.MainWindowTop = -18000;
                return;
            }

            if (Settings.WindowScreen == WindowScreenType.FollowMouse)
            {
                UpdatePositionNearCursor();
                return;
            }

            if (Settings.WindowScreen == WindowScreenType.RememberLastLaunchLocation)
            {
                var previousScreenWidth = Settings.PreviousScreenWidth;
                var previousScreenHeight = Settings.PreviousScreenHeight;
                GetDpi(out var previousDpiX, out var previousDpiY);

                Settings.PreviousScreenWidth = SystemParameters.VirtualScreenWidth;
                Settings.PreviousScreenHeight = SystemParameters.VirtualScreenHeight;
                GetDpi(out var currentDpiX, out var currentDpiY);

                if (previousScreenWidth != 0 && previousScreenHeight != 0 &&
                    previousDpiX != 0 && previousDpiY != 0 &&
                    (previousScreenWidth != SystemParameters.VirtualScreenWidth ||
                     previousScreenHeight != SystemParameters.VirtualScreenHeight ||
                     previousDpiX != currentDpiX || previousDpiY != currentDpiY))
                {
                    AdjustPositionForResolutionChange();
                    return;
                }

                Settings.MainWindowLeft = Settings.MainWindowLeft;
                Settings.MainWindowTop = Settings.MainWindowTop;
            }
            else
            {
                var screen = SelectedScreen();
                switch (Settings.WindowAlign)
                {
                    case WindowAlignType.Center:
                        Settings.MainWindowLeft = HorizonCenter(screen);
                        Settings.MainWindowTop = VerticalCenter(screen);
                        break;
                    case WindowAlignType.CenterTop:
                        Settings.MainWindowLeft = HorizonCenter(screen);
                        Settings.MainWindowTop = VerticalTop(screen);
                        break;
                    case WindowAlignType.LeftTop:
                        Settings.MainWindowLeft = HorizonLeft(screen);
                        Settings.MainWindowTop = VerticalTop(screen);
                        break;
                    case WindowAlignType.RightTop:
                        Settings.MainWindowLeft = HorizonRight(screen);
                        Settings.MainWindowTop = VerticalTop(screen);
                        break;
                    case WindowAlignType.Custom:
                        var customLeft = Win32Helper.TransformPixelsToDIP(MainWindow,
                            screen.WorkingArea.X + Settings.CustomWindowLeft, 0);
                        var customTop = Win32Helper.TransformPixelsToDIP(MainWindow, 0,
                            screen.WorkingArea.Y + Settings.CustomWindowTop);
                        Settings.MainWindowLeft = customLeft.X;
                        Settings.MainWindowTop = customTop.Y;
                        break;
                }
            }
        }
    }

    private void UpdatePositionNearCursor()
    {
        if (!PInvoke.GetCursorPos(out var cursorPosition))
            return;

        const double horizontalOffset = 16;
        const double verticalOffset = 20;
        const double edgePadding = 8;

        var cursorDip = Win32Helper.TransformPixelsToDIP(MainWindow, cursorPosition.X, cursorPosition.Y);

        var screen = MonitorInfo.GetCursorDisplayMonitor();
        UpdateMainWindowMaxHeightConstraint(screen);
        var workAreaTopLeft = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.X, screen.WorkingArea.Y);
        var workAreaBottomRight = Win32Helper.TransformPixelsToDIP(
            MainWindow,
            screen.WorkingArea.X + screen.WorkingArea.Width,
            screen.WorkingArea.Y + screen.WorkingArea.Height);

        var windowWidth = MainWindow.ActualWidth > 0 ? MainWindow.ActualWidth : Settings.MainWindowWidth;
        var windowHeight = MainWindow.ActualHeight > 0 ? MainWindow.ActualHeight : MainWindow.MinHeight;

        var left = cursorDip.X + horizontalOffset;
        var top = cursorDip.Y + verticalOffset;

        if (left + windowWidth > workAreaBottomRight.X - edgePadding)
            left = cursorDip.X - windowWidth - horizontalOffset;

        if (top + windowHeight > workAreaBottomRight.Y - edgePadding)
            top = cursorDip.Y - windowHeight - verticalOffset;

        var minLeft = workAreaTopLeft.X + edgePadding;
        var minTop = workAreaTopLeft.Y + edgePadding;
        var maxLeft = workAreaBottomRight.X - windowWidth - edgePadding;
        var maxTop = workAreaBottomRight.Y - windowHeight - edgePadding;

        if (maxLeft < minLeft) maxLeft = minLeft;
        if (maxTop < minTop) maxTop = minTop;

        Settings.MainWindowLeft = Math.Clamp(left, minLeft, maxLeft);
        Settings.MainWindowTop = Math.Clamp(top, minTop, maxTop);
    }

    /// <summary>
    /// 在窗口内容尺寸变化后，确保窗口底部不会超出当前屏幕工作区。
    /// </summary>
    [RelayCommand]
    private void AdjustPositionForContentSizeChanged()
    {
        if (_isAdjustingWindowPositionForContent || !IsMainWindowVisible || MainWindow.WindowState == WindowState.Minimized)
            return;

        var windowHeight = MainWindow.ActualHeight > 0 ? MainWindow.ActualHeight : MainWindow.MinHeight;
        if (windowHeight <= 0)
            return;

        try
        {
            _isAdjustingWindowPositionForContent = true;
            AdjustVerticalPositionWithinWorkArea();
        }
        finally
        {
            _isAdjustingWindowPositionForContent = false;
        }
    }

    /// <summary>
    /// 当窗口触底时，仅向上修正 Top，避免内容被屏幕底部遮挡。
    /// </summary>
    private void AdjustVerticalPositionWithinWorkArea()
    {
        const double edgePadding = 8;

        MonitorInfo screen;
        try
        {
            // 以主窗口句柄所在屏幕为准，避免多屏时误用鼠标屏幕。
            var windowHelper = new WindowInteropHelper(MainWindow);
            windowHelper.EnsureHandle();
            screen = MonitorInfo.GetNearestDisplayMonitor(windowHelper.Handle);
        }
        catch
        {
            screen = SelectedScreen();
        }

        UpdateMainWindowMaxHeightConstraint(screen);

        var workAreaTopLeft = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.X, screen.WorkingArea.Y);
        var workAreaBottomRight = Win32Helper.TransformPixelsToDIP(
            MainWindow,
            screen.WorkingArea.X + screen.WorkingArea.Width,
            screen.WorkingArea.Y + screen.WorkingArea.Height);

        var windowHeight = MainWindow.ActualHeight > 0 ? MainWindow.ActualHeight : MainWindow.MinHeight;
        var currentTop = Settings.MainWindowTop;
        var bottomLimit = workAreaBottomRight.Y - edgePadding;
        var currentBottom = currentTop + windowHeight;

        // 仅在触底时上移，未触底时保持原位避免抖动。
        if (currentBottom <= bottomLimit)
            return;

        var minTop = workAreaTopLeft.Y + edgePadding;
        var maxTop = bottomLimit - windowHeight;
        if (maxTop < minTop)
            maxTop = minTop;

        var targetTop = Math.Clamp(currentTop, minTop, maxTop);
        if (targetTop >= currentTop)
            return;

        Settings.MainWindowTop = targetTop;
    }

    private void AdjustPositionForResolutionChange()
    {
        var screenWidth = SystemParameters.VirtualScreenWidth;
        var screenHeight = SystemParameters.VirtualScreenHeight;
        GetDpi(out var currentDpiX, out var currentDpiY);

        var previousLeft = Settings.MainWindowLeft;
        var previousTop = Settings.MainWindowTop;
        GetDpi(out var previousDpiX, out var previousDpiY);

        var widthRatio = screenWidth / Settings.PreviousScreenWidth;
        var heightRatio = screenHeight / Settings.PreviousScreenHeight;
        var dpiXRatio = currentDpiX / previousDpiX;
        var dpiYRatio = currentDpiY / previousDpiY;

        var newLeft = previousLeft * widthRatio * dpiXRatio;
        var newTop = previousTop * heightRatio * dpiYRatio;

        var screenLeft = SystemParameters.VirtualScreenLeft;
        var screenTop = SystemParameters.VirtualScreenTop;

        var maxX = screenLeft + screenWidth - MainWindow.ActualWidth;
        var maxY = screenTop + screenHeight - MainWindow.ActualHeight;

        Settings.MainWindowLeft = Math.Max(screenLeft, Math.Min(newLeft, maxX));
        Settings.MainWindowTop = Math.Max(screenTop, Math.Min(newTop, maxY));
    }

    private void GetDpi(out double dpiX, out double dpiY)
    {
        var source = PresentationSource.FromVisual(MainWindow);
        if (source != null && source.CompositionTarget != null)
        {
            var matrix = source.CompositionTarget.TransformToDevice;
            dpiX = 96 * matrix.M11;
            dpiY = 96 * matrix.M22;
        }
        else
        {
            dpiX = 96;
            dpiY = 96;
        }
    }

    private MonitorInfo SelectedScreen()
    {
        MonitorInfo screen;
        switch (Settings.WindowScreen)
        {
            case WindowScreenType.Cursor:
            case WindowScreenType.FollowMouse:
                screen = MonitorInfo.GetCursorDisplayMonitor();
                break;
            case WindowScreenType.Focus:
                screen = MonitorInfo.GetNearestDisplayMonitor(Win32Helper.GetForegroundWindow());
                break;
            case WindowScreenType.Primary:
                screen = MonitorInfo.GetPrimaryDisplayMonitor();
                break;
            case WindowScreenType.Custom:
                var allScreens = MonitorInfo.GetDisplayMonitors();
                if (Settings.CustomScreenNumber <= allScreens.Count)
                    screen = allScreens[Settings.CustomScreenNumber - 1];
                else
                    screen = allScreens[0];
                break;
            default:
                screen = MonitorInfo.GetDisplayMonitors()[0];
                break;
        }

        return screen ?? MonitorInfo.GetDisplayMonitors()[0];
    }

    private double HorizonCenter(MonitorInfo screen)
    {
        var dip1 = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.X, 0);
        var dip2 = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.Width, 0);
        var left = (dip2.X - MainWindow.ActualWidth) / 2 + dip1.X;
        return left;
    }

    private double VerticalCenter(MonitorInfo screen)
    {
        var dip1 = Win32Helper.TransformPixelsToDIP(MainWindow, 0, screen.WorkingArea.Y);
        var dip2 = Win32Helper.TransformPixelsToDIP(MainWindow, 0, screen.WorkingArea.Height);
        var top = (dip2.Y - MainWindow.PART_Input.ActualHeight) / 4 + dip1.Y;
        return top;
    }

    private double HorizonRight(MonitorInfo screen)
    {
        var dip1 = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.X, 0);
        var dip2 = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.Width, 0);
        var left = (dip1.X + dip2.X - MainWindow.ActualWidth) - 10;
        return left;
    }

    private double HorizonLeft(MonitorInfo screen)
    {
        var dip1 = Win32Helper.TransformPixelsToDIP(MainWindow, screen.WorkingArea.X, 0);
        var left = dip1.X + 10;
        return left;
    }

    private double VerticalTop(MonitorInfo screen)
    {
        var dip1 = Win32Helper.TransformPixelsToDIP(MainWindow, 0, screen.WorkingArea.Y);
        var top = dip1.Y + 10;
        return top;
    }

    #endregion

    #region Global Hotkeys

    public void ToggleGlobalHotkey() => Settings.DisableGlobalHotkeys = !Settings.DisableGlobalHotkeys;

    #endregion

    #region 内存缓存

    /// <summary>
    /// 翻译结果内存缓存，替代已删除的 SQLite 历史表；最多保留 100 条，先进先出淘汰。
    /// </summary>
    private readonly Dictionary<(string Text, string Source, string Target), HistoryModel> _memoryCache = [];
    private readonly Lock _memoryCacheLock = new();
    private const int MemoryCacheLimit = 100;

    /// <summary>
    /// 从内存缓存取翻译记录。
    /// </summary>
    private HistoryModel? GetFromMemoryCache(string text, string source, string target)
    {
        lock (_memoryCacheLock)
        {
            return _memoryCache.TryGetValue((text, source, target), out var history) ? history : null;
        }
    }

    /// <summary>
    /// 把翻译记录写入内存缓存；超出容量时移除最早的一条。
    /// </summary>
    private void SaveToMemoryCache(HistoryModel history)
    {
        lock (_memoryCacheLock)
        {
            _memoryCache[(history.SourceText, history.SourceLang, history.TargetLang)] = history;
            if (_memoryCache.Count <= MemoryCacheLimit)
                return;

            var oldest = _memoryCache.Keys.First();
            _memoryCache.Remove(oldest);
        }
    }

    #endregion

    #region Helpers & Event Handlers

    private void EnterInputTranslateMode()
    {
        if (_forceShowInputForInputTranslate)
            return;

        _forceShowInputForInputTranslate = true;
        NotifyInputVisibilityProperties();
    }

    private void ExitInputTranslateMode()
    {
        if (!_forceShowInputForInputTranslate)
            return;

        _forceShowInputForInputTranslate = false;
        NotifyInputVisibilityProperties();
    }

    private void NotifyInputVisibilityProperties()
    {
        OnPropertyChanged(nameof(IsInputActuallyHidden));
        OnPropertyChanged(nameof(IsInputBoxVisible));
        OnPropertyChanged(nameof(IsLanguageSelectControlVisible));
    }

    partial void OnInputTextChanged(string value)
    {
        ResetTranslationLanguageState();

        if (!Settings.AutoTranslate)
            return;

        if (string.IsNullOrWhiteSpace(value))
        {
            _debounceExecutor.Cancel();
            return;
        }

        void Execute()
        {
            CancelAllOperations();
            App.Current.Dispatcher.Invoke(() => TranslateCommand.Execute(null));
            Show();
            UpdateCaret();
        }

        _debounceExecutor.Execute(Execute, TimeSpan.FromMilliseconds(Settings.AutoTranslateDelayMs));
    }

    private void ResetTranslationLanguageState()
    {
        _translationCoordinator.ResetIdentifiedLanguage(
            () => ApplyIdentifiedLanguageState(IdentifiedLanguageState.Empty));
    }

    private void ApplyIdentifiedLanguageState(IdentifiedLanguageState state)
    {
        _identifiedLanguageState = state;
        SelectedIdentifiedLanguage = state.Language ?? LangEnum.Auto;
        CanSelectIdentifiedLanguage = state.Kind != IdentifiedLanguageStateKind.None;
        IdentifiedLanguage = BuildIdentifiedLanguageText(state);
        OnPropertyChanged(nameof(CurrentIdentifiedLanguageState));
    }

    private string BuildIdentifiedLanguageText(IdentifiedLanguageState state)
    {
        return state.Kind switch
        {
            IdentifiedLanguageStateKind.None => string.Empty,
            IdentifiedLanguageStateKind.Cache when state.Language.HasValue => GetLanguageDisplayText(state.Language.Value),
            IdentifiedLanguageStateKind.Cache => _i18n.GetTranslation("IdentifiedUnknown"),
            IdentifiedLanguageStateKind.Detected when state.Language.HasValue => GetLanguageDisplayText(state.Language.Value),
            _ => string.Empty
        };
    }

    private string GetLanguageDisplayText(LangEnum language)
    {
        var translation = _i18n.GetTranslation($"LangEnum{language}");
        return string.IsNullOrWhiteSpace(translation) ? language.ToString() : translation;
    }

    private bool CanSelectIdentifiedLanguageForCurrentText(LangEnum language)
    {
        return CanSelectIdentifiedLanguage &&
               CanTranslate &&
               language != LangEnum.Auto;
    }

    private bool CanSelectLanguageDetectorForCurrentText(LanguageDetectorType _) => CanTranslate;

    private async Task<TranslationLanguageContext> ResolveTranslationLanguageContextAsync(
        TranslationOperation operation,
        LangEnum? forcedSourceLanguage)
    {
        if (forcedSourceLanguage is LangEnum forcedSource && forcedSource != LangEnum.Auto)
        {
            operation.PublishIdentifiedLanguage(
                () => ApplyIdentifiedLanguageState(CreateDetectedIdentifiedLanguageState(forcedSource)));
            return CreateTranslationLanguageContext(
                operation.SourceLang,
                operation.TargetLang,
                forcedSource,
                LanguageDetector.GetTargetLanguage(forcedSource, operation.TargetLang));
        }

        var (_, source, target) = await LanguageDetector
            .GetLanguageAsync(
                operation.Text,
                operation.SourceLang,
                operation.TargetLang,
                operation.CancellationToken,
                () => operation.PublishIdentifiedLanguage(StartProcess),
                (isSuccess, detectedSource) => operation.PublishIdentifiedLanguage(
                    () => CompleteProcess(isSuccess, detectedSource)),
                () => operation.PublishIdentifiedLanguage(FinishProcess))
            .ConfigureAwait(false);

        return CreateTranslationLanguageContext(
            operation.SourceLang,
            operation.TargetLang,
            source,
            target);
    }

    private IdentifiedLanguageState CreateCacheIdentifiedLanguageState(HistoryModel history)
    {
        return new IdentifiedLanguageState(
            IdentifiedLanguageStateKind.Cache,
            ParseHistoryLanguage(history.EffectiveSourceLang) ?? ParseHistoryLanguage(history.SourceLang));
    }

    private static LangEnum? ParseHistoryLanguage(string? language)
    {
        if (Enum.TryParse<LangEnum>(language, true, out var parsed) && parsed != LangEnum.Auto)
            return parsed;

        return null;
    }

    private static IdentifiedLanguageState CreateDetectedIdentifiedLanguageState(LangEnum language)
        => new(IdentifiedLanguageStateKind.Detected, language);

    private static TranslationLanguageContext CreateTranslationLanguageContext(
        LangEnum cacheSource,
        LangEnum cacheTarget,
        LangEnum effectiveSource,
        LangEnum effectiveTarget)
        => new(cacheSource, cacheTarget, effectiveSource, effectiveTarget);

    private void UpdateCaret()
    {
        MainWindow.PART_Input.SetCaretIndex(InputText.Length);
    }

    private string HandleCapturedText(string text, TextSeparatorHandleScope scope)
    {
        return Utilities.CapturedTextHandler(
            text,
            Settings.LineBreakHandleType,
            Settings.TextSeparatorHandleType,
            scope,
            Settings.TextSeparatorHandleScopes);
    }

    private string HandleSilentOcrText(string text)
    {
        if (Settings.TextSeparatorHandleType == TextSeparatorHandleType.None ||
            (Settings.TextSeparatorHandleScopes & TextSeparatorHandleScope.SilentOcr) != TextSeparatorHandleScope.SilentOcr)
        {
            return text;
        }

        return HandleCapturedText(text, TextSeparatorHandleScope.SilentOcr);
    }

    private void ResetAllServices(TranslationOperation operation)
    {
        var services = TranslateService.Services.Where(x => x.IsEnabled).ToList();
        foreach (var service in services)
        {
            service.Options?.TemporaryDisplay = false;
            if (service.Plugin is ITranslatePlugin translatePlugin)
                operation.TryPrepare(translatePlugin);
            else if (service.Plugin is IDictionaryPlugin dictionaryPlugin)
                operation.TryPrepare(dictionaryPlugin);
        }
    }

    private void CancelAllOperations()
    {
        CancelSingleTranslationTasks();
        TranslateCancelCommand.Execute(null);
        PlayAudioCancelCommand.Execute(null);
        PlayAudioUrlCancelCommand.Execute(null);
        SaveToVocabularyCancelCommand.Execute(null);
    }

    private async Task<(bool success, string text)> GetTextAsync(bool showFailureFeedback = true)
    {
        try
        {
            var text = await ClipboardHelper.GetSelectedTextAsync(Settings.SelectedTextFetchTimeoutMs);
            if (string.IsNullOrEmpty(text))
            {
                _logger.LogWarning("取词失败，可能：未选中文本、文本禁止复制、取词间隔过短、文本所属软件权限高于本软件");
                if (showFailureFeedback)
                {
                    Show();
                    _snackbar.ShowWarning(_i18n.GetTranslation("NoTextRecognizedMessage"));
                }
                return (false, string.Empty);
            }
            return (true, text);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "获取剪贴板异常请重试");
            return (false, string.Empty);
        }
    }

    private void HandleCrosswordFetchFailed()
    {
        switch (Settings.CrosswordFetchFailedFallbackTarget)
        {
            case CrosswordFetchFailedFallbackTarget.NotifyOnly:
                _notification.Show(
                    _i18n.GetTranslation("Hotkey_CrosswordTranslate"),
                    _i18n.GetTranslation("CrosswordTranslateFetchFailedNotifyOnly"));
                break;
            case CrosswordFetchFailedFallbackTarget.ShowWindow:
                Show();
                _snackbar.ShowWarning(_i18n.GetTranslation("CrosswordTranslateFetchFailedShowWindow"), 3000);
                break;
            case CrosswordFetchFailedFallbackTarget.InputTranslate:
            default:
                InputClear();
                _snackbar.ShowWarning(_i18n.GetTranslation("CrosswordTranslateFetchFailed"), 3000);
                break;
        }
    }

    private void StartProcess()
    {
        ApplyIdentifiedLanguageState(IdentifiedLanguageState.Empty);
        IsIdentifyProcessing = true;
    }
    private void FinishProcess() => IsIdentifyProcessing = false;
    private void CompleteProcess(bool _, LangEnum source)
    {
        ApplyIdentifiedLanguageState(CreateDetectedIdentifiedLanguageState(source));
    }

    #endregion

    #region IDisposable

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            _mouseSelectionService.TextSelected -= OnMouseSelectionTextSelected;
            _mouseSelectionService.SelectionStarted -= OnMouseSelectionStarted;
            _mouseSelectionService.BubbleRequested -= OnMouseSelectionBubbleRequested;
            _mouseSelectionService.BubbleDismissRequested -= OnMouseSelectionBubbleDismissRequested;
            _mouseSelectionService.LongPressTriggered -= OnLongPressTriggered;
            _mouseSelectionService.StateChanged -= OnMouseSelectionStateChanged;
            _mouseSelectionBubbleWindow.HoverCompleted -= OnMouseSelectionBubbleHoverCompleted;
            _mouseSelectionBubbleWindow.HideWindow();
            _clipboardMonitor?.OnClipboardTextChanged -= OnClipboardTextChanged;
            Settings.PropertyChanged -= OnSettingsPropertyChanged;
            TranslateService.Services.CollectionChanged -= OnQuickServiceCollectionChanged;
            Settings.PropertyChanged -= OnSettingsChangedForPhonetic;
            TtsService.Services.CollectionChanged -= OnQuickServiceCollectionChanged;
            VocabularyService.Services.CollectionChanged -= OnQuickServiceCollectionChanged;

            _debounceExecutor.Dispose();
            _clipboardMonitor?.Dispose();

            // 如果窗口一直没打开过，恢复位置后再退出
            if (Settings.MainWindowLeft <= -18000 && Settings.MainWindowTop <= -18000)
            {
                Settings.MainWindowLeft = _cacheLeft;
                Settings.MainWindowTop = _cacheTop;
                Settings.Save();
            }

            _i18n.OnLanguageChanged -= OnLanguageChanged;
        }

        _disposed = true;
    }

    #endregion
}

public sealed record ServiceQuickAccessItem(Service Service, bool ShowSeparatorBefore);

/// <summary>翻译历史条目（仅内存，重启不保留）。</summary>
/// <param name="Text">翻译过的文本。</param>
/// <param name="Time">翻译时间。</param>
public sealed record HistoryEntry(string Text, DateTime Time);
