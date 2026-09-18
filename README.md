# zcode-font-patch

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4?logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![GitHub top language](https://img.shields.io/github/languages/top/caixibei/zcode-font-patched)

![GitHub stars](https://img.shields.io/github/stars/caixibei/zcode-font-patched?style=social)
![GitHub forks](https://img.shields.io/github/forks/caixibei/zcode-font-patched?style=social)
![GitHub watchers](https://img.shields.io/github/watchers/caixibei/zcode-font-patched?style=social)
![GitHub contributors](https://img.shields.io/github/contributors/caixibei/zcode-font-patched)

![GitHub issues](https://img.shields.io/github/issues/caixibei/zcode-font-patched)
![GitHub closed issues](https://img.shields.io/github/issues-closed/caixibei/zcode-font-patched?color=success)
![GitHub PRs](https://img.shields.io/github/issues-pr/caixibei/zcode-font-patched)
![GitHub closed PRs](https://img.shields.io/github/issues-pr-closed/caixibei/zcode-font-patched?color=success)

![GitHub last commit](https://img.shields.io/github/last-commit/caixibei/zcode-font-patched)
![GitHub commit activity](https://img.shields.io/github/commit-activity/m/caixibei/zcode-font-patched)
![GitHub repo size](https://img.shields.io/github/repo-size/caixibei/zcode-font-patched)
![GitHub code size](https://img.shields.io/github/languages/code-size/caixibei/zcode-font-patched)
![GitHub file count](https://img.shields.io/github/directory-file-count/caixibei/zcode-font-patched)

ZCode 桌面客户端补丁工具包，包含两个独立补丁：

1. **UI 字体美化补丁**（`patch-zcode-font`）——替换界面字体栈
2. **会话标题自动生成修复补丁**（`patch-zcode-title`）——恢复 3.12.3 中失效的侧边栏会话标题自动提炼

---

## 一、UI 字体美化补丁

通过**等长字节替换**修改 ZCode 安装目录下 `resources/app.asar` 中的 Tailwind 根字体变量（`--font-sans` / `--font-mono`），两个变量使用各自独立的优先级栈（首个已安装的字体族命中）：

- **`--font-sans`（界面正文）**：Fragment Mono（英文）→ SFMono-Regular（macOS 专属，Windows 上为惰性声明）→ HarmonyOS Sans SC → PingFang SC（苹方，汉字）→ Source Han Sans SC（思源黑体）→ Noto Sans SC
- **`--font-mono`（代码 / 等宽）**：AnthropicMono Medium（英文）→ Fragment Mono → SFMono-Regular → HarmonyOS Sans SC → Noto Sans SC → PingFang SC（汉字由它们渲染）→ JetBrains Mono

无需重装客户端，可随时一键还原。

> 注：等长替换窗口有限，补丁后的字体栈不再包含 `Segoe UI Emoji` / `Noto Color Emoji`；emoji 在 Chromium 渲染管线中仍会通过系统回退链正常显示，不受影响。

## 环境要求

- Windows 10 / 11（仅需系统自带 PowerShell，无第三方依赖）
- ZCode 桌面版（Electron 应用，安装目录含 `resources\app.asar`）

## 使用方法

### 字体补丁

**打补丁**

1. 完全退出 ZCode（托盘图标右键 → Quit；点窗口 X 可能只是最小化到托盘）
2. 双击 `patch-zcode-font.bat`
3. 脚本自动定位安装目录（运行中的进程 → 注册表卸载项 → 常见安装路径），全部失败时按提示手动输入包含 `app.asar` 的 `resources` 目录
4. 补丁完成后自动重启 ZCode

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-font.bat`，从备份恢复原始 `app.asar` 并重启 ZCode

### 标题自动生成修复补丁（3.12.3 专用）

**适用症状**：ZCode 升级到 3.12.3 后，侧边栏新会话不再自动提炼中文短标题，标题停留在首条消息的原始截断文本（如 `NODE_ENV=development VUE_APP_BUILD_TYPE=…`），只能手动重命名。

**打补丁**

1. 完全退出 ZCode（托盘图标右键 → Quit）
2. 双击 `patch-zcode-title.bat`
3. 脚本自动定位安装目录，定位失败时手动输入包含 `zcode.cjs` 的 `resources\glm` 目录
4. 补丁完成后自动重启 ZCode；此后新建会话首轮对话完成后，侧边栏标题会自动替换为 LLM 提炼的短标题

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-title.bat`，从备份恢复原始 `zcode.cjs` 并重启 ZCode

> 两个补丁相互独立，可单独打/单独还原；同时使用时顺序不限。`restore-zcode-font.bat` 只还原字体、不影响标题补丁，反之亦然。

## 工作原理与安全机制

- **等长替换**：新字体栈比原字符串短，用空格填充到等长后写入。asar 索引头部记录的偏移量与尺寸全部保持不变，文件大小不变，无需重打包。
- **自动备份**：打补丁前把当前 `app.asar` 原样备份到工具包目录（`app.asar.font-backup`），并写入 SHA-256 指纹（`app.asar.font-backup.sha256`）。若已有备份与本机当前 asar 不一致（工具包拷贝自其他机器、或 ZCode 已升级），会先静默重建备份再打补丁，保证还原点始终是"本机打补丁前的原始状态"。
- **幂等**：重复运行自动识别当前状态——未打补丁则打，已打补丁则直接跳过并重启 ZCode，旧版本补丁自动升级。
- **版本保护**：asar 中找不到已知的原始 / 已补丁字符串（说明 ZCode 版本已变化）时拒绝写入，避免破坏性替换。
- **运行检查**：ZCode 未退出（asar 被占用）时拒绝执行；还原前校验备份文件与指纹一致，不一致时拒绝覆盖。

---

## 二、会话标题自动生成修复补丁（3.12.3）

### 背景

ZCode 3.12.3（2026-09-17 发布）起，新建交互会话不再触发标题自动提炼。排查确认：

- 旧版（3.12.2 及更早）中，首轮对话完成后 agent 运行时会发起一次 `querySource=session_title` 的独立模型请求，把用户首条消息提炼成 3–7 词的短标题写回会话；
- 3.12.3 运行时（`resources\glm\zcode.cjs`）中该请求彻底消失，且日志无任何 `session_title_generation.*` 事件（连 skipped 都没有）；
- 功能代码（标题提示词、模型调用、写回逻辑）在 3.12.3 中全部保留，未被移除。

### 根因

`zcode.cjs` 中两个标题生成资格判断函数（反混淆名 `FYi` / `NYi`，内部名 `shouldAttemptSessionTitleGeneration` / `shouldAttemptGoalSummaryTitleGeneration`）的短路条件为：

```js
... || e.config.titleGeneration?.enabled===!1 || !e.config.titleGeneration || ...
```

其中 `!e.config.titleGeneration` 要求配置对象必须存在（真值）。桌面端 host 创建会话时传入的是空对象 `{}`，经上游运行时配置合并后可能变为 `undefined`，于是该条件恒为真，函数在发出任何日志前就返回 `false`——标题生成被静默跳过。这是 3.12.3 的回归 bug（官方更新日志未声明此变更）。

### 补丁原理（v2，共两处修改）

**修改 1：恢复标题生成触发**。将两个函数中的 `||!e.config.titleGeneration` 条件删除（其余门槛全部保留：显式关闭、子会话、非交互任务、已尝试过、首条输入过短等仍正常拦截），删除出的 27 字节用等长的 `/*...*/` 空注释填充。补丁后的函数体经 Node 实测——配置 `undefined` / `{}` 时放行生成，`{enabled:!1}`（显式关闭）、短输入、非交互任务仍正确拦截；自动化/定时任务仍传 `titleGenerationEnabled:!1`，显式关闭语义不受影响。

**修改 2：强化标题语言规则**（v2 新增）。3.12.3 标题提示词中的语言规则原文是弱约束 `- Use the user's primary language.`，实测部分模型（如 minimax-m3）不遵守，对全中文输入会输出英文标题。v2 将其强化为 `- MUST use the user's primary language.`（+5 字节）。`zcode.cjs` 是独立文件（不在 asar 归档内，无偏移量/长度头依赖），文件小幅变长安全。

> v1 用户说明：v1 只含修改 1。直接重新运行 `patch-zcode-title.bat` 即可原地升级到 v2，脚本自动识别 v1 状态（含无备份时从补丁态反向重建干净基线），无需先还原。

### 安全机制

与字体补丁一致：

- 打补丁前把当前 `zcode.cjs` 备份到工具包目录（`zcode.cjs.title-backup`）并写入 SHA-256 指纹（`zcode.cjs.title-backup.sha256`）；
- 备份始终指向"本机打补丁前的原始状态"，已有有效备份不会被覆盖；
- 幂等：重复运行自动识别状态并跳过；
- 版本保护：`zcode.cjs` 中找不到已知原始字符串（说明 ZCode 版本已变化）时拒绝修改；
- 运行检查：ZCode 未退出时拒绝执行。

### 生效验证

补丁并重启后，新建一个会话发一条消息，等首轮对话完成后：

- 侧边栏标题自动变为提炼后的短标题（会话列表 `title_source` 变为 `generated`）；
- 日志 `~/.zcode/cli/log/zcode-*.jsonl` 中出现 `"querySource":"session_title"` 的 `model.request.completed` 事件；
- **中文输入应产出中文标题**。若仍出现英文标题：先确认已升级到 v2（检查 `zcode.cjs` 中语言规则是否为 `- MUST use the user's primary language.`），再检查该会话所用模型——个别模型对 MUST 指令遵从度仍低，属模型能力问题而非补丁失效。

### 升级注意

ZCode 后续版本升级会覆盖 `resources\glm\zcode.cjs`，标题补丁随之失效（字体补丁同理）。若官方已修复此 bug 则无需重打；若未修复，更新本工具包中 `$oldFy` / `$oldNy` 字符串以匹配新版代码后重新运行。

## 字体说明

`fonts/` 目录附带全部字体资源压缩包，需解压后安装：

| 压缩包 | 内容 | 对应补丁栈字体族 |
| --- | --- | --- |
| `Anthropic Sans.zip` | AnthropicSans 静态字体 14 款（Light ~ Black，含斜体） | `AnthropicSans`（sans 首位，英文） |
| `Anthropic Mono.zip` | AnthropicMono 静态字体 7 字重 + AnthropicMonoVariable 可变字体 | `AnthropicMono`（mono 首位，英文）、`Anthropic Mono Variable` |
| `Anthropic Serif.zip` | AnthropicSerif 静态字体 14 款（Light ~ Black，含斜体） | 备用资源，不在补丁栈内 |
| `LXGWWenKai.zip` | 霞鹜文楷 Regular | `LXGW WenKai`（sans 汉字首选） |
| `PingFang SC.zip` | 苹方 SC（ttf / woff2，Thin ~ Semibold） | `PingFang SC` |
| `HarmonyOS-Sans.zip` | HarmonyOS Sans 全家族（含 SC / TC / Condensed / Naskh Arabic） | `HarmonyOS Sans SC` |
| `SourceHanSansSC.zip` | 思源黑体 SC 全字重（ExtraLight ~ Heavy） | `Source Han Sans SC` |
| `MiSans.zip` | MiSans 全字重 + 可变字体 | `MiSans` |
| `JetBrainsMono-2.304.zip` | JetBrains Mono v2.304（ttf / woff2 / 可变字体） | `JetBrains Mono`（mono 栈） |

补丁写入的字体族名（按命中优先级）：

- `--font-sans`：`Fragment Mono` → `SFMono-Regular` → `HarmonyOS Sans SC` → `PingFang SC` → `Source Han Sans SC` → `Noto Sans SC`
- `--font-mono`：`AnthropicMono Medium` → `Fragment Mono` → `SFMono-Regular` → `HarmonyOS Sans SC` → `Noto Sans SC` → `PingFang SC` → `JetBrains Mono`

CSS 按**字体族名**精确匹配，系统里需安装同名族名的字体文件才会命中，例如：

- AnthropicMono Medium（族名 `AnthropicMono Medium`，即 AnthropicMono 静态字重的传统族名形式，nameID 1 实测带字重）
- Fragment Mono（族名 `Fragment Mono`，仅 Regular / Italic 两个字重）
- `SFMono-Regular` 为 macOS 系统字体，Windows 上未安装也不影响——CSS 对缺失族名自动跳过下一级，声明无害
- HarmonyOS Sans SC（族名 `HarmonyOS Sans SC`）
- 苹方（族名 `PingFang SC`）
- JetBrains Mono（族名 `JetBrains Mono`）

> 注意：`fonts/` 中静态字体安装后注册的族名可能与补丁引用的族名不同（如 `Anthropic Mono Web`、`思源黑体`），不会直接命中补丁字体栈。`fonts/` 目录用于留存与分发字体资源；如需实际命中补丁效果，请安装族名匹配的字体版本。

## 文件清单

| 文件 | 说明 |
| --- | --- |
| `patch-zcode-font.bat` / `patch-zcode-font.ps1` | 字体补丁入口（bat 双击后调用同名 ps1） |
| `restore-zcode-font.bat` / `restore-zcode-font.ps1` | 字体还原入口 |
| `patch-zcode-title.bat` / `patch-zcode-title.ps1` | 标题自动生成修复补丁入口（3.12.3 专用） |
| `restore-zcode-title.bat` / `restore-zcode-title.ps1` | 标题补丁还原入口 |
| `fonts/*.zip` | 字体资源压缩包，需解压安装，见「字体说明」 |
| `app.asar.font-backup.sha256` / `zcode.cjs.title-backup.sha256` | 备份 SHA-256 指纹 |
| `app.asar.font-backup` / `zcode.cjs.title-backup` | 首次打补丁时在本机生成的原始文件备份（体积大，已被 `.gitignore` 排除，不入库） |

工具包可整体拷贝到任意目录使用，备份与指纹始终存放在工具包所在目录内。

## 常见问题

- **提示 ZCode is running**：从托盘完全退出 ZCode 后重试。
- **提示 unknown asar state / unknown zcode.cjs state**：ZCode 版本更新导致目标字符串变化，脚本拒绝修改。先运行对应的 `restore-*.bat` 还原，再等待工具包适配新版本。
- **ZCode 升级后字体变回默认**：升级覆盖了 `app.asar`，重新运行 `patch-zcode-font.bat` 即可；脚本会以新版 asar 作为新的备份基线。
- **ZCode 升级后标题又不生成了**：升级覆盖了 `resources\glm\zcode.cjs`，见「升级注意」。
- **还原时提示 backup not found**：本机从未打过对应补丁（备份由补丁脚本生成），或备份文件已被删除。备份丢失时无法用本工具还原，需重新安装 ZCode。
