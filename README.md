# SolHawk Notch

Petit compagnon sous l'encoche du MacBook. Il lit le flux de ton serveur SolHawk et le montre avec un petit faucon.
**Lecture seule** : aucune clé de portefeuille, aucune signature, aucun achat ni vente.

## Ce qu'il fait
- Le faucon suit ta souris des yeux et cligne.
- Sa couleur dit l'état de la LECTURE, pas un conseil :
  - bleu-vert : calme (0 listé est un état normal, pas un feu vert) ;
  - vert : nouveau token qui « passe les filtres » (aucune garantie, pas « sûr ») ;
  - orange : nouveau token « à vérifier » ;
  - gris : en attente, ou données périmées ; yeux en croix : serveur injoignable ;
  - rouge + cadenas : jeton refusé. L'app arrête alors d'interroger (sinon le serveur te bloque 5 minutes, plugin compris).
- Clic sur la barre : elle s'étire en large, avec trois onglets :
  - **Direct** : 3 cartes de tokens (âge, MC, SOL réels, 5 feux, « passe les filtres » / « à vérifier »). Un feu gris = « non lu », jamais vert.
    Boutons « Copier CA » et « DexScreener » : l'adresse est vérifiée (base58, 32-44 caractères) avant toute copie ou ouverture.
  - **Trades** (simulation) : bouton « Acheter $10 fictif » sur chaque carte ; l'ordre est rempli au prix lu après un délai (2 s par défaut), avec frais et glissement estimés ; historique, capital fictif, résultat net estimé, pire baisse. Sauvegardé dans `~/Library/Application Support/SolHawkNotch/paper.json` (remise à zéro = archive, jamais effacé).
  - **Robots** (simulation) : Mise en liste, Momentum, Retracement Fibonacci, Achat du creux, face à un **témoin au hasard** ; mêmes données, mêmes coûts, mêmes règles de sortie. Aucune stratégie n'est démontrée rentable.
  - **Entonnoir** : vus → observés → listés, et les raisons d'abandon dominantes.
  - **Santé** : fraîcheur des données, état de la lecture RPC du serveur, suivi des écartés.
- Le faucon (style autocollant, dessin original) a une petite phrase par état. Jamais une promesse ni un conseil d'achat.

## Mascotte : Hawky
- Un seul personnage : Hawky, le chat à capuche, entièrement dessiné en code (`HawkyStage.swift`, aucune image). Les couches (oreilles, capuche, visage, yeux, museau) se décalent vers la souris à des profondeurs différentes : il tourne la tête vers le curseur. Les yeux clignent, se plissent en « ^^ » (gain), se baissent avec une larme (perte), etc.
- Petits objets autour de lui : étoiles (gain), « ! » (nouveau token / alerte), « ? » (il réfléchit), zzz (endormi). Ce sont des humeurs, jamais un conseil de trade.
- Les autres personnages (shibo, froggo, popcat, hawky chouette, hawky3d…) ont été retirés : ils restent dans l'historique git.
- Essais visuels : `SOLHAWK_HAWKY_EXPR=celebration` (idle, happy, thinking, surprise, concerned, critical, sleep, loading, celebration, greeting) et `SOLHAWK_HAWKY_LOOK=0.9,0`.

## Lancer (Terminal du Mac)
```bash
cd "…/solana-memecoin-lab 2/apps/notch-mac"
swift run --scratch-path "$HOME/Library/Caches/solhawk-notch-build" SolHawkNotch
```
Au premier lancement, la fenêtre Réglages s'ouvre : adresse du serveur (HTTPS obligatoire) et jeton.
Le jeton est rangé dans le Trousseau du Mac. Il n'est ni affiché, ni écrit dans un fichier.

## Essayer sans le serveur
```bash
python3 tools/mock_feed.py 8799     # faux serveur, données inventées, jeton jetable
SOLHAWK_NOTCH_URL=http://127.0.0.1:8799 SOLHAWK_NOTCH_DEV_TOKEN=dev-notch-mock swift run SolHawkNotch --expanded
```
(`SOLHAWK_NOTCH_DEV_TOKEN` n'est accepté que si l'adresse est 127.0.0.1.)

## Tests
```bash
swift test --scratch-path "$HOME/Library/Caches/solhawk-notch-build"
```

## Limites connues (honnêtes)
- Le dessin est vérifié par des images produites par l'app elle-même. Le placement sous l'encoche réelle, le suivi de la souris,
  le clic et la fenêtre Réglages ne sont PAS encore vérifiés à l'écran.
- Une adresse non sécurisée (http hors 127.0.0.1) s'affiche « Serveur injoignable » : le message devrait dire « adresse refusée ».
- Aucun son. Personnage original (pas celui de Coucou).

## Alertes et raccourcis
Barre repliée : vert qui clignote (un token passe les filtres), jaune (à vérifier), rouge (chute d'au moins 40 % depuis le pic, serveur injoignable, jeton ou adresse refusés). Notification macOS + son + ouverture du tiroir (réglables). Raccourci global Ctrl+Option+Espace. Dans le tiroir : 1–5 onglets, B acheter / S vendre (fictif), C copier l'adresse, D DexScreener, F plein écran, Échap fermer. Voir AUDIT.md pour l'état de la vérification.

## Installer pour de bon (toujours connecté)
```
tools/install_app.sh --login
```
Construit l'app en version optimisée, l'installe dans `~/Applications/SolHawk Notch.app` (signature locale) et la lance à chaque ouverture de session (relance si elle plante ; « Quitter » l'arrête jusqu'à la prochaine session). Au premier lancement, Réglages s'ouvre : colle l'adresse du serveur et ton jeton (gardé dans le Trousseau). Pour retirer le lancement automatique : `tools/install_app.sh --uninstall-login`.

## Logos des tokens
L'image vient du serveur (`image_url`, déclarée par le créateur : non vérifiée, décorative). L'app ne la charge qu'en https depuis des hôtes connus (CDN Pump.fun, passerelles IPFS), sans cookies, ≤ 2 Mo, décodée en vignette. Sinon : initiale colorée.
