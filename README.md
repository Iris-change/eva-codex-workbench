# EVA Codex Workbench

Windows / macOS 本地 Codex 工作台，红黑主题、启动动画及真实 Codex 连接。**0.3.1 预览版**，不是官方客户端，也不修改官方安装或已有桌面入口。

公开版保留动画结构和功能，系统唤醒和工作台侧栏使用红色 NERV 标志，启动确认页使用明日香头像，工作台背景使用明日香线稿，OpenAI 图案使用中性占位，系统播报使用与私人版完全相同的日语原录音。不包含原作素材包或 BGM。此目录也不包含另一个“动画后打开官方客户端”的独立启动器。

## macOS 原生版（Codex + Claude Code 双后端）

`native-macos/` 是 Swift / AppKit 编写的原生桌面应用 **EVA Workbench.app**（0.11.0），界面不使用 WebKit；后端仍是 `workbench/` 中的本地 Node 服务，同时驱动官方 Codex app-server 和官方 Claude Code（`@anthropic-ai/claude-agent-sdk` 随附的 CLI）。

主要功能：

- 一个窗口里同时使用 Codex 和 Claude Code；Claude Code 提供只读 / 写入（逐次确认）/ 完全访问三档权限，空闲会话可直接切换。
- 读取本机 Codex、Claude 桌面版和 Claude Code CLI 的历史会话；继续历史会话时创建 EVA 分支，原记录不改。
- 在当前对话里切换助手继续（Codex ⇄ Claude Code）：标题不变，历史作为参考转交，权限重置为只读，发送前可撤销。
- 重复会话可合并收起，本机历史可只在 EVA 中归档，均可恢复；官方记录不改动。
- 通用附件：多选、粘贴、拖入；PDF、Word（docx / doc）、RTF、Excel、PPT、OpenDocument 提取文字；图片转为可识图格式（多页 TIFF / 动图会标明只发送第 1 页 / 帧）。
- 上下文、5 小时和每周用量小组件；红黑 / 红白 / 跟随系统主题。
- 与网页版相同的约 20 秒开场（明朝体、LCL、同步率 99.2% 确认、日文播报与中文字幕），亮色 / 暗色各一套；Esc 跳过，“显示”菜单可关闭。
- 输入框回车发送，Shift + 回车换行；输入法选字时回车只确认候选词。
- 界面按网页版重做：红色渐变侧栏、黄黑警示条系统栏、明朝体标题、OPERATION 快捷卡片、红线输入区、扁平自绘按钮与下拉框、两侧红黑警示边；对话区随窗口宽度自适应。
- 执行过程实时可见：命令、文件读写与修改、搜索、网页、子任务、MCP 等每一步按发生顺序插在对话中，显示进行中 / 完成 / 失败 / 等待确认与耗时，点击展开输出或差异；底部实时显示“正在运行命令…”“正在思考…”等当前状态。
- 消息支持 Markdown：标题、粗体 / 斜体 / 删除线、行内代码与带语言标签的代码块、有序 / 无序 / 任务列表、引用、表格、链接、分隔线。
- 对话区背景可在默认原创线稿、自定义图片和无背景之间切换（见下文“更换背景图”）。

### 安装

需要：macOS 13.3+（Apple Silicon）、Node.js 20+（位于 `/opt/homebrew/bin` 或 `/usr/local/bin`）、Xcode 或 Apple 命令行工具（`xcode-select --install`）、官方 Codex CLI（若装有 ChatGPT 桌面版，会优先使用其中自带的 codex）。

```bash
git clone <本仓库地址> eva-codex-workbench
cd eva-codex-workbench
./Install-Native-macOS.command      # 或：npm run install:native
```

安装脚本会：把 `workbench/` 复制到 `~/Library/Application Support/EVA-Workbench/workbench/`（**不触碰其中的 `data/`**）并执行 `npm ci`；用 `native-macos/build-app.py` 编译、自检并 ad-hoc 签名应用；安装到 `~/Applications/EVA Workbench.app`（旧版改名为 `.previous`）。只想编译可运行 `npm run build:native`，产物在 `build-native/`。

