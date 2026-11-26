cask "pacemark" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/kezaer/pacemark/releases/download/v#{version}/Pacemark-#{version}.dmg"
  name "Pacemark"
  desc "Menu bar monitor for AI subscription usage"
  homepage "https://github.com/kezaer/pacemark"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Pacemark.app"
end
