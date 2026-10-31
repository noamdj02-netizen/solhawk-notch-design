import AppKit

// SolHawk Notch : compagnon d'encoche en LECTURE SEULE (GET sur le flux du serveur). Aucune clé, aucun ordre.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // pas d'icône dans le Dock
app.run()
