import SwiftUI
import SolHawkNotchCore

// Hawky, le chat à capuche, dessiné en code (aucune image). Repère fixe 880×656 : le Canvas met tout à l'échelle.
// Les couches se décalent vers le curseur à des profondeurs différentes (oreilles < capuche < visage < yeux < museau) :
// on a l'impression qu'il TOURNE la tête vers la souris. Tout est une fonction du temps (TimelineView parent) : aucun minuteur.

enum HawkyStageMetrics {
    static let imageSize = CGSize(width: 880, height: 656)
}

struct HawkyStage: View {
    var expression: HawkyExpression
    var pose: HawkyPose
    var leftLook: CGPoint
    var rightLook: CGPoint
    var date: Date
    var age: Double?

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let k = size.width / HawkyStageMetrics.imageSize.width
            var c = ctx
            c.scaleBy(x: k, y: k)
            draw(&c, t: date.timeIntervalSinceReferenceDate)
            for p in HawkyActing.particles(expression, age: age, t: date.timeIntervalSinceReferenceDate) {
                drawParticle(ctx, p, w: size.width)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: palette
    private let rim = Color(red: 0.05, green: 0.04, blue: 0.04)
    private let ink = Color(red: 0.043, green: 0.047, blue: 0.055)
    private let hoodTop = Color(red: 0.36, green: 0.23, blue: 0.15)
    private let hoodBottom = Color(red: 0.16, green: 0.09, blue: 0.06)
    private let faceLight = Color(red: 0.97, green: 0.88, blue: 0.75)
    private let faceDark = Color(red: 0.88, green: 0.75, blue: 0.58)
    private let earOrange = Color(red: 0.96, green: 0.55, blue: 0.22)
    private let earLight = Color(red: 1.0, green: 0.77, blue: 0.52)
    private let skin = Color(red: 0.93, green: 0.82, blue: 0.68)
    private let nose = Color(red: 0.55, green: 0.29, blue: 0.24)

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    // MARK: corps du dessin

    private func draw(_ ctx: inout GraphicsContext, t: Double) {
        let look = CGPoint(x: (leftLook.x + rightLook.x) / 2, y: (leftLook.y + rightLook.y) / 2)
        let reach: CGFloat = 40
        func shift(_ depth: CGFloat) -> CGSize { CGSize(width: look.x * reach * depth, height: look.y * reach * 0.7 * depth) }
        func layer(_ depth: CGFloat, _ body: (inout GraphicsContext) -> Void) {
            var c = ctx
            let s = shift(depth)
            c.translateBy(x: s.width, y: s.height)
            body(&c)
        }
        let twitch = pow(max(0, sin(t * 0.83)), 24) * 0.14
        let perk: CGFloat = pose.eyeScale > 1.05 ? 1.10 : 1
        let earTurn = CGFloat(pose.slant) * 0.20 + CGFloat(-pose.slant < -0.5 ? 0 : 0)

        layer(0.25) { c in
            ear(&c, mirrored: false, rot: -twitch + earTurn, perk: perk)
            ear(&c, mirrored: true, rot: -twitch * 0.4 + earTurn, perk: perk)
        }
        layer(0.35) { c in hood(&c) }
        layer(0.7) { c in face(&c) }
        layer(1.0) { c in
            cheeks(&c)
            eye(&c, cx: 292, cy: 412, rx: 98, ry: 104, rot: -7, look: leftLook, outer: -1)
            eye(&c, cx: 588, cy: 408, rx: 90, ry: 100, rot: 5, look: rightLook, outer: 1)
            brows(&c)
        }
        layer(1.25) { c in muzzle(&c, t: t) }
        layer(0.1) { c in paws(&c, t: t) }
    }

    private func ear(_ ctx: inout GraphicsContext, mirrored: Bool, rot: Double, perk: CGFloat) {
        var c = ctx
        if mirrored { c.translateBy(x: 880, y: 0); c.scaleBy(x: -1, y: 1) }
        c.translateBy(x: 200, y: 250)
        c.rotate(by: .radians(rot))
        c.scaleBy(x: 1, y: perk)
        c.translateBy(x: -200, y: -250)
        var outer = Path()
        outer.move(to: CGPoint(x: 70, y: 340))
        outer.addQuadCurve(to: CGPoint(x: 96, y: 52), control: CGPoint(x: 40, y: 160))
        outer.addQuadCurve(to: CGPoint(x: 330, y: 170), control: CGPoint(x: 230, y: 40))
        outer.closeSubpath()
        c.fill(outer, with: .linearGradient(Gradient(colors: [hoodTop, hoodBottom]), startPoint: CGPoint(x: 80, y: 60), endPoint: CGPoint(x: 260, y: 300)))
        var inner = Path()
        inner.move(to: CGPoint(x: 118, y: 290))
        inner.addQuadCurve(to: CGPoint(x: 128, y: 112), control: CGPoint(x: 96, y: 180))
        inner.addQuadCurve(to: CGPoint(x: 268, y: 184), control: CGPoint(x: 200, y: 108))
        inner.closeSubpath()
        c.fill(inner, with: .linearGradient(Gradient(colors: [earOrange, earLight]), startPoint: CGPoint(x: 120, y: 120), endPoint: CGPoint(x: 230, y: 280)))
    }

    private func hood(_ c: inout GraphicsContext) {
        let dome = ellipse(440, 400, 400, 345)
        c.fill(dome, with: .linearGradient(Gradient(colors: [hoodTop, hoodBottom]), startPoint: CGPoint(x: 300, y: 40), endPoint: CGPoint(x: 560, y: 660)))
        // reflet doux sur le dessus et pli de tissu
        var hl = Path()
        for i in 0...20 {
            let a = Angle.degrees(205 + Double(i) * 4).radians
            let pt = CGPoint(x: 440 + 372 * cos(a), y: 400 + 318 * sin(a))
            if i == 0 { hl.move(to: pt) } else { hl.addLine(to: pt) }
        }
        c.stroke(hl, with: .color(Color(red: 0.62, green: 0.42, blue: 0.28).opacity(0.55)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
        var crease = Path()
        crease.move(to: CGPoint(x: 560, y: 70))
        crease.addQuadCurve(to: CGPoint(x: 700, y: 210), control: CGPoint(x: 640, y: 100))
        c.stroke(crease, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
    }

    private func face(_ c: inout GraphicsContext) {
        let f = ellipse(440, 450, 335, 230)
        c.fill(f, with: .radialGradient(Gradient(colors: [faceLight, faceDark]), center: CGPoint(x: 420, y: 400), startRadius: 20, endRadius: 360))
        // l'ombre du bord de capuche sur le front
        var cl = c
        cl.clip(to: f)
        cl.fill(Path(CGRect(x: 80, y: 200, width: 720, height: 150)), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.38), .clear]), startPoint: CGPoint(x: 0, y: 220), endPoint: CGPoint(x: 0, y: 340)))
    }

