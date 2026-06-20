# Custom Board Integration & Troubleshooting Guide
## EFR32BG22C112F352 on Zephyr RTOS

This document provides a detailed breakdown of the clock-tree, toolchain, and radio library issues encountered while porting the Bluetooth Beacon sample to a custom board using the **EFR32BG22C112F352** SoC.

---

## 🔍 1. The Problems Encountered

During the porting and bring-up process, we encountered three distinct issues that blocked compiling, linking, and executing (advertising).

### Issue A: Malformed Board Metadata & Devicetree Preprocessing Failure
1. **YAML Schema Validation Error:** The board's [board.yml](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/boards/custom/my_bg22_board/board.yml) used the singular key `board:` instead of `boards:`. This triggered a validation error during the CMake generation phase.
2. **Missing SoC Include:** The device tree file originally included `<silabs/efr32bg22.dtsi>`, which does not exist in the newer Zephyr includes for Silicon Labs Series 2 devices. This caused devicetree preprocessing to fail.

### Issue B: Compiler/Linker Float-ABI Mismatch (VFP registers)
* **Symptom:** The linker failed during `zephyr_pre0.elf` generation, showing errors like:
  ```text
  librail_efr32xg22_gcc_release.a(rfhal_tempcal.o) uses VFP register arguments, zephyr/zephyr_pre0.elf does not
  failed to merge target specific data
  ```
* **Cause:** The Silicon Labs proprietary radio library (`librail`) and Bluetooth controller library are precompiled binaries compiled with **Hard Float ABI** (`-mfloat-abi=hard`). By default, Zephyr compiles Cortex-M33 targets with soft-float / softfp calling conventions unless the hardware FPU is explicitly enabled. This mismatch prevented the final linking step.

### Issue C: Radio Stack Crash / Assertion Code 66 (`SL_RAIL_ASSERT_INVALID_XTAL_FREQUENCY`)
* **Symptom:** Once successfully compiled, the board flashed correctly but **would not advertise**. By routing `printk` to the Segger RTT interface, we captured the program state and found the CPU was halted inside the precompiled RAIL library's assertion handler:
  ```text
  Program Counter (PC) = 0x0000F5C4 (inside RAILCb_AssertFailed)
  Register R1 = 0x00000042 (66 in decimal)
  ```
* **Cause:** Error code 66 corresponds to `SL_RAIL_ASSERT_INVALID_XTAL_FREQUENCY` (*"Radio Calculator configuration HFXO frequency mismatch with chip"*).
  There were two reasons for this:
  1. The CMSIS HFXO clock frequency config variable `CONFIG_CMU_HFXO_FREQ` was undefined, causing `SystemHFXOClock` to initialize to `0` at boot instead of the crystal frequency `38400000` (38.4 MHz).
  2. The devicetree clock tree was configured to run the CPU and peripherals from the **HFRCODPLL** at 76.8 MHz (copied from the reference board using the `C224` SoC). However, the **C112** SoC model on this custom board has a maximum CPU frequency limitation of **38.4 MHz** and does not support running the system clocks via the DPLL multiplier. When the DPLL failed to lock or coordinate with the HFXO frequency expected by the precompiled radio PHY parameters, RAIL threw the fatal assert.

---

## 🛠️ 2. How It Was Solved

### Step 1: Reconstruct Board Metadata & Devicetree
1. Renamed `board:` to `boards:` in `board.yml` to conform to the Zephyr hardware model schema.
2. Modified [my_bg22_board.dts](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/boards/custom/my_bg22_board/my_bg22_board.dts) to include the correct SoC dtsi: `#include <silabs/xg22/efr32bg22c222f352gm32.dtsi>`.

### Step 2: Adapt Clock Tree for the EFR32BG22C112 (38.4 MHz limit)
We modified the clock nodes in the custom board's Devicetree to bypass the PLL multiplier and run directly from the High-Frequency Crystal Oscillator (HFXO):
```dts
/* Set maximum supported frequency for C112 */
&cpu0 {
	clock-frequency = <38400000>;
};

/* Route the system and group clocks directly from the HFXO */
&sysclk {
	clocks = <&hfxo>;
};
&em01grpaclk {
	clocks = <&hfxo>;
};
&em01grpbclk {
	clocks = <&hfxo>;
};

/* Disable the HFRCODPLL */
&hfrcodpll {
	status = "disabled";
};

&hfxo {
	status = "okay";
};
```
Furthermore, low frequency sleep clocks were routed to the internal RC oscillator (`lfrco`) because this hardware design does not contain an external 32.768 kHz sleep crystal:
```dts
&lfxo {
	status = "disabled";
};
&lfrco {
	status = "okay";
};
&rtccclk {
	clocks = <&lfrco>;
};
/* ... mapped other LF peripheral clocks to &lfrco ... */
```

