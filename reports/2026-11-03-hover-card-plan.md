# 功能方案：沙拉查词式"划词气泡 + 悬停翻译"（待拍板）

日期：2026-11-03 ｜ 基线：STranslate 源码快照（已编译通过）｜ 级别：L2 功能

## 收益

选中文字 → 光标旁出现小气泡 → 鼠标移上去自动展开翻译卡片（原文/译文/词典释义 + 喇叭朗读 + 加入生词本），移开自动收起。
不用再点图标、不用弹主窗口，阅读时接近沙拉查词的手感。

## 现状（已核对源码）

- 划词取词：`Services/MouseHookService.cs` 全局鼠标钩子（拖选 + 双击选词）
- 悬浮图标：`Views/MouseSelectionIconWindow.xaml`（40×40 无激活窗口），**只在点击时**触发 `TranslateRequested`，3 秒无悬停自动消失
- 取词方式：`Helpers/ClipboardHelper.GetSelectedTextAsync()` → 模拟 `Ctrl+C` 读剪贴板
- **关键约束**：取词不恢复原剪贴板（`originalText` 只用于判断是否变化），hover 触发取词会把用户剪贴板换成所选文字
- 翻译结果目前只有两条出口：主窗口、独立窗口（`StandalonePage`）；没有轻量卡片通道

## 两种做法

### 方案 A：气泡 + 悬停展开卡片（推荐，沙拉查词体验）

改动面：

| 文件 | 改动 |
|---|---|
| `Views/MouseSelectionIconWindow.xaml(.cs)` | 增加悬停计时（默认 250ms）→ 触发 `HoverRequested`；点击仍保留立即翻译 |
| 新增 `Views/MouseSelectionCardWindow.xaml(.cs)` | 无激活卡片窗口，定位在图标右侧，含原文/译文/词典释义/喇叭/生词本按钮，Esc 与移开关闭，点击可钉住 |
| 新增 `Helpers/ClipboardSnapshot.cs` | 全格式备份 + 恢复剪贴板，抵消模拟复制的副作用 |
| 新增 `Services/QuickTranslateService.cs` | 轻量翻译通道，直接调启用中的翻译/词典插件，不经过 `MainWindowViewModel`，不弹主窗口 |
| `Services/MouseSelectionService.cs` | 增加 `HoverRequested` 分发与卡片生命周期管理 |
| `Core/Settings.cs` + 设置页 | 新增 `MouseSelectionHoverTranslate`（默认开）、`HoverTranslateDelayMs`（默认 250） |

工期：**3–5 天**（含 UI 打磨、DPI/多屏适配）。

### 方案 B：只把点击改悬停（最小改动）

hover 图标 → 直接走现有主窗口翻译。工期 **1 天**，但会弹出主窗口并抢焦点，不是沙拉查词的效果，只适合先验证链路。

## 风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| 剪贴板被抢 | 悬停即模拟 Ctrl+C，用户剪贴板被替换 | 全格式备份 + 取词后立即恢复；恢复失败则提示 |
| 与"直接翻译"模式冲突 | 两个开关同时开时现有逻辑直接翻译、不出图标 | 卡片功能跟随图标开关，UI 上标注互斥 |
| 取词时序竞争 | 用户选完立刻按 Ctrl+C，可能和恢复动作抢 | 悬停延迟 250ms；恢复动作在取词后 50ms 内完成 |
| 焦点/多屏 DPI | 无激活窗口定位偏、卡片跑到屏幕外 | 复用现有 `MonitorInfo` + `Win32Helper.GetDpiScaleForPhysicalPoint` 逻辑 |
| 取词失败 | 终端/游戏窗口模拟复制无效果 | 卡片显示"未取到文本"，回退到点击翻译 |

## 在线词典（你提的第 3 点）

不需要新建 API：STranslate 自带 金山词霸 / 必应 / 剑桥 / 有道 等词典服务（你截图里已经在用），卡片直接把已启用词典的结果并排渲染即可。新增词典时按 `IDictionaryPlugin` 写插件，不上主程序。

## 流程适配说明（桌面端 ≠ Web）

第 3 步"启动双端"→ 启动 WPF 应用（Debug 构建 + 独立 `PortableConfig`，不动你现有配置）；第 4 步"浏览器实测 + 375px"→ 真实应用交互 + 截图取证（PrintWindow）；第 5 步白盒审计对取词/剪贴板/UIA/窗口激活面做 Phase 0~6。其余步骤照原样执行。

## 待你拍板

1. 选 **方案 A**（3–5 天，沙拉查词手感）还是 **方案 B**（1 天，先验证链路）？
2. 卡片里要不要一开始就带"加入生词本"按钮（接入需等 P2 本地词库，还是先接现有欧路插件）？