首次让 Claude Code 读取“文稿”“桌面”等目录中的项目时，macOS 会询问是否允许访问，点“允许”即可。ad-hoc 签名在每次重新编译后会变化，系统可能会再问一次。

### 连接 Codex

1. 终端运行 `codex login`，用自己的账号登录（也可以在应用左下角点“登录”）。
2. 打开应用，Codex 连接状态显示“已连接”后即可新建对话。
3. 应用按以下顺序查找 codex：ChatGPT 桌面版自带的 CLI → 环境变量 `HACKCLAW_CODEX` → `PATH` 中的 `codex`。`CODEX_HOME` 照常生效。

### 连接 Claude Code

Claude Code 通过随附的官方 CLI **直接连接** Anthropic，不需要额外代理或沙箱：

1. 在应用里切到 “Claude Code”，点左下角“登录”，会打开终端运行官方的 `claude auth login`（即仓库根目录的 `Claude-Login.command`）；按提示在浏览器完成登录后回到应用点“刷新”。
2. 也可以手动登录 / 查看状态（Intel Mac 把 `arm64` 换成 `x64`）：

   ```bash
   CLAUDE="$HOME/Library/Application Support/EVA-Workbench/workbench/node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64/claude"
   "$CLAUDE" auth login
   "$CLAUDE" auth status
   ```

3. 想改用自己安装的 Claude Code，设置 `EVA_CLAUDE=/绝对路径/claude`。
4. 如需代理：服务会原样沿用 `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` 等环境变量，不强制、不改写。注意从 Finder 启动的应用不会继承终端里的变量，可用 `launchctl setenv HTTPS_PROXY http://host:port` 后重开应用，或在终端直接运行 `"$HOME/Applications/EVA Workbench.app/Contents/MacOS/eva-workbench"`。
5. 权限：只读模式只开放 Read / Glob / Grep；写入模式限所选项目，命令与写入逐次确认；完全访问使用官方 `bypassPermissions`，需要在界面中明确确认。

### 本地接口

服务只监听 `http://127.0.0.1:43137`（`Host` 必须是 `127.0.0.1:端口`）。调用方式：

1. `GET /native-session` 取得 `unit02_session` Cookie（网页版打开 `/` 时也会设置）。
2. 之后所有 `/api/*` 请求带上该 Cookie；`POST` 还必须带 `Origin: http://127.0.0.1:43137` 和 `Content-Type: application/json`，请求体是 JSON。
3. 出错时返回 `{"error": "原因"}`。

```python
import json, urllib.request
base = "http://127.0.0.1:43137"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # 本机地址不要走代理
cookie = opener.open(base + "/native-session").headers["Set-Cookie"].split(";")[0]
def api(route, body=None):
    req = urllib.request.Request(base + route, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Cookie": cookie, "Origin": base, "Content-Type": "application/json"})
    return json.load(opener.open(req))
state = api("/api/state")
project = api("/api/project", {"path": "/Users/me/code/demo"})
thread = api("/api/thread", {"provider": "claude", "projectId": project["id"], "mode": "read-only"})
api("/api/send", {"threadId": thread["id"], "text": "总结这个项目的结构"})
```