### Step 3: Align FPU & Clock Constants in Kconfig
We updated [my_bg22_board_defconfig](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/boards/custom/my_bg22_board/my_bg22_board_defconfig) with:
* `CONFIG_FPU=y`: Instructs the GCC toolchain to compile Zephyr with the hard floating-point ABI, matching the precompiled libraries.
* `CONFIG_CMU_HFXO_FREQ=38400000`: Sets the CMSIS HFXO clock constant to 38.4 MHz so that RAIL configuration matches `SystemHFXOClock`.

### Step 4: Implement SEGGER RTT for Headless Debugging
To view logs without physical serial pins, we modified the project's [prj.conf](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/prj.conf) to route all logging directly through the Segger debug probe:
```kconfig
CONFIG_USE_SEGGER_RTT=y
CONFIG_RTT_CONSOLE=y
CONFIG_UART_CONSOLE=n
```
This enabled us to run `JLinkRTTClient` and observe the boot sequence and check the assertion state.

---

## ⚠️ 3. Important to Know or Avoid (Best Practices)

### 📌 DO: Verify SoC Part Sub-Families Natively
Silicon Labs SoCs utilize complex part numbers where small changes indicate major silicon differences (e.g., `EFR32BG22C112` vs. `C222` vs. `C224`). 
Always check the datasheet constraints:
* **Category 1 (C112)**: Max 38.4 MHz, no DPLL system clock, 0 dBm max TX.
* **Category 2 (C222)**: Max 76.8 MHz (requires DPLL), +6 dBm max TX.
* **Category 3 (C224)**: +6 dBm TX, Direction Finding (AoA), Coded PHY (Long Range).

### 📌 DO: Always Define `CONFIG_CMU_HFXO_FREQ`
For all custom boards using Silicon Labs wireless SoCs, you **must** specify the crystal oscillator frequency in your board's `defconfig`. If left out:
* It defaults to `0`.
* The CMSIS startup code initializes `SystemHFXOClock` to `0`.
* The precompiled RAIL library will fetch this frequency, discover it doesn't match the expected 38.4 MHz configuration, and **hard fault/assert** inside `RAILCb_AssertFailed` (error code 66).

### 📌 DO: Use RTT Console for Headless Custom Boards
Headless custom boards (boards without an onboard UART-to-USB bridge or routed serial console headers) should always use Segger RTT Console. 
To debug, simply include:
```kconfig
CONFIG_USE_SEGGER_RTT=y
CONFIG_RTT_CONSOLE=y
CONFIG_UART_CONSOLE=n
```
You can view these logs using standard tools like:
```bash
JLinkExe -device EFR32BG22C222F352GM32 -if SWD -speed 4000 -autoconnect 1
# And in a separate terminal:
JLinkRTTClient
```

### ❌ AVOID: Copying Reference Board Devicetrees Blindly
Most Silicon Labs reference kits (like `bg22_ek4108a`) are populated with high-tier SoCs (e.g., C224) and external 32.768 kHz sleep crystals (`lfxo`). 
If your custom board uses a lower-tier SoC or lacks a sleep crystal, copying the reference devicetree will cause the system to:
1. Try to initialize `lfxo`, which stalls or times out.
2. Clock the CPU beyond the chip's maximum rated frequency, causing immediate system instability or RAIL assertions.

---

## 🚀 4. How to Build, Flash, and Debug

Follow these steps to compile, flash, and monitor the application on your custom EFR32BG22C112-based board.

### Step A: Build the Firmware
Run the following command from the root of the Bluetooth beacon sample directory ([/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon)):

```bash
west build -p always -b my_bg22_board -- -DBOARD_ROOT=/home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon
```

* **`-p always`**: Clean/pristine build to make sure cached clock settings are updated.
* **`-b my_bg22_board`**: Specifies the custom board target.
* **`-DBOARD_ROOT=...`**: Tells the West build system where to search for the `boards/` folder containing the custom board definitions.

### Step B: Flash the Chip
Ensure your J-Link debugger is connected to the board via SWD, then run:

```bash
west flash
```

* This command invokes `JLinkExe` under the hood using the configurations defined in [board.cmake](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/boards/custom/my_bg22_board/board.cmake).

### Step C: Monitor Logs via SEGGER RTT
Since we routed the system console output to RTT, you can read print logs live by starting the J-Link RTT interface.

1. **Keep the J-Link SWD Connection Open:**
   In a terminal, run:
   ```bash
   JLinkExe -device EFR32BG22C222F352GM32 -if SWD -speed 4000 -autoconnect 1
   ```
   *(Note: The `EFR32BG22C222F352GM32` target is compatible for programming and debugging all BG22 sub-families, including the `C112`)*.

