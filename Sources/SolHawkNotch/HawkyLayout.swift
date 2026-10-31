import CoreGraphics
import SwiftUI

/// Pose « accoudé ». Yeux = fractions de HawkyPeek (880×656), pas du cadre carré.
enum HawkyLayout {
    static let peekAspect: CGFloat = 880 / 656
    /// Centres des iris peints sur HawkyPeek.png (mesurés sur l'image : l'œil droit est vu de trois quarts, donc plus étroit).
    /// Si ces valeurs ne tombent pas sur les iris de l'image, on voit un 3e œil : les revérifier après tout changement d'image.
    static let leftEye = CGPoint(x: 0.447, y: 0.688)
    static let rightEye = CGPoint(x: 0.802, y: 0.628)
    static let leftEyeFrac = CGSize(width: 0.178, height: 0.258)
    static let rightEyeFrac = CGSize(width: 0.136, height: 0.244)

    static func scale(in size: CGSize) -> CGFloat { min(size.width, size.height) }

    static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.56)
    }

    static func eyeCenter(side: CGFloat, s: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + side * s * 0.158, y: origin.y + s * 0.028)
    }

    static func eyeWidth(_ s: CGFloat) -> CGFloat { max(8, s * 0.28) }
    static func eyeHeight(_ s: CGFloat) -> CGFloat { max(9, s * 0.33) }

    static func peekEyeCenter(side: CGFloat, in size: CGSize) -> CGPoint {
        let f = side < 0 ? leftEye : rightEye
        return CGPoint(x: f.x * size.width, y: f.y * size.height)
    }

    static func peekEyeSize(side: CGFloat, in size: CGSize) -> CGSize {
        let f = side < 0 ? leftEyeFrac : rightEyeFrac
        return CGSize(width: f.width * size.width, height: f.height * size.height)
    }
}
