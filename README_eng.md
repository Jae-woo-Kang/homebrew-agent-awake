# AgentAwake

[한국어](README_kor.md) | [English](README_eng.md)

AgentAwake is a macOS menu bar app that shows where Codex and Claude Code are
running and can keep your Mac awake when needed.

Click the menu bar icon to see these statuses at a glance:

- Codex: CLI / VS Code Extension / macOS App
- Claude Code: CLI / VS Code Extension / macOS App
- A `Keep Mac Awake` toggle that works independently of the agent status

> “Running” means that the corresponding process or app is open. AgentAwake
> does not distinguish between an agent generating a response and waiting for input.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- One administrator approval when the power helper is installed for the first time

## Install with Homebrew

```bash
brew tap Jae-woo-Kang/agent-awake
brew trust Jae-woo-Kang/agent-awake
brew install --cask agent-awake
open -a AgentAwake
```

The Homebrew `trust` step explicitly confirms that you intend to install a
macOS app from a third-party tap. Before running it, verify that the repository
and owner are `Jae-woo-Kang/homebrew-agent-awake`.

Update:

```bash
brew update
brew upgrade --cask agent-awake
```

Uninstall:

```bash
brew uninstall --cask agent-awake
```

AgentAwake is a menu-bar-only app, so it does not appear in the Dock. Look for
the eye icon in the menu bar. An outlined eye means keep-awake is off, a filled
eye means it is on, and an ellipsis icon means the state is changing. Clicking
outside the menu closes only the panel; the app and its keep-awake state remain
active. Opening the app does not create a separate app window or an empty
settings window.

macOS may block the first launch because the current public beta may not be
notarized with a Developer ID. Use the following steps only for AgentAwake
installed directly from this repository's Homebrew tap or GitHub Release. Do
not add a security exception for an app obtained from an unverified source.

### Allow the app through macOS security

1. Click **Done** in the security warning currently displayed.
2. Open **System Settings** on your Mac.
3. Select **Privacy & Security**.
4. Scroll down to the **Security** section.
5. Next to the message saying AgentAwake was blocked, click **Open Anyway**.
6. Authenticate with Touch ID or your Mac login password.
7. Click **Open** in the confirmation dialog that appears.

## Usage

1. Click the AgentAwake icon in the menu bar.
2. Check the CLI, VS Code, and App status for Codex and Claude Code.
3. Turn on `Keep Mac Awake` when the Mac needs to continue running.
4. Turn off `Keep Mac Awake` when the work is finished.

The toggle works independently of whether Codex or Claude is running. Even if
both are closed, the system and network continue working while keep-awake is
enabled. The display can still turn off separately. The single `Keep Mac Awake`
toggle prevents both automatic idle sleep and sleep caused by closing the lid.
The first activation displays a macOS administrator prompt to install the
restricted power helper. After installation, later toggles and app launches
apply the setting immediately without another password prompt.

## How keep-awake works

AgentAwake prevents idle sleep with a macOS IOKit power assertion. To prevent
closed-lid sleep, the power helper installed during the first approval
temporarily applies the `SleepDisabled` setting. The helper does not accept
arbitrary commands. It validates request files owned by the user who approved
the installation and supports only the fixed keep-awake operation. There is no
separate lid toggle; both behaviors are controlled by the single toggle.

The power helper restores the previous power setting when:

- The user turns off the toggle
- AgentAwake exits or stops responding
- Battery charge reaches 20% while running on battery
- The 12-hour limit is reached
- macOS reports severe CPU thermal throttling

Do not run a MacBook inside a bag or another area without adequate ventilation.
It can generate heat with the lid closed, and software safety limits cannot
replace sufficient airflow.

If normal sleep behavior is not restored, run:

```bash
sudo pmset -a disablesleep 0
```

Uninstalling AgentAwake through Homebrew also removes the installed power helper
with administrator privileges.

## Detection methods and limitations

| Target | Detection method | Notes |
|---|---|---|
| Codex CLI | Requires the executable name to be exactly `codex` | Only standalone execution is shown as CLI |
| Claude Code CLI | Requires the executable name to be exactly `claude` | Only standalone execution is shown as CLI |
| Codex VS Code | Combines extension path, App Server, and VS Code parent-process checks | May need updates when the extension implementation changes |
| Claude Code VS Code | Combines extension path, IDE mode, and VS Code parent-process checks | May need updates when the extension implementation changes |
| macOS App | Checks the running app name, bundle ID, and bundle path | Shown as running whenever the app is open |

VS Code extensions run inside the Extension Host rather than as independent
apps, so detection rules may need updates when their process structure changes.
If a status is detected incorrectly, open an issue with the app version and a
description of the environment where it occurred.

## Build from source

On a Mac with Xcode Command Line Tools and Swift 5.9 or later:

```bash
git clone https://github.com/Jae-woo-Kang/homebrew-agent-awake.git
cd homebrew-agent-awake
swift test
scripts/build-app.sh
scripts/install-local.sh
```

`scripts/build-app.sh` creates a universal app containing arm64 and x86_64
binaries at `dist/AgentAwake.app`.

## Release notes

GitHub Actions runs the macOS tests and universal build on every push. Pushing
a `v*` tag publishes the ZIP for that version to GitHub Releases.

Public beta releases may be ad-hoc signed. For a Developer ID release, provide
`AGENTAWAKE_CODESIGN_IDENTITY` in the build environment and add Apple
notarization to distribute the app without the Gatekeeper warning.

## License

[MIT](LICENSE)
