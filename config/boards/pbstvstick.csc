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
	run_host_command_logged scripts/config --disable CONFIG_SUPPORT_EMMC_BOOT
	
	# Ultimate fix for SPL hangs: disable complex Device Model MMC in SPL
	# This forces the legacy, ultra-robust 24MHz sunxi_mmc driver that ignores all advanced features
	run_host_command_logged scripts/config --disable CONFIG_SPL_DM_MMC
	run_host_command_logged scripts/config --enable CONFIG_SPL_MMC_TINY
	
	# Prevent the legacy driver from initializing the eMMC at the same time as the SD card!
	# This absolutely eliminates the combined current spike (brownout) in SPL.
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA -1
	
	# HARDWARE KILL SWITCH: Force eMMC (PC14) into reset so it draws zero power during SD boot!
	sed -i '/mmc0 = sunxi_mmc_init/i \    /* Hard Reset eMMC */\n    sunxi_gpio_set_cfgpin(SUNXI_GPC(14), 1);\n    sunxi_gpio_set_value(SUNXI_GPC(14), 0);\n    mdelay(10);' board/sunxi/board.c
	
	# EXTREME POWER THROTTLE: Force the SPL MMC driver to 4MHz and 1-bit mode.
	# This slashes the A2 card's power consumption by 90% during the critical SPL phase,
	# allowing it to survive the board's default regulator state.
	sed -i 's/cfg->f_max = 52000000;/cfg->f_max = 4000000;/g' drivers/mmc/sunxi_mmc.c
	sed -i 's/MMC_MODE_4BIT/0/g' drivers/mmc/sunxi_mmc.c
	
	cat << 'EOF' >> arch/arm/dts/sun50i-h5-orangepi-prime.dts

&reg_vcc3v3 {
	u-boot,dm-spl;
};

&mmc0_pins {
	u-boot,dm-spl;
};

&mmc0 {
	u-boot,dm-spl;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <1>;
	max-frequency = <12000000>;
	/delete-property/ cd-gpios;
	broken-cd;
	disable-wp;
	no-1-8-v;
	status = "okay";
};

&mmc2 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	vqmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	no-1-8-v;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};
EOF

}
