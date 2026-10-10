// Renders the Pomodoro app icon (1024×1024 PNG). Usage: swift scripts/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background tile: macOS icon grid (824 pt tile, 100 pt margin), continuous-ish corners, soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0xFFF1E6))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0xFFF7F0), color(0xFFDCC8)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Tomato body.
let center = CGPoint(x: 512, y: 470)
let radius: CGFloat = 285
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: color(0x8A1A12, 0.35))
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.94, width: radius * 2, height: radius * 1.88))
ctx.setFillColor(color(0xE0392C))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.94, width: radius * 2, height: radius * 1.88))
ctx.clip()
let body = CGGradient(colorsSpace: space, colors: [color(0xFF7A5C), color(0xE8402F), color(0xB9241B)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawRadialGradient(body, startCenter: CGPoint(x: center.x - 90, y: center.y + 110), startRadius: 0,
                       endCenter: center, endRadius: radius * 1.05, options: [.drawsAfterEndLocation])
// Glossy highlight.
ctx.translateBy(x: center.x - 196, y: center.y + 150)
ctx.rotate(by: .pi / 5)
ctx.setFillColor(color(0xFFFFFF, 0.3))
ctx.addEllipse(in: CGRect(x: -52, y: -26, width: 104, height: 52))
ctx.fillPath()
ctx.restoreGState()

// Timer ring: three quarters of focus time left, with a rounded cap.
let ringRadius: CGFloat = 178
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(34)
ctx.setStrokeColor(color(0xFFFFFF, 0.97))
ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: -.pi, clockwise: true)
ctx.strokePath()
// Clock hand pointing at the end of the arc, and its hub.
ctx.setLineWidth(30)
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x - 105, y: center.y))
ctx.strokePath()
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x, y: center.y + 120))
ctx.strokePath()
ctx.setFillColor(color(0xFFFFFF))
ctx.addEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
ctx.fillPath()
ctx.restoreGState()

// Leaves (calyx) and stem.
let top = CGPoint(x: 512, y: center.y + radius * 0.94 - 18)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: color(0x1E4D1F, 0.35))
let leafColor = color(0x3E9B47)
for angle in stride(from: -150.0, through: -30.0, by: 30.0) {
    let a = CGFloat(angle) * .pi / 180
    let length: CGFloat = (angle == -90) ? 0 : 150
    guard length > 0 else { continue }
    let tip = CGPoint(x: top.x + cos(a) * length * 1.15, y: top.y + sin(a) * length * 0.55 + 40)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: top.x - 26, y: top.y + 8))
    path.addQuadCurve(to: tip, control: CGPoint(x: (top.x + tip.x) / 2 - 20 * sin(a), y: top.y + 80))
    path.addQuadCurve(to: CGPoint(x: top.x + 26, y: top.y + 8), control: CGPoint(x: (top.x + tip.x) / 2 + 20 * sin(a), y: top.y - 10))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(leafColor)
    ctx.fillPath()
}
ctx.addEllipse(in: CGRect(x: top.x - 52, y: top.y - 18, width: 104, height: 60))
ctx.setFillColor(color(0x34883C))
ctx.fillPath()
// Stem.
let stem = CGMutablePath()
stem.move(to: CGPoint(x: top.x - 14, y: top.y + 20))
stem.addQuadCurve(to: CGPoint(x: top.x + 30, y: top.y + 120), control: CGPoint(x: top.x - 10, y: top.y + 90))
stem.addLine(to: CGPoint(x: top.x + 56, y: top.y + 110))
stem.addQuadCurve(to: CGPoint(x: top.x + 16, y: top.y + 18), control: CGPoint(x: top.x + 22, y: top.y + 70))
stem.closeSubpath()
ctx.addPath(stem)
ctx.setFillColor(color(0x2F7A35))
ctx.fillPath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
