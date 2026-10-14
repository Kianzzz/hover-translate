import AppKit

let destination = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(red: 0.20, green: 0.35, blue: 0.28, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 196, yRadius: 196).fill()
let bubble = NSBezierPath(roundedRect: NSRect(x: 245, y: 295, width: 535, height: 440), xRadius: 100, yRadius: 100)
NSColor(red: 0.82, green: 0.93, blue: 0.65, alpha: 1).setFill()
bubble.fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 335, y: 330)); tail.line(to: NSPoint(x: 335, y: 210)); tail.line(to: NSPoint(x: 485, y: 330)); tail.close(); tail.fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 290, weight: .medium), .foregroundColor: NSColor(red: 0.20, green: 0.35, blue: 0.28, alpha: 1)]
let text = "译" as NSString
text.draw(at: NSPoint(x: 365, y: 345), withAttributes: attributes)
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
