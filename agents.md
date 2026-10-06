# Rol y Objetivo Principal
Eres el **Experto en Compilación de U-Boot para Allwinner H5** (board `pbstvstick`, TV Stick genérico clon de Orange Pi).

**Propósito de este repositorio:** compilar y mantener soporte **únicamente en U-Boot** para el eMMC **KLMAG2WEPD** (puerto `mmc2`), lo cual a la vez resuelve temas de compatibilidad con microSD de alta velocidad (ej. clase **A2**).

**Tu objetivo principal es ayudar al usuario a compilar este repositorio.** Todo lo que no tenga que ver con compilar queda fuera de alcance por ahora. Guía al usuario según el entorno:
1. **Local (Windows) usando WSL** (Recomendado).
2. **Nativo (Linux)**.
3. **Docker** (SIEMPRE advierte que puede ser muy lento).

# Hardware Relevante
- **SoC:** Allwinner H5 (4 núcleos ARM64, Cortex-A53)
- **RAM:** 1GB
- **Almacenamiento interno:** eMMC KLMAG2WEPD soldada, en `mmc2`.
- **Almacenamiento externo:** microSD (incluyendo tarjetas de alta velocidad A2).

## Sticks de referencia (dos variantes de hardware)
| Stick | eMMC | CPU (marcado) | Carga desde eMMC |
|---|---|---|---|
| stick1 (`192.168.128.15`) | NCEMBSF9 (Linux la reporta como `NCard`, fab. `0x88`) | Allwinner H5 G8116AA | **Funciona** |
| stick2 | KLMAG2WEPD | Allwinner H5 G8006AA | **No funciona** (el SPL se cuelga leyendo el FIT) |

- **Variables confundidas:** cambian a la vez el chip eMMC **y** el marcado del CPU. Con estos dos datos no se puede atribuir el fallo a uno solo; el CPU (otra revisión o lote del H5) es una causa posible, igual que el eMMC o la placa.
- **Pendiente para separarlas** (cada una con responsable y fecha en Jira/Monday): (a) confirmar que stick1 arranca con el **mismo** binario SPL que falla en stick2; (b) comparar en Linux, en ambos sticks, `CID`/`EXT_CSD` del eMMC (`mmc-utils`) y `/sys/kernel/debug/mmc2/ios` (modo, reloj, ancho de bus); (c) comparar el comportamiento del SPL con la misma imagen y un reloj aún más bajo en stick2.
- **Medido en stick2 (SSH, 5-oct-2026):** CPU **Cortex-A53 r0p4** (`CPU part 0xd03`, ARMv8, 4 núcleos, `Features: fp asimd aes pmull sha1 sha2 crc32`); DT `xunlong,orangepi-prime allwinner,sun50i-h5`. eMMC: nombre `AWPD3R`, fabricante `0x15` (Samsung), fecha 07/2016, EXT_CSD rev 1.7 (MMC 5.0), 14.6G. **En Linux la eMMC corre a 50 MHz, 8 bits, timing `mmc high-speed`, 3.3 V**; el SPL la usa a 4 MHz y se cuelga.
- **Medido en stick1 (192.168.128.15, 6-oct-2026, arranca desde la eMMC):** CPU también **Cortex-A53 r0p4**; DT `Orange Pi Prime`. eMMC: nombre `NCard`, fabricante `0x88`, fecha 03/2017, EXT_CSD rev 1.7 (MMC 5.0), 14.5G, caché 8 MiB, BKOPS soportado; en Linux corre a **50 MHz, 8 bits, `mmc high-speed`, 3.3 V**, igual que stick2.
- **Comparación:**

| | stick1 (funciona) | stick2 (se cuelga) |
|---|---|---|
| eMMC (nombre / fabricante) | `NCard` / `0x88` | `AWPD3R` / `0x15` (Samsung) |
| Fecha eMMC | 03/2017 | 07/2016 |
| Núcleo CPU | Cortex-A53 r0p4 | Cortex-A53 r0p4 |
| Marcado CPU | G8116AA | G8006AA |
| `CMD1` en el init del SPL | 4 | 5 |
| Linux sobre la eMMC | 50 MHz, 8 bit, HS | 50 MHz, 8 bit, HS |

- **Lectura:** el núcleo del CPU es idéntico; lo que difiere es el chip eMMC (fabricante y revisión) y el marcado del SoC. Pendiente: comparar `mmc extcsd read` completo de ambos (stick2 estaba apagado al intentarlo).
- **Conclusión sobre el CPU:** el núcleo es el mismo Cortex-A53 que se asume, así que no es un problema de arquitectura. Falta medir stick1 (G8116AA) con los mismos comandos para ver si su `CPU revision`/`Stepping` difiere.
- **Nota:** Linux sí lee la eMMC de stick2 completa (14.6G, FIT verificado), así que el controlador funciona allí; Linux usa DMA y ajuste de fases de reloj, que el SPL no hace. Es una hipótesis sobre la diferencia, no un hallazgo.

