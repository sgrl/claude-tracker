# Homebrew cask template for Claude Tracker.
#
# This file belongs in the separate tap repository:
#   github.com/sgrl/homebrew-claude-tracker
#   └── Casks/claude-tracker.rb
#
# After each release, update `version` and `sha256` to match the numbers
# printed by scripts/release.sh, then commit & push the tap repo.
#
# Users install via:
#   brew tap sgrl/claude-tracker
#   brew install --cask claude-tracker

cask "claude-tracker" do
  version "0.1.2"
  sha256 "e0e7eedf64ddb8fad7b9b4760e931709c631d72b0d633766ff2d2f3742d3f88a"

  url "https://github.com/sgrl/claude-tracker/releases/download/v#{version}/claudetracker-#{version}.dmg"
  name "Claude Tracker"
  desc "Menubar view of Claude Code usage"
  homepage "https://github.com/sgrl/claude-tracker"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "claudetracker.app"

  # Claude Tracker is ad-hoc signed (no Apple Developer account). macOS's
  # Gatekeeper quarantine blocks launch until the attribute is removed.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/claudetracker.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/claudetracker",
    "~/Library/Preferences/io.github.sgrl.claude-tracker.plist",
    "~/Library/Caches/io.github.sgrl.claude-tracker",
    "~/.claude/claudetracker",
  ]
end
