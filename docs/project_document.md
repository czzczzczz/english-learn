# 项目档案：english_learn（英语学习工具）

> 稳定事实的权威记录。变更只在本文件维护，其他文档引用路径，不复制内容。

## 1. 目标

做一个开源的英语学习桌面工具，核心是「看到英文 → 立刻看懂 + 听到发音 + 进生词本」，再叠加复习与 AI 辅助。

三条主链路：

1. **划词**：任意应用选中英文 → 气泡 → 悬停 → 弹翻译（可选自动朗读）；
2. **框选识别**：左键长按 450ms 或 `Alt+Q` → 全屏遮罩 → 拖框 → OCR → 翻译；
3. **生词本**：一键收词、自动补音标与释义、AI 生成复习故事。

## 2. 技术底座

| 项 | 值 |
|---|---|
| 基线项目 | STranslate（WPF / .NET 10），fork 后二次开发 |
| 源码根 | `vendor/STranslate-main/src` |
| 主工程 | `STranslate/STranslate.csproj`（`net10.0-windows10.0.19041.0`） |
| 插件 SDK | `STranslate.Plugin`（`IPlugin` / `ITranslatePlugin` / `ITtsPlugin` / `ITtsOptions` / `IPhoneticAware`） |
| MVVM | CommunityToolkit.Mvvm（`ObservableProperty` partial 属性写法） |
| UI 库 | iNKORE UI (WPF-UI Modern) |
| 截图框选库 | ScreenGrab 1.0.17 |
| OCR | Windows 内置 `Windows.Media.Ocr`（离线免 key） |

## 3. 路径表

| 用途 | 路径 | 状态 |
|---|---|---|
| 项目根 | `D:\vibe_coding\english_learn` | 已确认 |
| 部署目录（运行/验证） | `D:\vibe_coding\STranslate-dev` | 已确认 |
| 本地 .NET SDK | `D:\vibe_coding\english_learn\toolchain\dotnet` | 已确认 |
| NuGet 包缓存 | `D:\vibe_coding\english_learn\toolchain\nuget` | 已确认 |
| 构建临时目录 | `D:\vibe_coding\english_learn\toolchain\tmp` | 已确认 |
| 旧备份目录（ZIP） | `D:\vibe_coding\english_learn\beifen` | 已确认 |
| 备份目录（新规则） | `reserve/` | 已确认 |
| 下载/导出/产物 | `D:\dsh\downloads` | **待用户确认** |
| 缓存/临时 | `D:\dsh\cache`（tmp: `D:\dsh\cache\tmp`） | **待用户确认** |

## 4. 构建 / 部署 / 验证

```bash
# 构建（必须设置这五个环境变量）
export DOTNET_CLI_HOME="D:/vibe_coding/english_learn/toolchain/home" \
       NUGET_PACKAGES="D:/vibe_coding/english_learn/toolchain/nuget" \
       TMP="D:/vibe_coding/english_learn/toolchain/tmp" \
       TEMP="D:/vibe_coding/english_learn/toolchain/tmp" \
       PATH="/d/vibe_coding/english_learn/toolchain/dotnet:$PATH"
dotnet build STranslate/STranslate.csproj -c Debug -v q          # 主程序
dotnet build Plugins/<插件目录>/<插件>.csproj -c Debug -v q      # 插件单独构建
```

- 部署：`pwsh7 -File toolchain/deploy_tts.ps1`（robocopy 到 `D:\vibe_coding\STranslate-dev`，**排除 `PortableConfig`**，否则会覆盖用户配置）
- 备份：`pwsh7 -File toolchain/backup_code.ps1 -Label "<说明>"`（保留目录层级，落到 `beifen/`）

### 关键坑（都已踩过）

