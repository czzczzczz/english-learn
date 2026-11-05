using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace STranslate.Plugin.Tts.Baidu.ViewModel;

/// <summary>
/// 朗读设置视图模型：口音、语速、单词音源。
/// </summary>
public partial class SettingsViewModel : ObservableObject
{
    private readonly IPluginContext _context;
    private readonly Settings _settings;

    public SettingsViewModel(IPluginContext context, Settings settings)
    {
        _context = context;
        _settings = settings;
        Accent = settings.Accent;
        Speed = settings.Speed;
        WordEngine = settings.WordEngine;
    }

    /// <summary>US 美音 / UK 英音。</summary>
    [ObservableProperty] public partial string Accent { get; set; }

    /// <summary>句子语速。</summary>
    [ObservableProperty] public partial string Speed { get; set; }

    /// <summary>单词音源：Youdao 或 Baidu。</summary>
    [ObservableProperty] public partial string WordEngine { get; set; }

    [RelayCommand]
    private void Save()
    {
        _settings.Accent = Accent;
        _settings.Speed = Speed;
        _settings.WordEngine = WordEngine;
        _context.SaveSettingStorage<Settings>();
    }
}
