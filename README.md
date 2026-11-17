<p align="center"><img src="assets/iCONIQ.png" width="128" alt="iCONIQ"></p>

# iCONIQ

[![Listed on OpenMacApps](https://openmacapps.com/badge.svg)](https://openmacapps.com/apps/iconiq/) [![Latest release](https://img.shields.io/github/v/release/starbudweiser/iCONIQ)](https://github.com/starbudweiser/iCONIQ/releases/latest) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A personal icon library for macOS, inspired by IconJar.

🇬🇧 English · 🇫🇷 [Français](#français)

## About

**iCONIQ** is a personal icon library for macOS, inspired by IconJar (no affiliation with its authors). Import your IconJar libraries, browse icon portals from inside the app and capture icons straight into your own database, and receive icons created in MiCONE automatically.

iCONIQ is part of the **DESKTOP MAC TOOLKIT**, Starbudweiser's collection of macOS apps.

Made by Starbudweiser & Claude Code (Anthropic). MIT License, © 2026 Starbudweiser. Provided as is, without warranty of any kind.

![The iCONIQ main window showing a grid of 60 colourful line icons organised in four collections, with icon portals in the sidebar.](docs/screenshot.png)

## Features

- Import IconJar libraries (`.ijlibrary`) and jars (`.iconjar`), icon folders and SVG / PNG / ICNS files.
- Built-in browser for icon portals whose addresses you enter yourself: search, navigation, detection of the icons on a page, click-to-capture mode, direct import of downloads (images and ZIP).
- Live link with MiCONE: every icon exported there lands in the "MiCONE" collection (a landing point: move it elsewhere and it leaves the folder) and is updated in place, wherever it was filed, when exported again.
- Search by name and tags, favorites, recents, collections and groups, copy as SVG / image, drag out to any app, export to PNG.
- **AI control (MCP server)**: let Claude, Codex, Cursor or Gemini CLI make an app icon and its Finder-style folder icon from one image, set it on a folder and file both in the collection you confirm. Off by default, approved once per client, works with iCONIQ closed; nothing is deleted, nothing leaves your Mac. See [AI control](#ai-control).
- Automatic updates (GitHub releases, Developer ID signature check). English, French, Spanish, Italian.

## AI control

*Settings › AI control*: turn on **Allow AI control**, click **Connect** next to your AI (or copy the command), then allow it once when it first calls iCONIQ. Choose the default collections for app and folder icons, optional filing rules (e.g. "path contains X → collection Y"), the default folder colour and whether the motif is engraved. The previous custom icon of a folder is backed up; system folders, Applications, app bundles and disk roots are always refused.

![iCONIQ settings, AI control tab: permission, connected AI clients, default filing collections and rules, default folder colour and folder protection.](docs/ai-control.png)

The server, `iconiq-mcp`, ships inside the app (`iCONIQ.app/Contents/MacOS/iconiq-mcp`, stdio). Tools: `icons_app_kit` (app icon + folder icon + set on folder + file in the library, in one call), `icons_make`, `icons_apply_to_folder`, `icons_clear_folder_icon`, `library_list`, `library_suggest_collection`, `library_create_collection`, `library_create_group`, `library_add_icon`, `library_search`, `library_get_icon`. Icons are rendered with MiCONE's engine.

## Install

**[Download the latest notarized release](https://github.com/starbudweiser/iCONIQ/releases/latest)**, unzip it and move **iCONIQ.app** to your Applications folder. Requires **macOS 14 Sonoma** or later.

## Build

```bash
swift test          # core (database, importers, MiCONE drop box) and texts in the 4 languages
./build_app.sh      # builds, signs, installs in ~/Applications/Applications Personnelles
./release.sh 1.0.1  # tests, build, notarization, GitHub release
```

## Languages

English, French, Spanish and Italian. The app follows your Mac's preferred language automatically (English if it is none of these four).

## Support

Bug reports and suggestions: [GitHub Issues](https://github.com/starbudweiser/iCONIQ/issues).

## License

Released under the **MIT License**, © 2026 Starbudweiser. See [LICENSE](LICENSE).

---

## Français

Bibliothèque d'icônes personnelle pour macOS, inspirée d'IconJar (sans lien avec ses auteurs).

### Utilisation

- **Import** : bouton IMPORTER ou glisser-déposer d'une bibliothèque IconJar, d'un dossier ou de fichiers.
- **Portails** : `+` dans la section Portails, adresse du site, modèle de recherche facultatif (`{q}` = mot cherché). DÉTECTER liste les icônes de la page ; le viseur active le mode capture (un clic = un ajout).
- **MiCONE** : rien à régler, voir `Réglages › Lien avec MiCONE`.
- **Pilotage par IA** : `Réglages › Pilotage IA`, cocher « Autoriser le pilotage par IA », raccorder votre IA (Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI) puis l'autoriser à son premier appel. Elle peut alors fabriquer l'icône d'une appli et celle de son dossier, la poser sur le dossier et ranger les deux dans la collection que vous confirmez. Désactivé par défaut, fonctionne appli fermée, ne supprime rien, n'envoie rien sur Internet ; l'ancienne icône d'un dossier est sauvegardée.
- Données : `~/Library/Application Support/iCONIQ/` (`ICONIQ_DATA_DIR` pour les essais).

### Développement

```bash
swift test          # cœur (base, importeurs, boîte MiCONE) et textes des 4 langues
./build_app.sh      # compile, signe, installe dans ~/Applications/Applications Personnelles
./release.sh 1.0.1  # tests, build, notarisation, release GitHub
```

Installation : téléchargez la [dernière version notarisée](https://github.com/starbudweiser/iCONIQ/releases/latest), décompressez-la et placez **iCONIQ.app** dans Applications (macOS 14 Sonoma ou plus récent).

Interface en français, anglais, espagnol et italien, choisie d'après la langue du Mac (anglais sinon). Licence MIT, © 2026 Starbudweiser. Questions et bugs : [Issues GitHub](https://github.com/starbudweiser/iCONIQ/issues).
