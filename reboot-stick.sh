#!/usr/bin/env bash
# Reinicia el TV Stick por SSH y comprueba que vuelve a arrancar.
#
#   MODE=reboot  -> reboot normal (systemd)
#   MODE=sysrq   -> sync; echo b > /proc/sysrq-trigger (reinicio inmediato, sin apagado limpio)
#
# Pensado para correr dentro del contenedor (ver servicio "reboot-stick" en docker-compose.yml).
# Variables (todas opcionales):
#   REMOTE_HOST  IP del stick                      (192.168.128.114)
#   REMOTE_USER  usuario SSH                       (root)
#   REMOTE_PASS  contraseña SSH                    (toor@100)
#   MODE         reboot | sysrq                    (reboot)
#   COUNT        reinicios consecutivos a probar   (1)
#   WAIT_DOWN    s máx. esperando que se apague    (90)
#   WAIT_UP      s máx. esperando que vuelva       (240)
#   PAUSE        s de espera entre reinicios       (0)
#   LOG_DIR      carpeta del CSV de resultados     (reboot-tests)
#
# Si el stick NO vuelve a responder (probable cuelgue del SPL) el script se detiene con
# código 2: hay que mirar el LED, esperar unos minutos, capturar la UART y cortar la energía.
set -uo pipefail

REMOTE_HOST="${REMOTE_HOST:-192.168.128.114}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASS="${REMOTE_PASS:-toor@100}"
MODE="${MODE:-reboot}"
COUNT="${COUNT:-1}"
WAIT_DOWN="${WAIT_DOWN:-90}"
WAIT_UP="${WAIT_UP:-240}"
PAUSE="${PAUSE:-0}"
LOG_DIR="${LOG_DIR:-reboot-tests}"

case "${MODE}" in
    reboot|sysrq) ;;
    *) echo "MODE debe ser 'reboot' o 'sysrq' (recibido: ${MODE})" >&2; exit 1 ;;
esac

# La clave va por variable de entorno (sshpass -e) para no verla en la lista de procesos
export SSHPASS="${REMOTE_PASS}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

ssh_run() {
    sshpass -e ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "$1"
}

host_up() {
    ssh_run true >/dev/null 2>&1
}

mkdir -p "${LOG_DIR}"
CSV="${LOG_DIR}/results.csv"
[ -s "${CSV}" ] || echo "timestamp,n,mode,temp_cpu_mC,temp_gpu_mC,uptime_s,seconds_to_ssh,result" > "${CSV}"

echo "Destino: ${REMOTE_USER}@${REMOTE_HOST}  modo: ${MODE}  repeticiones: ${COUNT}"

if ! host_up; then
    echo "ERROR: ${REMOTE_HOST} no responde por SSH antes de empezar." >&2
    exit 1
fi

fail=0
for n in $(seq 1 "${COUNT}"); do
    # Estado previo (temperatura, uptime, boot_id para confirmar luego que realmente reinició)
    info=$(ssh_run 'cat /sys/class/thermal/thermal_zone0/temp /sys/class/thermal/thermal_zone1/temp 2>/dev/null | tr "\n" " "; \
                    cut -d. -f1 /proc/uptime; cat /proc/sys/kernel/random/boot_id' 2>/dev/null) || info=""
    read -r t_cpu t_gpu up boot_id_before <<<"$(echo "${info}" | tr '\n' ' ')"
    echo
    echo "[${n}/${COUNT}] $(date '+%F %T')  cpu=${t_cpu:-?} mC  gpu=${t_gpu:-?} mC  uptime=${up:-?}s"

    # Lanza el reinicio. La conexión se corta, por eso se ignora el código de salida.
    case "${MODE}" in
        reboot) ssh_run 'sync; reboot' >/dev/null 2>&1 || true ;;
        sysrq)  ssh_run 'echo 1 > /proc/sys/kernel/sysrq; sync; echo b > /proc/sysrq-trigger' >/dev/null 2>&1 || true ;;
    esac

    # 1) esperar a que se apague
    went_down=0
    for _ in $(seq 1 "${WAIT_DOWN}"); do
        if ! host_up; then went_down=1; break; fi
        sleep 1
    done
    if [ "${went_down}" -eq 0 ]; then
        echo "  AVISO: el stick siguió respondiendo ${WAIT_DOWN} s: el reinicio no se ejecutó."
        echo "$(date '+%F %T'),${n},${MODE},${t_cpu:-},${t_gpu:-},${up:-},,no_reboot" >> "${CSV}"
        fail=1
        break
    fi

    # 2) esperar a que vuelva
    start=$(date +%s)
    came_back=0
    while [ $(( $(date +%s) - start )) -lt "${WAIT_UP}" ]; do
        if host_up; then came_back=1; break; fi
        sleep 2
    done
    secs=$(( $(date +%s) - start ))

    if [ "${came_back}" -eq 1 ]; then
        boot_id_after=$(ssh_run 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || echo "")
        if [ -n "${boot_id_before:-}" ] && [ "${boot_id_before}" = "${boot_id_after}" ]; then
            result="same_boot"
        else
            result="ok"
        fi
        echo "  Volvió a responder en ${secs} s  -> ${result}"
        echo "$(date '+%F %T'),${n},${MODE},${t_cpu:-},${t_gpu:-},${up:-},${secs},${result}" >> "${CSV}"
    else
        echo "  *** SIN RESPUESTA tras ${WAIT_UP} s: probable cuelgue del SPL ***"
        echo "  Revisa el LED (encendido = SPL congelado, apagado = reinicio), captura la UART,"
        echo "  espera unos minutos y después corta la energía."
        echo "$(date '+%F %T'),${n},${MODE},${t_cpu:-},${t_gpu:-},${up:-},,HANG" >> "${CSV}"
        exit 2
    fi

    [ "${n}" -lt "${COUNT}" ] && [ "${PAUSE}" -gt 0 ] && sleep "${PAUSE}"
done

echo
echo "Resumen (${CSV}):"
tail -n "$(( COUNT + 1 ))" "${CSV}" | column -s, -t 2>/dev/null || tail -n "${COUNT}" "${CSV}"
exit "${fail}"
