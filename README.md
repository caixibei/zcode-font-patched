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

ZCode 桌面客户端补丁工具包，包含四个独立补丁：

1. **UI 字体美化补丁**（`patch-zcode-font`）——替换界面字体栈
2. **会话标题自动生成修复补丁**（`patch-zcode-title`）——恢复 3.12.3 中失效的侧边栏会话标题自动提炼
3. **桌面壁纸补丁**（`patch-zcode-wallpaper`）——把窗口根背景换成自选照片（半透明主题色纱罩保证可读性）
4. **更新检查禁用补丁**（`patch-zcode-updates`）——彻底关闭自动更新检测，侧边栏不再出现绿色「更新」徽标；想升级时自行下载安装包

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

### 标题自动生成修复补丁（3.12.3 / 3.14.x）

**适用症状**：ZCode 3.12.3 起，侧边栏新会话不再自动提炼中文短标题，标题停留在首条消息的原始截断文本（如 `NODE_ENV=development VUE_APP_BUILD_TYPE=…`），只能手动重命名。

**打补丁**

1. 完全退出 ZCode（托盘图标右键 → Quit）
2. 双击 `patch-zcode-title.bat`
3. 脚本自动定位安装目录，定位失败时手动输入包含 `zcode.cjs` 的 `resources\glm` 目录
4. 补丁完成后自动重启 ZCode；此后新建会话首轮对话完成后，侧边栏标题会自动替换为 LLM 提炼的短标题

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-title.bat`，从备份恢复原始 `zcode.cjs` 并重启 ZCode

> 三个 UI 补丁相互独立，可单独打/单独还原；同时使用时顺序不限。`restore-zcode-font.bat` 只还原字体、不影响标题补丁和壁纸补丁，壁纸补丁还原时也会保留字体补丁。更新禁用补丁改的是主进程文件，与三者互不干扰。

## 工作原理与安全机制（字体 / 标题补丁）

- **等长替换**：新字体栈比原字符串短，用空格填充到等长后写入。asar 索引头部记录的偏移量与尺寸全部保持不变，文件大小不变，无需重打包。
- **自动备份**：打补丁前把当前 `app.asar` 原样备份到工具包目录（`app.asar.font-backup`），并写入 SHA-256 指纹（`app.asar.font-backup.sha256`）。若已有备份与本机当前 asar 不一致（工具包拷贝自其他机器、或 ZCode 已升级），会先静默重建备份再打补丁，保证还原点始终是"本机打补丁前的原始状态"。
- **幂等**：重复运行自动识别当前状态——未打补丁则打，已打补丁则直接跳过并重启 ZCode，旧版本补丁自动升级。
- **版本保护**：asar 中找不到已知的原始 / 已补丁字符串（说明 ZCode 版本已变化）时拒绝写入，避免破坏性替换。
- **运行检查**：ZCode 未退出（asar 被占用）时拒绝执行；还原前校验备份文件与指纹一致，不一致时拒绝覆盖。

---

## 二、会话标题自动生成修复补丁

### 背景

ZCode 3.12.3（2026-09-17 发布）起，新建交互会话不再触发标题自动提炼。排查确认：

- 旧版（3.12.2 及更早）中，首轮对话完成后 agent 运行时会发起一次 `querySource=session_title` 的独立模型请求，把用户首条消息提炼成 3–7 词的短标题写回会话；
- 3.12.3 起运行时（`resources\glm\zcode.cjs`）中该请求彻底消失，且日志无任何 `session_title_generation.*` 事件（连 skipped 都没有）；
- 功能代码（标题提示词、模型调用、写回逻辑）全部保留，未被移除。

### 根因

`zcode.cjs` 中两个标题生成资格判断函数（内部名 `shouldAttemptSessionTitleGeneration` / `shouldAttemptGoalSummaryTitleGeneration`；混淆名随版本变化：3.12.3 为 `FYi`/`NYi`，3.14.1 为 `Pba`/`Tba`）的短路条件为：

```js
... || e.config.titleGeneration?.enabled===!1 || !e.config.titleGeneration || ...
```

其中 `!e.config.titleGeneration` 要求配置对象必须存在（真值）。桌面端 host 创建会话时传入的是空对象 `{}`，经上游运行时配置合并后可能变为 `undefined`，于是该条件恒为真，函数在发出任何日志前就返回 `false`——标题生成被静默跳过。**经逐字节比对确认 3.12.3 至 3.14.1 均保留同一回归 bug**（官方更新日志未声明此变更）。

### 补丁原理（v3，共两处修改）

**修改 1：恢复标题生成触发**。将两个函数中的 `||!e.config.titleGeneration` 条件删除（其余门槛全部保留：显式关闭、子会话、非交互任务、已尝试过、首条输入过短等仍正常拦截），删除出的 27 字节用等长的 `/*...*/` 空注释填充。补丁后的函数体经 Node 实测——配置 `undefined` / `{}` 时放行生成，`{enabled:!1}`（显式关闭）、短输入、非交互任务仍正确拦截；自动化/定时任务仍传 `titleGenerationEnabled:!1`，显式关闭语义不受影响。

**修改 2：强化标题语言规则**。标题提示词中的语言规则原文是弱约束 `- Use the user's primary language.`，实测部分模型（如 minimax-m3）不遵守，对全中文输入会输出英文标题。补丁将其强化为 `- MUST use the user's primary language.`（+5 字节）。`zcode.cjs` 是独立文件（不在 asar 归档内，无偏移量/长度头依赖），文件小幅变长安全。

**多版本适配（v3 新增）**：函数名随版本被混淆器改名，v3 起脚本内置**按版本的特征签名表**，自动识别本机 `zcode.cjs` 对应哪个 ZCode 版本并选用对应原文片段：

| ZCode 版本 | 资格函数混淆名 | 支持状态 |
| --- | --- | --- |
| 3.14.x | `Pba` / `Tba` | ✅ 已适配 |
| 3.12.3 | `FYi` / `NYi` | ✅ 已适配 |
| 其他版本 | 未知 | ❌ 拒绝执行（安全保护） |

> 旧版补丁用户说明：直接重新运行 `patch-zcode-title.bat` 即可原地升级，脚本自动识别 v1/v2 状态（含无备份时从补丁态反向重建干净基线），无需先还原。ZCode 升级覆盖 `zcode.cjs` 后重跑脚本即可（见「升级注意」）。

### 安全机制

与字体补丁一致：

- 打补丁前把当前 `zcode.cjs` 备份到工具包目录（`zcode.cjs.title-backup`）并写入 SHA-256 指纹（`zcode.cjs.title-backup.sha256`）；
- 备份始终指向"本机打补丁前的原始状态"，已有有效备份不会被覆盖；
- 幂等：重复运行自动识别状态并跳过；
- 版本保护：`zcode.cjs` 中找不到任何已知版本的特征字符串（说明 ZCode 版本已变化）时拒绝修改；
- 运行检查：ZCode 未退出时拒绝执行。

### 生效验证

补丁并重启后，新建一个会话发一条消息，等首轮对话完成后：

- 侧边栏标题自动变为提炼后的短标题（会话列表 `title_source` 变为 `generated`）；
- 日志 `~/.zcode/cli/log/zcode-*.jsonl` 中出现 `"querySource":"session_title"` 的 `model.request.completed` 事件；
- **中文输入应产出中文标题**。若仍出现英文标题：先确认补丁已应用（检查 `zcode.cjs` 中语言规则是否为 `- MUST use the user's primary language.`），再检查该会话所用模型——个别模型对 MUST 指令遵从度仍低，属模型能力问题而非补丁失效。

