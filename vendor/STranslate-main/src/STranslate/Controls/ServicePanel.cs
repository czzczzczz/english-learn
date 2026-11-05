using STranslate.Plugin;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace STranslate.Controls;

/// <summary>
/// 显示并管理同一类型的插件服务。
/// 仅保留删除、复制两类操作命令；替换翻译与图片翻译已下线，对应命令与依赖属性一并移除。
/// </summary>
public class ServicePanel : ListBox
{
    static ServicePanel()
        => DefaultStyleKeyProperty.OverrideMetadata(typeof(ServicePanel),
            new FrameworkPropertyMetadata(typeof(ServicePanel)));

    protected override void OnSelectionChanged(SelectionChangedEventArgs e)
    {
        base.OnSelectionChanged(e);

        if (SelectedItem is not { } selectedItem)
            return;

        // 新增服务会通过绑定更新选中项；等待布局生成其容器后才能可靠地滚动到该项。
        Dispatcher.BeginInvoke(() =>
        {
            if (ReferenceEquals(SelectedItem, selectedItem))
                ScrollIntoView(selectedItem);
        }, DispatcherPriority.Loaded);
    }

    public ICommand? DeleteCommand
    {
        get => (ICommand?)GetValue(DeleteCommandProperty);
        set => SetValue(DeleteCommandProperty, value);
    }

    public static readonly DependencyProperty DeleteCommandProperty =
        DependencyProperty.Register(
            nameof(DeleteCommand),
            typeof(ICommand),
            typeof(ServicePanel));

    public ICommand? DuplicateCommand
    {
        get => (ICommand?)GetValue(DuplicateCommandProperty);
        set => SetValue(DuplicateCommandProperty, value);
    }

    public static readonly DependencyProperty DuplicateCommandProperty =
        DependencyProperty.Register(
            nameof(DuplicateCommand),
            typeof(ICommand),
            typeof(ServicePanel));
}