# Estrategias de Compilación Armbian

Se compila el sistema (`pbstvstick.csc`) con las siguientes vías:

## 1. Local (Windows) usando WSL o Nativo (Linux) [RECOMENDADO]
Es la forma más rápida y estable.

* **Si usas Windows + WSL:** Clona el repositorio **nativamente dentro del disco de WSL** (ej. `~/armbian-build` o `/opt/armbian-build`) para evitar symlinks rotos de Windows que destruyen la compilación. Luego copia tus parches a esa carpeta.
* **WSL SOLO se usa para compilar (`build`).** Pruebas y conexiones con el dispositivo se hacen desde la terminal nativa del host.

> [!IMPORTANT]
> **Arreglar soporte ARM64 en WSL (Error `arm64: not supported`)**
> Si al compilar nativamente como `root` aparece `arm64: not supported on this machine/kernel` o `Failed to update binfmts`, el kernel de WSL no tiene registrados los emuladores ARM. Para inyectarlos (hasta el próximo reinicio de WSL), lanza antes de compilar:
> ```bash
> docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
> ```

**A) El replicable y seguro (Desde cero):**
Borra toda la caché y descarga las fuentes desde cero (tarda más). Versión confirmada que compila exitosamente:
```bash
./compile.sh build BOARD=pbstvstick BRANCH=current BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_BTF=no RELEASE=trixie KERNEL_CONFIGURE=no KERNEL_GIT=shallow CLEAN_LEVEL=make,cache,sources
```

**B) El ultra rápido (Para iterar):**
Reusa la caché al remover `CLEAN_LEVEL`. Úsalo tras un build completo previo y cambios pequeños (ej. un parche):
```bash
./compile.sh build BOARD=pbstvstick BRANCH=current BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_BTF=no RELEASE=trixie KERNEL_CONFIGURE=no KERNEL_GIT=shallow
```

## 2. Docker Compose (Solo Windows)
⚠️ **ADVERTENCIA:** Montar el volumen desde el disco de Windows **puede ser extremadamente lento** comparado con WSL nativo.
```bash
docker compose up
```
*(Por detrás, `armbian-entrypoint.sh` fuerza una compilación limpia con `CLEAN_LEVEL=make,cache,sources`).*

## 3. Compilación remota con GitHub Actions (CI)
Evita la palabra `docker` en el comando (GitHub ya ejecuta en contenedor y causa el error `asking for docker... inside docker`). Usa `build`:
```bash
sudo ./compile.sh build BOARD=pbstvstick BRANCH=current BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_BTF=no KERNEL_CONFIGURE=no RELEASE=bookworm CLEAN_LEVEL=make,cache,sources
```

## 4. Extraer la Imagen Compilada (WSL a Windows)
La imagen `.img` queda en `output/images/`. Si compilaste dentro del disco de WSL:

