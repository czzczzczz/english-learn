import re

PATH = r"D:\vibe_coding\english_learn\vendor\STranslate-main\src\STranslate\Views\Pages\GeneralPage.xaml"
REMOVE_KEYS = {
    "General_CopyAfterOcr", "General_ScreenshotOcrLanguageHeader", "General_FocusInputAfterScreenshotTranslate",
    "General_ImageTranslateOnOcrServiceChanged", "General_ImageTranslateOnTranslateServiceChanged",
    "General_ImageTranslateOnLanguageChanged", "General_ImageTranslateOnLayoutChanged",
    "General_OcrOnServiceChanged", "General_OcrOnLanguageChanged", "General_UseClipboardOutput",
    "General_ImageQuality", "General_ShowScreenshotItemInNotifyIconMenu",
    "General_ShowImageTranslateItemInNotifyIconMenu", "General_ShowOcrItemInNotifyIconMenu",
    "General_ShowQrCodeItemInNotifyIconMenu",
    "General_HistoryCount", "General_AutoHideAtTopEdge", "General_TopEdgeAutoHideDelay",
    "General_WindowAlign", "General_MainWindowMaxHeightRatio", "General_StartMode",
    "General_AutoCheckUpdate", "General_WindowPosition",
    "General_IncrementalClearInput", "General_AutoHideAtTopEdge", "General_ShowScreenshotAuxiliaryLines", "General_AutoTranslateOnPromptChanged", "General_LocalDetector",
    "TextSeparatorHandleScopeScreenshotTranslate", "TextSeparatorHandleScopeSilentOcr",
    "TextSeparatorHandleScopeIncremental", "TextSeparatorHandleScopeClipboardMonitor",
}

raw = open(PATH, "rb").read()
had_bom = raw.startswith(b"\xef\xbb\xbf")
src = raw.decode("utf-8-sig")

blocks = []
pos = 0
while True:
    j = src.find("<ui:SettingsCard", pos)
    if j < 0:
        break
    tag_end = src.find(">", j)
    if tag_end < 0:
        break
    head = src[j:tag_end + 1]
    self_closing = head.rstrip().endswith("/>")
    if self_closing:
        end = tag_end + 1
    else:
        depth = 0
        k = j
        end = None
        while k < len(src):
            if re.match(r"<ui:SettingsCard(\s|>)", src[k:k+40]):
                inner_end = src.find(">", k)
                depth += 0 if src[k:inner_end + 1].rstrip().endswith("/>") else 1
                k = inner_end + 1
            elif src.startswith("</ui:SettingsCard>", k):
                depth -= 1
                k += len("</ui:SettingsCard>")
                if depth == 0:
                    end = k
                    break
            else:
                k += 1
        if end is None:
            break
    m = re.search(r'Header="\{DynamicResource ([A-Za-z_0-9]+)\}"', head)
    if m and m.group(1) in REMOVE_KEYS:
        line_start = src.rfind("\n", 0, j) + 1
        blocks.append((line_start, end))
    pos = end

removed = 0
for start, end in reversed(blocks):
    tail = end
    while tail < len(src) and src[tail] in " \t":
        tail += 1
    if src[tail:tail + 2] == "\r\n":
        tail += 2
    elif src[tail:tail + 1] == "\n":
        tail += 1
    src = src[:start] + src[tail:]
    removed += 1

data = src.encode("utf-8")
if had_bom:
    data = b"\xef\xbb\xbf" + data
open(PATH, "wb").write(data)
print("removed:", removed)
