import AppKit
import SwiftUI
import SolHawkNotchCore

// « Mes wallets à suivre » : liste locale (adresses publiques + étiquettes à moi), import par collage.
// Rien n'est envoyé nulle part. L'activité de ces wallets n'est pas lue pour l'instant (il faudrait une route serveur).

@MainActor @Observable
final class WatchStore {
    static let shared = WatchStore()
    private(set) var list: WatchList
    @ObservationIgnored private let file: WatchListFile

    init(file: WatchListFile = .standard) { self.file = file; list = file.load() }

    func importText(_ t: String, group: WatchGroup) -> WatchImportResult {
        var l = list; let r = l.importText(t, group: group); list = l; file.save(l); return r
    }
    func remove(_ a: String) { var l = list; l.remove(a); list = l; file.save(l) }
    func rename(_ a: String, _ s: String) { var l = list; l.rename(a, to: s); list = l; file.save(l) }
}

struct WatchedSection: View {
    var wallets: WalletStore
    var ui: UIState
    var now: Date
    var store = WatchStore.shared
    @State private var showImport = false
    @State private var group: WatchGroup = .traders

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mes wallets à suivre").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.list.exportText(), forType: .string) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.6)).help("Copier la liste (réimportable)").disabled(store.list.wallets.isEmpty)
                Button { showImport = true } label: {
                    Label("Importer", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(0.12))).foregroundStyle(.white)
                }.buttonStyle(PressStyle())
            }
            HStack(spacing: 8) {
                ForEach(WatchGroup.allCases, id: \.self) { g in
                    let n = store.list.wallets(in: g).count
                    Button { group = g } label: {
                        Text("\(g.label) \(n)/\(g.limit)").font(.system(size: 11, weight: .medium, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(group == g ? 0.16 : 0.05))).foregroundStyle(.white.opacity(group == g ? 1 : 0.6))
                    }.buttonStyle(PressStyle())
                }
            }
            let rows = store.list.wallets(in: group)
            if rows.isEmpty {
                Text("Aucun wallet dans ce groupe. « Importer » : colle une adresse par ligne, avec un nom si tu veux (jusqu'à \(group.limit)).")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView { VStack(spacing: 3) { ForEach(rows) { WatchedLine(w: $0, store: store, wallets: wallets, ui: ui, now: now) } } }.frame(maxHeight: 190).scrollIndicators(.hidden)
            }
            Text("Liste locale, adresses publiques seulement. « Activité » lit les dernières transactions de ce wallet via ton serveur (échantillon récent, pas l'historique) : un achat n'est pas un conseil.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
        .sheet(isPresented: $showImport) { ImportSheet(store: store, group: group) }
    }
}

struct WatchedLine: View {
    var w: WatchedWallet
    var store: WatchStore
    var wallets: WalletStore
    var ui: UIState
    var now: Date
    @State private var editing = false
    @State private var name = ""
    var body: some View {
        VStack(spacing: 4) { header; activity }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04)))
    }

    @ViewBuilder var activity: some View {
        if let r = wallets.recent[w.address] {
            if let a = r.value, let moves = a.moves {
                let shown = moves.filter { $0.side != "INDETERMINATE" }.prefix(4)
                if shown.isEmpty { Text(a.status == "RPC_NOT_CONFIGURED" ? "Serveur sans lecture de transactions (RPC non configuré)." : "Aucun achat ni vente dans l'échantillon récent.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(shown)) { m in
                    Button { ui.focusMint = m.mint; ui.tab = .live } label: {
                        HStack(spacing: 6) {
                            Text(sideLabel(m.side)).font(.system(size: 10, weight: .semibold)).foregroundStyle(m.side == "BUY" ? gain : m.side == "SELL" ? Color.orange : .white.opacity(0.5))
                            Text(shortAddress(m.mint)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                            Text(ago(m.blockTime, now)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            Spacer()
                        }
                    }.buttonStyle(.plain).help("Ouvrir ce token dans le Terminal")
                }
            } else {
                Text("Activité non lue (serveur injoignable ou sans cette route : mets le serveur à jour).").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            WalletAvatar(address: w.address, emoji: nil, size: 24)
            if editing {
                TextField("Nom", text: $name).textFieldStyle(.roundedBorder).frame(width: 140).onSubmit { store.rename(w.address, name); editing = false }
            } else {
                Text(w.label.isEmpty ? "sans nom" : w.label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    .onTapGesture(count: 2) { name = w.label; editing = true }
            }
            Text(shortAddress(w.address)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button { Task { await wallets.loadRecent(address: w.address) } } label: {
                if wallets.checking.contains(w.address) { ProgressView().controlSize(.mini) } else { Text("Activité").font(.system(size: 10, weight: .semibold)) }
            }.buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.7)).help("Lire les dernières transactions de ce wallet")
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.address, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.5)).help("Copier l'adresse")
            Button { store.remove(w.address) } label: { Image(systemName: "trash") }
                .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.5)).help("Retirer de ma liste")
        }
        .font(.system(size: 11))
    }
}

struct ImportSheet: View {
    var store: WatchStore
    @State var group: WatchGroup
    @State private var text = ""
    @State private var result: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Importer des wallets").font(.system(size: 15, weight: .semibold, design: .rounded))
            Picker("", selection: $group) {
                ForEach(WatchGroup.allCases, id: \.self) { Text("\($0.label) (max \($0.limit))").tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text("Colle une adresse par ligne, avec un nom après si tu veux (« adresse nom »). Un tableau JSON marche aussi. Les lignes qui ne ressemblent pas à une adresse Solana sont ignorées.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Coller depuis le presse-papiers") { text = NSPasteboard.general.string(forType: .string) ?? text }
                Spacer()
                Text("\(WatchList.countCandidates(text)) adresse(s) détectée(s)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            TextEditor(text: $text).font(.system(size: 11, design: .monospaced)).frame(minHeight: 180).border(.quaternary)
            if let r = result { Text(r).font(.system(size: 11, weight: .medium)).foregroundStyle(.green) }
            HStack {
                Button("Fermer") { dismiss() }
                Spacer()
                Button("Ajouter à \(group.label.lowercased())") { result = store.importText(text, group: group).summary }
                    .keyboardShortcut(.defaultAction).disabled(WatchList.countCandidates(text) == 0)
            }
        }
        .padding(18).frame(width: 520)
    }
}