- **Explorador de Windows:** `\\wsl.localhost\Ubuntu\opt\armbian-build\output\images\`
- **Terminal WSL** (cambia `TuUsuario`):
  ```bash
  cp output/images/Armbian_*.img /mnt/c/Users/TuUsuario/Desktop/
  ```

## 5. Compilación Rápida de U-Boot con Docker + Despliegue Automático [PARA ITERAR]
Para acelerar la búsqueda de la mejor solución se compila **solo U-Boot** (no la imagen completa) dentro de un contenedor y se despliega al TV Stick. Archivos en la raíz:

- `dockerfile`: imagen Debian con las dependencias de compilación de Armbian/U-Boot (`build-essential`, `swig`, `device-tree-compiler`, `sshpass`, `rsync`, etc.). Copia `build-deploy-uboot.sh` y lo usa como `CMD`.
- `docker-compose.yml`: servicio `build-uboot` (`privileged`, `network_mode: host` para alcanzar el dispositivo en la LAN). Monta el repo en `/workspace` y un volumen persistente `armbian-cache` en `/workspace/cache` para reusar la caché entre corridas.
- `build-deploy-uboot.sh`: orquesta todo el ciclo:
  1. `./compile.sh uboot BOARD=pbstvstick BRANCH=current KERNEL_GIT=shallow`.
  2. Localiza el `linux-u-boot-*.deb` más reciente (`output/debs/` o `scratch/uboot_extracted_new/`).
  3. Lo sube por `scp` a `root@192.168.128.114:/root/new_uboot.deb` (con `sshpass`) y lo instala con `dpkg -i`.
  4. Verifica la cadena `U-Boot SPL 2026` en el binario y lo flashea con `dd` a `/dev/mmcblk2` (`bs=1024 seek=8`); relee desde la eMMC para confirmar.
  5. Sincroniza `/usr/lib/linux-u-boot-current-pbstvstick/` a la partición 1 de la eMMC.

Uso:
```bash
docker compose up --build
```
⚠️ El script **no** comprueba si el host está activo antes de desplegar: si no responde, la compilación termina bien pero el `scp` falla (`ConnectTimeout=10`). El `.deb` queda en `output/debs/` para desplegarlo luego. Las credenciales SSH están definidas dentro del script (`REMOTE_PASS`).

> Aplican las advertencias de Docker sobre velocidad (sección 2); la caché persistente en volumen es lo que hace rentable este flujo para iterar.

# Soporte eMMC KLMAG2WEPD en U-Boot

Para que el SPL/U-Boot detecte y arranque desde el eMMC (`mmc2`) se requieren dos piezas:

1. **Configuración de U-Boot (.csc):** `scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA 2` dentro de `post_config_uboot_target`. **Debe ser `2`, no `-1`**: con `-1` solo se registra el slot 0 (microSD vacía) y el SPL falla con `Card did not respond to voltage select! : -110`.
2. **Un solo slot en el SPL:** el `.csc` usa `CONFIG_SPL_MMC_TINY`, que maneja un único `struct mmc` estático, y registrar ambos slots causó brownout. El parche `patch/u-boot/v2026.07-sunxi64/sunxi-spl-init-only-boot-mmc-slot.patch` hace que, si el BROM arrancó desde MMC2, `board_mmc_init` registre solo el eMMC. Log esperado: `[MMC2] legacy init b_max=1` y `[SPL] mmc init ok`. Si aparece `[MMC0]`, el fix no aplica.
3. **Device Tree de U-Boot (DTS):** **CRÍTICO PARA EVITAR LA PANTALLA NEGRA.** U-Boot usa su propio DT. Debe habilitarse `mmc2` en `arch/arm/dts/sun50i-h5-orangepi-prime.dts` (de U-Boot) mediante parche en `patch/u-boot/v2026.07-sunxi64/`. Sin esto no puede leer `/boot/boot.scr` ni el kernel.

```dts
&mmc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <8>;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};
```

# Depuración Actual: Arranque U-Boot SPL desde eMMC (MMC2)

## 0. Regresión del 5-oct-2026 (log: `[MMC0] legacy init`, `Card did not respond to voltage select! : -110`, `SPL: Unsupported Boot Device!`)
- **Causa:** el commit `88c0a0a` puso `SLOT_EXTRA=-1`; con `SPL_MMC_TINY` el SPL inicializaba el slot 0 (SD vacía) en vez del eMMC. Las hipótesis b_max/FIFO de abajo se investigaban sin que el SPL llegara al eMMC.
- **Fix aplicado (pendiente de validar en hardware):** `SLOT_EXTRA=2` + parche `sunxi-spl-init-only-boot-mmc-slot.patch`.
- **Riesgos abiertos:** el brownout podría reaparecer en U-Boot proper (inicializa ambos slots); el `sed` "Hard Reset eMMC" del `.csc` busca `mmc0 = sunxi_mmc_init`, que no existe en `board.c`, así que nunca se aplica.

## 0b. Estado de la iteración actual (5-oct-2026)
Cadena de builds y conclusiones (cada línea = un log real):
- `P2f00`: eMMC inicializa (`mmc init ok`, 4 MHz). Lectura de 1 692 sectores se cuelga tras `#3`.
- `P99c0`: con trace cada 4, se cuelga entre `#8` y `#12`.
- `P6b14`: con marcadores `w`/`t`, se cuelga en `w` sin `t` en `#7`: **dentro de la lectura del FIFO**, sin ningún timeout ni `[CL..]`. El sector cambia entre builds, así que no depende de la dirección.
- Dato de hardware nuevo: stick1 (eMMC NCEMBSF9, CPU G8116AA) carga desde eMMC; stick2 (KLMAG2WEPD, G8006AA) se cuelga. Ver "Sticks de referencia".
- `Paa9e`: sin ningún `[TR]`: el CPU se detiene fuera del lazo de espera, siempre en `#7`. Se añadieron marcadores `a`/`f`/`L` (putc) para acotar el punto.
- `P2066` y `P1e4c`: con marcadores por palabra el cuelgue es a mitad del bloque 7 y, en `P1e4c`, la consola termina con `resee` (inicio truncado de `resetting ...`). **Hipótesis principal (sin confirmar): el watchdog del SoC reinicia el SPL.** Indicios: (1) el punto de muerte se adelanta cuanto más se imprime (comportamiento por tiempo, no por sector); (2) el log termina con texto de reinicio; (3) el commit `ce56da3` alimentaba el watchdog (`0x01c20cb0`) y `b62ab9a` lo quitó. Config final: `WDT_SUNXI=y`, `WATCHDOG_TIMEOUT_MSECS=16000`, sin `SPL_WDT`. Parche de prueba: `mmc-sunxi-spl-wdt.patch` (apaga el WDT en `0x01c20cb8` y lo alimenta por comando). Si el cuelgue desaparece, la hipótesis queda confirmada.
- `Pe250` (con `mmc-sunxi-spl-wdt.patch`): **mismo cuelgue en el bloque 7** (`w a` y nada más). **La hipótesis del watchdog queda refutada** (los offsets del WDT H5 se verificaron: `wdog[0]` en `0x01c20ca0`, `mode` en `0xb8`). Se mantiene el patrón: muere siempre en el bloque 7 sin importar qué se imprima ni dónde, aunque con menos prints llegó un poco más lejos (`P99c0`, bloques 8 a 11). El `resee` de `P1e4c` no se reprodujo. Hipótesis vivas, sin confirmar: alimentación del stick2, margen de la DRAM (`DRAM_CLK 576` + ODT del `.csc`) o un efecto por tiempo desde el arranque. Siguiente experimento sin código: flashear la misma imagen en stick1 y probar stick2 con una fuente 5V/2A sólida.
- **Stick1 con el mismo binario `Pe250`: carga el FIT con normalidad** (lee el FIT completo y **completó el arranque**, confirmado por el equipo; hoy corre desde la eMMC). Stick2 con fuente 5V/2A: muere igual en el bloque 7. **Conclusión: el cuelgue depende del hardware de stick2 (eMMC KLMAG2WEPD, CPU G8006AA o su placa), no del software ni de la alimentación.** Diferencia visible en el init: stick2 necesita 5 `CMD1` y stick1 4.
- **`Pd342` (stick2): con una pausa de 2 s tras `mmc init ok` el SPL lee los 1 692 bloques completos** (`info->read count=866304`, `simple_fit_read ret=0`). Ese build aún llevaba el desplazamiento de sectores, por eso falla después con `mmc block read error` (esperado, lee datos que no son el FIT). **Es el primer avance real.** Interpretación (hipótesis): la eMMC KLMAG2WEPD necesita tiempo tras el init antes de aceptar lecturas de datos seguidas, o queda ocupada (DAT0 bajo) un rato; si el SPL emite comandos de datos en ese intervalo, el SoC se congela. Encaja con todo lo visto: muerte en un punto que se mueve según lo impreso, independiente del sector y de la DRAM, y sin efecto en stick1.
- **Build con pausa de 500 ms + espera de DAT0 (6-oct-2026): stick2 ARRANCA desde la eMMC** (confirmado por el equipo; falta pegar el log para ver si apareció la `B`, la pausa `[SETTLE 500ms]` y hasta dónde llegó el arranque). Es la primera vez que la KLMAG2WEPD arranca con el U-Boot de este repo.
- **`P6adb` (pausa 500 ms + espera de DAT0), log de stick2:** aparece `[SETTLE 500ms]` y el FIT se lee sin morir hasta al menos el bloque `#1072` de 1 692 (el log pegado termina ahí, cortado por el tamaño del pegado; el equipo confirmó que el stick arrancó). **No aparece ninguna `B`**: el busy-wait nunca vio la tarjeta ocupada, así que la hipótesis de DAT0 ocupado no queda apoyada; lo que arregla el problema es la pausa tras el init (o algo que depende del tiempo transcurrido desde el init). Causa exacta sin identificar.
- **`Pdeb7` (pausa 100 ms), stick2:** supera el bloque `#7` (el log pegado llega hasta `#48` y termina ahí, cortado por el pegado; falta confirmar si completó el arranque). Con 100 ms ya no muere donde moría sin pausa.
- **`Pdeb7` confirmado por el equipo: Linux inicia con pausa de 100 ms y el `reboot` desde consola arrancó bien** (el `reboot` fallido anterior fue con el build sin pausa suficiente; hipótesis: la misma causa). Falta repetirlo varias veces para darlo por estable.
- **`P6d7a` (build silencioso, pausa 100 ms), `reboot` desde SSH en stick2 (6-oct-2026): ARRANCA.** La UART muestra el SPL completo (`mmc init ok`, `[SETTLE 100ms]`, FIT leída `count=866304`, `simple_fit_read ret=0`, `mmc_load_image_raw_sector ret=0`), luego BL31 v2.12.9, Crust SCP v0.6.10000, y **U-Boot 2026.07 proper** (`MMC: mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1`), hasta `starting USB...`. El equipo reporta que Linux inició y más rápido que antes. Es **una sola muestra**: falta repetir arranques en frío y `reboot`.
- **`P6d7a`: arranque completo hasta `Starting kernel ...` (stick2, 6-oct-2026).** U-Boot proper encuentra `boot.scr` en la eMMC (`mmc 1:1`), carga el DTB `sun50i-h5-orangepi-prime.dtb` y el overlay `analog-codec`, y lee **initrd 18 368 787 B en 1 519 ms y kernel 33 405 440 B en 2 761 ms (11,5 MiB/s, medido por U-Boot)**: unos 4,3 s solo en cargar archivos. `Hit any key to stop autoboot: 0` (sin espera). Aviso inocuo: `Card did not respond to voltage select! ... Bad device specification mmc 0` (la microSD está ausente). El driver de U-Boot proper va a ≈ 25 MHz y 4 bits por el nodo `&mmc2` del `.csc` (`bus-width = <4>`, `max-frequency = <25000000>`); subirlo es la mejora más directa de tiempo, pendiente de datos de estabilidad.
- **Segundo `reboot` seguido: se quedó en `[MMC2] legacy init b_max=1`** (SPL sin trazas, no se ve en qué paso). El equipo percibió el CPU **muy caliente** en ese momento. Es la **primera vez que falla el build silencioso**. Hipótesis sin confirmar: (a) temperatura (arranque caliente tras haber corrido Linux); (b) estado de la eMMC tras un reinicio de software en el intervalo inmediato al init; (c) la misma causa del cuelgue original en otro punto. Ese mismo silencio tras `legacy init` ya se vio en el primer log después de arreglar `SLOT_EXTRA`. Se preparó `zzz-mmc-sunxi-init-trace-lite.patch` (solo `[T] clk`, `[T] clk ok`, `[T] create`, `[T] reset` y los 12 primeros `[T] cmdN`, ≈ 150 caracteres) para ver dónde se corta. Pruebas sugeridas: registrar `/sys/class/thermal/thermal_zone*/temp` antes de cada `reboot`; repetir reinicios dejando enfriar vs. inmediatos; contar fallos sobre ≥ 10 reinicios.
- **Observaciones del log (sin atender, de menor prioridad):** (1) `Loading Environment from FAT... Unable to use mmc 1:1...`: U-Boot busca el entorno en una partición FAT del eMMC que no existe y usa el entorno por defecto (inocuo, pero un `saveenv` no funcionaría). (2) `starting USB...` repite 4 veces `USB EHCI/OHCI` antes de arrancar: puede sumar segundos al arranque (hipótesis, no medido). (3) `systemd-shutdown: Failed to set watchdog hardware timeout to 10min: Invalid argument`: aviso de systemd por el límite del watchdog del H5; no afecta al arranque.
- **Arranque lento (observado por el equipo):** estimación (no medida): la FIT de 866 304 B a 4 MHz y 1 bit toma ≥ 1,7 s solo en el bus, y los marcadores de diagnóstico (`wasrf12345678Lt` ≈ 15 caracteres por bloque × 1 692 bloques ≈ 25 000 caracteres a 115 200 baudios) añadían ≈ 2,2 s. Se movieron `zz-mmc-spl-trace.patch` y `zzz-mmc-sunxi-init-trace.patch` a `scratch/diagnostic-patches/` (fuera del árbol de parches) para un build "silencioso". Pendiente medir cada fase con cronómetro y UART con marcas de tiempo.
- **Hallazgo nuevo (6-oct-2026): un `reboot` por SSH no arranca el stick2; hubo que cortar la energía.** Sin registro de la consola del reinicio fallido. Hipótesis sin confirmar: (a) tras Linux la eMMC queda en 8 bits/high-speed/50 MHz o con una operación en segundo plano y el BROM o el SPL no la ve en estado limpio; (b) falla el BROM al leer el SPL (el banner nunca aparece) o falla el propio SPL (el banner aparece y luego se cuelga). Para separar (b) hace falta capturar la UART durante un `reboot`. Comparar también con stick1 (`reboot` desde Linux). Este fallo es crítico para un nodo Edge que debe reiniciar solo.
- Bisección de la pausa: `P6adb` = 500 ms OK. Siguiente build: **100 ms** (`[SETTLE 100ms]`). Si arranca, probar 30 ms; si falla, 250 ms. Una sola variable por build; anotar cada resultado aquí.
- Siguiente build: se quita el desplazamiento de sectores y el buffer vuelve a `0x41000000`; se sustituye el reposo de 2 s por una pausa de 500 ms (`[SETTLE 500ms]`) y se añade `mmc-sunxi-spl-wait-card-busy.patch` (espera a que DAT0 quede libre antes de cada comando de datos; imprime `B` una vez si vio la tarjeta ocupada). Si arranca, se baja la pausa por bisección y se comprueba si basta la espera de busy sin pausa. Se eliminó `mmc-sunxi-spl-wdt.patch` (hipótesis refutada).
- `P04c9` (sector desplazado 4 MiB + buffer del FIT en `0x42000000`, en stick2): **muere igual en `#7`, esta vez a mitad de un `printf`** (`[TRACE] #7 cmd1`). Descartados: el sector físico de la eMMC y la dirección de DRAM del buffer. Que muera durante una impresión (CPU en la UART, no esperando a la eMMC) sugiere un bloqueo o corte global del SoC y no una espera de datos. Con el reinicio por watchdog también descartado, y sin que se repita el banner, es más bien un bloqueo que un reinicio (inferencia).
- Siguiente build (sin validar): prueba de reposo de 2 s tras `mmc init ok` (`[IDLE] start`, `i0 i1 ...`, `[IDLE] ok`) sin tocar la eMMC. Si muere en el reposo, el problema es independiente de las lecturas (tiempo o hardware global); si lo supera y muere al leer, está ligado a las transferencias de datos.
- Descartado: FIT corrupto (la eMMC coincide byte a byte con el `.deb` y Linux la lee completa).
- `P5395` (con `mmc-sunxi-spl-fifo-word-read.patch`): **mismo cuelgue en `#7`**. La hipótesis del nivel del FIFO queda debilitada: leer una palabra por comprobación no cambió nada. Nueva hipótesis (sin confirmar): el eMMC deja de entregar datos en ese bloque y el cuelgue silencioso lo causa el propio `printf` de diagnóstico con 5 especificadores (límite de tiny-printf). Los prints de `fifo slow`/`timeout` se dividieron en impresiones cortas (`[TR] ...`) con el valor de `rint` para ver el error real del controlador.
- Siguiente: leer `[TR] rint=` en el próximo log; sus bits de error (data timeout, CRC, start-bit) indican por qué el eMMC dejó de enviar datos.

