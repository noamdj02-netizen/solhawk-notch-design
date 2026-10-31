import SwiftUI

/// Petite animation au lancement, dans la barre : une bougie après l'autre, une courbe verte qui monte (une bourse qui grimpe),
/// pendant que Hawky sort. Pure fonction du temps écoulé depuis le lancement ; elle s'efface seule. Décor : ce n'est pas une donnée.
struct LaunchIntro: View {
    /// Secondes depuis le lancement.
    var age: Double
    static let duration = 3.0

    var body: some View {
        Canvas { ctx, size in
            let n = 14
            let grow = min(1, age / 1.9)
            let fade = age < 2.4 ? 1 : max(0, 1 - (age - 2.4) / 0.6)
            guard fade > 0 else { return }
            let w = size.width, h = size.height
            let gap = w / CGFloat(n)
            var line = Path()
            var tip = CGPoint.zero
            for i in 0..<n {
                let u = Double(i) / Double(n - 1)
                guard u <= grow else { break }
                // tendance haussière avec de petits creux (suite fixe : toujours la même animation)
                let wob = [0.0, 0.10, -0.06, 0.12, -0.10, 0.05, 0.14, -0.08, 0.09, -0.05, 0.12, 0.03, 0.10, 0.0][i]
                let lvl = 0.16 + 0.70 * pow(u, 1.15) + wob * 0.25
                let x = gap * (CGFloat(i) + 0.5)
                let top = h * (1 - CGFloat(lvl))
                let open = h * (1 - CGFloat(lvl - 0.07 * (wob >= 0 ? 1 : -1)))
                let up = wob >= 0
                let col = up ? Color(red: 0.2, green: 0.85, blue: 0.5) : Color(red: 0.95, green: 0.3, blue: 0.3)
                let a = CGFloat(min(1, (grow - u) * 6))
                var bar = ctx; bar.opacity = Double(a) * fade * 0.85
                bar.fill(Path(roundedRect: CGRect(x: x - gap * 0.28, y: min(top, open), width: gap * 0.56, height: max(2, abs(open - top))), cornerRadius: 1.5), with: .color(col))
                var wick = Path(); wick.move(to: CGPoint(x: x, y: top - 3)); wick.addLine(to: CGPoint(x: x, y: max(top, open) + 3))
                bar.stroke(wick, with: .color(col), lineWidth: 1)
                tip = CGPoint(x: x, y: top - 3)
                if i == 0 { line.move(to: tip) } else { line.addLine(to: tip) }
            }
            var l = ctx; l.opacity = fade
            l.addFilter(.shadow(color: Color(red: 0.2, green: 0.85, blue: 0.5).opacity(0.8), radius: 4))
            l.stroke(line, with: .color(Color(red: 0.55, green: 1.0, blue: 0.75)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            if grow > 0 { l.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(.white)) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
