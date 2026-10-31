import SwiftUI
import SolHawkNotchCore

/// Recherche universelle (⌘K ou « / ») : pages, tokens listés, adresse collée, mots du glossaire. Lecture seule : rien ne s'achète ici.
struct PaletteView: View {
    var store: FeedStore
    var ui: UIState
    @Environment(MarketStore.self) private var market
    @State private var query = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_PALETTE"] ?? ""   // (essais visuels)
    @State private var sel = 0
    @FocusState private var focused: Bool

    private var tokens: [PaletteToken] {
        var seen = Set<String>(), out: [PaletteToken] = []
        let all = (store.feed?.items ?? []) + (market.live?.new?.items ?? []) + (market.live?.soon?.items ?? []) + (market.live?.migrated?.items ?? [])
        for i in all where seen.insert(i.mint).inserted { out.append(PaletteToken(mint: i.mint, symbol: i.symbol, name: i.name)) }
        return out
    }
    private var results: [PaletteItem] { Palette.search(query, tokens: tokens) }

    var body: some View {
        let r = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Un token, une page, une adresse, un mot (ex. glissement)…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 15, design: .rounded)).foregroundStyle(.white).focused($focused)
                    .onSubmit { if r.indices.contains(sel) { pick(r[sel]) } }
                Text("Échap").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider().overlay(.white.opacity(0.08))
            VStack(spacing: 2) {
                ForEach(Array(r.enumerated()), id: \.element.id) { i, it in
                    Button { pick(it) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(it)).font(.system(size: 11, weight: .semibold)).frame(width: 20).foregroundStyle(.white.opacity(0.6))
                            Text(it.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            Text(it.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(i == sel ? 0.12 : 0)))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if r.isEmpty { Text("Rien trouvé. Un token absent du flux n'est ni bon ni mauvais : il n'est simplement pas lu.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(12) }
            }.padding(8)
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in sel = 0 }
        .onKeyPress(.downArrow) { sel = min(max(0, r.count - 1), sel + 1); return .handled }
        .onKeyPress(.upArrow) { sel = max(0, sel - 1); return .handled }
        .onExitCommand { ui.palette = false }
    }

    private func icon(_ it: PaletteItem) -> String {
        switch it.kind { case .page: return "rectangle.on.rectangle"; case .token: return "circle.hexagongrid"; case .pastedMint: return "link"; case .term: return "book" }
    }

    private func pick(_ it: PaletteItem) {
        switch it.kind {
        case .page(let id):
            let map: [String: Tab] = ["live": .live, "trades": .trades, "robots": .robots, "wallets": .wallets, "alerts": .alerts, "settings": .settings]
            if let t = map[id] { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.tab = t; ui.tradeDetail = nil } }
            ui.palette = false
        case .token(let m):
            ui.focusMint = m; ui.tab = .live; ui.tradeDetail = nil; ui.palette = false
        case .pastedMint(let m):
            openDexScreener(m, ui: ui); ui.palette = false
        case .term:
            break   // la définition est lisible dans la liste ; rien à ouvrir
        }
    }
}

/// Mot du métier : souligné en pointillés, définition au survol (infobulle). Textes de `Glossary`.
extension View {
    func glossary(_ term: String) -> some View {
        self.help(Glossary.meaning(of: term) ?? "")
    }
}