### 升级注意

ZCode 版本升级会覆盖 `resources\glm\zcode.cjs`，标题补丁随之失效并出现 `unknown zcode.cjs state` 报错（这是版本保护在起作用，不是故障）。处理方式：

1. 退出 ZCode 后重新运行 `patch-zcode-title.bat`；若脚本签名表已收录新版，会自动识别并重打；
2. 若签名表未收录（报错里会打印各版本特征的命中计数），需人工定位新版 `zcode.cjs` 中的新混淆函数名（搜索 `shouldAttemptSessionTitleGeneration` 调试标注附近的 `function` 定义），把新原文追加进两个脚本的 `$versions` 表；
3. 若官方已修复此 bug 则无需重打，直接删除旧备份即可。

---

## 三、桌面壁纸补丁

把 ZCode 桌面端窗口根背景（深/浅色主题下的纯色底）替换为一张照片：照片经等比缩放（长边 1920px）+ JPEG 压缩后以 data URI 形式内嵌进渲染层 CSS，整窗可见；聊天内容区叠加一层跟随主题色的半透明「纱」，纱越薄照片越清晰，越厚文字越易读。

**内置壁纸**：`wallpapers/` 目录自带 6 张（云雾山峦 / 博派·擎天柱 / 夏日侧脸 / 乡村山峰 / 原野孤树 / 手绘雪屋），也可在菜单选 `[0]` 输入任意本机图片路径（支持中文路径）。

