# Serveur MCP commun iCONIQ + MiCONE — proposition (17/11/2026)

**État : proposition validée par Stéphan le 17/11/2026 (options recommandées), aucun code encore.** Décisions en fin de document.
Copie de la partie MiCONE : `MiCONE/docs/MCP_PROPOSITION.md`.

## But

Qu'un agent (Claude Code, Claude Desktop, Codex, Cursor…) puisse, sans ouvrir de fenêtre :
fabriquer l'icône d'appli et l'icône de dossier façon Finder (dossier « nuit » `#2f4f84`, icône de l'appli en couleur au
centre), la poser sur un dossier, la ranger dans iCONIQ dans une collection donnée, lister et créer collections et groupes,
chercher une icône. Usage n° 1 : **à chaque création d'appli**, l'icône du dossier de développement est faite et rangée
automatiquement (aujourd'hui : script `mSOCLE/assets/make_folder_icon.swift`).

## Constats

- MiCONE sait déjà tout faire côté rendu : `Rendu.rendreDossier` avec `fondDossier = "nuit"` et `grave = false` donne le
  dossier nuit avec l'icône en couleur ; `Rendu.exporterICNS`, `Rendu.appliquerDossier`. Tout est dans `MiCONECore`
  (CoreGraphics, sans interface) : utilisable sans lancer l'appli. La CLI n'expose ni `fondDossier` ni `grave`.
- iCONIQ : `Library` (SQLite en WAL, `busy_timeout` 5 s) offre collections, groupes, ajout, recherche ; la boîte
  `Inbox/` ne sait qu'ajouter ou mettre à jour une icône. Tout est dans `iCONIQCore`, sans interface.
- mTAPES : auxiliaire stdio JSON-RPC dans le paquet, `MCPCore` commun, HTTP local facultatif, **désactivé par défaut**,
  **accord par client**, raccordement en un clic. On reprend ce modèle, en plus simple : ici rien ne demande
  d'autorisation d'écran, donc **pas de socket vers l'appli**.

## Architecture recommandée

**Un seul serveur, `iconiq-mcp`, livré dans `iCONIQ.app/Contents/MacOS/`**, qui lie `iCONIQCore` et `MiCONECore`.

| Option | Pour | Contre |
| --- | --- | --- |
| **A. Dans iCONIQ, lie MiCONECore (recommandé)** | un seul raccordement, un seul réglage, outils enchaînés (fabriquer puis ranger) dans le même processus | iCONIQ dépend du paquet MiCONE (dépendance SwiftPM : chemin local en dev, tag GitHub en release) |
| B. Un serveur par appli (`micone-mcp`, `iconiq-mcp`) | chaque appli reste autonome | deux raccordements, deux accords, l'agent doit passer le fichier de l'un à l'autre |
| C. Binaire commun dans un 3e dépôt | neutre | un dépôt, une notarisation et une mise à jour de plus à maintenir |

Pourquoi iCONIQ plutôt que MiCONE : la bibliothèque (collections, recherche) est l'état durable et vit chez iCONIQ ;
MiCONE n'apporte qu'un moteur de rendu sans état, facile à lier comme bibliothèque.

```
agent ──stdio JSON-RPC──▶ iconiq-mcp (iCONIQ.app/Contents/MacOS)
                            ├─ MCPCore (outils, schémas, accord par client, journal)
                            ├─ MiCONECore  : rendu appli / dossier, .icns, détourage Vision, pose sur dossier
                            └─ iCONIQCore  : Library.db (WAL), Files/, recherche
                                 └─▶ notification Darwin « fr.stephan.iconiq.library-changed »
                                       └─▶ iCONIQ ouvert : recharge la barre latérale et la grille
```

- **Appli fermée ou ouverte : les deux marchent.** Le serveur écrit lui-même dans `Library.db` (WAL + `busy_timeout`,
  écritures courtes en transaction) ; si iCONIQ est ouvert, il recharge à la notification. iCONIQ n'est jamais lancé ni
  activé par le serveur (mode silencieux).
- **Lien d'origine conservé** : une icône ajoutée par MCP avec `origin` (chemin de l'image source) est mise à jour sur
  place si on la refait, comme le lien MiCONE actuel (`linkPath`).
- **Édition de dev** : `iconiq-mcp` de `iCONIQ-dev` lit `~/Library/Application Support/iCONIQ-dev/` (ni iCONIQ ni MiCONE
  n'ont aujourd'hui de version de dev : à créer, voir questions).
- HTTP local facultatif : **non prévu** au départ (tous les clients visés savent lancer une commande stdio).

## Outils (v1)

Les noms suivent le préfixe `icons_` (rendu, fichiers) et `library_` (bibliothèque). Chaque outil qui produit une image
renvoie aussi un aperçu PNG 256 px (contenu `image` MCP) pour que l'agent vérifie le résultat.

