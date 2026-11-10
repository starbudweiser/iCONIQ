# iCONIQ

[![Listed on OpenMacApps](https://openmacapps.com/badge.svg)](https://openmacapps.com/apps/iconiq/)

## About

**iCONIQ** is a personal icon library for macOS, inspired by IconJar (no affiliation with its authors). Import your IconJar libraries, browse icon portals from inside the app and capture icons straight into your own database, and receive icons created in MiCONE automatically.

- Import IconJar libraries (`.ijlibrary`) and jars (`.iconjar`), icon folders and SVG / PNG / ICNS files.
- Built-in browser for icon portals whose addresses you enter yourself: search, navigation, detection of the icons on a page, click-to-capture mode, direct import of downloads (images and ZIP).
- Live link with MiCONE: every icon exported there lands in the "MiCONE" collection (a landing point: move it elsewhere and it leaves the folder) and is updated in place, wherever it was filed, when exported again.
- Search by name and tags, favorites, recents, collections and groups, copy as SVG / image, drag out to any app, export to PNG.
- Automatic updates (GitHub releases, Developer ID signature check). English, French, Spanish, Italian.

Released under the MIT license. © 2026 Starbudweiser.

## Utilisation (français)

- **Import** : bouton IMPORTER ou glisser-déposer d'une bibliothèque IconJar, d'un dossier ou de fichiers.
- **Portails** : `+` dans la section Portails, adresse du site, modèle de recherche facultatif (`{q}` = mot cherché). DÉTECTER liste les icônes de la page ; le viseur active le mode capture (un clic = un ajout).
- **MiCONE** : rien à régler, voir `Réglages › Lien avec MiCONE`.
- Données : `~/Library/Application Support/iCONIQ/` (`ICONIQ_DATA_DIR` pour les essais).

## Développement

```bash
swift test          # cœur (base, importeurs, boîte MiCONE) et textes des 4 langues
./build_app.sh      # compile, signe, installe dans ~/Applications/Applications Personnelles
./release.sh 1.0.1  # tests, build, notarisation, release GitHub
```
