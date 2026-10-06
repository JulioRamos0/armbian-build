#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# CONFIGURACIÓN DEL DISPOSITIVO REMOTO
# (sobrescribible por variables de entorno)
# ==========================================
REMOTE_HOST="${REMOTE_HOST:-192.168.128.114}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASS="${REMOTE_PASS:-toor@100}"
REMOTE_DEB="${REMOTE_DEB:-/root/new_uboot.deb}"
UBOOT_BIN_PATH="${UBOOT_BIN_PATH:-/usr/lib/linux-u-boot-current-pbstvstick/u-boot-sunxi-with-spl.bin}"
EMMC_DEV="${EMMC_DEV:-/dev/mmcblk2}"
SPL_SEEK_KB=8                  # offset del SPL en la eMMC (KiB)
SPL_READ_KB=1024               # tamaño leído para verificar/respaldar (KiB)
BACKUP_DIR="${BACKUP_DIR:-backups}"

# Modos (export SKIP_BUILD=1, SKIP_DEPLOY=1, etc.)
SKIP_BUILD="${SKIP_BUILD:-0}"        # reusar el .deb más reciente sin recompilar
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"      # solo compilar
SKIP_BACKUP="${SKIP_BACKUP:-0}"      # no respaldar el bootloader actual de la eMMC

# sshpass lee la clave de SSHPASS (-e): no queda visible en la lista de procesos
export SSHPASS="${REMOTE_PASS}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10)

ssh_run() {
    local cmd="$1"
    echo -e "\n>>> ${cmd}"
    sshpass -e ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "${cmd}"
}

scp_push() {
    echo "Subiendo $1 -> $2..."
    sshpass -e scp "${SSH_OPTS[@]}" "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2"
    echo "Upload OK!"
}

scp_pull() {
    sshpass -e scp "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}:$1" "$2"
}

host_alive() {
    sshpass -e ssh "${SSH_OPTS[@]}" -o BatchMode=no "${REMOTE_USER}@${REMOTE_HOST}" true 2>/dev/null
}

START_TS=$(date +%s)
elapsed() { echo "$(( $(date +%s) - START_TS ))s"; }

# ==========================================
# 1. COMPILACIÓN DE U-BOOT
# ==========================================
if [ "${SKIP_BUILD}" = "1" ]; then
    echo "SKIP_BUILD=1: se reutiliza el último .deb."
else
    echo "=========================================="
    echo "Iniciando compilación de U-Boot..."
    echo "=========================================="
    ./compile.sh uboot \
        BOARD=pbstvstick \
        BRANCH=current \
        KERNEL_GIT=shallow
    echo "Compilación finalizada con éxito ($(elapsed))."
fi

# ==========================================
# 2. LOCALIZACIÓN DEL ARCHIVO .DEB
# ==========================================
echo -e "\nBuscando paquete .deb generado..."

DEB_FILE=$(find output/debs/ scratch/uboot_extracted_new/ -type f -name "linux-u-boot-*.deb" \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2- || true)

if [ -z "${DEB_FILE}" ]; then
    echo "ERROR: No se encontró ningún archivo linux-u-boot-*.deb" >&2
    exit 1
fi
echo "Paquete encontrado: ${DEB_FILE}"

if [ "${SKIP_DEPLOY}" = "1" ]; then
    echo "SKIP_DEPLOY=1: no se despliega. Tiempo total: $(elapsed)."
    exit 0
fi

# ==========================================
# 3. ¿HOST ACTIVO?
# ==========================================
echo "Comprobando ${REMOTE_HOST}..."
if ! host_alive; then
    echo "AVISO: ${REMOTE_HOST} no responde por SSH. Se omite el despliegue." >&2
    echo "El .deb queda en ${DEB_FILE}; reintenta con SKIP_BUILD=1 cuando el stick esté activo." >&2
    exit 0
fi

# ==========================================
# 4. DESPLIEGUE REMOTO VÍA SSH
# ==========================================
echo "=========================================="
echo "Iniciando despliegue hacia ${REMOTE_HOST}..."
echo "=========================================="

scp_push "${DEB_FILE}" "${REMOTE_DEB}"
ssh_run "dpkg -i ${REMOTE_DEB}"

# Verifica que el binario instalado trae el SPL esperado
ssh_run "strings ${UBOOT_BIN_PATH} | grep -m1 'U-Boot SPL 2026'"

# Respaldo del bootloader actual antes de sobrescribirlo (permite recuperar si no arranca)
if [ "${SKIP_BACKUP}" != "1" ]; then
    mkdir -p "${BACKUP_DIR}"
    BACKUP_NAME="emmc-spl-$(date +%Y%m%d-%H%M%S).bin"
    ssh_run "dd if=${EMMC_DEV} of=/root/${BACKUP_NAME} bs=1024 skip=${SPL_SEEK_KB} count=${SPL_READ_KB} conv=fsync 2>/dev/null"
    scp_pull "/root/${BACKUP_NAME}" "${BACKUP_DIR}/${BACKUP_NAME}"
    echo "Respaldo guardado en ${BACKUP_DIR}/${BACKUP_NAME}"
fi

# Flashear en la eMMC
ssh_run "dd if=${UBOOT_BIN_PATH} of=${EMMC_DEV} bs=1024 seek=${SPL_SEEK_KB} conv=fsync"

# Verificación bit a bit: lo escrito en la eMMC debe coincidir con el binario
ssh_run "SZ=\$(stat -c %s ${UBOOT_BIN_PATH}) && \
         dd if=${EMMC_DEV} bs=1024 skip=${SPL_SEEK_KB} 2>/dev/null | head -c \$SZ | cmp - ${UBOOT_BIN_PATH} \
         && echo 'VERIFICACION OK: eMMC == binario'"

# Sincronizar archivos del paquete a la partición 1 de la eMMC
ssh_run "mkdir -p /mnt/emmc && \
         (mount ${EMMC_DEV}p1 /mnt/emmc 2>/dev/null || true) && \
         (rsync -aHAXx /usr/lib/linux-u-boot-current-pbstvstick/ /mnt/emmc/usr/lib/linux-u-boot-current-pbstvstick/ 2>/dev/null || true) && \
         sync && \
         (umount /mnt/emmc 2>/dev/null || true)"

echo -e "\n******************************************"
echo "***        eMMC FLASH COMPLETE         ***"
echo "***        Tiempo total: $(elapsed)"
echo "******************************************"
