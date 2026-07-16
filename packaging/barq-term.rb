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
  version "0.8.0"
  sha256 "ba689690eec13c443ca7fcb967a4019fcc999cceeed4bd10c4ccc0d554580fcc"

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