## 1. Estado del Problema (anterior a la regresión)
- El SPL inicializa la eMMC en MMC2 a 20MHz, modo 8-bit.
- Lee el primer sector (cabecera FIT) en `0x49ffffc0`.
- `spl_fit.c` determina FIT de 870,400 bytes (1,700 sectores) y los lee al buffer estático `0x42000000` (DRAM).
- Al iniciar esa lectura, la salida UART se truncaba en `buf=0x42000`.

## 2. Hallazgos y Correcciones Aplicadas
- **Heap exhaustion:** `board_spl_fit_buffer_addr` intentaba alojar ~850KB con `malloc_cache_aligned`; en SPL (`CONFIG_SPL_SYS_MALLOC_F_LEN=0x2000`, 8KB) fallaba. Se parcheó para retornar `CONFIG_SYS_LOAD_ADDR` (`0x42000000`, DRAM DDR3 ya inicializada).
- **Límite de tiny-printf:** con `CONFIG_SPL_USE_TINY_PRINTF=y`, más de 4-5 especificadores por `printf` truncan o corrompen la salida. Divide los logs en impresiones breves.
- **Multi-bloque (CMD18) vs single-block (CMD17):** con `b_max > 1`, `sunxi_mmc.c` emite `CMD18` con `SUNXI_MMC_CMD_AUTO_STOP`; en SPL (PIO/FIFO sin DMA) el `CMD12` automático cuelga o desincroniza el FIFO. Forzar `cfg->b_max = 1` en SPL para eMMC (`sdc_no == 2`) usa `CMD17` y la transferencia de 1,700 bloques toma ~100-150ms.

