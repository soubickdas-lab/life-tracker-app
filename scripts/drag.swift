// A slow drag from one screen point to another:  swift scripts/drag.swift x1 y1 x2 y2
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 5, let x1 = Double(a[1]), let y1 = Double(a[2]),
      let x2 = Double(a[3]), let y2 = Double(a[4]) else {
    print("usage: drag.swift x1 y1 x2 y2"); exit(1)
}
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}
post(.mouseMoved, CGPoint(x: x1, y: y1));   usleep(200_000)
post(.leftMouseDown, CGPoint(x: x1, y: y1)); usleep(350_000)

let steps = 40
for i in 1...steps {
    let f = Double(i) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * f, y: y1 + (y2 - y1) * f))
    usleep(30_000)
}
usleep(400_000)
post(.leftMouseUp, CGPoint(x: x2, y: y2))
print("dragged \(Int(x1)),\(Int(y1)) → \(Int(x2)),\(Int(y2))")
