# Security and power-management notes

AgentAwake uses a user-level macOS IOKit power assertion to prevent automatic
idle system sleep while its toggle is enabled. It does not request
administrator access, run a privileged helper, or change a system-wide power
setting.

The assertion is released when the user turns the toggle off or AgentAwake
exits. Closing the MacBook lid or explicitly selecting Sleep is left to the
normal macOS behavior.

Please report security problems privately through GitHub's security advisory
feature instead of opening a public issue.
