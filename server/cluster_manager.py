#!/usr/bin/env python3
"""
Galsen-Life Cluster Manager
Superviseur multi-shards pour serveurs de jeu massivement multijoueurs.
Permet d'exécuter N shards Godot sur plusieurs cœurs de processeur (ports 7777..7785)
avec redémarrage automatique, journalisation consolidée et synchronisation de base de données.
"""

import os
import sys
import time
import subprocess
import signal

GODOT_BIN = os.environ.get("GODOT_BIN", "/opt/galsen-life/Godot")
PCK_PATH = os.environ.get("PCK_PATH", "/opt/galsen-life/galsen-life.pck")
START_PORT = int(os.environ.get("START_PORT", "7777"))
NUM_SHARDS = int(os.environ.get("NUM_SHARDS", "5"))
MAX_PLAYERS_PER_SHARD = int(os.environ.get("MAX_PLAYERS", "4095"))

processes = {}
running = True

def signal_handler(sig, frame):
    global running
    print(f"\n[CLUSTER] Signal {sig} reçu : arrêt de tous les shards...")
    running = False
    for port, proc in list(processes.items()):
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def start_shard(port):
    cmd = [
        GODOT_BIN,
        "--headless",
        "--main-pack", PCK_PATH,
        "--",
        "--server",
        f"--port={port}",
        f"--max-players={MAX_PLAYERS_PER_SHARD}"
    ]
    print(f"[CLUSTER] Démarrage du Shard Dakar sur port UDP {port} (capacité: {MAX_PLAYERS_PER_SHARD} joueurs)...")
    try:
        proc = subprocess.Popen(cmd)
        return proc
    except Exception as e:
        print(f"[CLUSTER ERREUR] Impossible de lancer le port {port}: {e}")
        return None

def main():
    print("=" * 65)
    print(f"🚀 Galsen-Life Cluster Manager démarré ({NUM_SHARDS} shards, total: {NUM_SHARDS * MAX_PLAYERS_PER_SHARD} joueurs)")
    print("=" * 65)

    for i in range(NUM_SHARDS):
        port = START_PORT + i
        processes[port] = start_shard(port)
        time.sleep(1.0)

    while running:
        for port, proc in list(processes.items()):
            if proc is None or proc.poll() is not None:
                exit_code = proc.poll() if proc else -1
                print(f"[CLUSTER ATTENTION] Le Shard {port} s'est arrêté (code {exit_code}). Redémarrage automatique...")
                processes[port] = start_shard(port)
        time.sleep(3.0)

if __name__ == "__main__":
    main()