| Outil | Paramètres | Retour |
| --- | --- | --- |
| `icons_make` | `image` (chemin PNG/JPEG/SVG/ICNS), `kind` (`app` \| `folder`), `folder_color?` (`nuit` défaut, `bleu`, `graphite`, `clair`, ou `#rrggbb`), `engraved?` (défaut faux = icône en couleur), `background?` (appli : `sombre` défaut…), `remove_background?`, `size?` (% , 72), `offset_y?`, `output_dir?`, `name?` | chemins `.icns` et PNG 1024, aperçu |
| `icons_apply_to_folder` | `icon` (`.icns`/`.png` ou `icon_id` iCONIQ), `folder` | `ok`, icône précédente sauvegardée (chemin) |
| `icons_clear_folder_icon` | `folder` | `ok` |
| `icons_app_kit` | `image`, `app_name`, `folder?` (dossier de dev à habiller), `collection_app?`, `collection_folder?`, `apply?` (défaut vrai si `folder`) | les deux icônes, ids iCONIQ, état de la pose — **l'enchaînement « nouvelle appli » en un appel** |
| `library_list` | `include_counts?` | arbre groupes → collections (id, nom, nombre d'icônes, kind) |
| `library_create_collection` | `name`, `group?` (id ou nom) | collection (id) ; existante de même nom dans le même groupe → renvoyée telle quelle |
| `library_create_group` | `name`, `parent?` | groupe (id) |
| `library_add_icon` | `file`, `name`, `collection` (id **ou** nom exact), `tags?`, `kind?` (`app` \| `folder` \| autre), `origin?` | icône (id, chemin dans `Files/`) ; nom de collection ambigu → erreur listant les candidates |
| `library_suggest_collection` | `app_name`, `path?`, `kind` (`app` \| `folder`) | collection proposée (id, nom) et règle appliquée |
| `library_search` | `query?`, `collection?`, `tags?`, `kind?`, `starred?`, `limit?` (50) | icônes : id, nom, collection, tags, chemin, aperçu |
| `library_get_icon` | `id`, `export_png?` (taille), `dest?` | métadonnées, chemin du fichier, export éventuel |

Ressources en lecture : `iconiq://icon/<id>` (image), `iconiq://collections` (arbre).

**Volontairement absents de la v1** : suppression d'icônes / collections / groupes, renommage, génération par IA de
MiCONE (services en ligne, crédits), portails web. À ajouter seulement sur demande (suppression : confirmée dans l'appli).

## Flux « nouvelle appli »

1. L'agent appelle `library_list`, puis **demande la collection à Stéphan** (fenêtre de questions, candidates
   « MES APPLICATIONS », « FOLDERS », « SKYRIM FOLDERS », préselection selon la réponse à la question 4).
2. `icons_app_kit image=assets/icon-1024.png app_name=mSOCLE folder="/Volumes/OWC 6To/TAF/DEV/mSOCLE"
   collection_app=… collection_folder=…`
3. Le serveur : rend l'icône d'appli et l'icône de dossier nuit, écrit `assets/folder-1024.png` + `.icns`, pose l'icône
   sur le dossier (ancienne icône sauvegardée), range les deux dans iCONIQ (`origin` = image source), envoie la
   notification. Renvoie les deux aperçus.
4. Le skill `icones` (livré avec iCONIQ, recopié dans `~/.claude/skills`) décrit cet enchaînement ; la règle
   « nouvelle appli » de CLAUDE.md y renvoie.

## Sécurité

- **Désactivé par défaut**. Réglage iCONIQ « Autoriser le pilotage par IA » (comme mTAPES). Désactivé : le serveur
  répond à `initialize` puis refuse chaque outil avec un message clair (« activez-le dans iCONIQ › Réglages »).
- **Accord par client** (nom annoncé à `initialize`) : premier appel d'un client inconnu → refus « en attente d'accord »,
  ligne en attente dans Réglages › Pilotage IA (boutons Autoriser / Refuser). Fichier `mcp.json` (droits 600) dans le
  dossier de données, lu par l'auxiliaire à chaque appel.
- **Chemins** : lecture d'images partout dans le dossier personnel et les volumes ; **pose d'icône** refusée sur `/System`,
  `/Library`, `/Applications`, un paquet `.app` ou la racine d'un volume (sauf réglage) ; jamais d'écrasement silencieux :
  l'icône personnalisée existante est sauvegardée dans `~/Library/Application Support/iCONIQ/Backups/`.
- **Aucun réseau** : le serveur ne contacte rien (détourage = Vision local). Images limitées à 50 Mo / 8192 px.
- **Journal** des commandes consultable (Réglages › Pilotage IA), 500 dernières lignes.
- Calcul léger (CoreGraphics, quelques centaines de ms) : pas de passage par `calcul-lourd`, sauf le détourage Vision
  sur un lot (> 10 images) qui prend le verrou.

## Interface (maquette à faire au design Socle après accord)

Réglages d'iCONIQ, nouvel onglet **Pilotage IA** (même structure que mTAPES) :

```
┌ Pilotage IA ─────────────────────────────────────────────┐
│ [■] Autoriser le pilotage par IA                          │
│     Un agent peut créer des icônes, les poser sur des    │
│     dossiers et les ranger dans votre bibliothèque.      │
│ Raccorder :  Claude Code [Raccorder]  Claude Desktop […]  │
│              Codex […]  Cursor […]   [Copier la commande] │
│ Clients :    claude-code  ✓ autorisé        [Retirer]     │
│              cursor       ⏳ en attente  [Autoriser][Refuser]│
│ Journal :    13:42 icons_app_kit mSOCLE → MES APPLICATIONS│
│              [Afficher le journal]                        │
└──────────────────────────────────────────────────────────┘
```

Textes dans les 4 langues (clés `mcp.*`), « i » violet d'iCONIQ dans les textes, jamais dans un menu.

## Côté MiCONE (petit, utile tout de suite)

- Exposer dans la CLI : `--fond-dossier nuit|bleu|graphite|clair|#rrggbb`, `--grave` / `--sans-grave`, `--appliquer DOSSIER`.
  Permet de remplacer `make_folder_icon.swift` dès maintenant, avant le MCP.
- Garder `MiCONECore` sans dépendance à l'interface (c'est déjà le cas) et le publier comme produit SwiftPM
  (`.library(name: "MiCONECore")`) pour qu'iCONIQ le lie.

