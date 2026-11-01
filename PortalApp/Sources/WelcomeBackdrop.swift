import SwiftUI

/// WelcomePalette is the welcome screen's colors, light and dark, as the web landing page defines them.
struct WelcomePalette {
    let background: Color
    let text: Color
    let textMuted: Color
    let textFaint: Color
    let wordmark: [Color]
    /// The rust the arm is drawn in, brighter on dark so it reads against the ground.
    let armTone: Color
    let armOpacity: Double
    let veilFirst: [Color]
    let veilSecond: [Color]
    let glow: Color
    let gridFine: Color
    let gridCoarse: Color
    let ctaFill: [Color]
    let ctaText: Color

    static let orange = Color(red: 0.906, green: 0.380, blue: 0.145)
    static let amber = Color(red: 0.953, green: 0.573, blue: 0)

    static let dark = WelcomePalette(
        background: Color(red: 0.039, green: 0.043, blue: 0.063),
        text: Color(red: 0.98, green: 0.98, blue: 0.98),
        textMuted: Color(red: 0.98, green: 0.98, blue: 0.98).opacity(0.72),
        textFaint: Color(red: 0.98, green: 0.98, blue: 0.98).opacity(0.45),
        wordmark: [Color(red: 0.98, green: 0.98, blue: 0.98), Color(red: 1, green: 0.69, blue: 0.537), orange],
        armTone: orange, armOpacity: 0.45,
        veilFirst: [orange.opacity(0.09), Color(red: 1, green: 0.702, blue: 0.278).opacity(0.06)],
        veilSecond: [Color(red: 1, green: 0.702, blue: 0.278).opacity(0.07), orange.opacity(0.09)],
        glow: orange.opacity(0.05),
        gridFine: orange.opacity(0.05), gridCoarse: orange.opacity(0.10),
        ctaFill: [.white, .white], ctaText: Color(red: 0.039, green: 0.043, blue: 0.063))

    static let light = WelcomePalette(
        background: Color(red: 0.965, green: 0.957, blue: 0.937),
        text: Color(red: 0.039, green: 0.043, blue: 0.063),
        textMuted: Color(red: 0.039, green: 0.043, blue: 0.063).opacity(0.66),
        textFaint: Color(red: 0.039, green: 0.043, blue: 0.063).opacity(0.42),
        wordmark: [amber, orange, Color(red: 0.757, green: 0.141, blue: 0.141)],
        armTone: Color(red: 0.769, green: 0.333, blue: 0.125), armOpacity: 0.5,
        veilFirst: [orange.opacity(0.09), Color(red: 1, green: 0.702, blue: 0.278).opacity(0.10)],
        veilSecond: [Color(red: 1, green: 0.702, blue: 0.278).opacity(0.12), orange.opacity(0.09)],
        glow: Color(red: 1, green: 0.702, blue: 0.278).opacity(0.10),
        gridFine: Color(red: 0.235, green: 0.157, blue: 0.078).opacity(0.05), gridCoarse: Color(red: 0.235, green: 0.157, blue: 0.078).opacity(0.10),
        ctaFill: [Color(red: 1, green: 0.894, blue: 0.8), Color(red: 1, green: 0.812, blue: 0.639)],
        ctaText: Color(red: 0.039, green: 0.043, blue: 0.063))

    static func palette(for scheme: ColorScheme) -> WelcomePalette { scheme == .dark ? dark : light }
}

/// WelcomeBackdrop is the warm wash behind the welcome screen: a radial bloom, two blurred conic veils turning slowly
/// against each other, and a fine and a coarse engineering grid fading out toward the edges. The motion stops under Reduce Motion.
struct WelcomeBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var isReducingMotion

    var body: some View {
        let palette = WelcomePalette.palette(for: colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isReducingMotion)) { context in
            let seconds = isReducingMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let longSide = max(proxy.size.width, proxy.size.height)
                ZStack {
                    palette.background
                    RadialGradient(colors: [palette.glow, .clear], center: UnitPoint(x: 0.5, y: 0.6), startRadius: 0, endRadius: longSide * 0.55)
                    Self.veil(colors: palette.veilFirst, center: UnitPoint(x: 0.3, y: 0.4), startDegrees: 220, order: [60, 200])
                        .frame(width: longSide * 1.4, height: longSide * 1.4)
                        .blur(radius: 60)
                        .rotationEffect(.degrees(seconds / 32 * 360))
                    Self.veil(colors: palette.veilSecond, center: UnitPoint(x: 0.7, y: 0.6), startDegrees: 50, order: [80, 240])
                        .frame(width: longSide * 1.4, height: longSide * 1.4)
                        .blur(radius: 75)
                        .rotationEffect(.degrees(-seconds / 44 * 360))
                    WelcomeGrid(fine: palette.gridFine, coarse: palette.gridCoarse)
                        .mask(
                            EllipticalGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.9)], center: UnitPoint(x: 0.5, y: 0.55))
                        )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static func veil(colors: [Color], center: UnitPoint, startDegrees: Double, order: [Double]) -> some View {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: colors[0], location: order[0] / 360),
                .init(color: .clear, location: (order[0] + 60) / 360),
                .init(color: colors[1], location: order[1] / 360),
                .init(color: .clear, location: min(1, (order[1] + 80) / 360)),
            ],
            center: center, angle: .degrees(startDegrees))
    }
}

