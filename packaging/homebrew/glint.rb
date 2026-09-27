cask "glint" do
  version "0.1.0"
  sha256 "REPLACED_BY_SCRIPTS_RELEASE_SH"

  url "https://github.com/jordan-jakisa/glint/releases/download/v#{version}/Glint-#{version}.dmg"
  name "Glint"
  desc "Fast native git panel: read the diff, stage, and commit"
  homepage "https://github.com/jordan-jakisa/glint"

  depends_on macos: ">= :sequoia"

  app "Glint.app"

  zap trash: [
    "~/Library/Preferences/com.kerustudios.glint.plist",
    "~/Library/Saved Application State/com.kerustudios.glint.savedState",
  ]
end