| 方法与路径 | 参数 | 说明 |
| --- | --- | --- |
| `GET /health` | — | 不需要 Cookie；返回 `{app, version}`，用于检测服务 |
| `GET /native-session` | — | 设置会话 Cookie |
| `GET /api/state` | — | 完整状态：项目、会话、连接、账号、模型、用量、待确认请求 |
| `GET /api/events` | — | Server-Sent Events，每次状态变化推送完整快照 |
| `POST /api/project` | `path`（绝对路径） | 添加项目，返回 `{id, name, path}` |
| `POST /api/pick-folder` | — | 弹出系统文件夹选择框 |
| `POST /api/thread` | `provider`（`codex` / `claude`）、`projectId`、`mode`、`model`、`effort`、`confirmFullAccess` | 新建会话；`mode` 为 `read-only` / `workspace-write`，Claude 另有 `full-access`（需 `confirmFullAccess: true`） |
| `POST /api/send` | `threadId`、`text`、`attachments`（附件 id 数组）、`model`、`effort` | 发送一轮消息；结果通过 `/api/state` 或 `/api/events` 查看 |
| `POST /api/cancel` | `threadId` | 停止当前任务 |
| `POST /api/approval` | `id`、`accept`、`answers` | 回应命令 / 文件写入 / 提问类授权请求 |
| `POST /api/thread/mode` | `threadId`、`mode`、`confirmFullAccess` | 空闲时切换权限，下一次发送生效 |
| `POST /api/thread/rename` | `threadId`、`title` | 重命名（1–100 字） |
| `POST /api/thread/archive` | `threadId`、`archived` | 归档 / 恢复；本机历史只在 EVA 中隐藏 |
| `POST /api/thread/transfer` | `threadId`、`targetProvider`、`inPlace`、`recent` | 换另一助手继续；`inPlace: true` 为就地切换，`recent: true` 只带最近 200 条 |
| `POST /api/thread/transfer/undo` | `threadId` | 撤销尚未发送过消息的就地切换 |
| `POST /api/thread/merge` | `threadId`、`intoThreadId`（`null` 为取消合并） | 把重复会话收起到保留的会话下 |
| `POST /api/history/sync` | — | 重新扫描本机 Codex / Claude 历史 |
| `POST /api/history/read` | `threadId`、`older` | 读取历史正文，`older: true` 向前翻页 |
| `POST /api/history/continue` | `threadId`、`mode`、`model`、`effort` | 从历史创建可续聊的 EVA 分支 |
| `POST /api/attachment` | `name` + `dataBase64`（任意文件）或 `dataUrl`（PNG / JPEG）；可选 `textPreview`、`previewTruncated`、`frames` | 上传附件，返回 `{id, kind, readability, …}`；单个文件 ≤ 32 MB |
| `GET /api/attachment-info?id=` | `id` | 附件信息与提取出的文字预览 |
| `GET /api/attachment/<id>` | — | 下载附件原文件 |
| `GET /api/files?projectId=&path=` | — | 列出项目目录（不显示 `.env`、`node_modules` 等） |
| `GET /api/file?projectId=&path=` | — | 读取 ≤ 512 KB 的文本文件 |
| `POST /api/usage/refresh` | `provider`、`threadId` | 刷新用量信息 |
| `POST /api/login` / `POST /api/refresh-account` / `POST /api/reconnect` | `provider` | 登录、刷新账号、重新连接 |
| `POST /api/dev/<操作>` | `projectId` 等 | 终端：`terminal-list` / `terminal-create` / `terminal-input` / `terminal-resize` / `terminal-close`（输出用 `GET /api/dev/terminal-events?id=`）；Git：`git-status` / `git-diff` / `git-action`；插件：`plugins-list` / `plugins-change` |
| `POST /api/shutdown` | — | 保存状态并结束服务 |

### 更换背景图

对话区右侧的背景默认是一张程序生成的原创抽象线稿。换成自己的图片：

1. 菜单栏 **显示 → 背景图 → 自定义图片…**，选择本机任意图片（PNG / JPG / HEIC / WebP 等）。立即生效。
2. 程序会自动处理：去色；按当前主题判断明暗，暗色主题下把浅底图片反相成暗底亮线、亮色主题下反之；按高度铺满、靠右对齐，并向对话区左侧渐隐，不影响阅读。
3. 想恢复：**显示 → 背景图 → 默认线稿**；不要背景：**无背景**。

也可以用命令行设置（重启应用后生效）：

```bash
defaults write local.eva.dual-workbench native.backdrop custom
defaults write local.eva.dual-workbench native.backdropImage "/绝对路径/my-art.png"
# 恢复默认线稿或关闭背景
defaults write local.eva.dual-workbench native.backdrop linework   # 或 none
defaults delete local.eva.dual-workbench native.backdropImage
```

