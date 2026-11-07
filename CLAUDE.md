# iCONIQ

Version personnelle d'IconJar (geticonjar.com) : bibliothèque d'icônes, import IconJar, navigateur de portails d'icônes, lien dynamique avec MiCONE. Swift / SwiftUI, sans bac à sable, macOS 14+.

- Interface : design system Socle (https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah). `Sources/iCONIQ/Socle.swift`, `Updater.swift` et `UpdaterView.swift` sont recopiés par `build_app.sh` / `_tools/sync_shared.sh` : ne pas les modifier ici. Le « i » du nom prend le violet du logo (#8b5cf6, `Brand.color`).
- Cœur testable : `Sources/iCONIQCore` (SQLite `Library`, importeurs, `WebCapture`, `Inbox`). Interface : `Sources/iCONIQ`.
- Données : `~/Library/Application Support/iCONIQ/` : `Library.db`, `Files/<collection>/`, `Cache/thumbs`, `Inbox/` (`ICONIQ_DATA_DIR` pour les essais). Les fichiers sont copiés dans iCONIQ (aucune dépendance à la bibliothèque IconJar d'origine).
- Import IconJar : `.ijlibrary` / `.iconjar` contenant `Jars.db` (Core Data : ZIJGROUP, ZIJCOLLECTION, ZIJITEM) et `Sets/<ZIDENTIFIER de la collection>/<ZNEWFILENAME>`. Collections ZTYPE 0 seulement (favoris et récents sont recalculés). Un jar sans `Jars.db` est lu comme un dossier.
- Portails : `PortalController` (WKWebView par portail, conservé en mémoire). `CaptureScript` (JS) liste les icônes de la page, remplit le champ de recherche du site si le portail n'a pas de modèle `{q}`, et fournit le mode capture. Les téléchargements (image, zip) sont importés directement.
- Lien MiCONE : MiCONE dépose fichier + `.json` dans `Inbox/` (`src/iconiq.py` côté MiCONE). `Inbox.process` range dans la collection « MiCONE » (kind `micone`, masquée de l'arborescence, affichée en tête de la barre latérale : simple point de chute, une icône déplacée n'y reste pas) ou met à jour sur place, où qu'elle soit, l'icône déjà liée à la même `origin`. Surveillance par DispatchSource, schéma `iconiq://`.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it), un test vérifie les clés et les paramètres. Moteur de mise à jour : `UpdateEngine` (dépôt GitHub starbudweiser/iCONIQ).
- Build et installation (~/Applications/Applications Personnelles) : `./build_app.sh` ou `_tools/build_all.sh iCONIQ`. Release : `./release.sh <version>` (notes : `_tools/changelogs/iCONIQ_<version>.txt`).
- Tests : `swift test`.
