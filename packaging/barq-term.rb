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
  version "0.7.1"
  sha256 "03ba6767334cb2193ff2e015bd29cbd9a66628fd089711b3c4d7ed23697a0f81"

  url "https://github.com/awaistechnologist/barq-term/releases/download/v#{version}/Barq-#{version}.dmg"
  name "Barq"
  desc "AI-native macOS terminal with SSH, serial, Context Vault, and MCP"
  homepage "https://github.com/awaistechnologist/barq-term"

  depends_on macos: ">= :ventura"   # macOS 13+

  app "Barq.app"

  zap trash: [
    "~/Library/Application Support/Barq",
    "~/Library/Preferences/io.barq.terminal.plist",
  ]
end
