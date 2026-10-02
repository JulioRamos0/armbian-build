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
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "504"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
	run_host_command_logged scripts/config --disable CONFIG_SPL_SPI_SUNXI
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA 2
	run_host_command_logged scripts/config --disable CONFIG_SUPPORT_EMMC_BOOT
	cat << 'EOF' >> arch/arm/dts/sun50i-h5-orangepi-prime.dts

&mmc0 {
	u-boot,dm-spl;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	no-1-8-v;
	status = "okay";
};

&mmc2 {
	u-boot,dm-spl;
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	vqmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	no-1-8-v;
	non-removable;
	status = "okay";
};
EOF

}
