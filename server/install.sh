#!/usr/bin/env bash
# Installe (ou met à jour) le serveur Galsen-Life sur un VPS Ubuntu 22.04 / 24.04.
# À lancer en root depuis le dossier qui contient galsen-life.pck et galsen-life.service :
#   bash install.sh
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
SRC="$(cd "$(dirname "$0")" && pwd)"
DIR=/opt/galsen-life
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}"
ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"

apt-get update -y
apt-get install -y unzip curl

# Utilisateur système dédié (les comptes des joueurs sont dans son dossier personnel)
id -u galsen >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/galsen --shell /usr/sbin/nologin galsen

mkdir -p "$DIR"
cd "$DIR"
if [ ! -x Godot ]; then
  echo "Téléchargement de Godot ${GODOT_VERSION} (version officielle)..."
  curl -fsSL -o "$ZIP" "$BASE/$ZIP"
  curl -fsSL -o SHA512-SUMS.txt "$BASE/SHA512-SUMS.txt"
  grep " ${ZIP}\$" SHA512-SUMS.txt | sha512sum -c -
  unzip -o "$ZIP"
  mv "Godot_v${GODOT_VERSION}_linux.x86_64" Godot
  chmod +x Godot
  rm -f "$ZIP" SHA512-SUMS.txt
fi

cp "$SRC/galsen-life.pck" "$DIR/galsen-life.pck"
cp "$SRC/galsen-life.service" /etc/systemd/system/galsen-life.service
if [ -f "$SRC/galsen-cluster@.service" ]; then
  cp "$SRC/galsen-cluster@.service" /etc/systemd/system/galsen-cluster@.service
fi
if [ -f "$SRC/tune_kernel.sh" ]; then
  bash "$SRC/tune_kernel.sh" || true
fi
chown -R galsen:galsen "$DIR"

systemctl daemon-reload
systemctl enable galsen-life
systemctl restart galsen-life

# Pare-feu : SSH et les ports de shards UDP (7777..7785)
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp
  ufw allow 7777:7785/udp
fi

sleep 3
systemctl --no-pager status galsen-life | head -n 12
echo
echo "Serveur Galsen-Life installé. Adresse à saisir dans le jeu : $(curl -fsS -4 https://ifconfig.me || echo 'l IP de ton VPS')"
echo "Journal en direct : journalctl -u galsen-life -f"
