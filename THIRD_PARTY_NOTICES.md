# Third-party notices / 第三方声明

The app uses Swift, SwiftUI, AppKit, Foundation, Security, and ServiceManagement.
Sign-in and quota queries use the app-server interface of the user's installed Codex CLI.
Codex CLI is governed by its own license and is not included in this app bundle.

Feature research referenced the public documentation and source of
4LAU/codex-profile-switcher at commit `4f2f313b5156be84341f21ce43a73b501ff5dc3a`.

应用使用 Swift、SwiftUI、AppKit、Foundation、Security 和 ServiceManagement。
账号登录与额度查询通过用户本机安装的 Codex CLI 提供的 app-server 接口完成。
Codex CLI 由其各自的许可协议约束，本应用安装包不包含 Codex CLI。

功能研究参考了 4LAU/codex-profile-switcher 的公开说明与源码，参考提交为
`4f2f313b5156be84341f21ce43a73b501ff5dc3a`。

Reference / 参考项目：[4LAU/codex-profile-switcher](https://github.com/4LAU/codex-profile-switcher)

The reference project uses the MIT License, reproduced below.
参考项目采用 MIT License，许可内容如下：

MIT License

Copyright (c) 2026 Aaron Lau

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## JWTDecode.swift

JWTDecode.swift 4.0.0 by Auth0 is included through Swift Package Manager and used
to decode account identity claims from local sign-in tokens. Account quota
requests are authenticated by the installed Codex app-server.

应用通过 Swift Package Manager 使用 Auth0 的 JWTDecode.swift 4.0.0，读取本地
登录令牌中的账号身份信息。额度请求由已安装的 Codex app-server 完成身份验证。

Source / 源码：https://github.com/auth0/JWTDecode.swift

The MIT License (MIT)

Copyright (c) 2022 Auth0, Inc. <support@auth0.com> (http://auth0.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