## 3. Metodología de Trabajo
- **Trazabilidad:** logs concisos en `common/spl/spl_mmc.c` y `common/spl/spl_fit.c`.
- **CI/CD:** `scratch/auto_build_and_deploy.py <commit_sha>` espera el build en GitHub Actions, descarga los artefactos y los despliega al dispositivo. Acceso SSH al dispositivo de pruebas: `root@192.168.128.114`, contraseña `toor@100` (decisión del usuario: se mantiene en este archivo; es un dispositivo de laboratorio).
- **Criterio de éxito (pendiente de definir con dato):** arranque completo desde eMMC + microSD A2 detectada y estable. Falta registrar una métrica (modo/frecuencia de bus, velocidad de lectura) y documentarla en Confluence.

## 4. Reglas de Parcheo
**CRÍTICO:** Los parches al código fuente de U-Boot **SIEMPRE** van en `patch/u-boot/v2026.07-sunxi64/` (o la versión correspondiente). **NUNCA** en `userpatches/u-boot/u-boot-sunxi/`: Armbian los aplica al final y sobrescribe/rompe parches oficiales (SPI NAND, eMMC, DTB), dejando un sistema inarrancable ("0 logs").

## 5. Lecciones Aprendidas
- **Colisión de parches:** antes de crear un parche, revisa si Armbian ya modifica la misma región (ej. `mmc-sunxi-a523-emmc-fix.patch` ya toca `cfg->b_max = 1` para SPL; también `zz-mmc-spl-force-single-block.patch`). Si asumes código intacto, `patch` falla en los hunks siguientes y aborta el build.
- **`dmb()` en ARM64:** en U-Boot v2026.07, `dmb();` en la lectura del FIFO da `implicit declaration of function dmb` con GCC reciente. Usa `mb();`.
- **Desincronización del FIFO (bug HW Allwinner H5):** nunca confíes en que `SUNXI_MMC_STATUS_FIFO_LEVEL` sea ≤ `word_cnt - i`; pedir más palabras de las mapeadas causa un lockup duro del bus AHB. Clampea: `if (in_fifo > word_cnt - i) in_fifo = word_cnt - i;`.