**打补丁 / 换图**

1. 完全退出 ZCode（托盘图标右键 → Quit）
2. 双击 `patch-zcode-wallpaper.bat`
3. 菜单选壁纸编号 + 输入纱浓度（0–85，`0` = 纯照片，越大纱越实、照片越淡，默认 60）
4. 完成后自动重启 ZCode

**随时换图**：直接再次运行 `patch-zcode-wallpaper.bat`，选另一张图或调整纱浓度即可，无需先还原。

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-wallpaper.bat`，从备份恢复原始 `app.asar`（字节级还原，SHA-256 与原厂一致）并重启 ZCode

**工作原理与安全机制**

- **asar 重打包**（与字体补丁的等长替换不同，照片无法塞进等长窗口）：脚本自带 PowerShell 版 asar 读写器，解包 → 追加壁纸 CSS 块 → 重算全部文件偏移 → 重新打包。除目标 CSS 追加一段带 `ZCODE-WALLPAPER-PATCH` 标记的规则外，其余 27000+ 个文件逐字节保持不变（已实测比对）。产物已通过官方 `@electron/asar` 工具读取验证；本机 ZCode.exe 未启用 asar 完整性熔丝（EnableEmbeddedAsarIntegrityValidation），重打包可被正常加载。
- **自动备份**：首次打补丁时对当前 `app.asar` 做字节级备份（`app.asar.wallpaper-backup` + SHA-256 指纹）；若当前 asar 已含壁纸补丁而备份缺失，用「剥除补丁块」方式重建干净基线。还原即 verbatim 恢复备份。
- **幂等与状态识别**：重复运行自动识别已打补丁状态并支持换图；检测到损坏的补丁块时拒绝执行并提示先还原。
- **与字体补丁共存**：字体栈在 CSS 补丁块之前，互不干扰；打壁纸补丁前打过字体补丁，还原壁纸后字体补丁仍然保留。
- **版本保护**：`app.asar` 内找不到渲染层 CSS（按 3.14.1 的路径 `out/renderer/assets/styles-C8Nayk5k.css` 定位）时拒绝执行。

> 升级注意：ZCode 升级会覆盖 `app.asar`（CSS 文件名随版本变化），壁纸补丁随之失效——先运行还原，再等工具包适配新版后重打。

---

## 四、更新检查禁用补丁

ZCode 桌面端启动时会检查更新并每小时轮询一次，检测到新版本后侧边栏左上角常驻一枚绿色「更新」徽标（点开就是提示重启安装）。本补丁让应用走其自带的「product flavor 禁用更新」分支：不再发起任何更新检测请求，徽标永远不会出现；是否升级、何时升级完全由用户手动决定（自行下载新安装包覆盖安装即可）。

**打补丁**

1. 完全退出 ZCode（托盘图标右键 → Quit）
2. 双击 `patch-zcode-updates.bat`
3. 补丁完成后自动重启 ZCode

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-updates.bat`，从备份恢复原始 `app.asar` 并重启 ZCode，更新检测恢复如初

**工作原理与安全机制**

