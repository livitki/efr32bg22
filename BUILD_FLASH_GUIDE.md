# EFR32BG22 Build & Flash Guide

## Custom Board: `my_bg22_board`

This guide documents how to build and flash Zephyr RTOS applications for your custom **EFR32BG22C222F352GM32** board configuration.

---

## Board Specifications

| Parameter | Value |
|-----------|-------|
| **SoC** | EFR32BG22C222F352GM32 |
| **CPU** | ARM Cortex-M33 @ 38.4 MHz |
| **Flash** | 352 KB |
| **RAM** | 32 KB |
| **Bluetooth** | Bluetooth LE 5.2 |
| **Board Root** | `/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon` |

---

## Prerequisites

### 1. Zephyr SDK Installation

```bash
# Install Zephyr SDK (if not already done)
# https://docs.zephyrproject.org/latest/develop/getting_started/index.html

# Verify installation
zephyr-sdk-1.0.1/hosttools/arm-zephyr-eabi-gcc --version
```

### 2. West Build Tools

```bash
# Activate Zephyr Python environment
source ~/zephyrproject/.venv/bin/activate

# Verify west installation
west --version
```

### 3. J-Link Debugger

```bash
# Verify J-Link is installed and accessible
JLinkExe -version
```

---

## Build Commands

### Basic Build (Clean)

```bash
cd ~/zephyrproject/workspace/bg22c11

# Build with pristine build directory
west build -p always -b my_bg22_board \
  /home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon \
  -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon
```

### Build with Custom Application

```bash
# Build your own application (replace with your app path)
west build -p always -b my_bg22_board \
  /path/to/your/application \
  -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon
```

### Build with Menuconfig

```bash
# Open configuration menu
west build -p always -b my_bg22_board \
  /path/to/your/application \
  -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon \
  -- -DZEPHYR_ENABLE_MENUCONFIG=ON

# Then run menuconfig
cd build
make menuconfig
```

---

## Flash Commands

### Flash Using J-Link (Default)

```bash
cd ~/zephyrproject/workspace/bg22c11

# Flash the built application
west flash -d build
```

### Flash Without Rebuild

```bash
# Skip rebuild and just flash
west flash -d build --no-rebuild
```

### Flash with Specific Runner

```bash
# Explicitly specify J-Link runner
west flash -d build -r jlink
```

---

## Configuration Files

### prj.conf (Application Configuration)

```conf
# Bluetooth configuration
CONFIG_BT=y
CONFIG_BT_PERIPHERAL=y
CONFIG_BT_DEVICE_NAME="Test beacon"

# Logging
CONFIG_LOG=y
CONFIG_LOG_DEFAULT_LEVEL=3

# UART Console
CONFIG_UART_CONSOLE=y
```

### Custom Board Configuration

Your custom board configuration is located at:
```
/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/
```

The `BOARD_ROOT` parameter tells Zephyr where to find the board definition files.

---

## Build Output

After a successful build, you'll find:

| File | Location | Description |
|------|----------|-------------|
| **zephyr.elf** | `build/zephyr/` | Debug executable |
| **zephyr.hex** | `build/zephyr/` | HEX file for flashing |
| **zephyr.bin** | `build/zephyr/` | Binary file |
| **autoconf.h** | `build/zephyr/include/generated/` | Generated config header |

---

## Memory Usage

After build, check memory usage:

```
Memory region         Used Size  Region Size  %age Used
           FLASH:      131356 B       352 KB     36.44%
             RAM:       21320 B        32 KB     65.06%
        IDT_LIST:           0 B        32 KB      0.00%
```

---

## Troubleshooting

### Issue: Build directory not found

**Solution:** Specify build directory explicitly:
```bash
west flash -d build
```

### Issue: CMake cache missing

**Solution:** Clean and rebuild:
```bash
west build -p always -b my_bg22_board \
  /path/to/application \
  -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon
```

### Issue: J-Link not found

**Solution:** Verify J-Link installation:
```bash
JLinkExe -version
```

### Issue: Board not found

**Solution:** Verify BOARD_ROOT path and board files exist:
```bash
ls -la /home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/
```

---

## Quick Reference Commands

```bash
# Navigate to project
cd ~/zephyrproject/workspace/bg22c11

# Clean build
west build -p always -b my_bg22_board \
  /home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon \
  -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon

# Flash
west flash -d build

# View logs (if UART console enabled)
# Use screen, minicom, or similar:
screen /dev/ttyUSB0 115200
```

---

## Board Definition Files

Your custom board should include these files in the BOARD_ROOT directory:

```
beacon/
├── Kconfig.board
├── Kconfig.defconfig
├── board.cmake
├── my_bg22_board.dts
├── my_bg22_board.defconfig
└── (optional overlays)
```

---

## Next Steps

1. **Customize prj.conf** for your application needs
2. **Add application code** to implement your specific functionality
3. **Configure Bluetooth** services and advertising
4. **Enable debugging** (SEGGER RTT, UART, etc.)
5. **Optimize power consumption** for battery-operated use

---

## References

- [Zephyr Build System Documentation](https://docs.zephyrproject.org/latest/build/index.html)
- [EFR32BG22 Product Page](https://www.silabs.com/wireless/gecko-series-2/efr32bg22)
- [Silicon Labs Zephyr SDK](https://www.silabs.com/software-and-tools/zephyr-rtos)
- [West Command Reference](https://docs.zephyrproject.org/latest/tools/west/index.html)
