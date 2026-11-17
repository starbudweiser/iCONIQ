---
name: icones
description: Fabriquer l'icône d'une appli et l'icône de son dossier (façon Finder), la poser sur le dossier et la ranger dans la bibliothèque iCONIQ, par le serveur MCP d'iCONIQ (outils icons_* et library_*). À utiliser à la création d'une appli, quand on demande une icône de dossier, ou pour chercher, ranger ou exporter une icône de la bibliothèque.
---

# Icônes avec iCONIQ (serveur MCP `iconiq`)

Le serveur `iconiq-mcp` est livré dans iCONIQ.app. Il fonctionne appli fermée, n'ouvre aucune fenêtre, ne supprime rien et
n'envoie rien sur Internet. Il est **désactivé par défaut** : si un outil répond « AI control is off » ou « Waiting for the
user's approval », demander à l'utilisateur d'ouvrir iCONIQ › Réglages › Pilotage IA (activer, puis autoriser le client).

## Nouvelle appli (enchaînement recommandé)

1. `library_suggest_collection` avec `app_name`, `path` (dossier de l'appli) et `kind` = `app`, puis `kind` = `folder`.
2. **Demander la confirmation à l'utilisateur** : proposer la collection suggérée en premier choix, avec les autres
   collections de `library_list` (et « nouvelle collection » → `library_create_collection`). Ne jamais ranger sans accord.
3. `icons_app_kit` avec `image` (icône 1024 px de l'appli), `app_name`, `folder`, `collection_app`, `collection_folder`.
   Il fabrique l'icône d'appli et l'icône de dossier, pose l'icône sur le dossier (l'ancienne est sauvegardée) et range les
   deux dans la bibliothèque. Refaire l'appel met à jour les mêmes icônes (même image source).
4. Regarder les deux aperçus renvoyés avant de conclure.

La couleur du dossier, la gravure et le détourage suivent les réglages d'iCONIQ ; ne les passer (`folder_color`, `engraved`,
`remove_background`) que si l'utilisateur le demande.

## Autres outils

- `icons_make` : une icône seule (`kind` = `app` ou `folder`), fichiers `.icns` + PNG 1024.
- `icons_apply_to_folder` / `icons_clear_folder_icon` : poser ou retirer l'icône d'un dossier (dossiers du système,
  Applications, paquets d'appli et racines de disque refusés).
- `library_list`, `library_create_collection`, `library_create_group`, `library_add_icon` (avec `origin` pour mettre à jour
  sur place), `library_search`, `library_get_icon` (aperçu, export PNG).

## Raccordement

iCONIQ › Réglages › Pilotage IA › Raccorder (Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI), ou :
`claude mcp add --scope user iconiq -- "<iCONIQ.app>/Contents/MacOS/iconiq-mcp"`.
