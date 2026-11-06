cask "molebar" do
  version "0.2.1"
  sha256 "dfd71cc49f982aa1667ff21d218745b8e91ea5498952c03c375aa3b25396d2cb"

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
