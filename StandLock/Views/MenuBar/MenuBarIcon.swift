import AppKit
import StandLockCore

enum MenuBarIcon {
    static func make(progress: Double, look: MenuSceneLook = .working) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)

            NSColor.black.setStroke()
            NSColor.black.setFill()

            if look == .working {
                drawProgress(progress, center: center)
            } else {
                drawRing(center: center, dashed: look == .noSchedules)
                switch look {
                case .working:
                    break
                case .breakSoon:
                    drawExclamation()
                case .timeToStand:
                    drawSleepingSymbol()
                case .paused:
                    drawPauseSymbol()
                case .breakWaiting:
                    drawClockSymbol()
                case .noSchedules:
                    break
                }
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    static func accessibilityLabel(for look: MenuSceneLook) -> String {
        switch look {
        case .working:
            String(localized: "Working")
        case .breakSoon:
            String(localized: "Break soon")
        case .timeToStand:
            String(localized: "Time to stand")
        case .paused:
            String(localized: "Paused")
        case .breakWaiting:
            String(localized: "Break waiting")
        case .noSchedules:
            String(localized: "No active schedules")
        }
    }

    private static let outerRadius: CGFloat = 6.5
    private static let strokeWidth: CGFloat = 1.5

    private static func drawProgress(_ progress: Double, center: CGPoint) {
        drawRing(center: center, dashed: false)

        let fillRadius = outerRadius - strokeWidth
        switch ProgressDisplayBranch(progress: progress) {
        case .empty:
            break
        case .full:
            let fillRect = CGRect(
                x: center.x - fillRadius, y: center.y - fillRadius,
                width: fillRadius * 2, height: fillRadius * 2
            )
            NSBezierPath(ovalIn: fillRect).fill()
        case .partial:
            let clamped = min(1.0, max(0.0, progress))
            let startAngle: CGFloat = 90
            let endAngle = 90 - 360 * clamped
            let sector = NSBezierPath()
            sector.move(to: center)
            sector.appendArc(
                withCenter: center, radius: fillRadius,
                startAngle: startAngle, endAngle: endAngle,
                clockwise: true
            )
            sector.close()
            sector.fill()
        }
    }

    private static func drawRing(center: CGPoint, dashed: Bool) {
        let circleRect = CGRect(
            x: center.x - outerRadius, y: center.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2
        )
        let circle = NSBezierPath(ovalIn: circleRect)
        circle.lineWidth = strokeWidth
        if dashed {
            circle.setLineDash([2, 1.8], count: 2, phase: 0)
        }
        circle.stroke()
    }

    private static func drawExclamation() {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 9, y: 12.9))
        line.line(to: NSPoint(x: 9, y: 8.5))
        stroke(line, width: 1.65)
        NSBezierPath(ovalIn: NSRect(x: 8.1, y: 4.95, width: 1.8, height: 1.8)).fill()
    }

    private static func drawSleepingSymbol() {
        let symbol = NSBezierPath()
        symbol.move(to: NSPoint(x: 4.6, y: 9.9))
        symbol.line(to: NSPoint(x: 8.7, y: 9.9))
        symbol.line(to: NSPoint(x: 4.6, y: 5.1))
        symbol.line(to: NSPoint(x: 8.7, y: 5.1))
        symbol.move(to: NSPoint(x: 8.5, y: 12.7))
        symbol.line(to: NSPoint(x: 11.9, y: 12.7))
        symbol.line(to: NSPoint(x: 8.5, y: 8.9))
        symbol.line(to: NSPoint(x: 11.9, y: 8.9))
        symbol.move(to: NSPoint(x: 11.8, y: 14.6))
        symbol.line(to: NSPoint(x: 14.2, y: 14.6))
        symbol.line(to: NSPoint(x: 11.8, y: 12.1))
        symbol.line(to: NSPoint(x: 14.2, y: 12.1))
        stroke(symbol, width: 1.05)
    }

    private static func drawPauseSymbol() {
        NSBezierPath(roundedRect: NSRect(x: 6.8, y: 5.8, width: 1.5, height: 6.4), xRadius: 0.45, yRadius: 0.45).fill()
        NSBezierPath(roundedRect: NSRect(x: 10.1, y: 5.8, width: 1.5, height: 6.4), xRadius: 0.45, yRadius: 0.45).fill()
    }

    private static func drawClockSymbol() {
        let hands = NSBezierPath()
        hands.move(to: NSPoint(x: 9, y: 12.3))
        hands.line(to: NSPoint(x: 9, y: 8.8))
        hands.line(to: NSPoint(x: 11.45, y: 7.55))
        stroke(hands, width: 1.4)
        NSBezierPath(ovalIn: NSRect(x: 8.3, y: 8.3, width: 1.4, height: 1.4)).fill()
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
