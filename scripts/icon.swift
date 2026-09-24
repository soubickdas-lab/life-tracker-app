// Draws the app icon: a soft indigo→mint square with a ring and a tick.
import AppKit
import CoreGraphics
import Foundation

func icon(_ size: CGFloat) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // rounded background with the app's gradient
    let corner = size * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    let colors = [CGColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1),
                  CGColor(red: 0.24, green: 0.66, blue: 0.68, alpha: 1),
                  CGColor(red: 0.20, green: 0.74, blue: 0.52, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // the progress ring, open at the top right
    let inset = size * 0.235
    let ring = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    ctx.setLineWidth(size * 0.075)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    ctx.addEllipse(in: ring)
    ctx.strokePath()

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: ring.width / 2,
               startAngle: .pi / 2, endAngle: -.pi / 3, clockwise: true)
    ctx.strokePath()

    // the tick
    ctx.setLineWidth(size * 0.085)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: size * 0.36, y: size * 0.50))
    ctx.addLine(to: CGPoint(x: size * 0.46, y: size * 0.40))
    ctx.addLine(to: CGPoint(x: size * 0.66, y: size * 0.62))
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for size in [16, 32, 64, 128, 256, 512, 1024] {
    write(icon(CGFloat(size)), to: "\(out)/icon_\(size).png")
}
print("icons in \(out)")
