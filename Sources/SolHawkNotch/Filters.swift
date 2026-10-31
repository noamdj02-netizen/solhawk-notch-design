import SwiftUI
import SolHawkNotchCore

// Filtres d'affichage du Terminal : ils ne changent que ce que tu vois, jamais ce que le serveur écarte.

/// Lit un nombre tapé à la main (« 20 », « 10000 », « 0,5 »). Vide ou invalide = 0 (pas de limite).
func parseLimit(_ raw: String) -> Double {
    let v = Double(raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    return v.isFinite && v > 0 ? v : 0
}

struct FilterPopover: View {
    @AppStorage("vfMinMcap") private var minM = ""
    @AppStorage("vfMaxMcap") private var maxM = ""
    @AppStorage("vfMinSol") private var minS = ""
    @AppStorage("vfMaxAge") private var maxA = ""
    @AppStorage("vfOnlyPassing") private var onlyPassing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Filtres d'affichage")
            field("Market cap min ($)", $minM, "ex. 20")
            field("Market cap max ($)", $maxM, "ex. 10000")
            field("SOL réels min", $minS, "ex. 3")
            field("Âge max (minutes)", $maxA, "ex. 10")
            Toggle("Seulement ceux qui passent les filtres du serveur", isOn: $onlyPassing).font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
            HStack {
                Button("Tout effacer") { minM = ""; maxM = ""; minS = ""; maxA = ""; onlyPassing = false }.font(.system(size: 11))
                Spacer()
            }
            Text("Vide = pas de limite. Une valeur non lue est cachée quand un filtre est actif. Ça ne change que l'affichage.")
                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(width: 250)
    }

    func field(_ label: String, _ b: Binding<String>, _ ph: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11))
            Spacer()
            TextField(ph, text: b).textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
        }
    }
}

/// Valeurs courantes des filtres (lues par la vue via @AppStorage, mêmes clés que FilterPopover, pour qu'elle se redessine).
struct ViewFilterReader {
    var minM = "", maxM = "", minS = "", maxA = ""
    var onlyPassing = false
    var filter: ViewFilter { ViewFilter(minMcap: parseLimit(minM), maxMcap: parseLimit(maxM), minSol: parseLimit(minS), maxAgeMin: parseLimit(maxA)) }
    var isActive: Bool { filter.isActive || onlyPassing }
    func apply(_ items: [Feed.Item]) -> [Feed.Item] {
        let f = filter.apply(items)
        return onlyPassing ? f.filter { status(of: $0) == .passesFilters } : f
    }
}
