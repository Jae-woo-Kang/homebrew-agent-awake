# Security and power-management notes

AgentAwake combines a user-level macOS IOKit power assertion with a temporary
system-wide `SleepDisabled` setting so one toggle can prevent both idle sleep
and closed-lid sleep.

The first activation asks for administrator approval to install a small power
helper under `/Library/PrivilegedHelperTools` and a matching LaunchDaemon.
Later toggles use that already-approved helper and require no password. A
helper-version change can require approval again.

The helper does not accept shell commands or executable paths. It only scans
strictly named, per-session request directories, verifies file ownership and
the owner process UID against the user approved during installation, and
supports the fixed keep-awake on/off operation.

The helper restores the previous `SleepDisabled` value when the toggle is
turned off, AgentAwake exits or stops responding, battery charge reaches 20%
while discharging, the 12-hour limit expires, macOS reports severe CPU thermal
throttling, or the helper itself restarts. Homebrew uninstallation also removes
the helper and restores the previous setting when recovery state is present.

If an operating-system failure prevents cleanup, restore normal sleep with:

```bash
sudo pmset -a disablesleep 0
```

Do not leave a running MacBook in a bag or another unventilated enclosure.

Please report security problems privately through GitHub's security advisory
feature instead of opening a public issue.