2. **Connect the RTT Client:**
   In a separate terminal, start the client to stream output:
   ```bash
   JLinkRTTClient
   ```

Upon a successful boot, the `JLinkRTTClient` terminal will print:
```text
*** Booting Zephyr OS build v4.4.0-4487-g932e9a426982 ***
Starting Beacon Demo
[00:00:00.011,108] <inf> bt_hci_core: HCI transport: efr32
[00:00:00.011,322] <inf> bt_hci_core: Identity: 8C:F6:81:44:A2:6A (public)
[00:00:00.011,352] <inf> bt_hci_core: HCI: version 6.1 (0x0f) revision 0x0660, manufacturer 0x02ff
[00:00:00.011,413] <inf> bt_hci_core: LMP: version 6.1 (0x0f) subver 0x0660
Bluetooth initialized
Beacon started, advertising as 8C:F6:81:44:A2:6A (public)
```

---

## 🔋 5. Optimizing Power Saving (Sub-100 µA Current)

By default, the beacon sample consumes ~1 mA because System Power Management is disabled (holding the CPU in EM0 active/idle), and it advertises at a very fast rate (100–150 ms).

To reduce power consumption to **under 100 µA** (averaging ~15–30 µA between advertisement pulses), the following updates have been made or must be applied:

### 1. Enable System Power Management
We added the following to [prj.conf](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/prj.conf):
```kconfig
CONFIG_PM=y
```
When no threads are ready to run, the idle thread will automatically put the CPU into **EM2 Deep Sleep** (`EMU_EnterEM2(true)`), disabling high-frequency clocks (HFXO) and leaving only the low-frequency sleep clock (LFRCO) and RTCC active.

### 2. Increase the Advertising Interval
The default advertising interval is 100–150 ms, causing the radio to transmit frequently. We updated [main.c](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/src/main.c) to configure a **1000 ms (1.0 second)** advertising interval:
```c
struct bt_le_adv_param adv_param = *BT_LE_ADV_NCONN_IDENTITY;
adv_param.interval_min = 1600; /* 1600 * 0.625 ms = 1000 ms */
adv_param.interval_max = 1600;
```
This reduces the radio's active duty cycle by roughly 90%.

### 3. Disconnect J-Link Debug Session (CRITICAL)
When J-Link is actively debugging or communicating with RTT, the SoC's debug power domain is kept fully powered. In this state, **the chip cannot enter deep sleep and will continue to draw 1–1.5 mA.**
* **For real low-power measurement:** Disconnect/unplug the SWD debug probe lines (SWCLK, SWDIO, RESET) or close JLinkExe and power the board directly from a battery.

### 4. Production Low-Power Configuration
When compiling the final production release, disable all serial, logging, and RTT peripherals in [prj.conf](file:///home/mihail/zephyrproject/zephyr/samples/bluetooth/beacon/prj.conf) to prevent peripheral clock power draw:
```kconfig
# Core BLE Config
CONFIG_BT=y
CONFIG_BT_DEVICE_NAME="Test beacon"

# Enable Sleep/Power Management
CONFIG_PM=y

# Disable All Logging, Console, and Serial Drivers
CONFIG_LOG=n
CONFIG_CONSOLE=n
CONFIG_SERIAL=n
CONFIG_UART_CONSOLE=n
CONFIG_USE_SEGGER_RTT=n
CONFIG_RTT_CONSOLE=n
```

### 5. Allow Inaccurate Sleep Clock (Internal LFRCO Calibration)
In the Simplicity SDK Bluetooth Link Layer initialization ([sl_btctrl_init.c](file:///home/mihail/zephyrproject/modules/hal/silabs/simplicity_sdk/protocol/bluetooth/bgstack/ll/src/sl_btctrl_init.c)), the Bluetooth Controller checks the sleep clock accuracy of the low-frequency source. Since the board does not contain a high-precision 32.768kHz sleep crystal (`LFXO`), it uses the internal **LFRCO** RC oscillator, which has an accuracy worse than the default Bluetooth Link Layer limit of 500 ppm.

By default, if the clock accuracy is worse than 500 ppm, the controller calls `sl_power_manager_add_em_requirement(SL_POWER_MANAGER_EM1)`, **permanently locking the system in EM1 sleep (~1 mA)** to prevent connection timing drift.

To resolve this, we modified [sl_btctrl_init.c](file:///home/mihail/zephyrproject/modules/hal/silabs/simplicity_sdk/protocol/bluetooth/bgstack/ll/src/sl_btctrl_init.c) to enable the inaccurate sleep clock flag:
```c
config.flags |= SL_BTCTRL_CONFIG_FLAG_USE_INACCURATE_SLEEP_CLOCK;
```
This enables the controller to sleep in EM2 while compensating for the lower accuracy of the internal LFRCO.



