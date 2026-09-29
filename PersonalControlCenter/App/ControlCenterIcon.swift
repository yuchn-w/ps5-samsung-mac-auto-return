import AppKit

/// Resolution-independent monitor with three control nodes, not generic sliders.
enum ControlCenterIcon {
  static func make() -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
      NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
      let screen = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5.5, width: 19, height: 13), xRadius: 2, yRadius: 2)
      screen.lineWidth = 1.5; screen.stroke()
      let stand = NSBezierPath()
      stand.move(to: NSPoint(x: 11, y: 5)); stand.line(to: NSPoint(x: 11, y: 2))
      stand.move(to: NSPoint(x: 7, y: 1.5)); stand.line(to: NSPoint(x: 15, y: 1.5))
      stand.lineWidth = 1.5; stand.lineCapStyle = .round; stand.stroke()
      for (x, y) in [(6.0, 11.0), (11.0, 14.0), (16.0, 10.0)] {
        let rail = NSBezierPath()
        rail.move(to: NSPoint(x: x, y: 8)); rail.line(to: NSPoint(x: x, y: 16))
        rail.lineWidth = 1; rail.stroke()
        NSBezierPath(ovalIn: NSRect(x: x - 1.7, y: y - 1.7, width: 3.4, height: 3.4)).fill()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "個人控制中心"
    return image
  }
}