    private func cheeks(_ c: inout GraphicsContext) {
        let a = max(pose.lidBottom * 1.4, pose.arcs, pose.mouth == .smile ? 0.5 : 0)
        guard a > 0.01 else { return }
        var b = c
        b.opacity = min(0.55, a * 0.6)
        for x in [190.0, 690.0] { b.fill(ellipse(x, 522, 44, 24), with: .color(Color(red: 1.0, green: 0.55, blue: 0.5))) }
    }

    private func brows(_ c: inout GraphicsContext) {
        guard pose.arcs < 0.5, pose.lid < 0.9, abs(pose.slant) > 0.15 || pose.brow != 0 else { return }
        let lift = CGFloat(pose.brow) * 34
        for (cx, outer) in [(292.0, -1.0), (588.0, 1.0)] {
            var p = Path()
            let y = 292 - lift
            let drop = CGFloat(pose.slant) * 22 * outer      // triste : coin extérieur vers le bas
            p.move(to: CGPoint(x: cx - 62, y: y + (outer < 0 ? drop : -drop)))
            p.addLine(to: CGPoint(x: cx + 62, y: y + (outer < 0 ? -drop : drop)))
            c.stroke(p, with: .color(hoodBottom), style: StrokeStyle(lineWidth: 17, lineCap: .round))
        }
    }

