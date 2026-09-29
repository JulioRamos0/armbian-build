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
}