- **单一入口，等长替换**：更新逻辑只在主进程包 `out/main/index.js` 初始化（`initAutoUpdater`，全包唯一调用点；host/worker/preload 均无更新逻辑）。初始化函数的第一个分支就是应用自带的禁用开关（`enabled===!1` 时清掉轮询定时器直接返回），补丁把唯一调用点的 `enabled:Ge==="production"`（`Ge` 是构建期常量 `"production"`）等长替换为 `enabled:!1/*…*/`（25 字节 → 25 字节，全文件仅 17 个字节变化），asar 头部偏移与文件大小不变，无需重打包。
- **禁用后的行为**（静态分析确认）：启动检查与每小时轮询均不注册；`UpdateStateChanged` / `UpdateReady` 不再广播；侧边栏绿色徽标由渲染层订阅这些状态渲染，状态恒为 idle，徽标不会出现；菜单「检查更新」点击后返回禁用态（渲染层弹「开发环境不检查更新」提示，不发起网络请求）。设置里的 `autoDownloadAndInstallUpdates` 开关只控制自动下载，与本补丁无关、互不影响。
- **自动备份与幂等**：与字体补丁同机制——首打时字节级备份当前 `app.asar`（`app.asar.updates-backup` + SHA-256 指纹）；备份缺失时从补丁态反向重建；重复运行自动识别已打补丁状态；写入前后自检（仅允许 17 字节差异、tmp 文件通过 asar 解析校验后才替换）。
- **与其他补丁共存**：字体/壁纸补丁只改渲染层 CSS，本补丁只改主进程 `index.js`，互不干扰。
- **版本保护**：`app.asar` 内找不到目标片段（说明 ZCode 版本已变化）时拒绝执行。

> 升级注意：ZCode 升级会覆盖 `app.asar`，更新检测会随新版恢复——在新版 `app.asar` 上重跑 `patch-zcode-updates.bat` 即可（脚本会以新版 asar 作为新的备份基线；若签名因版本变化无法匹配，脚本会拒绝执行，等待工具包适配）。

---

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
| `patch-zcode-wallpaper.bat` / `patch-zcode-wallpaper.ps1` | 桌面壁纸补丁入口（含选图菜单与纱浓度调节） |
| `restore-zcode-wallpaper.bat` / `restore-zcode-wallpaper.ps1` | 壁纸还原入口 |
| `patch-zcode-updates.bat` / `patch-zcode-updates.ps1` | 更新检查禁用补丁入口 |
| `restore-zcode-updates.bat` / `restore-zcode-updates.ps1` | 更新检测还原入口 |
| `wallpapers/` | 内置壁纸（6 张），可自行增删图片文件，菜单自动列出 |
| `fonts/*.zip` | 字体资源压缩包，需解压安装，见「字体说明」 |
| `app.asar.font-backup.sha256` / `zcode.cjs.title-backup.sha256` / `app.asar.wallpaper-backup.sha256` / `app.asar.updates-backup.sha256` | 备份 SHA-256 指纹 |
| `app.asar.font-backup` / `zcode.cjs.title-backup` / `app.asar.wallpaper-backup` / `app.asar.updates-backup` | 首次打补丁时在本机生成的原始文件备份（体积大，已被 `.gitignore` 排除，不入库） |

工具包可整体拷贝到任意目录使用，备份与指纹始终存放在工具包所在目录内。

## 常见问题

- **提示 ZCode is running**：从托盘完全退出 ZCode 后重试。
- **提示 unknown asar state / unknown zcode.cjs state**：ZCode 版本更新导致目标字符串变化，脚本拒绝修改。先运行对应的 `restore-*.bat` 还原，再等待工具包适配新版本。
- **ZCode 升级后字体变回默认**：升级覆盖了 `app.asar`，重新运行 `patch-zcode-font.bat` 即可；脚本会以新版 asar 作为新的备份基线。
- **ZCode 升级后标题又不生成了**：升级覆盖了 `resources\glm\zcode.cjs`，见「升级注意」。
- **ZCode 升级后壁纸消失了**：升级覆盖了 `app.asar` 且渲染层 CSS 文件名随版本变化，先运行 `restore-zcode-wallpaper.bat`（识别不了会拒绝执行），再等工具包适配新版后重打。
- **壁纸文字看不清**：重新运行 `patch-zcode-wallpaper.bat`，把纱浓度调高（如 70–85）。
- **又出现绿色「更新」徽标了**：ZCode 升级覆盖了 `app.asar`，更新检测随新版恢复——重新运行 `patch-zcode-updates.bat` 即可。
- **还原时提示 backup not found**：本机从未打过对应补丁（备份由补丁脚本生成），或备份文件已被删除。备份丢失时无法用本工具还原，需重新安装 ZCode。
