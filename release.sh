#!/bin/bash
# Publie une version : tests, compilation, notarisation (Developer ID), puis release GitHub avec iCONIQ.zip et son .sha256,
# que la mise à jour automatique de l'appli va chercher. Notes : _tools/changelogs/iCONIQ_<version>.txt (4 langues).
# Usage : ./release.sh <version>   (ex. 1.0.1 ; le tag devient v1.0.1)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?Usage : ./release.sh <version>}"
NOTARIZE=/Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh
DIST="$(mktemp -d)"

swift test
VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
DIST="$DIST" "$NOTARIZE" iCONIQ.app
(cd "$DIST" && shasum -a 256 iCONIQ.zip > iCONIQ.zip.sha256)
python3 /Volumes/SKYRIM/TOOLS/MAC/_tools/release_notes.py iCONIQ "$VERSION" --sha "$DIST/iCONIQ.zip.sha256" -o "$DIST/notes.md"
git push origin main
gh release create "v$VERSION" "$DIST/iCONIQ.zip" "$DIST/iCONIQ.zip.sha256" --title "iCONIQ $VERSION" --notes-file "$DIST/notes.md"
rm -rf "$DIST"