说明：

- 应用只在本机偏好里记下图片路径，不复制、不打包、不上传；移动或删除原图后会自动退回默认线稿。
- 建议使用纯色背景上的线稿或插画，竖幅、高度 1500 像素以上效果最好；照片也可以，但会显得更“灰”。
- 请只使用你有权使用的图片；本仓库不附带任何角色图像。
- 开发者想改默认线稿，可修改 `native-macos/NativeStyle.swift` 中 `Backdrop.linework(size:)`。

### 环境变量与参数

| 名称 | 作用 |
| --- | --- |
| `EVA_DESKTOP_PORT` | 原生应用使用的端口（默认 43137） |
| `EVA_DESKTOP_DATA_DIR` | 原生应用使用的数据目录（默认支持目录下的 `workbench/data`） |
| `HACKCLAW_PORT` / `HACKCLAW_DATA_DIR` | 直接运行 `node workbench/server.cjs` 时的端口和数据目录 |
| `HACKCLAW_CODEX` | 指定 codex 可执行文件 |
| `EVA_CLAUDE` | 指定 Claude Code 可执行文件 |
| `CODEX_HOME` | 官方 Codex 配置目录 |
| `eva-workbench --self-test` | 原生端自检（构建时自动运行） |
| `eva-workbench --render-intro <目录>` | 不开窗口，把开场的关键帧（亮色 / 暗色）导出为 PNG |
| `eva-workbench --render-markdown <输入.md> <输出前缀>` | 不开窗口，按亮色 / 暗色渲染一段 Markdown 消息，用于检查排版 |
| `eva-workbench --render-activity <输出前缀>` | 不开窗口，用示例数据渲染执行步骤（进行中 / 完成 / 失败 / 等待确认），用于检查样式 |

应用偏好保存在 `defaults read local.eva.dual-workbench`：`native.theme`（`system` / `dark` / `light`）、`native.introEnabled`、`native.introSound`、`native.backdrop`（`linework` / `custom` / `none`）、`native.backdropImage`。日志在 `~/Library/Logs/EVA-Workbench.log`，会话数据在 `~/Library/Application Support/EVA-Workbench/workbench/data`，不要上传或提交。

### 测试

```bash
npm run setup
npm test     # 后端与原生启动器测试
npm run build:native   # 编译原生应用并运行自检
```

## 网页版安装与启动

### Windows

1. 使用 Windows 10/11，安装 Microsoft Edge、Node.js 20+（含 npm）、官方 Codex CLI。Git 面板还需安装较新的 Git for Windows。
2. 确认 node --version、npm --version、codex --version 可用。先用自己的账号完成官方 Codex 登录；首次运行工作台未登录时也可点击左下角登录。
3. 从 GitHub 的 Code → Download ZIP 下载并完整解压；或 git clone。不要直接双击压缩包内的文件。
4. 双击 Install-Dependencies.cmd，安装此项目的终端依赖。也可在项目根目录执行 npm run setup。
5. 双击 Start-EVA.cmd。同步率到 99.2% 后点击驾驶员确认，补完到 100% 并进入工作台。
6. 添加本地项目；默认只读，需要编辑时在新对话中选择允许项目写入。额外权限由用户确认。

### macOS

