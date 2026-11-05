INIT_DONE 2026-11-04T23:45:12+08:00

# 会话时间线

> 每轮记录：做了什么、结论、待办。超过 200 行转存 `reserve/session_information-YYYYMMDD.md`。

## 2026-11-03

- **调研与选型**：确定以 STranslate 为底座 fork，三条翻译链路（热键 / 划词气泡 / 选中即翻译）。
- **划词气泡**：新增 44×44 无激活气泡窗口、悬停延时、自动隐藏；UIA 取词优先、剪贴板快照兜底（验证剪贴板未被污染）。
- **瘦身**：删除 OCR 页、图片翻译、历史页、插件市场、网络页、首启向导、外部调用、SQLite；资源字典同步清理。
- **TTS 插件**：自建 Baidu TTS 插件，单词走有道真人、整句走 Google 合成、百度兜底。
- **朗读设置面板**：发现插件 `GetSettingUI()` 的 UserControl 在宿主 ContentControl 中不渲染；改为宿主原生 `SettingsCard` 直显三个下拉 + 试听。

## 2026-11-04

- **生词本内建**：`VocabularyStore`（JSON + 原子写 + 去重）、词表页（搜索/删除/导出/空态）、主窗口书签常显。
- **回退事件**：备份 ZIP 用 `Compress-Archive` 传绝对路径导致文件平铺（937 文件压成 407 且互相覆盖），无法直接还原；改为按文件内容核对后逐个还原 8 个文件 + 插件目录。备份脚本已改用 `ZipArchive` 保留层级。
- **整句朗读**：Google TTS 在国内不可用导致整句无声；改为「有道优先 + 百度兜底」，并用音频魔数校验避免把 JSON 错误体当音频播放。
- **删除顶边吸附**：`TopEdgeAutoHideController` / `TopEdgeSlideAnimation` 整体移除；它会在贴顶时断开 `Topmost` 双向绑定，是「钉不住」的元凶。
- **置顶状态修正**：窗口 `Topmost` 改单向绑定；`_userTopmost` 提升为 `IsUserTopmost`；钉子图标绑它而非 `IsTopmost`，解决「开=不钉、关=钉」的反相。
- **左键长按框选 OCR**：`MouseHookService` 加长按状态机（450ms + 6px 容差）；新增全屏 Canvas 遮罩（粘滞模式）；`OcrService` 走 `Windows.Media.Ocr`，三重重试（原图/反色/放大 2×）；失败截图落 `D:\dsh\downloads\ocr-debug`。
- **踩坑**：长按吞掉 ButtonUp 导致系统鼠标状态错乱、遮罩收不到事件 → 改为放行抬起；框选时隐藏主窗口后忘记恢复 → OCR 空结果分支补 `Show()`。
- **`Alt+Q` 热键 + Free Dictionary 插件**：新增翻译插件（dictionaryapi.dev，免 key），默认服务顺序 彩云 → Free Dictionary → Bing。
- **KK 音标**：`PhoneticConverter`（SDK 共享），宿主 `PhoneticSystem` 注入 `IPhoneticAware` 插件；生词本顶部下拉可切 KK/IPA/对照。
- **翻译历史**：标题栏左右箭头，20 条纯内存，切换走内存缓存不重复请求；列定义从 3 列改 4 列解决与钉子重叠。
- **AI 生词故事**：`StoryService`（OpenAI 兼容）、模型列表拉取、专用代理字段、故事窗口（加粗渲染/朗读/复制/重新生成）。用户中转站 `api.yicode.ai/v1` 需走 `127.0.0.1:10809`；`gpt-4o-mini` 不可用已改 `deepseek-v4.1-flash`。
- **初始化**：按 `zzc` 指令创建 `docs/`、`reserve/` 与两份文档。

## 待办

- 框选 OCR 失败时的截图待用户反馈（`D:\dsh\downloads\ocr-debug`）。
- 英式音标的 KK 转换未完全隔离（Bing 输出的「英国」标记后仍被转换）。
- AI 故事可选增强：故事内点词查义、生成前选词、难度档位。
