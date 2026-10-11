# Template for rayhankhilji/homebrew-tap (Casks/widefive.rb). Scripts/release.sh writes a copy with the
# real version and sha256 to dist/widefive.rb; push that to the tap after each release.
cask "widefive" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/rayhankhilji/widefive/releases/download/v#{version}/widefive-#{version}.zip"
  name "widefive"
  desc "Take over the MacBook Pro Touch Bar with widgets, per-app layouts and games"
  homepage "https://github.com/rayhankhilji/widefive"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :monterey

  app "widefive.app"

  uninstall quit: "com.rayhankhilji.widefive"

  zap trash: [
    "~/.widefive",
    "~/Library/Caches/com.rayhankhilji.widefive",
    "~/Library/HTTPStorages/com.rayhankhilji.widefive",
    "~/Library/Preferences/com.rayhankhilji.widefive.plist",
  ]

  caveats <<~EOS
    widefive is ad-hoc signed unless a release was notarized. If macOS says it can't be opened, run once:
      xattr -dr com.apple.quarantine "#{appdir}/widefive.app"
    or use System Settings → Privacy & Security → Open Anyway.
  EOS
end
