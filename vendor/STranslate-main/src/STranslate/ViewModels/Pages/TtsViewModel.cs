using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using STranslate.Plugin;
using STranslate.Services;
using System.Collections.ObjectModel;

namespace STranslate.ViewModels.Pages;

/// <summary>
/// 朗读设置页视图模型：直接读写当前启用朗读插件的参数，不需要先选中服务行。
/// </summary>
public partial class TtsViewModel : ObservableObject
{
    /// <summary>可选单词发音源。</summary>
    private static readonly (string Value, string Display)[] WordEngineOptions =
    [
        ("Youdao", "有道（真人录音）"),
        ("Baidu", "百度（合成音）"),
    ];

    /// <summary>可选口音。</summary>
    private static readonly (string Value, string Display)[] AccentOptions =
    [
        ("US", "美音 US"),
        ("UK", "英音 UK"),
    ];

    /// <summary>可选整句语速。</summary>
    private static readonly (string Value, string Display)[] SpeedOptions =
    [
        ("0.5", "0.5x 慢速"),
        ("0.75", "0.75x 稍慢"),
        ("1", "1.0x 正常"),
        ("1.25", "1.25x 稍快"),
    ];

    private readonly TtsService _service;

    /// <summary>初始化阶段不回写，避免一进页面就写盘。</summary>
    private bool _loading;

    public TtsViewModel(TtsService service)
    {
        _service = service;
        WordEngines = BuildItems(WordEngineOptions);
        Accents = BuildItems(AccentOptions);
        Speeds = BuildItems(SpeedOptions);
        Reload();
    }

    /// <summary>单词发音源下拉项。</summary>
    public ObservableCollection<OptionItem> WordEngines { get; }

    /// <summary>口音下拉项。</summary>
    public ObservableCollection<OptionItem> Accents { get; }

    /// <summary>整句语速下拉项。</summary>
    public ObservableCollection<OptionItem> Speeds { get; }

    /// <summary>当前启用朗读插件的参数接口，插件未加载时为 null。</summary>
    private ITtsOptions? Options => _service.GetActiveSvc<ITtsPlugin>() as ITtsOptions;

    /// <summary>是否找到可用的朗读服务。</summary>
    [ObservableProperty]
    public partial bool IsServiceAvailable { get; set; }

    /// <summary>提示信息（加载失败、试听失败）。</summary>
    [ObservableProperty]
    public partial string Message { get; set; } = string.Empty;

    /// <summary>是否显示提示信息。</summary>
    public bool HasMessage => !string.IsNullOrEmpty(Message);

    /// <summary>单词发音源：Youdao / Baidu。</summary>
    [ObservableProperty]
    public partial string? WordEngine { get; set; }

    /// <summary>口音：US / UK。</summary>
    [ObservableProperty]
    public partial string? Accent { get; set; }

    /// <summary>整句语速：0.5 / 0.75 / 1 / 1.25。</summary>
    [ObservableProperty]
    public partial string? Speed { get; set; }

    /// <summary>从插件读取当前参数。</summary>
    public void Reload()
    {
        var options = Options;
        IsServiceAvailable = options is not null;
        if (options is null)
        {
            Message = "未找到可用的朗读服务，请检查插件是否正常加载。";
            return;
        }

        _loading = true;
        WordEngine = MatchOrDefault(WordEngineOptions, options.WordEngine);
        Accent = MatchOrDefault(AccentOptions, options.Accent);
        Speed = MatchOrDefault(SpeedOptions, options.Speed);
        _loading = false;
    }

    partial void OnWordEngineChanged(string? value) => Apply(o => o.WordEngine = value ?? o.WordEngine);

    partial void OnAccentChanged(string? value) => Apply(o => o.Accent = value ?? o.Accent);

    partial void OnSpeedChanged(string? value) => Apply(o => o.Speed = value ?? o.Speed);

    /// <summary>把改动写进插件并落盘。</summary>
    private void Apply(Action<ITtsOptions> mutate)
    {
        if (_loading)
            return;

        var options = Options;
        if (options is null)
            return;

        mutate(options);
        options.Save();
    }

    partial void OnMessageChanged(string value) => OnPropertyChanged(nameof(HasMessage));

    /// <summary>试听单词发音。</summary>
    [RelayCommand]
    private Task TrySpeakWordAsync() => SpeakAsync("hello");

    /// <summary>试听整句发音。</summary>
    [RelayCommand]
    private Task TrySpeakSentenceAsync() => SpeakAsync("Learning English is easier when you listen every day.");

    /// <summary>调用插件朗读指定文本。</summary>
    private async Task SpeakAsync(string text)
    {
        var plugin = _service.GetActiveSvc<ITtsPlugin>();
        if (plugin is null)
        {
            Message = "未找到可用的朗读服务，请检查插件是否正常加载。";
            return;
        }

        try
        {
            Message = string.Empty;
            await plugin.PlayAudioAsync(text);
        }
        catch (Exception ex)
        {
            Message = "试听失败：" + ex.Message;
        }
    }

    private static ObservableCollection<OptionItem> BuildItems((string Value, string Display)[] sources)
        => [.. sources.Select(s => new OptionItem(s.Value, s.Display))];

    /// <summary>插件存的值不在候选里时回到第一项，避免下拉空白。</summary>
    private static string MatchOrDefault((string Value, string Display)[] sources, string? current)
    {
        foreach (var item in sources)
        {
            if (string.Equals(item.Value, current, StringComparison.OrdinalIgnoreCase))
                return item.Value;
        }

        return sources[0].Value;
    }
}

/// <summary>下拉选项。</summary>
public sealed class OptionItem(string value, string display)
{
    /// <summary>写入配置的值。</summary>
    public string Value { get; } = value;

    /// <summary>界面显示的文案。</summary>
    public string Display { get; } = display;

    /// <summary>供无障碍读取与调试输出使用，避免暴露类型名。</summary>
    public override string ToString() => Display;
}
