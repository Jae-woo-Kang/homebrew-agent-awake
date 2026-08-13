cask "agent-awake" do
  version "0.1.2"
  sha256 "39ce69d1009041bb7aa12ec3d8e1c6f93e21a074edc0a1cae2f746afa95fc7f4"

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