/// WelcomeGrid is the engineering grid: fine lines every 24 points and heavier ones every 120.
struct WelcomeGrid: View {
    let fine: Color
    let coarse: Color

    var body: some View {
        Canvas { context, size in
            func lines(every step: CGFloat, color: Color) {
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            lines(every: 24, color: fine)
            lines(every: 120, color: coarse)
        }
    }
}

/// WelcomeArm is a schematic six-axis robot arm in blueprint line art: a disc base, the column, the shoulder drum, an upper
/// arm and a tapering forearm that swing slowly about the shoulder, a wrist, a two-finger gripper and a crosshair at the tool point.
struct WelcomeArm: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var isReducingMotion

    private static let shoulder = CGPoint(x: 110, y: 290)

    var body: some View {
        let palette = WelcomePalette.palette(for: colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isReducingMotion)) { context in
            let swing = isReducingMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 18) * 5
            ZStack {
                ArmBase().stroke(palette.armTone, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                ReachArc().stroke(palette.armTone.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 5]))
                ArmUpper().stroke(palette.armTone, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(swing), anchor: UnitPoint(x: Self.shoulder.x / 360, y: Self.shoulder.y / 460))
                CropMarks().stroke(palette.armTone.opacity(0.5), lineWidth: 0.8)
            }
            .frame(width: 360, height: 460)
        }
        .opacity(palette.armOpacity)
        .accessibilityHidden(true)
    }

    struct ArmBase: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addEllipse(in: CGRect(x: 30, y: 416, width: 160, height: 28))
            path.addEllipse(in: CGRect(x: 48, y: 404, width: 124, height: 22))
            path.move(to: CGPoint(x: 92, y: 410))
            path.addLine(to: CGPoint(x: 92, y: 300))
            path.move(to: CGPoint(x: 128, y: 410))
            path.addLine(to: CGPoint(x: 128, y: 300))
            path.addEllipse(in: CGRect(x: 80, y: 260, width: 60, height: 60))
            path.addEllipse(in: CGRect(x: 100, y: 280, width: 20, height: 20))
            return path
        }
    }

    struct ArmUpper: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            // Upper arm: two rails from the shoulder to the elbow drum, with a cable loom between.
            path.move(to: CGPoint(x: 96, y: 276)); path.addLine(to: CGPoint(x: 236, y: 154))
            path.move(to: CGPoint(x: 124, y: 304)); path.addLine(to: CGPoint(x: 264, y: 186))
            path.addEllipse(in: CGRect(x: 226, y: 146, width: 48, height: 48))
            path.addEllipse(in: CGRect(x: 242, y: 162, width: 16, height: 16))
            path.move(to: CGPoint(x: 110, y: 296))
            path.addQuadCurve(to: CGPoint(x: 250, y: 176), control: CGPoint(x: 150, y: 190))
            // Forearm: tapers toward the wrist, with vent slats.
            path.move(to: CGPoint(x: 258, y: 150)); path.addLine(to: CGPoint(x: 318, y: 222))
            path.move(to: CGPoint(x: 262, y: 192)); path.addLine(to: CGPoint(x: 326, y: 246))
            for index in 0..<4 {
                let offset = CGFloat(index) * 12
                path.move(to: CGPoint(x: 276 + offset, y: 168 + offset * 0.95))
                path.addLine(to: CGPoint(x: 282 + offset, y: 196 + offset * 0.95))
            }
            // Wrist, gripper and the tool point.
            path.addEllipse(in: CGRect(x: 310, y: 224, width: 24, height: 24))
            path.move(to: CGPoint(x: 316, y: 248)); path.addLine(to: CGPoint(x: 308, y: 284)); path.addLine(to: CGPoint(x: 314, y: 290))
            path.move(to: CGPoint(x: 328, y: 248)); path.addLine(to: CGPoint(x: 336, y: 284)); path.addLine(to: CGPoint(x: 330, y: 290))
            path.addEllipse(in: CGRect(x: 313, y: 296, width: 18, height: 18))
            path.move(to: CGPoint(x: 322, y: 288)); path.addLine(to: CGPoint(x: 322, y: 322))
            path.move(to: CGPoint(x: 304, y: 305)); path.addLine(to: CGPoint(x: 340, y: 305))
            return path
        }
    }

    struct ReachArc: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addArc(center: CGPoint(x: 110, y: 290), radius: 225, startAngle: .degrees(-65), endAngle: .degrees(10), clockwise: false)
            return path
        }
    }

    struct CropMarks: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            for (x, y, dx, dy) in [(8.0, 8.0, 1.0, 1.0), (352.0, 8.0, -1.0, 1.0), (8.0, 452.0, 1.0, -1.0), (352.0, 452.0, -1.0, -1.0)] {
                path.move(to: CGPoint(x: x, y: y + dy * 14)); path.addLine(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + dx * 14, y: y))
            }
            return path
        }
    }
}
