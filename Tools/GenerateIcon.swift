// Rebuild the original app icon with: swift Tools/GenerateIcon.swift
import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.045, green: 0.32, blue: 0.28, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let transform = NSAffineTransform(); transform.translateX(by: 512, yBy: 512); transform.rotate(byDegrees: -28); transform.translateX(by: -512, yBy: -512); transform.concat()
NSColor(red: 0.94, green: 0.96, blue: 0.90, alpha: 1).setStroke()
let band = NSBezierPath(roundedRect: NSRect(x: 340, y: 195, width: 344, height: 634), xRadius: 172, yRadius: 172)
band.lineWidth = 48; band.stroke()
NSColor(red: 0.94, green: 0.96, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 422, y: 338, width: 180, height: 348), xRadius: 90, yRadius: 90).fill()
NSColor(red: 0.045, green: 0.32, blue: 0.28, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 498, y: 600, width: 28, height: 28)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
