namespace STranslate.Core;

public static class MainHeaderActions
{
    public const string ClipboardMonitor = "clipboard_monitor";
    public const string AutoTranslate = "auto_translate";
    public const string Ocr = "ocr";
    public const string ImageTranslate = "image_translate";
    public const string ScreenshotTranslate = "screenshot_translate";
    public const string MouseSelectionTranslation = "mouse_selection_translation";

    /// <summary>方式二：划词气泡开关。</summary>
    public const string MouseSelectionBubble = "mouse_selection_bubble";
    public const string ColorScheme = "color_scheme";

    /// <summary>头栏主题按钮（瘦身后沿用该键位）。</summary>
    public const string ColorTheme = ColorScheme;
    public const string HideInput = "hide_input";
    public const string ServiceSwitcher = "service_switcher";
    public const string HistoryNavigation = "history_navigation";

    /// <summary>
    ///     头栏可见动作：瘦身后只保留与"划词翻译 + 朗读"相关的入口。
    /// </summary>
    public static IReadOnlyList<string> DefaultOrder { get; } =
    [
        MouseSelectionBubble,
        MouseSelectionTranslation,
        ColorScheme
    ];

    public static IReadOnlyList<string> All => DefaultOrder;

    private static readonly Dictionary<string, string> CanonicalActionMap = DefaultOrder
        .ToDictionary(action => action, StringComparer.OrdinalIgnoreCase);

    public static List<string> Normalize(IEnumerable<string>? actions)
    {
        if (actions == null)
        {
            return [];
        }

        var normalizedActions = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var action in actions)
        {
            if (string.IsNullOrWhiteSpace(action))
            {
                continue;
            }

            var trimmedAction = action.Trim();
            if (!CanonicalActionMap.TryGetValue(trimmedAction, out var canonicalAction))
            {
                continue;
            }

            if (seen.Add(canonicalAction))
            {
                normalizedActions.Add(canonicalAction);
            }
        }

        return normalizedActions;
    }
}
