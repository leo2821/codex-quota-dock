# Codex Quota Dock

[English](README.md) · 简体中文

macOS 原生账号管理应用，用于查看多个 ChatGPT 账号的 Codex 剩余额度、重置时间，并切换 Codex 当前使用的账号。

本项目为独立第三方工具，与 OpenAI 无隶属关系，也未经 OpenAI 官方认可。OpenAI、ChatGPT 和 Codex 的名称及商标归各自权利人所有。

## 运行

双击 `Codex Quota Dock.app`。可以将应用复制到 Applications 目录。

环境要求：macOS 14 或更新版本，已经安装包含 Codex 的 ChatGPT 桌面应用。当前提供的应用包支持 Apple Silicon，使用 ad-hoc 签名，尚未经过 Apple 公证。其他 Mac 可能需要在系统设置的“隐私与安全性”中允许打开；也可以在自己的 Mac 上从源码构建。

应用启动后会保存本机 Codex 已登录的 ChatGPT 账号，并查询该账号的额度。顶部菜单栏显示账号图标和当前账号的剩余额度，点击后可查看所有已保存账号。

使用 iBar 等菜单栏管理工具时，请在该工具中展开或显示本应用的菜单栏项目。

## 界面语言

一个安装包包含简体中文和英文。在 **应用设置 → 语言 → 应用语言** 中选择 **跟随系统**、**简体中文** 或 **English**。英文界面的入口为 **Settings → Language → App language**。

首次启动默认跟随系统，支持中文和英文；其他系统语言使用英文。切换语言后，主窗口、添加账号界面、菜单栏、额度周期、倒计时和应用提示立即更新。语言选择保存在本机，重新启动后继续使用。账号名称和邮箱保持原有内容。

## 使用范围

