cask "agent-awake" do
  version "0.1.4"
  sha256 "0f6be34c9431dcf6db47c73fcb08b1102ecab651f37000a9a9c6bfa303ce09e4"

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
    AgentAwake prevents automatic idle system sleep while its toggle is on.
    Closing the MacBook lid or explicitly choosing Sleep still puts the Mac
    to sleep.

    This beta build may be ad-hoc signed. If macOS blocks the first launch,
    open System Settings > Privacy & Security and choose Open Anyway.
  EOS
end
