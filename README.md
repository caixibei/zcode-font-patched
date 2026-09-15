# zcode-font-patch

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4?logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![GitHub stars](https://img.shields.io/github/stars/caixibei/zcode-font-patched?style=social)
![Last commit](https://img.shields.io/github/last-commit/caixibei/zcode-font-patched)

ZCode 桌面客户端 UI 字体美化补丁。

通过**等长字节替换**修改 ZCode 安装目录下 `resources/app.asar` 中的 Tailwind 根字体变量（`--font-sans` / `--font-mono`），两个变量使用各自独立的优先级栈（首个已安装的字体族命中）：

- **`--font-sans`（界面正文）**：LXGW WenKai（霞鹜文楷）→ HarmonyOS Sans SC → Source Han Sans SC（思源黑体）→ Noto Sans SC → HarmonyOS Sans → MiSans
- **`--font-mono`（代码 / 等宽）**：Anthropic Mono Variable → LXGW WenKai（汉字由它渲染）→ JetBrains Mono

无需重装客户端，可随时一键还原。

> 注：等长替换窗口有限，补丁后的字体栈不再包含 `Segoe UI Emoji` / `Noto Color Emoji`；emoji 在 Chromium 渲染管线中仍会通过系统回退链正常显示，不受影响。

## 环境要求

- Windows 10 / 11（仅需系统自带 PowerShell，无第三方依赖）
- ZCode 桌面版（Electron 应用，安装目录含 `resources\app.asar`）

## 使用方法

**打补丁**

1. 完全退出 ZCode（托盘图标右键 → Quit；点窗口 X 可能只是最小化到托盘）
2. 双击 `patch-zcode-font.bat`
3. 脚本自动定位安装目录（运行中的进程 → 注册表卸载项 → 常见安装路径），全部失败时按提示手动输入包含 `app.asar` 的 `resources` 目录
4. 补丁完成后自动重启 ZCode

**还原**

1. 完全退出 ZCode
2. 双击 `restore-zcode-font.bat`，从备份恢复原始 `app.asar` 并重启 ZCode

## 工作原理与安全机制

- **等长替换**：新字体栈比原字符串短，用空格填充到等长后写入。asar 索引头部记录的偏移量与尺寸全部保持不变，文件大小不变，无需重打包。
- **自动备份**：打补丁前把当前 `app.asar` 原样备份到工具包目录（`app.asar.font-backup`），并写入 SHA-256 指纹（`app.asar.font-backup.sha256`）。若已有备份与本机当前 asar 不一致（工具包拷贝自其他机器、或 ZCode 已升级），会先静默重建备份再打补丁，保证还原点始终是"本机打补丁前的原始状态"。
- **幂等**：重复运行自动识别当前状态——未打补丁则打，已打补丁则直接跳过并重启 ZCode，旧版本补丁自动升级。
- **版本保护**：asar 中找不到已知的原始 / 已补丁字符串（说明 ZCode 版本已变化）时拒绝写入，避免破坏性替换。
- **运行检查**：ZCode 未退出（asar 被占用）时拒绝执行；还原前校验备份文件与指纹一致，不一致时拒绝覆盖。

## 字体说明

`fonts/` 目录附带字体资源：

| 文件 | 字体 |
| --- | --- |
| `Anthropic Mono Web.otf`、`Anthropic Mono Web Regular Italic.otf` | Anthropic Mono 网页版（Regular / Italic） |
| `SourceHanSansSC-ExtraLight / Light / Normal / Regular / Medium / Bold / Heavy .otf` | 思源黑体全字重 |

补丁写入的字体族名（按命中优先级）：

- `--font-sans`：`LXGW WenKai` → `HarmonyOS Sans SC` → `Source Han Sans SC` → `Noto Sans SC` → `HarmonyOS Sans` → `MiSans`
- `--font-mono`：`Anthropic Mono Variable` → `LXGW WenKai` → `JetBrains Mono`

CSS 按**字体族名**精确匹配，系统里需安装同名族名的字体文件才会命中，例如：

- Anthropic Mono 可变字体（族名 `Anthropic Mono Variable`）
- 霞鹜文楷（族名 `LXGW WenKai`，注意不是连写的 `LXGWWenKai`）
- JetBrains Mono（族名 `JetBrains Mono`）

> 注意：`fonts/` 中静态字体安装后注册的族名可能与补丁引用的族名不同（如 `Anthropic Mono Web`、`思源黑体`），不会直接命中补丁字体栈。`fonts/` 目录用于留存与分发字体资源；如需实际命中补丁效果，请安装族名匹配的字体版本。

## 文件清单

| 文件 | 说明 |
| --- | --- |
| `patch-zcode-font.bat` / `patch-zcode-font.ps1` | 打补丁入口（bat 双击后调用同名 ps1） |
| `restore-zcode-font.bat` / `restore-zcode-font.ps1` | 还原入口 |
| `fonts/*.otf` | 字体资源，见「字体说明」 |
| `app.asar.font-backup.sha256` | 备份 SHA-256 指纹 |
| `app.asar.font-backup` | 首次打补丁时在本机生成的原始 asar 备份（体积大，已被 `.gitignore` 排除，不入库） |

工具包可整体拷贝到任意目录使用，备份与指纹始终存放在工具包所在目录内。

## 常见问题

- **提示 ZCode is running**：从托盘完全退出 ZCode 后重试。
- **提示 unknown asar state**：ZCode 版本更新导致目标字符串变化，脚本拒绝修改。先运行 `restore-zcode-font.bat` 还原，再等待工具包适配新版本。
- **ZCode 升级后字体变回默认**：升级覆盖了 `app.asar`，重新运行 `patch-zcode-font.bat` 即可；脚本会以新版 asar 作为新的备份基线。
- **还原时提示 backup not found**：本机从未打过补丁（备份由补丁脚本生成），或备份文件已被删除。备份丢失时无法用本工具还原，需重新安装 ZCode。