用于管理本人有权使用的账号。使用者需要遵守适用的 [OpenAI 使用条款](https://openai.com/policies/terms-of-use/)，包括账号凭据保密和服务额度限制。请勿共享账号凭据、出售账号访问权，或通过多账号规避额度限制。开源许可仅适用于本项目代码，服务使用仍受相应条款约束。

## 添加账号

点击主窗口右上角的 **添加账号**，选择一种方式：

1. **登录新的 ChatGPT 账号**：在 Chrome 等默认浏览器中完成登录，应用自动为该账号保存独立的本地 `auth.json`。添加其他账号时，请在登录页面选择对应账号。
2. **导入当前 Codex 账号**：保存本机 Codex 当前已经登录的账号。
3. **从 auth.json 文件导入**：选择一个或多个已有的 Codex 账号文件。

同一个 ChatGPT 用户和工作区重复导入时，会更新已有记录。可以通过账号卡片右上角菜单修改名称、刷新额度、更新登录凭据或移除账号。

## 额度与重置

- 百分比表示剩余额度，由接口返回的已用百分比计算。
- 周期长度使用接口实际返回值，支持小时周期、每周周期及其他周期长度。
- 同时显示倒计时和本机时区下的准确重置时间。
- 接口返回多个额度类别时，分别显示各类别。
- 接口提供额度余额或可用重置次数时，一并显示。
- 缺少的额度显示为未知；到达重置时间后显示等待刷新确认。
- 查询失败时显示错误。此前查询结果带有时间标记，排序和账号建议会排除过期或查询失败的记录。

默认每 5 分钟刷新，可以在应用设置中选择手动、每分钟、每 2 分钟、每 5 分钟或每 15 分钟。

## 切换账号

在主窗口点击 **切换并重启**，或者点击菜单栏账号旁的 **切换**。

应用会查询目标账号额度，保存当前账号的最新凭据，正常退出 Codex，写入目标账号凭据，重新打开 Codex，并核验账号文件中的身份。切换会重新启动 Codex，请在正在执行的任务完成后操作。应用设置中可以关闭切换确认提示。

应用针对使用 `auth.json` 保存登录状态的 Codex 配置。独立运行的 Codex CLI 会话可能继续使用其已经读取的登录信息，需要重新启动相关 CLI 会话。

## 登录状态

当前账号的登录更新由 Codex 管理。其他账号无法查询额度时，可以使用账号菜单中的 **更新登录凭据**。服务要求重新登录时，通过 **重新登录账号** 完成浏览器登录。

每个账号的凭据分别保存在：

`~/Library/Application Support/CodexAccounts/credentials/<profileID>/auth.json`

查询额度、更新登录和切换账号都读取这些本地文件。通过 **应用设置 → 账号数据 → 查看账号文件** 可以打开保存位置。目录权限为 `0700`，凭据文件权限为 `0600`；登录令牌未经加密，当前 macOS 用户运行的程序可以读取。请保管好这些文件，并将其排除在源码仓库和发布包之外。

账号名称、设置和最近查询结果保存在：

`~/Library/Application Support/CodexAccounts/accounts.json`

账号接口在该目录下独立的 `runtime` 目录中运行。浏览器登录完成后，应用先保存并核验对应账号的凭据文件，然后清理登录期间的临时目录。额度查询采用独立的外部令牌会话。

已有钥匙串账号会显示 **迁移已保存的账号** 按钮。迁移会逐个读取账号、核验身份、写入并核验本地文件，然后记录完成状态。macOS 可能在此期间请求钥匙串访问授权。已经完成的账号在重新启动和刷新额度时均使用本地文件，原有钥匙串副本保留。重新登录已有账号也会生成对应的本地文件。当前 Codex 账号会从现有 `auth.json` 自动保存。

桌面应用继续使用现有 Codex 数据目录。切换时更新其中的 `auth.json`，本应用的文件操作保留本地对话文件、任务数据库、项目设置和项目目录。重新启动 Codex 可能中断正在执行的任务。

## 源码构建

安装 Xcode Command Line Tools 后，在本项目目录运行：

```bash
bash Scripts/package.sh
```

构建结果为 `dist/Codex Quota Dock.app`，包含完整的中英文语言资源。编译文件和图标中间文件保存在已经被 Git 忽略的 `work` 目录。

代码分为三个 Swift Package target：

- `AccountCore`：账号、额度、本地凭据文件、账号迁移、界面语言与 Codex 通信。
- `CodexAccounts`：主窗口、添加账号界面、菜单栏与设置。
- `AccountCheck`：使用真实 Codex 程序和现有账号的集成验证。

## 集成验证

```bash
swift build --scratch-path work/build
work/build/debug/account-check "$PWD/work/validation" "$HOME/.codex/auth.json"
python3 Scripts/check-localization.py "$PWD"
```

验证程序查询真实额度，启动并取消独立的登录流程，在独立目录中检查本地凭据保存、权限、重新读取、去重、替换及清理。如果本机存在对话与项目设置文件，还会检查这些文件的副本在替换凭据后是否保持一致。原有 Codex 凭据在结束时逐字节核验。

验证同时检查中英文资源、真实额度周期与登录错误的翻译，以及语言设置的持续保存。

1.2.0 使用真实账号和本机 Codex app-server 通过 43 项集成检查。176 条中英文资源通过条目完整性和格式参数检查，Release 编译、应用签名及 `Info.plist` 在 Apple Silicon、macOS 26.6.2 上验证通过。

两个不同真实账号之间的完整桌面切换，以及切换后全部已有对话的保留情况，尚未完成验证，当前版本以预发布形式提供。

开发时可设置 `CODEX_ACCOUNTS_DATA_DIR` 指定应用数据目录，设置 `CODEX_ACCOUNTS_TARGET_DIR` 指定账号切换的目标 Codex 目录。正式使用时保持默认即可。

## 许可

本项目采用 [MIT License](LICENSE)。参考项目的版权与许可声明保存在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 参考

- [4LAU/codex-profile-switcher](https://github.com/4LAU/codex-profile-switcher)
- [Codex app-server 官方说明](https://developers.openai.com/codex/app-server)
- [Codex 登录与凭据保存说明](https://developers.openai.com/codex/auth)
