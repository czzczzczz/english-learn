using CommunityToolkit.Mvvm.Input;
using STranslate.Services;
using STranslate.Plugin;

namespace STranslate.ViewModels.Pages;

public partial class TranslateViewModel(TranslateService service) : ServiceViewModelBase<TranslateService>(service)
{
    /// <summary>
    /// 把已启用的服务按原有相对顺序整体前移，停用的服务保持在后；用于面板上的「重排」操作。
    /// </summary>
    [RelayCommand]
    private void ReorderEnabledServices()
    {
        var services = Service.Services;
        if (services.Count <= 1)
            return;

        var targetOrder = new List<Service>(services.Count);
        foreach (var svc in services)
        {
            if (svc.IsEnabled)
                targetOrder.Add(svc);
        }

        foreach (var svc in services)
        {
            if (!svc.IsEnabled)
                targetOrder.Add(svc);
        }

        // 按目标顺序执行 Move，复用现有顺序持久化逻辑，且保持组内相对顺序稳定。
        for (var targetIndex = 0; targetIndex < targetOrder.Count; targetIndex++)
        {
            var service = targetOrder[targetIndex];
            var currentIndex = services.IndexOf(service);
            if (currentIndex >= 0 && currentIndex != targetIndex)
                services.Move(currentIndex, targetIndex);
        }
    }
}
