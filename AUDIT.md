# Check-up SolHawk Notch (29/10/2026)

## Architecture (2 400 lignes, 52 tests)
- `SolHawkNotchCore` (sans interface, testé) : lecture du flux (`FeedClient`, GET seulement, chemin autorisé unique), états (`Mood`), signal de la barre (`BarSignal`), alertes (`AlertEngine`), séries réelles (`Series`), Trousseau (`TokenStore`).
- `SolHawkNotch` (SwiftUI / AppKit) : fenêtre sous l'encoche (`NotchController`), vues (`RootView`, `TokenColumn`, `Tabs`, mascottes), livraison des alertes (`AlertDelivery`), réglages.
- Règle gardée : aucun envoi, aucune clé, aucun achat/vente. Tout ce qui vient du serveur est traité comme non fiable (adresses validées, textes nettoyés et bornés).

## Corrigé pendant ce check-up
- Adresse refusée (http hors 127.0.0.1) : avant « Serveur injoignable », maintenant un état à part (« adresse ? », rouge, message qui dit quoi faire).
- Écran branché / débranché / résolution changée : la barre est replacée toute seule (avant : restait au mauvais endroit).
- Petit écran : le tiroir ne dépasse plus la largeur de l'écran.
- Mac sans encoche : mise en page vérifiée (essai avec `SOLHAWK_NOTCH_SIMULATE_NONOTCH=1`).
- Repliée, l'app redessine moins souvent (20 images/s au lieu de 30).
- Les listes d'alertes déjà faites sont bornées (pas de croissance sans fin).

## Vérifié (images produites par l'app elle-même, faux serveur)
Barre repliée (vert, rouge), tiroir (3 onglets), plein écran, sans encoche, adresse refusée, visite guidée.

## NON vérifié (à essayer sur le vrai Mac)
Suivi de la souris en direct, clics des boutons, raccourci Ctrl+Option+Espace, touches du clavier, son et notification en vrai, fenêtre de réglages et Trousseau, changement d'écran réel, multi-écrans.

## Limites connues
- Pas de courbe tant que le serveur n'a pas relu le token plusieurs fois (« pas encore d'historique »).
- L'app lit le serveur à intervalles ; pas de websocket.

## Pistes (pas faites)
- App iPhone séparée (le module Core est réutilisable).
- Paquet `.app` signé pour lancer sans Terminal (nécessite un compte développeur pour la signature).
- Plugin Chrome : non audité ici (fichier `sidepanel.js` de ~6 000 lignes, à découper — voir le plan « Audit, nettoyage »).

## Simulation (trading fictif) — 2026-10-30
- Cœur : `Paper.swift` (ordres en attente, latence, glissement selon la taille, frais, ordres non exécutés), `Robots.swift` (5 robots dont un témoin au hasard, règles de sortie communes), `PaperLab.swift` (sauvegarde JSON locale, fichier illisible mis de côté, remise à zéro = archive).
- Interface : onglets Trades et Robots, bouton « Acheter $10 fictif » sous chaque carte, ligne pointillée « ton entrée » sur la courbe, colonne Portefeuille en plein écran. Touches B / S.
- Vérifié : 18 tests unitaires du moteur et des robots ; rendus PNG sur le serveur factice (`tools/mock_feed.py`, cours inventés qui bougent).
- NON vérifié : clics réels, ressenti, comportement sur le vrai flux du VPS (peu de tokens listés pour l'instant).
- Limites : le flux ne donne pas la liquidité → glissement = hypothèse (`depthRatio` 0,15) ; prix = market cap lu toutes les ~5 s, donc pas d'exécution à la seconde ; « sortie supposée à −50 % » quand un token n'a plus de prix ; aucune stratégie démontrée rentable, échantillon minuscule.
- Hors périmètre volontaire : aucun mode réel, aucune clé de portefeuille, aucune signature.

## Terminal (plein écran) — 2026-10-30
- Terminal : bande de tokens (image d'abord), grand graphique (DexScreener intégré, page verrouillée sur dexscreener.com, sans cookies gardés, sans pop-up ; ou lectures natives avec viseur et marqueurs A/V), panneau d'ordre FICTIF avec estimation des coûts, tes trades sur le token avec analyse, robots sur le token.
- Analyse des trades (`Review.swift`) : pistes tirées des chiffres (entrée après forte hausse, coûts, sortie loin du plus haut, perte > 25 %, trade très court). Pas des règles prouvées.
- « Pas achetés » : variation brute (sans frais) depuis que l'app a vu le token.
- Robots : avatar dessiné en code + journal (raison d'entrée, raison de sortie).
- NON vérifié : rendu de la page DexScreener intégrée (les captures internes ne dessinent pas une page web, et les mints du serveur factice ne sont pas de vraies adresses).
- À faire : section Wallets suivis (le serveur ne donne qu'un résumé : il faut une route qui liste les wallets), explication par un modèle avec la clé de l'utilisateur.
