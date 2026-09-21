import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 24/255, green: 24/255, blue: 27/255, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 208, yRadius: 208).fill()
NSColor(calibratedRed: 0, green: 1, blue: 119/255, alpha: 1).setStroke()
let line = NSBezierPath()
line.lineWidth = 65
line.lineCapStyle = .round
line.move(to: NSPoint(x: 421, y: 270)); line.line(to: NSPoint(x: 475, y: 752))
line.move(to: NSPoint(x: 588, y: 270)); line.line(to: NSPoint(x: 642, y: 752))
line.move(to: NSPoint(x: 310, y: 427)); line.line(to: NSPoint(x: 739, y: 427))
line.move(to: NSPoint(x: 327, y: 595)); line.line(to: NSPoint(x: 756, y: 595))
line.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
