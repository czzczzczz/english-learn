# 基于 STranslate 的改造方案（v1）

日期：2026-11-03 ｜ 基线：STranslate main 分支快照（2026-09-24 提交，2.4MB 源码包，1,063 个文件）
源码位置：`vendor/STranslate-main/`

## 结论

可以，改造量比自研小一个量级：**四件需求里 3 件已有现成实现，只缺语音输入**。

| 你的需求 | STranslate 现状 | 缺口 |
|---|---|---|
| 任意软件选中英文 → 弹窗翻译 | 已有：全局鼠标 Hook + 模拟复制取词 | 无 |
| → 朗读 | TTS 插件（MicrosoftEdge）已有，但**只在点击喇叭时播放** | 缺"翻译完成自动朗读" |
| → 加入生词本 | 已有插件接口 `IVocabularyPlugin`，只实现了欧路词典插件 | 缺本地词库 + 复习 |
| 快捷键唤起对话框 | 已有：输入翻译 / OCR / 截图翻译 / 增量翻译热键 | 无 |
| 中英语音互转 | **无**：全仓无 ASR 代码，只有 TTS 输出 | 全新模块 |

## 代码级落点（已核对源码路径）

技术栈：.NET 10 WPF（`net10.0-windows10.0.19041.0`）+ CommunityToolkit.Mvvm + DI + SQLite/Dapper + NAudio + NHotkey/ChefKeys + MouseKeyHook。

| 改造项 | 落点文件 | 说明 |
|---|---|---|
| 自动朗读 | `STranslate/ViewModels/MainWindowViewModel.cs:1442` `PlayAudioAsync` + `Core/Settings.cs` | 新增 `AutoSpeakOnTranslate` 开关；翻译成功后按 scope 调用现有 TTS 通路 |
| 取词链路 | `Services/MouseSelectionService.cs`、`Helpers/ClipboardHelper.GetSelectedTextAsync` | 已有 UIA 无关的模拟复制取词（超时 50–5000ms 可调） |
| 生词本 | `Services/VocabularyService.cs` + `STranslate.Plugin/IVocabularyPlugin.cs` + 现有 `Views/Pages/VocabularyPage.xaml` | 插件只管"保存"；本地库、复习、调度要新增 |
| 语音输入 | 新增 `Services/SpeechInputService.cs` + `Core/HotkeySettings.cs` + `Views/MainWindow.xaml` 输入区 | 热键 → NAudio 录音 → ASR → 填入 `InputText` → 复用现有 `TranslateAsync()` |
| 朗读输出复用 | `STranslate.Plugin/ITtsPlugin.cs`、`Services/TtsService.cs` | 语音回读直接用现成 TTS |

## 分四步做

**P0 环境与基线（0.5 天）**：装 .NET 10 SDK（本机只有 9.0.318，无法编译 net10 目标）→ `dotnet build STranslate.slnx` → 跑起原版。**这一步不做完，后面全是空谈。**

**P1 划词即读（1 天）**：翻译成功自动朗诵单词/整句；设置页加开关与语速；用现有 TTS 插件，无新依赖。

**P2 本地生词本 + FSRS（1.5 周）**：SQLite 表（word / phonetic / 释义 / 原句 / 来源 app / FSRS 状态）→ 划词弹窗一键入库 → 复习卡片窗口 → 托盘提醒。插件接口保留，本地库作为内置 `IVocabularyPlugin` 实现，不破坏上游结构。

**P3 语音输入（1.5–2 周，唯一全新模块）**：全局热键按住说话 → 录音 → ASR → 文本进输入框 → 现有翻译链路 → TTS 回读。语种走现有 `LanguageDetector` 自动判定，中英双向天然成立。

**P4 对话模式（可选，2 周）**：连续多轮语音对话 + LLM 纠错打磨。

## 三个必须先定的决策

| 决策 | 选项 | 影响 |
|---|---|---|
| ASR 引擎 | ① 在线 API（2 天接通，需 key，识别质量最好）② 本地 whisper.cpp（Whisper.net，模型 75MB–1.5GB，CPU 慢但离线）③ Windows 系统识别（零依赖，中文质量一般） | 决定 P3 工期与安装包体积；建议先①跑通链路，②做离线选项 |
| 生词本形态 | ① 内置本地库 + 复习（推荐）② 只做导出到 Anki/欧路 | ①多 1 周，但"学习闭环"是你产品的差异点 |
| 上游同步 | ① 只读快照 + 手工 patch ② 建 git 仓库 + upstream remote 定期 merge | 改动集中在 host 层、插件 SDK 不动，merge 冲突可控，推荐② |

## 风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| .NET 10 工具链 | 本机 SDK 9.0.318，net10 目标编译不了 | 已下载 10.0.403 SDK 到 `toolchain/dotnet`（不写 C 盘） |
| 商标/身份 | MIT 允许 fork，但沿用 STranslate 名会混淆 | fork 改名，插件市场地址改为空或自建 |
| 取词盲区 | 模拟 Ctrl+C 取词在终端、部分游戏、受保护窗口失效 | 上游已有失败回退到输入翻译；后续可补 OCR 兜底（上游截图 OCR 现成） |
| 上游归档风险 | STranslate 若停更，安全更新与插件兼容要自己扛 | 改动集中、依赖都走 NuGet，可独立演进 |

## 下一步

P0 编译通过后，先做 P1（1 天可见效果），再按上表决策进 P2/P3。
