# QuotaDock

macOS 原生账号管理应用，用于查看多个 ChatGPT 账号的 Codex 剩余额度、重置时间，并切换 Codex 当前使用的账号。

本项目为独立第三方工具，与 OpenAI 无隶属关系，也未经 OpenAI 官方认可。OpenAI、ChatGPT 和 Codex 的名称及商标归各自权利人所有。

## 运行

双击 `QuotaDock.app`。可以将应用复制到 Applications 目录。

环境要求：macOS 14 或更新版本，已经安装包含 Codex 的 ChatGPT 桌面应用。当前提供的应用包支持 Apple Silicon，使用 ad-hoc 签名，尚未经过 Apple 公证。其他 Mac 可能需要在系统设置的“隐私与安全性”中允许打开；也可以在自己的 Mac 上从源码构建。

应用启动后会保存本机 Codex 已登录的 ChatGPT 账号，并查询该账号的额度。顶部菜单栏显示 `QuotaDock` 和当前账号的剩余额度，点击后可查看所有已保存账号。

使用 iBar 等菜单栏管理工具时，请在该工具中展开或显示本应用的菜单栏项目。

## 使用范围

用于管理本人有权使用的账号。使用者需要遵守适用的 [OpenAI 使用条款](https://openai.com/policies/terms-of-use/)，包括账号凭据保密和服务额度限制。请勿共享账号凭据、出售账号访问权，或通过多账号规避额度限制。开源许可仅适用于本项目代码，服务使用仍受相应条款约束。

## 添加账号

点击主窗口右上角的 **添加账号**，选择一种方式：

1. **登录新的 ChatGPT 账号**：在打开的浏览器页面中登录所需账号，成功后自动保存。添加其他账号时，请在登录页面选择对应账号。
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

每个账号的凭据保存在 macOS 钥匙串，账号名称、设置和最近查询结果保存在：

`~/Library/Application Support/CodexAccounts/accounts.json`

账号接口在该目录下独立的 `runtime` 目录中运行。需要文件形式凭据的登录和账号识别操作使用权限为 `0700` 的目录与 `0600` 的文件，操作结束后清理。额度查询采用独立的外部令牌会话。

## 源码构建

安装 Xcode Command Line Tools 后，在本项目目录运行：

```bash
bash Scripts/package.sh
```

构建结果为 `dist/QuotaDock.app`。编译文件和图标中间文件保存在已经被 Git 忽略的 `work` 目录。

代码分为三个 Swift Package target：

- `AccountCore`：账号、额度、钥匙串、文件保存与 Codex 通信。
- `CodexAccounts`：主窗口、添加账号界面、菜单栏与设置。
- `AccountCheck`：使用真实 Codex 程序和现有账号的集成验证。

## 集成验证

```bash
swift build --scratch-path work/build
work/build/debug/account-check "$PWD/work/validation" "$HOME/.codex/auth.json"
```

验证程序查询真实额度，启动并取消独立的登录流程，在专属钥匙串项目和独立目录中检查保存、去重、替换及清理。原有 Codex 凭据在结束时逐字节核验。

当前发布包已经在 macOS 26.6.2、Apple Silicon、Codex CLI `0.155.0-alpha.2.6` 上完成编译、启动和 27 项单账号集成检查。两个不同真实账号之间的完整桌面切换尚未完成验证，当前版本以预发布形式提供。

开发时可设置 `CODEX_ACCOUNTS_DATA_DIR` 指定应用数据目录，设置 `CODEX_ACCOUNTS_TARGET_DIR` 指定账号切换的目标 Codex 目录。正式使用时保持默认即可。

## 许可

本项目采用 [MIT License](LICENSE)。参考项目的版权与许可声明保存在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 参考

- [4LAU/codex-profile-switcher](https://github.com/4LAU/codex-profile-switcher)
- [Codex app-server 官方说明](https://developers.openai.com/codex/app-server)
- [Codex 登录与凭据保存说明](https://developers.openai.com/codex/auth)
