cask "molebar" do
  version "0.2.3"
  sha256 "6aa436113a709be5c12cb63c7e4228c83b0daa39fb228c2ef30f02913aa05cfc"

  url "https://github.com/osmanbarutcu/mole-bar/releases/download/v#{version}/MoleBar-#{version}-macos.zip"
  name "MoleBar"
  desc "Menu bar monitor and clean-up preview built on Mole"
  homepage "https://github.com/osmanbarutcu/mole-bar"

  depends_on formula: "mole"
  depends_on macos: :sequoia

  app "MoleBar.app"

  zap trash: [
    "~/Library/Preferences/local.molebar.plist",
    "~/Library/Saved Application State/local.molebar.savedState",
  ]

  caveats <<~EOS
    MoleBar is ad-hoc signed and not notarized.
    On first launch, right-click the app and choose Open.
  EOS
end
