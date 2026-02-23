cask "ipregionbar" do
  version "1.0.1"
  sha256 "05fdddbc23a46053021e70f371a2dc50c73bc495b9c38704c8609d4789e01368"

  url "https://github.com/svishniakov/ip-region-bar/releases/download/v#{version}/IPRegionBar.dmg"
  name "IP Region Bar"
  desc "macOS menu bar app showing external IP geolocation with local DB-IP lookup"
  homepage "https://github.com/svishniakov/ip-region-bar"

  app "IPRegionBar.app"

  zap trash: [
    "~/Library/Preferences/com.svishniakov.ipregionbar.plist",
    "~/Library/Application Support/IPRegionBar",
  ]
end
