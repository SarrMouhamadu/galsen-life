#!/usr/bin/env bash
# Optimisation des performances du noyau Linux pour serveurs MMO massivement multijoueurs (Galsen-Life)
# À exécuter en tant que root : sudo bash server/tune_kernel.sh
set -euo pipefail

echo "⚙️ Application des réglages noyau Linux pour des millions de connexions UDP sans perte..."

# 1. Tampons mémoire réseau UDP (64 Mo max, 32 Mo par défaut pour éviter tout drop de paquet)
cat << 'EOF' > /etc/sysctl.d/99-galsen-net.conf
# Tampons de réception et d'émission UDP
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432

# File d'attente de la carte réseau (évite le goulot d'étranglement lors des pics de trafic)
net.core.netdev_max_backlog = 100000

# Tampons minimum UDP
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Descripteurs de fichiers système
fs.file-max = 2097152

# Gestion de la mémoire et swapping réduit pour préserver la réactivité du serveur
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-galsen-net.conf

# 2. Limites de descripteurs de fichiers pour l'utilisateur galsen
cat << 'EOF' > /etc/security/limits.d/99-galsen.conf
galsen soft nofile 65535
galsen hard nofile 1048576
galsen soft nproc 65535
galsen hard nproc 65535
EOF

echo "✅ Noyau Linux optimisé pour la charge réseau maximale (UDP 64MB buffers, 1M file descriptors)."
