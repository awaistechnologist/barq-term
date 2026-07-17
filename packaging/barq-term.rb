# Homebrew cask for Barq.
#
# Lives in a tap repo: github.com/awaistechnologist/homebrew-barq
# (path there: Casks/barq-term.rb). Then users install with:
#
#     brew tap awaistechnologist/barq
#     brew install --cask barq-term
#
# Unsigned build → users may need one-time approval, or install without the
# quarantine flag to skip the Gatekeeper prompt entirely:
#
#     brew install --cask barq-term --no-quarantine
#
# `brew upgrade --cask barq-term` then handles updates.
cask "barq-term" do
  version "0.8.1"
  sha256 "e8d645425a810294921e547b9113692e0e8f5db9347e87fcf4bcdcf1e033460a"

  url "https://github.com/awaistechnologist/barq-term/releases/download/v#{version}/Barq-#{version}.dmg"
  name "Barq"
  desc "AI-native macOS terminal with SSH, serial, Context Vault, and MCP"
  homepage "https://github.com/awaistechnologist/barq-term"

  app "Barq.app"

  zap trash: [
    "~/Library/Application Support/Barq",
    "~/Library/Preferences/io.barq.terminal.plist",
  ]
end
