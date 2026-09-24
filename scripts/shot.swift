// Window id (for screencapture -l) and its on-screen bounds (for clicking).
import CoreGraphics
import Foundation

let wantBounds = CommandLine.arguments.contains("--bounds")
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.contains("LifeTracker") || owner.contains("Life Tracker"),
          (w[kCGWindowLayer as String] as? Int ?? 0) == 0,
          let number = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat],
          (b["Width"] ?? 0) * (b["Height"] ?? 0) > 100_000 else { continue }
    if wantBounds {
        print("\(Int(b["X"] ?? 0)) \(Int(b["Y"] ?? 0)) \(Int(b["Width"] ?? 0)) \(Int(b["Height"] ?? 0))")
    } else {
        print(number)
    }
    exit(0)
}
exit(1)
