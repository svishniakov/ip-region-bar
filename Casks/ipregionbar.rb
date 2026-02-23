cask "ipregionbar" do
  version "1.0.0"
  sha256 "24d7ecf45a8885343651e13c63833886f847833da33a16d435e08ede9cec5bc9"

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