    private func muzzle(_ c: inout GraphicsContext, t: Double) {
        var n = Path()
        n.move(to: CGPoint(x: 418, y: 472))
        n.addQuadCurve(to: CGPoint(x: 462, y: 472), control: CGPoint(x: 440, y: 464))
        n.addQuadCurve(to: CGPoint(x: 440, y: 498), control: CGPoint(x: 462, y: 490))
        n.addQuadCurve(to: CGPoint(x: 418, y: 472), control: CGPoint(x: 418, y: 490))
        c.fill(n, with: .color(nose))
        c.fill(ellipse(434, 473, 7, 3.5), with: .color(.white.opacity(0.35)))
        let line = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        var m = Path()
        switch pose.mouth {
        case .none:
            m.move(to: CGPoint(x: 428, y: 516)); m.addLine(to: CGPoint(x: 452, y: 516))
        case .line:
            m.move(to: CGPoint(x: 440, y: 498)); m.addLine(to: CGPoint(x: 440, y: 508))
            m.move(to: CGPoint(x: 410, y: 512)); m.addQuadCurve(to: CGPoint(x: 440, y: 508), control: CGPoint(x: 425, y: 520))
            m.addQuadCurve(to: CGPoint(x: 470, y: 512), control: CGPoint(x: 455, y: 520))
        case .smile:
            m.move(to: CGPoint(x: 440, y: 498)); m.addLine(to: CGPoint(x: 440, y: 508))
            m.move(to: CGPoint(x: 394, y: 508)); m.addQuadCurve(to: CGPoint(x: 440, y: 508), control: CGPoint(x: 416, y: 538))
            m.addQuadCurve(to: CGPoint(x: 486, y: 508), control: CGPoint(x: 464, y: 538))
        case .frown:
            m.move(to: CGPoint(x: 440, y: 498)); m.addLine(to: CGPoint(x: 440, y: 510))
            m.move(to: CGPoint(x: 402, y: 532)); m.addQuadCurve(to: CGPoint(x: 440, y: 510), control: CGPoint(x: 418, y: 506))
            m.addQuadCurve(to: CGPoint(x: 478, y: 532), control: CGPoint(x: 462, y: 506))
        case .oh:
            c.fill(ellipse(440, 530, 17, 22), with: .color(Color(red: 0.35, green: 0.12, blue: 0.12)))
            return
        case .grin:
            var g = Path()
            g.move(to: CGPoint(x: 392, y: 506))
            g.addQuadCurve(to: CGPoint(x: 488, y: 506), control: CGPoint(x: 440, y: 510))
            g.addQuadCurve(to: CGPoint(x: 392, y: 506), control: CGPoint(x: 440, y: 590))
            c.fill(g, with: .color(Color(red: 0.35, green: 0.12, blue: 0.12)))
            var tg = c; tg.clip(to: g)
            tg.fill(ellipse(440, 556, 26, 16), with: .color(Color(red: 1.0, green: 0.5, blue: 0.5)))
            return
        }
        c.stroke(m, with: .color(nose), style: line)
    }

