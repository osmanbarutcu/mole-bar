cask "molebar" do
  version "0.3.0"
  sha256 "7a1662686a3a906b8c6faf298b78ec8972de9e104eed91cff1b7db0dc35832a8"

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
