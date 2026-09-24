// A click at a screen point, without System Events:  swift scripts/click.swift 600 322
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    print("usage: click.swift <x> <y>"); exit(1)
}
let point = CGPoint(x: x, y: y)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,   mouseCursorPosition: point, mouseButton: .left)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120_000)
down?.post(tap: .cghidEventTap)
usleep(60_000)
up?.post(tap: .cghidEventTap)
print("clicked \(Int(x)),\(Int(y))")