    private func paws(_ c: inout GraphicsContext, t: Double) {
        for (cx, mir) in [(262.0, 1.0), (618.0, -1.0)] {
            let lift: CGFloat = expression == .celebration ? CGFloat(abs(sin(t * 5 + (mir > 0 ? 0 : 1.6)))) * 22 : 0
            let p = ellipse(cx, 634 - lift, 98, 54)
            c.fill(p, with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.82), Color(red: 0.88, green: 0.72, blue: 0.55)]),
                                            center: CGPoint(x: cx - 10, y: 616 - lift), startRadius: 4, endRadius: 100))
            for dx in [-30.0, 0.0, 30.0] {
                var l = Path()
                l.move(to: CGPoint(x: cx + dx, y: 622 - lift)); l.addLine(to: CGPoint(x: cx + dx, y: 646 - lift))
                c.stroke(l, with: .color(Color(red: 0.55, green: 0.38, blue: 0.27).opacity(0.7)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
        }
    }

    // MARK: œil

    private func eye(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: Double, look: CGPoint, outer: Double) {
        var c = ctx
        c.translateBy(x: cx, y: cy)
        c.rotate(by: .degrees(rot))
        let blink = HawkyBlink.lid(at: date.addingTimeInterval(outer > 0 ? 0.02 : 0))
        let lidAmt = min(1, max(pose.lid, blink))
        let closedness = max(pose.arcs, lidAmt > 0.9 ? lidAmt : 0)
        let g = HawkyLook.clamp(look, maxR: 1)

        // œil ouvert (s'efface quand il se ferme en arc)
        var e = c
        e.opacity = 1 - min(1, closedness)
        e.fill(ellipse(0, 0, rx + 11, ry + 10), with: .color(rim))
        var inner = e
        inner.clip(to: ellipse(0, 0, rx, ry))
        inner.fill(ellipse(0, 0, rx, ry), with: .radialGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.93), Color(red: 0.96, green: 0.91, blue: 0.86), Color(red: 0.80, green: 0.72, blue: 0.67)]),
            center: .zero, startRadius: 0, endRadius: max(rx, ry) * 1.08))
        inner.fill(Path(CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 0.9)), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.28), .clear]), startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: -ry * 0.1)))

        // « trop de requêtes » : yeux en spirale qui tournent (il est dépassé)
        if expression == .loading {
            var sp = inner
            sp.rotate(by: .radians(date.timeIntervalSinceReferenceDate * 5 * (outer > 0 ? -1 : 1)))
            var path = Path()
            let turns = 3.2, steps = 90
            for i in 0...steps {
                let u = Double(i) / Double(steps)
                let a = u * turns * 2 * .pi, r = u * min(rx, ry) * 0.82
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            sp.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: max(4, rx * 0.09), lineCap: .round, lineJoin: .round))
        }

        // iris + pupille : grande course, bien visible
        let sc = CGFloat(pose.eyeScale)
        let irx = rx * 0.78 * sc, iry = ry * 0.82 * sc
        let ic = CGPoint(x: g.x * rx * 0.36, y: g.y * ry * 0.30)
        var iris = inner
        if expression == .loading { iris.opacity = 0 }
        iris.translateBy(x: ic.x, y: ic.y)
        iris.fill(ellipse(0, 0, irx, iry), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 1.0, green: 0.74, blue: 0.36), location: 0),
                .init(color: Color(red: 1.0, green: 0.48, blue: 0.18), location: 0.42),
                .init(color: Color(red: 0.62, green: 0.24, blue: 0.07), location: 0.80),
                .init(color: Color(red: 0.20, green: 0.07, blue: 0.03), location: 1),
            ]),
            center: CGPoint(x: 0, y: iry * 0.55), startRadius: 0, endRadius: iry * 1.15))
        var pupil = iris
        pupil.translateBy(x: g.x * irx * 0.07, y: g.y * iry * 0.07 - iry * 0.03)
        pupil.fill(ellipse(0, 0, irx * 0.64 * CGFloat(pose.pupil), iry * 0.68 * CGFloat(pose.pupil)), with: .color(ink))
        var hl = inner
        if expression == .loading { hl.opacity = 0.5 }
        hl.translateBy(x: ic.x * 0.5, y: ic.y * 0.5)
        hl.fill(ellipse(rx * 0.16, -ry * 0.38, ry * 0.115, ry * 0.115), with: .color(.white))
        hl.fill(ellipse(-rx * 0.34, ry * 0.36, ry * 0.045, ry * 0.045), with: .color(Color(red: 1, green: 0.85, blue: 0.62).opacity(0.85)))

        // paupière du haut (mi-close, ou inclinée : triste / sévère) et du bas (sourire des yeux)
        if lidAmt > 0.001 || abs(pose.slant) > 0.001 {
            var edge: [CGPoint] = []
            for i in 0...24 {
                let u = Double(i) / 24 * 2 - 1
                var y = -ry + 2 * ry * lidAmt + pose.slant * 0.55 * ry * (outer * u)
                y = max(-ry * 1.4, min(ry * 1.4, y))
                edge.append(CGPoint(x: u * rx * 1.15, y: y))
            }
            var p = Path()
            p.move(to: CGPoint(x: -rx * 1.15, y: -ry * 1.5)); p.addLine(to: CGPoint(x: rx * 1.15, y: -ry * 1.5))
            for pt in edge.reversed() { p.addLine(to: pt) }
            p.closeSubpath()
            inner.fill(p, with: .color(skin))
            var line = Path(); line.addLines(edge)
            inner.stroke(line, with: .color(rim), style: StrokeStyle(lineWidth: max(3, rx * 0.06), lineCap: .round, lineJoin: .round))
        }
        if pose.lidBottom > 0.001 {
            let top = ry - 2 * ry * CGFloat(pose.lidBottom)
            var p = Path()
            p.move(to: CGPoint(x: -rx * 1.2, y: ry * 1.5)); p.addLine(to: CGPoint(x: -rx * 1.2, y: top + ry * 0.25))
            p.addQuadCurve(to: CGPoint(x: rx * 1.2, y: top + ry * 0.25), control: CGPoint(x: 0, y: top - ry * 0.35))
            p.addLine(to: CGPoint(x: rx * 1.2, y: ry * 1.5)); p.closeSubpath()
            inner.fill(p, with: .color(skin))
        }

        // œil fermé : arc « ^^ » (très content) ou arc de sommeil
        if closedness > 0.01 {
            var arc = Path()
            if pose.arcs > 0.5 {
                arc.addArc(center: CGPoint(x: 0, y: ry * 0.45), radius: rx * 0.72, startAngle: .degrees(198), endAngle: .degrees(342), clockwise: false)
            } else {
                arc.addArc(center: CGPoint(x: 0, y: -ry * 0.25), radius: rx * 0.78, startAngle: .degrees(22), endAngle: .degrees(158), clockwise: false)
            }
            var l = c
            l.opacity = min(1, closedness)
            l.stroke(arc, with: .color(rim), style: StrokeStyle(lineWidth: max(4, rx * 0.15), lineCap: .round))
        }
    }

    // MARK: objets autour de lui

    private func star(_ outer: CGFloat, _ innerR: CGFloat, points n: Int) -> Path {
        var p = Path()
        for i in 0..<(n * 2) {
            let r = i % 2 == 0 ? outer : innerR
            let a = Double(i) * .pi / Double(n) - .pi / 2
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func drawParticle(_ ctx: GraphicsContext, _ p: HawkyParticle, w: CGFloat) {
        guard p.alpha > 0.01, p.size > 0.001 else { return }
        var c = ctx
        c.translateBy(x: p.x * w, y: p.y * w)
        c.rotate(by: .radians(p.rot))
        c.opacity = min(1, p.alpha)
        let s = p.size * w
        switch p.kind {
        case .star:
            c.fill(star(s, s * 0.45, points: 5), with: .color(Color(red: 1.0, green: 0.78, blue: 0.2)))
        case .spark:
            c.fill(star(s * 0.9, s * 0.2, points: 4), with: .color(.white))
        case .tear:
            var d = Path()
            d.move(to: CGPoint(x: 0, y: -s))
            d.addQuadCurve(to: CGPoint(x: 0, y: s * 0.7), control: CGPoint(x: s * 0.95, y: s * 0.25))
            d.addQuadCurve(to: CGPoint(x: 0, y: -s), control: CGPoint(x: -s * 0.95, y: s * 0.25))
            c.fill(d, with: .color(Color(red: 0.49, green: 0.78, blue: 1.0)))
            c.fill(ellipse(-s * 0.2, s * 0.05, s * 0.14, s * 0.14), with: .color(.white.opacity(0.8)))
        case .bill:
            // billet vert qui se retourne en tombant ou en s'envolant
            let flip = 0.35 + 0.65 * abs(cos(p.rot * 1.9))
            c.scaleBy(x: 1, y: flip)
            let r = CGRect(x: -s, y: -s * 0.55, width: s * 2, height: s * 1.1)
            c.fill(Path(roundedRect: r, cornerRadius: s * 0.14), with: .linearGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.85, blue: 0.5), Color(red: 0.27, green: 0.62, blue: 0.34)]),
                startPoint: CGPoint(x: 0, y: -s * 0.55), endPoint: CGPoint(x: 0, y: s * 0.55)))
            c.stroke(Path(roundedRect: r.insetBy(dx: s * 0.1, dy: s * 0.1), cornerRadius: s * 0.1), with: .color(.white.opacity(0.55)), lineWidth: max(1, s * 0.06))
            c.fill(ellipse(0, 0, s * 0.32, s * 0.32), with: .color(Color(red: 0.16, green: 0.42, blue: 0.22).opacity(0.9)))
            c.draw(Text("$").font(.system(size: s * 0.55, weight: .heavy, design: .rounded)).foregroundColor(.white), at: .zero)
        case .bang, .question:
            let col = p.red ? Color(red: 0.94, green: 0.27, blue: 0.27) : (p.kind == .bang ? Color(red: 1.0, green: 0.55, blue: 0.2) : Color.white.opacity(0.92))
            c.draw(Text(p.kind == .bang ? "!" : "?").font(.system(size: s * 2.2, weight: .heavy, design: .rounded)).foregroundColor(col), at: .zero)
        case .zee:
            c.draw(Text("z").font(.system(size: s * 2.0, weight: .bold, design: .rounded)).foregroundColor(Color(red: 0.82, green: 0.86, blue: 0.95)), at: .zero)
        }
    }
}