| 现象 | 原因 / 解法 |
|---|---|
| exe 放在工作区运行，鼠标钩子收不到输入 | 工作区 exe 是低完整性；必须从 `D:\vibe_coding\STranslate-dev` 启动 |
| 启动即退，无异常日志 | 多为 XAML 解析崩溃。用 `Get-WinEvent Application -ProviderName ".NET Runtime"` 看完整堆栈 |
| 设置窗口一开就崩 | iNKORE `ui:NumberBox` 在此环境让 `MinWidth` 变成 `UnsetValue`；改用 `ComboBox` |
| 只读属性绑定到双向 DP | `ui:SettingsCard` 内的 DP 默认双向，绑只读属性要显式 `Mode=OneWay` |
| `Compress-Archive` 备份丢目录层级 | 已改用 `ZipArchive` 逐条写入（`backup_code.ps1`） |
| 应用启动后主窗口不可见 | 用 `Alt+G`（OpenWindowHotkey）唤起，或 `ShowWindow`；UIA 对隐藏窗口不可见 |

## 5. 功能现状

| 模块 | 状态 |
|---|---|
| 划词气泡 + 悬停翻译 | ✅ 实测通过 |
| 选中即翻译（方式三） | ✅ 与气泡互斥 |
| 自动朗读（有道真人 / 百度兜底） | ✅ 整句走百度合成（Google 在国内不可用，已移除） |
| 朗读设置页 | ✅ 宿主原生控件直显（发音源/口音/语速/试听） |
| 生词本（内置 JSON） | ✅ 收词/搜索/删除/导出/AI 故事 |
| 生词本音标补全 | ✅ dictionaryapi.dev（免 key） |
| 音标体系 KK/IPA/对照 | ✅ 默认 KK，插件与生词本共用 |
| OCR 框选识别 | ✅ 左键长按 450ms + `Alt+Q`；Windows OCR + 反色/放大兜底 |
| 翻译历史左右箭头 | ✅ 标题栏，20 条，纯内存 |
| AI 生词故事 | ✅ OpenAI 兼容中转站，可拉模型列表，支持专用代理 |
| 顶边吸附 | ❌ 已删除（与置顶冲突） |
| OCR/图片翻译/历史页/插件市场 | ❌ 瘦身时删除，仅保留底层插件 |

## 6. 行为契约

- **置顶**：钉子按钮是唯一置顶入口；`IsUserTopmost` 是用户意图，`IsTopmost` 是窗口实际层级（含气泡临时置顶）。钉子图标绑前者，避免被临时置顶污染。
- **点外部隐藏**：未钉住时点窗口外隐藏；钉住时任何路径都不隐藏（`Hide()` 首行拦 `IsUserTopmost`）。
- **划词 vs 长按**：450ms 内移动超 6px 判为划词；按住不动触发框选。
- **音标**：词典数据统一存 IPA，显示时按 `PhoneticSystem` 转换；KK 只用于美式，英式保持原样。
- **导出**：CSV 导到 `D:\dsh\downloads`，不写用户目录。

## 7. 外部依赖与密钥

| 服务 | 用途 | 认证 |
|---|---|---|
| `api.dictionaryapi.dev` | 音标 + 英文释义 | 免 key |
| 彩云翻译 | 主力翻译 | key 在插件配置 |
| Bing 词典（网页解析） | 中英释义 + 例句 | 免 key |
| 有道 `dictvoice` | 单词真人发音 | 免 key |
| 百度 `gettts` | 整句合成 | 免 key |
| AI 中转站（`api.yicode.ai/v1`） | 生词故事 | 用户 key，**需代理 `127.0.0.1:10809`** |

## 8. 变更记录

| 日期 | 内容 |
|---|---|
| 2026-11-03 | fork 落地；划词气泡、瘦身（删 OCR/图片翻译/历史页/插件市场/SQLite） |
| 2026-11-03 | TTS 插件改造（有道+Google+百度）；朗读设置页直显 |
| 2026-11-03 | 生词本内建（JSON 存储 + 词表页） |
| 2026-11-04 | 删顶边吸附；修置顶状态反相（`IsUserTopmost` 拆分） |
| 2026-11-04 | 左键长按框选 OCR（Windows OCR + 三重兜底） |
| 2026-11-04 | `Alt+Q` 热键 + Free Dictionary 翻译插件 + KK 音标体系 |
| 2026-11-04 | 翻译历史左右箭头（20 条内存） |
| 2026-11-04 | AI 生词故事（中转站 + 模型拉取 + 代理） |
