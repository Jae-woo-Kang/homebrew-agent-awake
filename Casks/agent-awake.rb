cask "agent-awake" do
  version "0.1.5"
  sha256 "29b7d1cf213bc1002fe45b7548fc5ac7a02022a83ad7dd1d180e34d90f0c8682"

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
    AgentAwake asks for administrator approval when enabling its keep-awake
    toggle so it can keep the Mac running with the lid closed. If a previous
    session was interrupted, restore normal sleep with:

      sudo pmset -a disablesleep 0

    This beta build may be ad-hoc signed. If macOS blocks the first launch,
    open System Settings > Privacy & Security and choose Open Anyway.
  EOS
end
