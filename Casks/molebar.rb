cask "molebar" do
  version "0.2.5"
  sha256 "868980c8060c2e3e30647606b410c849bd288000f137979eb9a3bfda12e198f4"

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