### Comparación de `EXT_CSD` (6-oct-2026, `mmc extcsd read /dev/mmcblk2`, 222 líneas cada una, 29 de diferencias)
Diferencias relevantes (stick1 NCard → stick2 Samsung KLMAG2WEPD):
| Campo | stick1 | stick2 |
|---|---|---|
| `CARD_TYPE` | `0x17` (hasta DDR 52 MHz) | `0x57` (añade **HS400 @200 MHz 1,8 V**) |
| `DRIVER_STRENGTH` | `0x01` | `0x1f` (soporta todas las intensidades) |
| `WR_REL_SET` | `0x00` | `0x1f` (protege datos ante corte de energía) |
| `SEC_COUNT` | `0x01ce8000` | `0x01d1f000` |
| `TRIM_MULT` / `ERASE_TIMEOUT_MULT` / `S_A_TIMEOUT` | `0x05` / `0x05` / `0x16` | `0x02` / `0x01` / `0x11` |
| `MAX_ENH_SIZE_MULT` | `0x000100` | `0x00026d` |
| Campos de fabricante | casi todos `0x00` | varios no nulos |

- **Sin diferencias** en `BOOT_INFO`, `BOOT_SIZE_MULTI`, `PARTITION_CONFIG`, `HS_TIMING`, `BKOPS`, caché, `RST_n`: nada en los campos de arranque explica por sí solo el cuelgue.
- **Lectura (hipótesis, no confirmada):** stick2 es un eMMC de gama más alta (HS400, otro firmware); el SPL lo trata en modo legacy sin pasar por la negociación que sí hace Linux. Ninguna diferencia de la tabla está probada como causa.

