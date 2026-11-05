using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace STranslate.Plugin.Translate.Caiyun.ViewModel;

/// <summary>
/// 彩云小译 token 设置视图模型：填写后立即保存到插件配置。
/// </summary>
public partial class SettingsViewModel : ObservableObject
{
    private readonly IPluginContext _context;
    private readonly Settings _settings;

    public SettingsViewModel(IPluginContext context, Settings settings)
    {
        _context = context;
        _settings = settings;
        Token = settings.Token;
    }

    /// <summary>彩云开放平台 token。</summary>
    [ObservableProperty] public partial string Token { get; set; }

    /// <summary>保存 token 到插件配置。</summary>
    [RelayCommand]
    private void Save()
    {
        _settings.Token = string.IsNullOrWhiteSpace(Token) ? Settings.DefaultToken : Token.Trim();
        _context.SaveSettingStorage<Settings>();
        Token = _settings.Token;
    }
}
