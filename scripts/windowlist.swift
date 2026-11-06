import CoreGraphics
import Foundation
let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in l where (w["kCGWindowOwnerName"] as? String) == "MoleBar" {
    let b = w["kCGWindowBounds"] as! [String: Any]
    print(w["kCGWindowNumber"]!, w["kCGWindowLayer"]!, w["kCGWindowIsOnscreen"] ?? "-", b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!)
}
