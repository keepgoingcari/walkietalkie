class Walkietalkie < Formula
  desc "Global push-to-talk layer for terminal coding workflows"
  homepage "https://github.com/keepgoingcari/walkietalkie"
  url "https://github.com/keepgoingcari/walkietalkie/releases/download/v0.1.0/walkietalkie-0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  version "0.1.0"

  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/walkietalkie"
  end

  test do
    assert_match "walkietalkie commands", shell_output("#{bin}/walkietalkie help")
  end
end
