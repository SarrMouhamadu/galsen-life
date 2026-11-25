#!/usr/bin/env python3
"""
Télécharge et découpe les 4 musiques demandées par l'utilisateur :
1. IklAfq4-o9A : Muet les 30 premières secondes (départ à 30s) -> Sabar, Tama & Mbeur
2. Q54RfLqqpKE : Musique principale générique JOJ 2026 par Iss 814
3. tmkblsttfVk : Départ à la 45e seconde -> Niany bagne na (Kiné Lam)
4. wJvhycjb1-I : Musique principale par défaut au lancement -> Départ à la 57e seconde (Baaba Maal)
"""

import os
import subprocess
import tempfile
import sys

TRACKS = [
    {
        "id": "wJvhycjb1-I",
        "name": "baaba_maal_joj",
        "title": "Cérémonie JOJ 2026 — Prestation Baaba Maal (Musique Principale Lancement)",
        "start_sec": 57,
        "fade_in": 0.5,
    },
    {
        "id": "Q54RfLqqpKE",
        "name": "iss814_joj",
        "title": "Générique JOJ 2026 — Iss 814 Beats (Musique Principale)",
        "start_sec": 0,
        "fade_in": 0.5,
    },
    {
        "id": "tmkblsttfVk",
        "name": "kine_lam_niany",
        "title": "Niany Bagne Na — Prestation Kiné Lam",
        "start_sec": 45,
        "fade_in": 0.5,
    },
    {
        "id": "IklAfq4-o9A",
        "name": "sabar_tama_mbeur",
        "title": "Ambiance Sabar, Tama & Mbeur — Cérémonie JOJ",
        "start_sec": 30,
        "fade_in": 0.5,
    },
]

OUT_DIR = os.path.abspath("audio/music")
os.makedirs(OUT_DIR, exist_ok=True)

def process_track(track):
    url = f"https://www.youtube.com/watch?v={track['id']}"
    out_mp3 = os.path.join(OUT_DIR, f"{track['name']}.mp3")

    print(f"\n=======================================================")
    print(f"🎵 Traitement de : {track['title']}")
    print(f"🔗 URL: {url} | Départ à: {track['start_sec']}s")
    print(f"=======================================================")

    with tempfile.TemporaryDirectory() as tmpdir:
        raw_dl = os.path.join(tmpdir, "raw.%(ext)s")
        
        # 1. Téléchargement audio via yt-dlp
        dl_cmd = [
            "yt-dlp",
            "--no-update",
            "--extractor-args", "youtube:player_client=android",
            "-f", "ba/b",
            "-o", raw_dl,
            url
        ]
        print("Téléchargement du flux audio...")
        res = subprocess.run(dl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            print(f"Erreur yt-dlp: {res.stderr}")
            return False

        files = os.listdir(tmpdir)
        if not files:
            print("Aucun fichier téléchargé dans le dossier temporaire.")
            return False
        dl_file = os.path.join(tmpdir, files[0])
        print(f"Téléchargé avec succès: {files[0]} ({os.path.getsize(dl_file)} octets)")

        # 2. Découpage et conversion MP3 avec ffmpeg
        fade_filter = f"afade=t=in:ss=0:d={track['fade_in']}"

        mp3_cmd = [
            "ffmpeg", "-y",
            "-ss", str(track["start_sec"]),
            "-i", dl_file,
            "-af", fade_filter,
            "-vn",
            "-c:a", "libmp3lame",
            "-b:a", "160k",
            out_mp3
        ]
        print(f"Conversion MP3 -> {out_mp3}")
        subprocess.run(mp3_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True)

        print(f"✅ Terminé : {out_mp3} ({os.path.getsize(out_mp3) // 1024} Ko)")
        return True

def main():
    success = 0
    for t in TRACKS:
        if process_track(t):
            success += 1
    print(f"\n=======================================================")
    print(f"🎉 {success}/{len(TRACKS)} morceaux traités avec succès dans {OUT_DIR}")
    print(f"=======================================================")

if __name__ == "__main__":
    main()
