import AppKit
import Foundation
import Observation
import SolHawkNotchCore

/// Position de la souris, normalisée par rapport au personnage. Lecture seule de NSEvent.mouseLocation (aucun hook global).
@MainActor @Observable
final class Gaze {
    var look = CGPoint.zero
    var enabled = true
    @ObservationIgnored var center: () -> CGPoint = { .zero }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastMouse = CGPoint.zero
    @ObservationIgnored private var lastMoveAt = Date.distantPast

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        look = .zero
    }

    private func tick() {
        guard enabled else {
            if look != .zero { look = .zero }
            return
        }
        let m = NSEvent.mouseLocation, c = center()
        if hypot(m.x - lastMouse.x, m.y - lastMouse.y) > 2.5 {
            lastMouse = m
            lastMoveAt = Date()
        }
        // Il suit le curseur tant qu'il est dans l'écran, même immobile (plus de retour au centre après 1,7 s).
        let target = HawkyLook.screenTarget(mouse: m, center: c, idle: false)
        look.x += (target.x - look.x) * 0.28
        look.y += (target.y - look.y) * 0.28
        if hypot(look.x, look.y) < 0.012 { look = .zero }
    }
}