## Étapes (après validation)

0. Versions de dev d'iCONIQ et MiCONE (bundle `….dev`, dossier de données `-dev`).
1. CLI MiCONE (`--fond-dossier`, `--grave`, `--appliquer`) ; produit `MiCONECore`.
2. iCONIQ : `MCPCore` (repris de mTAPES), `iconiq-mcp`, outils `library_*` ; notification de rechargement.
3. Outils `icons_*` et `icons_app_kit` ; sauvegarde des icônes de dossier.
4. Réglages › Pilotage IA (maquette Socle d'abord), raccordement en un clic, 4 langues.
5. Skill `icones`, test de bout en bout (`scripts/mcp_e2e.py`), mise à jour de la règle « nouvelle appli ».
6. Documentation d'iCONIQ, MiCONE et mTAPES : README (section About en anglais et texte en 4 langues), CLAUDE.md, et
   **captures d'écran complétées** (nouvel onglet Pilotage IA, icône de dossier, rangement), prises par mTAPES. Puis
   envoi de ces mises à jour à OpenMacApps (fiches iCONIQ et MiCONE déjà listées), seulement après accord de Stéphan,
   à la sortie de la version.

## Principe : règles universelles, personnalisation par réglages (décision de Stéphan, 17/11/2026)

iCONIQ et MiCONE sont des applis publiques : **rien de propre à Stéphan n'est écrit dans le code**. Les choix personnels
(dossier « nuit », collections MES APPLICATIONS / FOLDERS / SKYRIM FOLDERS, règle Skyrim) deviennent de simples réglages.

- **Rangement d'une nouvelle appli = règle + confirmation.** Réglages › Pilotage IA › « Rangement par défaut » :
  collection de l'icône d'appli, collection de l'icône de dossier (au premier usage : collections « Applications » et
  « Dossiers » créées si elles manquent, noms traduits), plus des **règles facultatives** « si le nom / le chemin /
  une étiquette contient X → collection Y » (c'est là que vit la règle Skyrim de Stéphan). `library_suggest_collection`
  (`app_name`, `path?`, `kind`) renvoie la proposition et sa raison ; l'agent la présélectionne dans sa question, la
  personne confirme ou change.
- **Couleur de dossier par défaut** : réglage (défaut public = bleu Finder de MiCONE ; Stéphan choisit « nuit »).
  `folder_color` absent → ce réglage.
- Aucun chemin, nom de collection ou couleur personnel dans le skill livré ; mes valeurs vont dans mon CLAUDE.md.

## Décisions (17/11/2026)

1. Architecture A : un seul serveur `iconiq-mcp` dans iCONIQ.app, qui lie `MiCONECore` ; fonctionne appli fermée.
2. Pose d'icône sur un dossier : directe, ancienne icône sauvegardée ; dossiers système, `/Applications`, paquets `.app`
   et racines de volume refusés.
3. Accord : interrupteur « Autoriser le pilotage par IA » (désactivé par défaut) + accord par client, comme mTAPES.
4. Rangement : règle + confirmation, règles en réglages (principe universel ci-dessus).
5. Versions de dev d'iCONIQ et MiCONE à créer (étape 0).

6. Maquette Socle de Réglages › Pilotage IA validée le 17/11/2026 : `maquettes/pilotage-ia.html` (capture `maquettes/images/pilotage-ia.png`).
7. Les 3 applis dont doc, captures et fiche OpenMacApps sont mises à jour : iCONIQ, MiCONE, mTAPES.

Prochaine étape : le code, dans l'ordre des étapes (versions de dev d'abord).
