# Security and power-management notes

AgentAwake combines a user-level macOS IOKit power assertion with a temporary
system-wide `SleepDisabled` setting so one toggle can prevent both idle sleep
and closed-lid sleep. macOS requests administrator approval when the toggle is
enabled.

The bundled guardian accepts only fixed, validated arguments. It restores the
previous `SleepDisabled` value when the toggle is turned off, AgentAwake exits
or stops responding, battery charge reaches 20% while discharging, the 12-hour
limit expires, or macOS reports severe CPU thermal throttling.

If an operating-system failure prevents cleanup, restore normal sleep with:

```bash
sudo pmset -a disablesleep 0
```

Do not leave a running MacBook in a bag or another unventilated enclosure.

Please report security problems privately through GitHub's security advisory
feature instead of opening a public issue.
