import CoreGraphics
import Foundation

// Jeu d'acteur de Hawky : petits objets dessinés autour de lui (étoiles, larme, « ! », zzz…) et regard imposé selon l'émotion.
// Fonctions PURES du temps (aucun minuteur) : la vue les recalcule à chaque image. Ce sont des humeurs, jamais un conseil de trade.
// Coordonnées : fractions de la largeur de l'image (x : 0 gauche … 1 droite ; y : 0 haut …).

public struct HawkyParticle: Equatable, Sendable {
    public enum Kind: String, Sendable { case star, spark, tear, bang, question, zee, bill }
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var size: Double
    public var alpha: Double
    public var rot: Double
    /// Rouge pour l'alerte, sinon couleur par défaut du genre.
    public var red = false
}

public enum HawkyActing {
    /// Yeux (fractions de la largeur) : gauche, droit.
    public static let leftEye = CGPoint(x: 0.4045, y: 0.507)
    public static let rightEye = CGPoint(x: 0.783, y: 0.485)

    /// Regard imposé par l'émotion (nil = suivre le curseur).
    public static func gaze(_ e: HawkyExpression, at t: Double) -> CGPoint? {
        switch e {
        case .thinking: return CGPoint(x: 0.42 + 0.04 * sin(t * 0.9), y: -0.50)
        case .concerned: return CGPoint(x: 0.28 * sin(t * 0.7), y: 0.55)
        case .loading: return CGPoint(x: 0.62 * cos(t * 3.4), y: 0.50 * sin(t * 3.4))
        default: return nil
        }
    }

    /// Objets à dessiner. `age` : secondes depuis le début de l'émotion si on le sait (réaction, nouveau token), sinon nil (boucle sur `t`).
    public static func particles(_ e: HawkyExpression, age: Double?, t: Double) -> [HawkyParticle] {
        var out: [HawkyParticle] = []
        switch e {
        case .celebration:
            let a = age ?? t.truncatingRemainder(dividingBy: 2.2)
            for i in 0..<9 {
                let u = a - Double(i) * 0.09
                guard u > 0, u < 1.25 else { continue }
                let side = Double(i % 2 == 0 ? -1 : 1)
                let spread = 0.10 + 0.05 * Double(i / 2)
                let x = 0.5 + side * spread + side * 0.16 * u
                let y = 0.20 - 0.30 * u + 0.20 * u * u        // jaillit puis retombe
                let k = u / 1.25
                out.append(HawkyParticle(kind: i % 3 == 2 ? .spark : .star, x: x, y: y, size: 0.034 + 0.012 * Double(i % 3),
                                         alpha: envelope(k), rot: Double(i) * 1.3 + u * 3))
            }
            if let a = age { out += bills(rising: true, age: a) }
        case .surprise:
            let a = age ?? (0.4 + 0.4 * sin(t * 2))
            let pop = a < 0.18 ? max(0, backOut(a / 0.18)) : 1.0
            out.append(HawkyParticle(kind: .bang, x: 0.90, y: 0.16 - 0.01 * sin(t * 12), size: 0.10 * pop, alpha: a > 1.5 ? max(0, 1 - (a - 1.5) / 0.3) : 1, rot: 0.25))
        case .critical:
            out.append(HawkyParticle(kind: .bang, x: 0.90, y: 0.15, size: 0.095, alpha: 0.65 + 0.35 * sin(t * 8), rot: 0.2, red: true))
        case .thinking:
            out.append(HawkyParticle(kind: .question, x: 0.88, y: 0.16 + 0.012 * sin(t * 2.2), size: 0.095, alpha: 0.9, rot: -0.15))
        case .concerned:
            if let a = age { out += bills(rising: false, age: a) }
            // une larme coule de chaque œil, en décalé
            for (i, eye) in [leftEye, rightEye].enumerated() {
                let period = 2.6, ph = (t + Double(i) * 1.3).truncatingRemainder(dividingBy: period) / period
                let fall = ph * ph
                out.append(HawkyParticle(kind: .tear, x: eye.x + (i == 0 ? -0.045 : 0.03), y: eye.y + 0.075 + 0.17 * fall,
                                         size: 0.034 * (0.6 + 0.6 * min(1, ph * 4)), alpha: ph < 0.1 ? ph / 0.1 : max(0, 1 - max(0, ph - 0.75) / 0.25), rot: 0))
            }
        case .sleep:
            for i in 0..<3 {
                let period = 3.3, ph = (t + Double(i) * 1.1).truncatingRemainder(dividingBy: period) / period
                out.append(HawkyParticle(kind: .zee, x: 0.84 + 0.07 * ph, y: 0.30 - 0.22 * ph, size: 0.05 + 0.04 * ph, alpha: envelope(ph), rot: 0.2))
            }
        case .happy:
            if let a = age {                      // étincelles qui jaillissent (achat fictif, barre verte)
                for i in 0..<6 {
                    let u = a - Double(i) * 0.07
                    guard u > 0, u < 1.0 else { continue }
                    let ang = Double(i) / 6 * 2 * .pi + 0.4
                    out.append(HawkyParticle(kind: i % 2 == 0 ? .star : .spark, x: 0.5 + cos(ang) * (0.18 + 0.22 * u), y: 0.28 + sin(ang) * (0.10 + 0.16 * u) - 0.05 * u,
                                             size: 0.03 + 0.01 * Double(i % 3), alpha: envelope(u), rot: ang + u * 4))
                }
            }
            for i in 0..<2 {
                let ph = (t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                out.append(HawkyParticle(kind: .spark, x: i == 0 ? 0.90 : 0.10, y: 0.30 - 0.04 * Double(i), size: 0.034 * sin(.pi * ph), alpha: sin(.pi * ph), rot: ph * 3))
            }
        default: break
        }
        return out
    }

    /// Billets : ils s'envolent vers le haut (gain, `rising`) ou tombent en tournoyant (perte). Des billets de jeu : la simulation est fictive.
    static func bills(rising: Bool, age: Double) -> [HawkyParticle] {
        var out: [HawkyParticle] = []
        for i in 0..<8 {
            let delay = Double(i) * 0.11
            let dur = rising ? 1.7 : 1.6
            let u = (age - delay) / dur
            guard u > 0, u < 1 else { continue }
            let seed = Double(i) * 2.399
            let x0 = rising ? 0.5 + 0.30 * sin(seed) : 0.5 + 0.28 * sin(seed)
            let sway = 0.045 * sin(u * 7 + seed)
            let y: Double
            if rising { y = 0.62 - 0.55 * (1 - pow(1 - u, 2)) }        // part des pattes, monte en ralentissant
            else { y = 0.07 + 0.70 * pow(u, 1.7) }                       // part du haut, accélère en tombant
            let fade = rising ? max(0, min(1, (1 - u) / 0.3)) : max(0, min(1, (1 - u) / 0.25))
            out.append(HawkyParticle(kind: .bill, x: x0 + sway, y: y, size: 0.064, alpha: min(1, u * 8) * fade, rot: sin(u * 5 + seed) * 0.7 + (rising ? 0 : u * 2.5)))
        }
        return out
    }

    static func envelope(_ k: Double) -> Double { k < 0.2 ? k / 0.2 : max(0, 1 - (k - 0.2) / 0.8) }
    static func backOut(_ x: Double) -> Double { let c = 1.7; return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }
}
