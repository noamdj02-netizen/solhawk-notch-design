#!/bin/bash
# Installe SolHawk Notch comme une vraie app (~/Applications) et, avec --login, la lance à chaque ouverture de session.
# LECTURE SEULE : l'app ne contient ni clé ni ordre réel. Le jeton du serveur se saisit dans Réglages (Trousseau macOS).
# Usage : tools/install_app.sh [--login] | --uninstall-login
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$HOME/Applications/SolHawk Notch.app"
LABEL="fr.solhawk.notch"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
BUILD="$HOME/Library/Caches/solhawk-notch-build"

if [ "${1:-}" = "--uninstall-login" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  [ -f "$AGENT" ] && mv "$AGENT" "$AGENT.desactive"   # gardé à côté, pas effacé
  echo "Lancement automatique désactivé (l'app reste dans ~/Applications)."
  exit 0
fi

swift build -c release --scratch-path "$BUILD"
BIN="$(swift build -c release --scratch-path "$BUILD" --show-bin-path)/SolHawkNotch"
VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SolHawkNotch"
# HawkyPeek.png vit dans le bundle SPM (Bundle.module cherche Contents/Resources).
RES_BUNDLE="$(dirname "$BIN")/SolHawkNotch_SolHawkNotch.bundle"
if [ -d "$RES_BUNDLE" ]; then
  rsync -a --delete "$RES_BUNDLE" "$APP/Contents/Resources/"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>SolHawk Notch</string>
  <key>CFBundleExecutable</key><string>SolHawkNotch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null   # signature locale (ad hoc) : stable pour le Trousseau entre deux lancements
echo "App installée : $APP"

if [ "${1:-}" = "--login" ]; then
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/SolHawkNotch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  echo "Lancement automatique activé (relance si l'app plante ; « Quitter » l'arrête jusqu'à la prochaine session)."
  echo "Pour l'enlever : tools/install_app.sh --uninstall-login"
fi
