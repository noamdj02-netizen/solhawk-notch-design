import SwiftUI
import AppKit
import SolHawkNotchCore

/// Journal d'un trade : mes mots, après coup. Enregistré sur ce Mac avec le portefeuille fictif, jamais envoyé nulle part.
struct JournalPanel: View {
    var t: PaperTrade
    var lab: PaperLab
    @State private var note = ""
    @State private var tag: String?
    @State private var saved = false

    var body: some View {
        Panel(title: "Mon journal", trailing: saved ? "enregistré" : "ce que j'ai appris") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(JournalTag.allCases, id: \.rawValue) { g in
                        let on = tag == g.rawValue
                        Button { tag = on ? nil : g.rawValue; saved = false } label: {
                            Text(g.rawValue).font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(on ? Color.white.opacity(0.22) : .white.opacity(0.07)))
                                .foregroundStyle(on ? .white : .white.opacity(0.65))
                        }.buttonStyle(PressStyle())
                    }
                    Spacer()
                }
                TextField("Pourquoi j'ai acheté, ce que j'aurais dû voir… (500 caractères)", text: $note, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white).lineLimit(2...6)
                    .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                    .onChange(of: note) { _, _ in saved = false }
                HStack {
                    Text("Ces mots restent sur ton Mac. Ils ne sont pas des règles.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button {
                        saved = lab.setJournal(t.id, note: note, tag: tag)
                    } label: {
                        Text("Enregistrer").font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.16))).foregroundStyle(.white)
                    }.buttonStyle(PressStyle())
                }
            }
        }
        .onAppear { note = t.journal ?? ""; tag = t.tag }
        .id(t.id)
    }
}

/// Export CSV des trades fictifs (tu choisis où l'enregistrer). Aucune donnée n'est envoyée ailleurs.
@MainActor func exportTradesCSV(_ rows: [(owner: String, trade: PaperTrade)], ui: UIState) {
    guard !rows.isEmpty else { ui.flash("Aucun trade à exporter"); return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "solhawk-trades-fictifs.csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.message = "Export de tes trades fictifs (simulation)."
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try TradeExport.csv(rows).write(to: url, atomically: true, encoding: .utf8); ui.flash("CSV enregistré") }
    catch { ui.flash("Export impossible : \(error.localizedDescription)") }
}
