import os
import subprocess
import sys

TRACKS = [
    ("Dr8JR8EogT0", "audio/music/souleymane_faye_nobel.mp3", "Souleymane Faye & Xalam - Nobel"),
    ("nO5aCDfV2ZQ", "audio/music/toure_kunda_fatou_yo.mp3", "Touré Kunda - Fatou Yo"),
    ("OX4i1NXN_lQ", "audio/music/toure_kunda_fondinke.mp3", "Touré Kunda - Fondinke"),
    ("tPQjw-rKrpc", "audio/music/toure_kunda_emma.mp3", "Touré Kunda - Em'ma"),
    ("VshSexUMyzY", "audio/music/xalam_is_do_si.mp3", "Xalam - Is Do Si"),
    ("XVzf5U36gBo", "audio/music/xalam_ninki_nanka.mp3", "Xalam - Ninki Nanka"),
    ("bfC2F7o0kno", "audio/music/toure_kunda_natalia.mp3", "Touré Kunda - Natalia"),
    ("10Uc-P0j06Y", "audio/music/toure_kunda_duunya.mp3", "Touré Kunda - Duunya"),
    ("6uk6P5Tbrig", "audio/music/coumba_gawlo_miniyamba.mp3", "Coumba Gawlo - Miniyamba"),
    ("ZV9PH593QRU", "audio/music/books_jas_reference.mp3", "Books feat. Jas - Reference"),
    ("-RcgCDqVC9k", "audio/music/diogal_sakho_massa_thiono.mp3", "Diogal Sakho - Massa Thiono"),
    ("glcij6-S11E", "audio/music/el_hadji_ndiaye_weet.mp3", "El Hadji Ndiaye - Weet"),
    ("MIAf60xzjZo", "audio/music/pape_et_cheikh_sogni.mp3", "Pape & Cheikh - Sogni"),
    ("k5eDy7N_zks", "audio/music/choeurs_senegal_wolof.mp3", "African Choirs - Wolof Song"),
    ("ONFTONKdR_4", "audio/music/ashs_the_best_dellusil.mp3", "Ashs The Best - Dellusil"),
    ("3erGLa8nhyc", "audio/music/mamy_mbaye_teranga_joj.mp3", "Mamy Mbaye - Teranga (JOJ Dakar 2026)"),
]

for video_id, out_path, title in TRACKS:
    if os.path.exists(out_path):
        print(f"[SKIP] {title} already exists at {out_path}")
        continue
    print(f"\n[DOWNLOADING] {title} ({video_id})...")
    prefix = out_path.rsplit(".", 1)[0]
    cmd = [
        "/opt/homebrew/bin/yt-dlp",
        "--js-runtimes", "node:/opt/homebrew/bin/node",
        "--extractor-args", "youtube:player_client=android,ios,web",
        "-x", "--audio-format", "mp3",
        "--audio-quality", "128k",
        "-o", f"{prefix}.%(ext)s",
        f"https://www.youtube.com/watch?v={video_id}"
    ]
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f"[ERROR] Failed to download {title}")
    else:
        print(f"[DONE] {title} saved to {out_path}")

print("\n--- ALL DOWNLOADS FINISHED ---")
