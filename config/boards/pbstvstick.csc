# Allwinner H5 quad core 1GB RAM Wi-Fi/BT
BOARD_MAINTAINER="julioramos0"
BOARD_NAME="PBS TV Stick"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="orangepi_prime_defconfig"
CRUSTCONFIG="orangepi_pc2_defconfig"
DEFAULT_CONSOLE="both"
DEFAULT_OVERLAYS="analog-codec"
HAS_VIDEO_OUTPUT="yes"
FDTFILE="allwinner/sun50i-h5-pbstvstick.dtb"
INTRODUCED="2016"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
MODULES="g_serial"
SERIALCON="ttyS0,ttyGS0"
PACKAGE_LIST_BOARD="mmc-utils"

function post_config_uboot_target__pbstvstick() {
	display_alert "$BOARD" "u-boot: DRAM tune (504/ODT) + SPI-flash boot" "info"
	# Upstream orangepi_prime_defconfig runs DRAM at an aggressive 672; pin the
	# Armbian-tuned 504 + ODT for stability (v2026.07 family default u-boot).
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
	# Allow booting from the on-board SPI flash (not in the upstream defconfig).
	# Safe on H5 (the SPL_SPI A64 SPL-boot regression does not affect sun50iw2).
	# CONFIG_MACPWR (old eth PHY power GPIO) is gone in v2026.07 - the PHY rail is
	# now driven from the DT, so it is intentionally not re-added.
	run_host_command_logged scripts/config --enable CONFIG_SPL_SPI_SUNXI
	# Enable eMMC (MMC2) for pbstvstick
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA 2
	run_host_command_logged scripts/config --enable CONFIG_SUPPORT_EMMC_BOOT
	# Inyectamos el nodo de eMMC directamente en el Device Tree de U-Boot
	cat << 'EOF' >> arch/arm/dts/sun50i-h5-orangepi-prime.dts

&{/aliases} {
	mmc0 = &mmc0;
	mmc1 = &mmc2;
	mmc2 = &mmc1;
};

&mmc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <8>;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};
EOF

	# El Boot ROM del Allwinner H5 verifica el sector 256 (128KB offset) en la eMMC.
	# Esto permite instalar U-Boot en el User Area sin destruir la tabla de particiones GPT,
	# y sin requerir la cabecera propietaria en la partición boot0.
	function write_uboot_platform() {
		if [[ $2 == /dev/mmcblk* ]]; then
			dd if=$1/u-boot-sunxi-with-spl.bin of=$2 conv=notrunc,fsync bs=1024 seek=128 status=none || return 1
		else
			dd if=$1/u-boot-sunxi-with-spl.bin of=$2 conv=notrunc,fsync bs=1024 seek=8 status=none || return 1
		fi
	}
}
