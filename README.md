# Codex Quota Dock

English · [简体中文](README.zh-CN.md)

A native macOS app for viewing the remaining Codex quota and reset times of multiple ChatGPT accounts, with account switching from the main window and menu bar.

This is an independent third-party project. It is not affiliated with or endorsed by OpenAI. OpenAI, ChatGPT, and Codex names and trademarks belong to their respective owners.

## Run

Open `Codex Quota Dock.app`. You can copy it to your Applications folder.

Requires macOS 14 or later and an installed ChatGPT desktop app that includes Codex. The downloadable build supports Apple Silicon, uses an ad-hoc signature, and is not notarized by Apple. On another Mac, you may need to allow the app in **System Settings → Privacy & Security**, or build it from source on your own Mac.

On launch, the app saves the ChatGPT account currently signed in to your local Codex installation and reads its quota. The menu bar shows `Codex Quota Dock` and the current account's remaining quota. Click it to view saved accounts.

If you use iBar or another menu bar manager, expand or show this app's menu bar item in that tool.

## Language

One app includes both English and Simplified Chinese. Select **Settings → Language → App language → Follow system / 简体中文 / English**. In Chinese, use **应用设置 → 语言 → 应用语言**.

The first launch follows the system language, with English used for unsupported languages. Changing the language immediately updates the main window, add-account sheet, menu bar, quota windows, countdowns, and app messages. Your choice is saved and persists across launches. Account names and email addresses retain their original contents.

## Intended use

Use accounts you are authorized to access and comply with the applicable [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/), including credential confidentiality and service limits. Do not share account credentials, sell account access, or use multiple accounts to evade usage limits. The open-source license covers this project's code; service usage remains subject to the applicable terms.

## Add accounts

Click **Add account** at the top right of the main window and choose a method:

1. **Sign in to a new ChatGPT account**: sign in through the browser. The app saves the account when sign-in completes. Select the intended account on the sign-in page when adding another account.
2. **Import current Codex account**: save the account already signed in on this Mac.
3. **Import from auth.json**: select one or more existing Codex account files.

Importing the same ChatGPT user and workspace again updates the existing record. Each account card's menu lets you rename the account, refresh its quota, renew its credentials, sign in again, or remove it.

## Quotas and resets

- Percentages show the remaining quota, calculated from the used percentage returned by the account API.
- Window lengths come from the API and can include hourly, weekly, or other durations.
- Each window shows a countdown and its exact reset time in your Mac's time zone.
- Multiple limit categories appear separately when returned by the API.
- Credit balances and available reset credits appear when provided.
- Missing values display as unknown. After a reset time passes, the app waits for a fresh query to confirm the quota.
- Query failures show an error. Previous results retain their timestamps. Expired or failed results are excluded from quota-based ranking and account suggestions.

Automatic refresh defaults to every five minutes. Settings supports manual refresh or intervals of one, two, five, or fifteen minutes.

## Switch accounts

Click **Switch & restart** in the main window or **Switch** beside an account in the menu bar.

The app checks the target account's quota, saves the current account's latest credentials, quits Codex normally, writes the target credentials, reopens Codex, and verifies the identity in the account file. Switching restarts Codex, so wait for running tasks to finish. You can disable the confirmation prompt in Settings.

The app is designed for Codex configurations that store authentication in `auth.json`. Separately running Codex CLI sessions may keep the credentials they already loaded; restart those sessions as needed.

## Sign-in and storage

Codex manages sign-in renewal for the current account. If another account cannot retrieve its quota, use **Renew credentials** in its menu. When a new sign-in is required, choose **Sign in again** and complete browser authentication.

Credentials are stored in macOS Keychain. Account names, preferences, and recent quota results are stored at:

`~/Library/Application Support/CodexAccounts/accounts.json`

The account API runs in separate sessions inside that directory's `runtime` folder. Operations that need file-based credentials use directories with `0700` permissions and files with `0600` permissions, then clean up after completion. Quota queries use separate external-token sessions.

## Build from source

Install Xcode Command Line Tools, then run from the project directory:

```bash
bash Scripts/package.sh
```

The result is `dist/Codex Quota Dock.app`, including both language resources. Build and icon intermediates are stored in the Git-ignored `work` directory.

The Swift package has three targets:

- `AccountCore`: accounts, quotas, Keychain, storage, localization, and Codex communication.
- `CodexAccounts`: the main window, add-account sheet, menu bar, and settings.
- `AccountCheck`: integration checks using the installed Codex executable and an existing account.

## Integration checks

```bash
swift build --scratch-path work/build
work/build/debug/account-check "$PWD/work/validation" "$HOME/.codex/auth.json"
python3 Scripts/check-localization.py "$PWD"
```

The checker queries real quotas, starts and cancels a separate sign-in flow, and verifies storage, deduplication, replacement, and cleanup with dedicated Keychain items and isolated directories. It confirms that the original Codex credentials remain byte-for-byte unchanged.

Checks also cover both language resources, translated quota windows and real sign-in errors, and persisted language preferences.

Version 1.1.0 was built and launched on macOS 26.6.2 with Apple Silicon and Codex CLI `0.155.0-alpha.2.6`, passing 34 integration checks. Three real accounts refreshed successfully. The English account page, add-account options, switching confirmation, and both language settings were checked through macOS accessibility. Restarting the app retained the selected English interface. All 160 translation entries passed resource and format-argument checks. A full desktop switch between two different real accounts has not yet been validated, so builds are provided as prereleases.

For development, `CODEX_ACCOUNTS_DATA_DIR` selects a separate app data directory, and `CODEX_ACCOUNTS_TARGET_DIR` selects the target Codex directory for account switching. Keep the defaults for normal use.

## License

[MIT License](LICENSE). Attribution and license details for the reference project are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## References

- [4LAU/codex-profile-switcher](https://github.com/4LAU/codex-profile-switcher)
- [Official Codex app-server documentation](https://developers.openai.com/codex/app-server)
- [Codex authentication and credential storage](https://developers.openai.com/codex/auth)