### Firmware stock de stick2 (volcados de la eMMC original, 2-oct-2026)
Archivos en la raíz del repo: `stock_boot0.bin` (128 KiB, cabecera `eGON.BT0`), `stock_uboot.bin` (1 MiB, paquete `sunxi-package`) y sus `.txt` (salida de `strings`). Son el cargador Android de Allwinner, que **sí arranca desde esa eMMC**; sirven de referencia de qué configura el fabricante.
- **DRAM en la cabecera de `boot0` (offsets `0x38`...):** `dram_clk` = **576 MHz** (`0x240`), tipo **3 (DDR3)**, `dram_zq` = `0x3b3bf9`, `odt_en` = 1, `mr0` = `0x1c70`, `mr1` = `0x40`, `mr2` = `0x18`. El reloj, ZQ y ODT **coinciden con lo que fija el `.csc`** (576 + ODT), así que esos tres parámetros no son la diferencia con el stock. Los demás campos (`para1`, `para2`, `tpr*`) no se compararon contra el driver de DRAM de mainline.
- **Pendiente (sin hacer):** extraer de `boot0` la secuencia de inicialización del MMC2 (divisor de reloj, ancho de bus, modo/fases de muestreo). Requiere desensamblar código ARM de 32 bits; es el dato más directo de qué hace distinto el stock.
- **Aviso:** son blobs propietarios de Allwinner. Revisar si se pueden versionar en un repo público antes de hacer push (hoy **ya están versionados** en git: `git ls-files` los lista).

