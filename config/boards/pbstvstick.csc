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
	display_alert "$BOARD" "u-boot: DRAM tune (576/ODT) + eMMC boot" "info"
	run_host_command_logged scripts/config --set-val CONFIG_DRAM_CLK "576"
	run_host_command_logged scripts/config --enable CONFIG_DRAM_ODT_EN
	run_host_command_logged scripts/config --disable CONFIG_SPL_SPI_SUNXI
	run_host_command_logged scripts/config --disable CONFIG_SUPPORT_EMMC_BOOT
	run_host_command_logged scripts/config --disable CONFIG_OF_UPSTREAM

	# MASTERPLAN TO SURVIVE A2 SDCARD BROWNOUT WITH SAMSUNG EMMC:
	# 1. Force SPL to ALWAYS boot from SD card, even if BootROM fell back to eMMC!
	sed -i '/u32 spl_boot_device(void)/a \treturn BOOT_DEVICE_MMC1; /* FORCE SD CARD */' arch/arm/mach-sunxi/board.c

	# 2. Disable complex DM MMC in SPL to use the ultra-robust TINY legacy driver
	run_host_command_logged scripts/config --disable CONFIG_SPL_DM_MMC
	run_host_command_logged scripts/config --enable CONFIG_SPL_MMC_TINY
	
	# 3. Disable simultaneous dual-initialization in SPL
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA -1

	# 4. Hardware Kill Switch: Hold eMMC (PC14) in reset during SPL to free up power for SD card
	sed -i '/mmc0 = sunxi_mmc_init/i \    /* Hard Reset eMMC */\n    sunxi_gpio_set_cfgpin(SUNXI_GPC(14), 1);\n    sunxi_gpio_set_value(SUNXI_GPC(14), 0);\n    mdelay(10);' board/sunxi/board.c
	
	# 5. Extreme Power Throttle: Slow down SD card to 4MHz / 1-bit in SPL to survive brownout
	sed -i 's/cfg->f_max = 52000000;/cfg->f_max = 4000000;/g' drivers/mmc/sunxi_mmc.c
	sed -i 's/MMC_MODE_4BIT/0/g' drivers/mmc/sunxi_mmc.c

	local node_content='
&mmc0 {
	u-boot,dm-spl;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <4>;
	cap-sd-highspeed;
	broken-cd;
	no-1-8-v;
	status = "okay";
};

&mmc2 {
	u-boot,dm-spl;
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_vcc3v3>;
	bus-width = <8>;
	max-frequency = <25000000>;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};
'
	if [ -f "arch/arm/dts/sun50i-h5-orangepi-prime.dts" ]; then
		echo "$node_content" >> arch/arm/dts/sun50i-h5-orangepi-prime.dts
	fi
	if [ -f "dts/upstream/src/arm64/allwinner/sun50i-h5-orangepi-prime.dts" ]; then
		echo "$node_content" >> dts/upstream/src/arm64/allwinner/sun50i-h5-orangepi-prime.dts
	fi
}