1. 安装 Node.js 20+（含 npm）、官方 Codex CLI，以及 Microsoft Edge 或 Google Chrome（放在 `/Applications` 或 `~/Applications`）。Git 面板还需本机 Git；可通过 `xcode-select --install` 安装 Apple 命令行工具。
2. 在终端确认 `node --version`、`npm --version`、`codex --version` 可用，使用 `codex login` 完成自己的官方账号登录。
3. 克隆或完整解压项目，在项目根目录运行 `npm run setup`，或双击 `Install-Dependencies.command`。安装会修正 node-pty 1.1.0 的 macOS `spawn-helper` 执行权限；若原生依赖需要本机编译，先安装 Apple 命令行工具。
4. 双击 `Start-EVA.command`，或在项目根目录运行 `npm run start:mac`。Finder 启动时会额外查找 Apple Silicon 与 Intel Homebrew 的默认工具目录；自定义安装的 Codex 可用 `HACKCLAW_CODEX=/绝对路径/codex npm run start:mac` 指定。
5. 启动器会使用独立的 Edge / Chrome 应用窗口和浏览器配置，不改动已有浏览器个人配置。同步率到 99.2% 后点击驾驶员确认进入工作台。项目选择使用 macOS 原生文件夹对话框，终端使用 `$SHELL`（未设置时为 `/bin/zsh`）；发送消息支持 **⌘+Enter** 和 Ctrl+Enter。
6. **保持启动器的 Terminal 窗口打开**。使用工作台退出按钮或在此窗口按 Control+C 结束服务；关掉浏览器窗口不等于退出服务。重复启动只复用同端口的 EVA 服务，不会停止其他启动器创建的服务。

默认地址是 `http://127.0.0.1:43137`。可通过 `npm run start:mac -- --port 43200` 换端口，或加 `--no-browser` 仅启动服务。若 `.command` 在 ZIP 解压后丢失执行权限，在项目目录运行 `chmod +x Start-EVA.command Install-Dependencies.command`；也可直接使用上述 npm 命令。若 macOS 拦截下载的脚本，先检查来源及内容，再在 Finder 中右键 → 打开；无需关闭系统安全保护。

重播使用顶部按钮，退出使用工作台退出按钮。更新时先退出服务，保留自己的 workbench/data，再替换运行文件并重新安装依赖。不要把 data 上传给维护者。

## 功能和边界

- 真实 Codex：流式聊天、图片输入、模型与思考强度选择、项目任务、命令结果、文件变更、Diff、停止和权限确认。
- 本工作台会话：保存、重启接续、重命名和归档。**尚未提供官方全部历史会话的浏览／导入，不保证同账号跨设备历史同步。**
- 本机终端：Windows 使用 PowerShell，macOS 使用 `$SHELL` / zsh；支持多会话、输入输出、Ctrl+C、尺寸适配。关闭工具面板后继续运行，退出服务时结束。手动终端不受聊天只读设置限制。
- Git：仓库根目录的状态和差异、暂存／取消暂存、提交、创建／切换本地分支、获取、快进拉取和推送。不提供强推、自动合并、回滚或丢弃；认证由本机 Git 负责。
- 插件：使用官方 codex plugin 命令搜索已配置市场，查看安装／启用状态、安装与卸载。新对话使用更新后的插件；账号连接在官方客户端完成。没有独立启停、市场配置编辑或自动授权，也不保证与 ChatGPT 桌面插件同步。旧 CLI 不支持 plugin 时需更新 CLI。

不是官方 Codex 全功能替代品。没有自动更新或安装器。GitHub Pages 不能运行它，必须在自己的电脑启动 Node 服务和 Codex。仅监听 127.0.0.1，不提供公网托管功能。

## 数据与验证

本地状态、图片附件及独立 Edge / Chrome 配置位于 workbench/data。不复制官方账号文件，不打包凭据，不发送诊断日志。终端输出仅在内存保存最近约 512 KB。

运行 npm test 做代码检查。新终端、Git 操作及插件管理已在维护者电脑验证；全新设备、不同 CLI 分发方式及首次登录仍需要反馈。提交问题时只提供报错截图、系统／Node／Codex 版本和复现步骤，不上传登录文件、完整认证链接、项目秘密或聊天数据。

## 许可与素材

自有代码采用 MIT，Copyright (c) 2026 Iris-change，见 LICENSE。第三方原有许可证分别保留，见 THIRD_PARTY_NOTICES.md、CODE-ORIGINS.md 和 ASSETS.md；字体适用 SIL OFL。MIT 不授予 EVA 图片、商标、角色或语音模型的权利，也不表示官方授权。系统播报按所有者已取得的分发授权提供，不自动纳入代码 MIT；见 workbench/public/media/audio-unit02-fluid/README.md。
