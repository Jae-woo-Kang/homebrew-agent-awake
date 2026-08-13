cask "agent-awake" do
  version "0.1.8"
  sha256 "6ebf80fdfbdc7935a23d13a8eacaacd5e2e7d9c482545a72c8b48c9ee0bc6964"

  url "https://github.com/Jae-woo-Kang/homebrew-agent-awake/releases/download/v#{version}/AgentAwake-#{version}.zip"
  name "AgentAwake"
  desc "Menu bar monitor for Codex and Claude with a safe Mac keep-awake toggle"
  homepage "https://github.com/Jae-woo-Kang/homebrew-agent-awake"

  depends_on macos: :ventura

  app "AgentAwake.app"

  uninstall quit: "io.github.jaewookang.agentawake",
            script: {
              executable: "/bin/bash",
              args:       [
                "-c",
                'if [[ -x "$1" ]]; then exec /bin/bash "$1"; fi',
                "agent-awake-uninstall",
                "#{appdir}/AgentAwake.app/Contents/Resources/agentawake-uninstall-helper.sh",
              ],
              sudo: true,
            }

  zap trash: [
    "~/Library/Application Support/AgentAwake",
    "~/Library/Preferences/io.github.jaewookang.agentawake.plist",
  ]

  caveats <<~EOS
    AgentAwake asks for administrator approval once to install its restricted
    power helper. Later keep-awake toggles do not require another password.
    If a previous session was interrupted, restore normal sleep with:

      sudo pmset -a disablesleep 0

    This beta build may be ad-hoc signed. If macOS blocks the first launch,
    open System Settings > Privacy & Security and choose Open Anyway.
  EOS
end
