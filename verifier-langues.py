#!/usr/bin/env python3
# Vérifie que les 4 dictionnaires lang/*.json ont exactement les mêmes clés.
# Usage : python3 verifier-langues.py
import json, sys

LANGS = ["fr", "en", "es", "zh"]
dicos = {}
for l in LANGS:
    with open(f"lang/{l}.json", encoding="utf-8") as f:
        dicos[l] = json.load(f)

cles_fr = set(dicos["fr"].keys())
ok = True
for l in LANGS[1:]:
    k = set(dicos[l].keys())
    manq = cles_fr - k
    trop = k - cles_fr
    if manq:
        ok = False
        print(f"[{l}] clés manquantes ({len(manq)}) : {sorted(manq)}")
    if trop:
        ok = False
        print(f"[{l}] clés en trop ({len(trop)}) : {sorted(trop)}")

# vérifie les valeurs vides
for l in LANGS:
    vides = [c for c, v in dicos[l].items() if not str(v).strip()]
    if vides:
        ok = False
        print(f"[{l}] valeurs vides : {vides}")

print(f"Total clés (fr) : {len(cles_fr)}")
print("OK — clés identiques et non vides dans les 4 langues" if ok else "DIFFÉRENCES détectées")
sys.exit(0 if ok else 1)