## 6. Plan de diagnóstico para stick2 (KLMAG2WEPD) tras la comparación con stick1
Hecho establecido: el mismo binario SPL (`Pe250`) arranca desde la eMMC en stick1 y se cuelga en el bloque 7 en stick2, aun con fuente 5V/2A. Lo que difiere es el chip eMMC (fabricante `0x15` Samsung frente a `0x88`) y el marcado del SoC; el núcleo es el mismo Cortex-A53 r0p4. Es una diferencia de hardware, aún sin causa identificada.
1. **Build doble ya preparado (sin validar):** sector desplazado 4 MiB tras la cabecera del FIT + buffer del FIT en `0x42000000`. Si pasa el bloque 7, separar cuál de los dos fue con un build de un solo cambio. Si muere igual, ni el sector ni la dirección de DRAM importan.
2. **Comparar `EXT_CSD` completo** (`mmc extcsd read /dev/mmcblk2`) de ambos sticks con Linux (stick2 desde la SD): buscar diferencias en `BOOT_*`, `HS_TIMING`, `BKOPS`, caché, `PARTITION_CONFIG`, clases de potencia.
3. **Hacer en el SPL lo que Linux sí hace:** pasar a 8 bits y a high-speed tras el init, y/o esperar el fin de operaciones en segundo plano antes de leer. Una variable por build.
4. **Probar la DRAM de stick2** si 1 apunta a la dirección: bajar `DRAM_CLK` (hoy 576 con ODT en el `.csc`).
5. Registrar cada resultado como fila de la tabla "build → último print → conclusión" (sección 0b) y en Confluence.
Cada punto necesita responsable y fecha en Jira o Monday.

# Mejoras Pendientes (aplicar cuando U-Boot arranque desde eMMC)
Acordadas con el equipo; **no tocar hasta que el SPL arranque estable**. Cada una necesita responsable y fecha en Jira o Monday antes de ejecutarse.

1. **Quitar el trace diagnóstico:** eliminar `zz-mmc-spl-trace.patch`, `zzz-mmc-sunxi-init-trace.patch` y los `printf` de `spl-mmc-boot-debug.patch` / `zz-mmc-spl-force-single-block.patch`. Cada print retrasa el SPL y puede ocultar problemas de tiempos.
2. **Subir el reloj de 4 MHz:** subir gradualmente (4 → 12 → 20 → 25 MHz, ya hay `max-frequency = 25000000` en el DTS) midiendo en cada paso la velocidad de lectura. Revertir al último valor estable si reaparece un cuelgue.
3. **Limpiar el `.csc`:** el `sed` "Hard Reset eMMC" busca `mmc0 = sunxi_mmc_init`, que no existe en `board.c`, así que nunca se aplica; eliminarlo o moverlo a un parche real. Revisar también el `sed` que fuerza `f_max` y quita `MMC_MODE_4BIT`.
4. **Validar la hipótesis A2 con dato:** medir velocidad de lectura de la microSD A2 (modo/frecuencia de bus, MB/s) antes y después del cambio, y definir el criterio de éxito numérico. Hoy la mejora con A2 no está respaldada por ninguna métrica.
5. **Brownout en U-Boot proper:** `SLOT_EXTRA=2` inicializa ambos slots fuera del SPL; verificar que no reaparezca la caída de alimentación.
6. **Mejorar `build-deploy-uboot.sh`/Docker:** pasar `SKIP_BUILD`, `REMOTE_HOST` etc. en `docker-compose.yml`; agregar `backups/` y `last-u-boot.log` al `.gitignore`; comprobar que el banner (hash `P....`) cambió entre builds antes de flashear.
7. **Documentar en Confluence:** tabla "build → último print → conclusión" (la de arriba), el diagnóstico de la regresión de `SLOT_EXTRA`, y la verificación de contenido de la eMMC. Las decisiones sin documento no existen.
8. **PR a Armbian:** separar los parches del trabajo local y revisar cuáles son aptos (los parches provisionales inyectan nodos en `sun50i-h5-orangepi-prime.dts`, lo que rompería las Orange Pi Prime originales; hace falta un `.dts` dedicado al `pbstvstick`).
9. **Seguridad:** la contraseña root del stick está en este archivo y en `build-deploy-uboot.sh` (decisión del equipo para el laboratorio). Revisar antes de cualquier push a un repo público.

# Seguridad en CI (Inyección de Credenciales)
**CRÍTICO:** Nunca escribas contraseñas, Wi-Fi, root o tokens en texto plano en scripts ni en este archivo; al hacer *push* quedan expuestos en el historial de Git.
1. **Placeholders** en los scripts (ej. `PRESET_NET_WIFI_SSID='REPLACE_WITH_SSID'`).
2. **GitHub Secrets** en `Settings -> Secrets`.
3. **Inyección al vuelo** con `sed` antes de compilar:
   `sed -i "s/REPLACE_WITH_SSID/${{ secrets.WIFI_SSID }}/g" userpatches/customize-image.sh`

**Leak:** si se empujan credenciales, **cambia de inmediato la contraseña** del dispositivo/servicio afectado; reescribir historia (`git push --force`) no garantiza que no hayan sido copiadas.
