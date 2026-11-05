using CommunityToolkit.Mvvm.ComponentModel;
using STranslate.Core;
using STranslate.Plugin;

namespace STranslate.Services;

public partial class TranslateService : BaseService
{
    private readonly ServiceSettings _serviceSettings;

    [ObservableProperty] public partial Service? ImageTranslateService { get; set; }

    protected override ServiceType ServiceType => ServiceType.Translation;

    public TranslateService(
        PluginManager pluginManager,
        ServiceManager serviceManager,
        PluginService PluginService,
        ServiceSettings serviceSettings,
        Internationalization i18n
    ) : base(pluginManager, serviceManager, PluginService, serviceSettings, i18n)
    {
        _serviceSettings = serviceSettings;

        // Ensure all service data have translation options
        foreach (var item in SvcSettingDatas)
        {
            item.Options ??= new TranslationOptions();
        }

        LoadPlugins<ITranslatePlugin>();
        LoadPlugins<IDictionaryPlugin>();
        LoadServices<ITranslatePlugin, IDictionaryPlugin>();
        InitialOtherService();
    }

    private void InitialOtherService()
    {
        ImageTranslateService = Services.FirstOrDefault(s => s.ServiceID == _serviceSettings.ImageTranslateSvcID);
    }

    public override async Task<bool> DeleteAsync(Service service)
    {
        var result = await base.DeleteAsync(service);
        if (result && service == ImageTranslateService)
        {
            ImageTranslateService = null;
            _serviceSettings.ImageTranslateSvcID = string.Empty;
            _serviceSettings.Save();
        }

        return result;
    }

}
