#!/usr/bin/env python3
"""Essai de bout en bout du serveur MCP d'iCONIQ (iconiq-mcp), sur un dossier de données temporaire.
Usage : python3 scripts/mcp_e2e.py [chemin/vers/iconiq-mcp]   (défaut : .build/debug/iconiq-mcp)"""
import json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".build/debug/iconiq-mcp")
IMAGE = os.path.join(ROOT, "assets/iCONIQ.png")
data = tempfile.mkdtemp(prefix="iconiq-mcp-")
work = os.path.join(ROOT, ".build/mcp-e2e"); shutil.rmtree(work, ignore_errors=True); os.makedirs(work)
folder = os.path.join(work, "MonAppli"); os.makedirs(folder)
env = dict(os.environ, ICONIQ_DATA_DIR=data)
checks = 0

def ok(cond, label):
    global checks
    if not cond: print("ÉCHEC :", label); sys.exit(1)
    checks += 1; print("ok", label)

class Client:
    def __init__(self):
        self.p = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, text=True)
        self.n = 0
        r = self.rpc("initialize", {"protocolVersion": "2025-03-26", "clientInfo": {"name": "e2e-test"}})
        ok(r["result"]["serverInfo"]["name"] == "iconiq", "initialize")
    def rpc(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n"); self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())
    def call(self, tool, **args):
        r = self.rpc("tools/call", {"name": tool, "arguments": args})["result"]
        text = r["content"][0]["text"]
        try: body = json.loads(text)
        except ValueError: body = text
        return body, r["isError"], [c for c in r["content"] if c["type"] == "image"]

def settings(change):
    p = os.path.join(data, "mcp.json")
    s = json.load(open(p)) if os.path.exists(p) else {}
    change(s); json.dump(s, open(p, "w"))

c = Client()
tools = {t["name"] for t in c.rpc("tools/list")["result"]["tools"]}
ok(len(tools) == 11 and "icons_app_kit" in tools, "tools/list : 11 outils")
_, err, _ = c.call("library_list"); ok(err, "refus quand le pilotage est désactivé")
settings(lambda s: s.update(enabled=True))
body, err, _ = c.call("library_list"); ok(err and "approval" in body, "client inconnu mis en attente")
ok(json.load(open(os.path.join(data, "mcp.json")))["clients"]["e2e-test"] == "pending", "état pending écrit")
settings(lambda s: s["clients"].update({"e2e-test": "allowed"}))
body, err, _ = c.call("library_create_group", name="Mes applis"); ok(not err and body["created"], "création d'un groupe")
g = body["id"]
body, err, _ = c.call("library_create_collection", name="Applications", group="Mes applis"); ok(not err and body["created"], "création d'une collection (groupe par nom)")
capp = body["id"]
body, _, _ = c.call("library_create_collection", name="applications", group=g); ok(body["id"] == capp and not body["created"], "collection existante renvoyée")
body, _, _ = c.call("library_create_collection", name="Dossiers"); cfold = body["id"]
body, _, _ = c.call("library_suggest_collection", app_name="MonAppli", kind="app"); ok("collection" not in body, "aucune suggestion sans réglage")
settings(lambda s: s.update(appCollection=capp, folderCollection=cfold, folderColor="nuit",
                            rules=[{"id": "r1", "field": "path", "contains": "skyrim", "kind": "any", "collection": cfold}]))
body, _, _ = c.call("library_suggest_collection", app_name="MonAppli", kind="app"); ok(body["collection"]["id"] == capp, "suggestion par défaut")
body, _, _ = c.call("library_suggest_collection", app_name="X", path="/Volumes/SKYRIM/TOOLS/X", kind="app"); ok(body["collection"]["id"] == cfold and "rule" in body["reason"], "suggestion par règle")
body, err, imgs = c.call("icons_make", image=IMAGE, kind="folder", output_dir=work, name="essai")
ok(not err and os.path.exists(body["icns"]) and os.path.exists(body["png"]) and imgs, "icons_make dossier (.icns, PNG, aperçu)")
body, err, _ = c.call("icons_make", image=IMAGE, kind="folder", folder_color="rose"); ok(err, "couleur inconnue refusée")
for bad in ["/Applications", os.path.expanduser("~"), "/System/Library", "/Volumes/" + os.listdir("/Volumes")[0]]:
    _, err, _ = c.call("icons_apply_to_folder", folder=bad, icon=IMAGE); ok(err, "pose refusée : " + bad)
body, err, imgs = c.call("icons_app_kit", image=IMAGE, app_name="MonAppli", folder=folder, output_dir=work)
ok(not err and body["folder_dressed"] == os.path.realpath(folder) and len(imgs) == 2, "icons_app_kit : deux icônes, dossier habillé")
ok(os.path.exists(os.path.join(folder, "Icon\r")), "icône personnalisée posée sur le dossier")
kinds = {e["kind"]: e["collection"] for e in body["library"]}; ok(kinds == {"app": "Applications", "folder": "Dossiers"}, "rangées dans les collections par défaut")
first = {e["kind"]: e["id"] for e in body["library"]}
body, err, _ = c.call("icons_app_kit", image=IMAGE, app_name="MonAppli", folder=folder, output_dir=work)
ok(not err and "previous_icon_backup" in body and os.path.exists(body["previous_icon_backup"]), "ancienne icône sauvegardée")
ok({e["kind"]: e["id"] for e in body["library"]} == first, "refaire met à jour les mêmes icônes (origine)")
body, err, _ = c.call("library_search", query="monappli"); ok(not err and body["count"] == 2, "recherche par nom")
body, err, imgs = c.call("library_get_icon", id=first["folder"], export_png=128, dest=work)
ok(not err and os.path.exists(body["exported"]) and imgs, "library_get_icon + export PNG")
body, err, _ = c.call("library_add_icon", file=IMAGE, name="Logo", collection="Applications", tags="logo", kind="app"); ok(not err, "library_add_icon")
body, err, _ = c.call("icons_clear_folder_icon", folder=folder); ok(not err and not os.path.exists(os.path.join(folder, "Icon\r")), "icône du dossier retirée")
ok(len(open(os.path.join(data, "mcp.log")).read().splitlines()) >= 10, "journal écrit")
c.p.stdin.close(); c.p.wait()
shutil.rmtree(data); shutil.rmtree(work)
print(f"{checks} vérifications réussies")
