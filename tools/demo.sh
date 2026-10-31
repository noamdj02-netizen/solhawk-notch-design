#!/bin/bash
# Lance SolHawk Notch en MODE DÉMO pour filmer : serveur factice local (données inventées, bandeau « DÉMO » visible),
# portefeuille fictif séparé (ne touche pas au vrai). Quitte d'abord l'app installée (menu Quitter) pour n'avoir qu'une encoche.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! lsof -tiTCP:8799 -sTCP:LISTEN >/dev/null 2>&1; then
  nohup python3 tools/mock_feed.py >/dev/null 2>&1 &
  sleep 1
fi
DEMO_DIR="$HOME/Library/Application Support/SolHawkNotch/demo"
mkdir -p "$DEMO_DIR"
[ "${1:-}" = "--fresh" ] && [ -f "$DEMO_DIR/paper.json" ] && mv "$DEMO_DIR/paper.json" "$DEMO_DIR/paper.archive-$(date +%s).json"
exec env SOLHAWK_NOTCH_URL=http://127.0.0.1:8799 SOLHAWK_NOTCH_DEV_TOKEN=dev-notch-mock \
  SOLHAWK_NOTCH_PAPER_FILE="$DEMO_DIR/paper.json" \
  swift run -c release --scratch-path "$HOME/Library/Caches/solhawk-notch-build" SolHawkNotch
