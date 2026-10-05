#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# CONFIGURACIÓN DEL DISPOSITIVO REMOTO
# ==========================================
REMOTE_HOST="192.168.128.114"
REMOTE_USER="root"
REMOTE_PASS="toor@100"
REMOTE_DEB="/root/new_uboot.deb"
UBOOT_BIN_PATH="/usr/lib/linux-u-boot-current-pbstvstick/u-boot-sunxi-with-spl.bin"

# Función auxiliar para ejecutar SSH
ssh_run() {
    local cmd="$1"
    echo -e "\n>>> ${cmd}"
    sshpass -p "${REMOTE_PASS}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "${REMOTE_USER}@${REMOTE_HOST}" "${cmd}"
}

# Función auxiliar para transferir vía SCP
scp_push() {
    local local_file="$1"
    local dest_path="$2"
    echo "Subiendo ${local_file} -> ${dest_path}..."
    sshpass -p "${REMOTE_PASS}" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "${local_file}" "${REMOTE_USER}@${REMOTE_HOST}:${dest_path}"
    echo "Upload OK!"
}

# ==========================================
# 1. COMPILACIÓN DE U-BOOT (EN EL CONTENEDOR)
# ==========================================
echo "=========================================="
echo "Iniciando compilación de U-Boot..."
echo "=========================================="

./compile.sh uboot \
    BOARD=pbstvstick \
    BRANCH=current \
    KERNEL_GIT=shallow

echo "Compilación finalizada con éxito."

# ==========================================
# 2. LOCALIZACIÓN DEL ARCHIVO .DEB
# ==========================================
echo -e "\nBuscando paquete .deb generado..."

DEB_FILE=$(find output/debs/ scratch/uboot_extracted_new/ -type f -name "linux-u-boot-*.deb" 2>/dev/null | xargs ls -t 2>/dev/null | head -n 1 || true)

if [ -z "${DEB_FILE}" ]; then
    echo "ERROR: No se encontró ningún archivo linux-u-boot-*.deb" >&2
    exit 1
fi

echo "Paquete encontrado: ${DEB_FILE}"

# ==========================================
# 3. DESPLIEGUE REMOTO VÍA SSH
# ==========================================
echo "=========================================="
echo "Iniciando despliegue hacia ${REMOTE_HOST}..."
echo "=========================================="

# 1. Subir paquete deb
scp_push "${DEB_FILE}" "${REMOTE_DEB}"

# 2. Instalar paquete en el dispositivo
ssh_run "dpkg -i ${REMOTE_DEB}"

# 3. Verificar la versión en los archivos del paquete
ssh_run "strings ${UBOOT_BIN_PATH} 2>/dev/null | grep 'U-Boot SPL 2026'"

# 4. Flashear en la eMMC (/dev/mmcblk2)
ssh_run "dd if=${UBOOT_BIN_PATH} of=/dev/mmcblk2 bs=1024 seek=8 conv=fsync"

# 5. Verificar lectura directa desde la eMMC
ssh_run "dd if=/dev/mmcblk2 bs=1024 skip=8 count=1024 2>/dev/null | strings | grep 'U-Boot SPL 2026'"

# 6. Montar partición eMMC, sincronizar archivos y desmontar
ssh_run "mkdir -p /mnt/emmc && \
         (mount /dev/mmcblk2p1 /mnt/emmc 2>/dev/null || true) && \
         (rsync -aHAXx /usr/lib/linux-u-boot-current-pbstvstick/ /mnt/emmc/usr/lib/linux-u-boot-current-pbstvstick/ 2>/dev/null || true) && \
         sync && \
         (umount /mnt/emmc 2>/dev/null || true)"

echo -e "\n******************************************"
echo "***        eMMC FLASH COMPLETE         ***"
echo "******************************************"