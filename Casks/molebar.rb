cask "molebar" do
  version "0.2.2"
  sha256 "28e47e707e433a883b7d6aa95a74c91302a77b5550b1a1c9a16ecada2ae53264"

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
