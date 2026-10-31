import Testing
@testable import SolHawkNotchCore

@Suite struct MascotStatusTests {
    @Test func reactionWinsOverEverything() {
        #expect(mascotStatus(mood: .offline, signal: .red, reaction: .soldWin).dot == .green)
        #expect(mascotStatus(mood: .calm(listed: 2), signal: .none, reaction: .soldLoss).dot == .red)
    }
    @Test func failuresAreRedAndNeverGreen() {
        for m in [Mood.offline, .tokenRejected, .badConfig] { #expect(mascotStatus(mood: m, signal: .green, reaction: nil).dot == .red) }
    }
    @Test func greenBarIsNotSafe() {
        let s = mascotStatus(mood: .calm(listed: 1), signal: .green, reaction: nil)
        #expect(s.dot == .green)
        #expect(!s.text.lowercased().contains("sûr") && !s.text.lowercased().contains("bon"))
    }
    @Test func quietIsQuiet() {
        #expect(mascotStatus(mood: .calm(listed: 0), signal: .none, reaction: nil) == MascotStatus(dot: .none, text: "Rien à signaler"))
        #expect(mascotStatus(mood: .calm(listed: 3), signal: .none, reaction: nil).text == "3 tokens en vue")
        #expect(mascotStatus(mood: .stale(ageS: 99), signal: .none, reaction: nil).dot == .gray)
    }
}
