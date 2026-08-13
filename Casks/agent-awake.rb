cask "agent-awake" do
  version "0.1.1"
  sha256 "d0ec9ceb6b106ba52483a9e3e8218e4ffdadb644490f0d590344003652731ceb"

  url "https://github.com/Jae-woo-Kang/homebrew-agent-awake/releases/download/v#{version}/AgentAwake-#{version}.zip"
  name "AgentAwake"
  desc "Menu bar monitor for Codex and Claude with a safe Mac keep-awake toggle"
  homepage "https://github.com/Jae-woo-Kang/homebrew-agent-awake"

  depends_on macos: :ventura

  app "AgentAwake.app"

  uninstall quit: "io.github.jaewookang.agentawake"

  zap trash: [
    "~/Library/Application Support/AgentAwake",
    "~/Library/Preferences/io.github.jaewookang.agentawake.plist",
  ]

  caveats <<~EOS
    AgentAwake asks for administrator approval only when enabling closed-lid
    keep-awake mode. If a previous session was interrupted, restore normal
    sleep with:

      sudo pmset -a disablesleep 0

    This beta build may be ad-hoc signed. If macOS blocks the first launch,
    open System Settings > Privacy & Security and choose Open Anyway.
  EOS
end
