//
//  PrayerPostureIcon.swift
//  Groo
//
//  SwiftUI Path-drawn prayer posture silhouettes for rakat flow visualization.
//

import SwiftUI

struct PrayerPostureIcon: View {
    let posture: PrayerPosture
    var size: CGFloat = 32

    var body: some View {
        PostureShape(posture: posture)
            .fill(.secondary)
            .frame(width: size, height: size)
    }
}

// MARK: - Posture Shape

private struct PostureShape: Shape {
    let posture: PrayerPosture

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        switch posture {
        case .standing:
            return standingPath(w: w, h: h, rect: rect)
        case .handsRaised:
            return handsRaisedPath(w: w, h: h, rect: rect)
        case .bowing:
            return bowingPath(w: w, h: h, rect: rect)
        case .standingBrief:
            return standingBriefPath(w: w, h: h, rect: rect)
        case .prostrating:
            return prostratingPath(w: w, h: h, rect: rect)
        case .sitting:
            return sittingPath(w: w, h: h, rect: rect)
        case .salam:
            return salamPath(w: w, h: h, rect: rect)
        }
    }

    // MARK: - Standing (Qiyam) — hands folded below navel

    private func standingPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()
        let cx = w * 0.5

        // Head
        path.addEllipse(in: CGRect(x: cx - w * 0.1, y: h * 0.02, width: w * 0.2, height: w * 0.2))

        // Body line
        path.move(to: CGPoint(x: cx, y: h * 0.22))
        path.addLine(to: CGPoint(x: cx, y: h * 0.65))

        // Arms folded at waist level (Hanafi position — right over left below navel)
        path.move(to: CGPoint(x: cx - w * 0.18, y: h * 0.38))
        path.addQuadCurve(to: CGPoint(x: cx + w * 0.02, y: h * 0.44),
                          control: CGPoint(x: cx - w * 0.08, y: h * 0.44))
        path.move(to: CGPoint(x: cx + w * 0.18, y: h * 0.38))
        path.addQuadCurve(to: CGPoint(x: cx - w * 0.02, y: h * 0.44),
                          control: CGPoint(x: cx + w * 0.08, y: h * 0.44))

        // Legs
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.98))
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.98))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Hands Raised (Takbir) — hands raised to ears

    private func handsRaisedPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()
        let cx = w * 0.5

        // Head
        path.addEllipse(in: CGRect(x: cx - w * 0.1, y: h * 0.08, width: w * 0.2, height: w * 0.2))

        // Body line
        path.move(to: CGPoint(x: cx, y: h * 0.28))
        path.addLine(to: CGPoint(x: cx, y: h * 0.65))

        // Arms raised — elbows bent, hands at ear level
        path.move(to: CGPoint(x: cx, y: h * 0.35))
        path.addLine(to: CGPoint(x: cx - w * 0.22, y: h * 0.38))
        path.addLine(to: CGPoint(x: cx - w * 0.2, y: h * 0.14))
        path.move(to: CGPoint(x: cx, y: h * 0.35))
        path.addLine(to: CGPoint(x: cx + w * 0.22, y: h * 0.38))
        path.addLine(to: CGPoint(x: cx + w * 0.2, y: h * 0.14))

        // Legs
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.98))
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.98))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Bowing (Ruku) — bent at waist, hands on knees

    private func bowingPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()

        // Head (forward)
        path.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.18, width: w * 0.18, height: w * 0.18))

        // Back (horizontal from head to hip)
        path.move(to: CGPoint(x: w * 0.26, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.3))

        // Arms down to knees
        path.move(to: CGPoint(x: w * 0.36, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.55))
        path.move(to: CGPoint(x: w * 0.48, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.55))

        // Legs (slightly bent)
        path.move(to: CGPoint(x: w * 0.62, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.98))
        path.move(to: CGPoint(x: w * 0.62, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.98))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Standing Brief (Qawmah) — standing straight after ruku, arms at sides

    private func standingBriefPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()
        let cx = w * 0.5

        // Head
        path.addEllipse(in: CGRect(x: cx - w * 0.1, y: h * 0.02, width: w * 0.2, height: w * 0.2))

        // Body line
        path.move(to: CGPoint(x: cx, y: h * 0.22))
        path.addLine(to: CGPoint(x: cx, y: h * 0.65))

        // Arms at sides
        path.move(to: CGPoint(x: cx, y: h * 0.32))
        path.addLine(to: CGPoint(x: cx - w * 0.2, y: h * 0.5))
        path.move(to: CGPoint(x: cx, y: h * 0.32))
        path.addLine(to: CGPoint(x: cx + w * 0.2, y: h * 0.5))

        // Legs
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.98))
        path.move(to: CGPoint(x: cx, y: h * 0.65))
        path.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.98))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Prostrating (Sujud) — forehead on ground

    private func prostratingPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()

        // Head (on ground, left side)
        path.addEllipse(in: CGRect(x: w * 0.06, y: h * 0.58, width: w * 0.16, height: w * 0.16))

        // Back curving up from head to hips
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.64))
        path.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.28),
                          control: CGPoint(x: w * 0.38, y: h * 0.2))

        // Arms (hands flat on ground near head)
        path.move(to: CGPoint(x: w * 0.30, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.72))
        path.move(to: CGPoint(x: w * 0.36, y: h * 0.36))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.72))

        // Legs (folded, knees on ground)
        path.move(to: CGPoint(x: w * 0.58, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))

        // Ground line
        path.move(to: CGPoint(x: w * 0.02, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.76))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.06, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Sitting (Jalsah/Tashahhud) — sitting on legs

    private func sittingPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()
        let cx = w * 0.45

        // Head
        path.addEllipse(in: CGRect(x: cx - w * 0.1, y: h * 0.02, width: w * 0.2, height: w * 0.2))

        // Body (slightly forward lean)
        path.move(to: CGPoint(x: cx, y: h * 0.22))
        path.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.52))

        // Arms on thighs
        path.move(to: CGPoint(x: cx + w * 0.02, y: h * 0.34))
        path.addLine(to: CGPoint(x: cx + w * 0.2, y: h * 0.54))
        path.move(to: CGPoint(x: cx + w * 0.02, y: h * 0.34))
        path.addLine(to: CGPoint(x: cx - w * 0.12, y: h * 0.54))

        // Legs (folded underneath — sitting on heels)
        path.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.52))
        path.addQuadCurve(to: CGPoint(x: cx + w * 0.34, y: h * 0.68),
                          control: CGPoint(x: cx + w * 0.28, y: h * 0.52))
        path.addLine(to: CGPoint(x: cx + w * 0.08, y: h * 0.72))

        // Ground line
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.74))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Salam — sitting, head turned to side

    private func salamPath(w: CGFloat, h: CGFloat, rect: CGRect) -> Path {
        var path = Path()
        let cx = w * 0.45

        // Head (turned to right — offset)
        path.addEllipse(in: CGRect(x: cx + w * 0.02, y: h * 0.02, width: w * 0.2, height: w * 0.2))

        // Small line indicating head turn direction
        path.move(to: CGPoint(x: cx + w * 0.22, y: h * 0.1))
        path.addLine(to: CGPoint(x: cx + w * 0.3, y: h * 0.08))

        // Body
        path.move(to: CGPoint(x: cx, y: h * 0.22))
        path.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.52))

        // Arms on thighs
        path.move(to: CGPoint(x: cx + w * 0.02, y: h * 0.34))
        path.addLine(to: CGPoint(x: cx + w * 0.2, y: h * 0.54))
        path.move(to: CGPoint(x: cx + w * 0.02, y: h * 0.34))
        path.addLine(to: CGPoint(x: cx - w * 0.12, y: h * 0.54))

        // Legs folded
        path.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.52))
        path.addQuadCurve(to: CGPoint(x: cx + w * 0.34, y: h * 0.68),
                          control: CGPoint(x: cx + w * 0.28, y: h * 0.52))
        path.addLine(to: CGPoint(x: cx + w * 0.08, y: h * 0.72))

        // Ground line
        path.move(to: CGPoint(x: w * 0.08, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.74))

        return path.strokedPath(StrokeStyle(lineWidth: w * 0.07, lineCap: .round, lineJoin: .round))
    }
}
