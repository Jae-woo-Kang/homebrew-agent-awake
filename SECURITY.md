# Security and power-management notes

The primary AgentAwake toggle only creates a user-level IOKit power assertion;
it does not request administrator access or change a system-wide setting.

AgentAwake changes a system-wide macOS power setting only when the user
separately enables closed-lid mode and accepts the standard administrator
prompt. The bundled guardian accepts a fixed set of validated arguments and
does not execute user-provided commands.

The guardian restores the `SleepDisabled` value that existed before AgentAwake
was enabled when any of the following happens:

- the user turns the toggle off;
- AgentAwake exits or its heartbeat disappears;
- battery charge reaches 20% while discharging;
- the 12-hour maximum duration expires; or
- macOS reports severe CPU thermal throttling.

`pmset disablesleep` is a system-wide setting. A power loss, force kill of the
privileged guardian, or an operating-system failure can prevent normal cleanup.
To restore the default manually, run:

```bash
sudo pmset -a disablesleep 0
```

Do not leave a working MacBook in a bag or other unventilated enclosure. A
software thermal guard is a last line of defense, not a substitute for airflow.

Please report security problems privately through GitHub's security advisory
feature instead of opening a public issue.
