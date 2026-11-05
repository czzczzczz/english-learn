using System.Windows;

namespace STranslate.Controls;

public static class SizeToContentBehavior
{
    private static readonly DependencyProperty SizeChangedHandlerProperty =
        DependencyProperty.RegisterAttached(
            "SizeChangedHandler",
            typeof(SizeChangedEventHandler),
            typeof(SizeToContentBehavior),
            new PropertyMetadata(null));

    private static SizeChangedEventHandler? GetSizeChangedHandler(DependencyObject obj)
        => (SizeChangedEventHandler?)obj.GetValue(SizeChangedHandlerProperty);

    private static void SetSizeChangedHandler(DependencyObject obj, SizeChangedEventHandler? value)
        => obj.SetValue(SizeChangedHandlerProperty, value);

    public static readonly DependencyProperty PersistentSizeToContentProperty =
        DependencyProperty.RegisterAttached(
            "PersistentSizeToContent",
            typeof(SizeToContent),
            typeof(SizeToContentBehavior),
            new PropertyMetadata(SizeToContent.Manual, OnPersistentSizeToContentChanged));

    public static void SetPersistentSizeToContent(Window window, SizeToContent value)
    {
        window.SetValue(PersistentSizeToContentProperty, value);
    }

    public static SizeToContent GetPersistentSizeToContent(Window window)
    {
        return (SizeToContent)window.GetValue(PersistentSizeToContentProperty);
    }

    private static void OnPersistentSizeToContentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is Window window)
        {
            var oldHandler = GetSizeChangedHandler(window);
            if (oldHandler != null)
            {
                window.SizeChanged -= oldHandler;
                SetSizeChangedHandler(window, null);
            }

            window.SizeToContent = (SizeToContent)e.NewValue;

            if ((SizeToContent)e.NewValue == SizeToContent.Manual)
                return;

            SizeChangedEventHandler sizeChangedHandler = (s, args) =>
            {
                var sizeToContent = GetPersistentSizeToContent(window);
                if (window.SizeToContent == SizeToContent.Manual && sizeToContent != SizeToContent.Manual)
                {
                    window.SizeToContent = sizeToContent;
                }
            };
            SetSizeChangedHandler(window, sizeChangedHandler);
            window.SizeChanged += sizeChangedHandler;
        }
    }
}
