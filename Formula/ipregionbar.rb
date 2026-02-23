cask "ipregionbar" do
  version "1.0.0"
  sha256 "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

  url "https://github.com/<user>/ipregionbar/releases/download/v#{version}/IPRegionBar.dmg"
  name "IP Region Bar"
  desc "macOS menu bar app showing current external IP geolocation"
  homepage "https://github.com/<user>/ipregionbar"

  app "IPRegionBar.app"

  zap trash: [
    "~/Library/Preferences/com.yourname.ipregionbar.plist",
    "~/Library/Application Support/IPRegionBar",
  ]
end
