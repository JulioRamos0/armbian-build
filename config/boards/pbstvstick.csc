# Allwinner H5 quad core 1GB RAM Wi-Fi/BT
BOARD_MAINTAINER="julioramos0"
BOARD_NAME="PBS TV Stick"
BOARD_VENDOR="shaghal"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="pbstvstick_defconfig"
CRUSTCONFIG="orangepi_pc2_defconfig"
DEFAULT_CONSOLE="both"
DEFAULT_OVERLAYS="analog-codec"
HAS_VIDEO_OUTPUT="yes"
FDTFILE="allwinner/sun50i-h5-pbstvstick.dtb"
INTRODUCED="2016"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES="g_serial"
SERIALCON="ttyGS0,ttyS0"
PACKAGE_LIST_BOARD="mmc-utils"
BOOTENV_FILE="pbstvstick.txt"
GOVERNOR="performance"

function pre_umount_final_image__pbstvstick_disable_ramlog() {
	display_alert "$BOARD" "Permanently disabling armbian-ramlog and logrotate" "info"
	chroot_sdcard systemctl --no-reload disable armbian-ramlog.service logrotate.timer 2> /dev/null || true
	rm -f "${MOUNT}"/etc/systemd/system/sysinit.target.wants/armbian-ramlog.service
	rm -f "${MOUNT}"/etc/systemd/system/timers.target.wants/logrotate.timer
}
