cask "walkietalkie" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/REPLACE_WITH_OWNER/walkietalkie/releases/download/v#{version}/Walkietalkie.app.zip"
  name "Walkietalkie"
  desc "Global push-to-talk layer for terminal coding workflows"
  homepage "https://github.com/REPLACE_WITH_OWNER/walkietalkie"

  app "Walkietalkie.app"

  zap trash: [
    "~/Library/Application Support/walkietalkie",
    "~/.config/walkietalkie"
  ]
end
