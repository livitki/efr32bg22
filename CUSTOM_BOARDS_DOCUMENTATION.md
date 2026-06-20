# Custom Board Integration & Troubleshooting Guide
## EFR32BG22 Custom Boards on Zephyr RTOS

This guide documents the design, configuration, compilation, and debugging of the two custom Silicon Labs EFR32BG22 Series 2 Bluetooth LE boards. It details the clock tree, power management, toolchain, and debugging configurations required to run Zephyr RTOS application code on these custom designs.

---

## 📋 1. Hardware Specifications Comparison

The two custom boards utilize different sub-families of the Silicon Labs Series 2 Bluetooth SoC, which introduces different memory, clock speed, package, and RF power characteristics.

| Parameter | Board 1: `my_bg22_board` | Board 2: `my_bg22_c112_board` |
|-----------|--------------------------|-------------------------------|
| **SoC Model** | **EFR32BG22C224F512GM40** | **EFR32BG22C112F352GM32** |
| **SoC Category** | Category 3 (High-Tier) | Category 1 (Entry-Level) |
| **CPU Core** | ARM Cortex-M33 @ 76.8 MHz | ARM Cortex-M33 @ 38.4 MHz |
| **Flash Memory** | 512 KB | 352 KB |
| **RAM** | 32 KB | 32 KB |
| **RF Max TX Power** | +6 dBm | 0 dBm |
| **Package** | QFN40 (40-pin) | QFN32 (32-pin) |
| **Sleep Crystal (LFXO)** | **Present** (Onboard 32.768 kHz) | **Absent** (Uses internal LFRCO RC) |
| **Bluetooth PHYs** | 1M, 2M, Coded (Long Range) | 1M, 2M only |
| **Direction Finding (AoA/AoD)**| Supported | Not Supported |

---

## 🛠️ 2. Device Tree & Clock Tree Architectures

### Board 1: `my_bg22_board` (C224 - 76.8 MHz Clock & LFXO)
The high-tier Category 3 SoC supports running the CPU up to 76.8 MHz. It achieves this by locking the internal DPLL (`&hfrcodpll`) to the 38.4 MHz external HFXO crystal reference. Because this custom board layout includes an onboard 32.768 kHz sleep crystal, we enable the low-frequency crystal oscillator (`&lfxo`) and route all low-power sleep clocks to it.

```dts
/* my_bg22_board.dts Clock Tree configuration */

/* EFR32BG22C224 runs at max 76.8 MHz using the internal HFRCODPLL */
&cpu0 {
	clock-frequency = <76800000>;
};

&hfxo {
	status = "okay";
};

&hfrcodpll {
	clock-frequency = <DT_FREQ_K(76800)>;
	clocks = <&hfxo>;
	dpll-autorecover;
	dpll-edge = "fall";
	dpll-lock = "phase";
	dpll-m = <1919>;
	dpll-n = <3839>;
};

/* Sleep Clocks routed to the external 32.768 kHz crystal (LFXO) */
&lfxo {
	status = "okay";
};

&lfrco {
	status = "okay";
};

&em23grpaclk {
	clocks = <&lfxo>;
};
&em4grpaclk {
	clocks = <&lfxo>;
};
&prortcclk {
	clocks = <&lfxo>;
};
&rtccclk {
	clocks = <&lfxo>;
};
&wdog0clk {
	clocks = <&lfxo>;
};
```

### Board 2: `my_bg22_c112_board` (C112 - 38.4 MHz Clock, No DPLL, No LFXO)
The entry-level Category 1 SoC cannot exceed a 38.4 MHz CPU speed and does not support running system clocks through the DPLL multiplier. Additionally, the C112 custom board does not populate the external sleep crystal. 

To prevent startup hangs and assertion failures, we:
1. Bypassed the PLL and mapped the group and system clocks directly to the High-Frequency Crystal Oscillator (`&hfxo`) at 38.4 MHz.
2. Disabled the PLL (`&hfrcodpll`).
3. Disabled the LFXO (`&lfxo`) and mapped all sleep, watchdogs, and RTCC clocks to the internal low-frequency RC oscillator (`&lfrco`).
4. Disabled unsupported radio capabilities (CTE transmission) and capped maximum TX power to `0` dBm.

```dts
/* my_bg22_c112_board.dts configuration */

/* CPU restricted to direct HFXO frequency (38.4 MHz) */
&cpu0 {
	clock-frequency = <38400000>;
};

&sysclk {
	clocks = <&hfxo>;
};
&em01grpaclk {
	clocks = <&hfxo>;
};
&em01grpbclk {
	clocks = <&hfxo>;
};

&hfrcodpll {
	status = "disabled";
};

&hfxo {
	status = "okay";
};

/* Sleep clocks mapped to internal RC oscillator (LFRCO) */
&lfxo {
	status = "disabled";
};

&lfrco {
	status = "okay";
};

&em23grpaclk {
	clocks = <&lfrco>;
};
&em4grpaclk {
	clocks = <&lfrco>;
};
&prortcclk {
	clocks = <&lfrco>;
};
&rtccclk {
	clocks = <&lfrco>;
};
&wdog0clk {
	clocks = <&lfrco>;
};

/* C112 specific radio boundaries */
&radio {
	/delete-property/ ble-cte-tx-supported;
	pa-max-power-dbm = <0>;
};
```

---

## 🔍 3. Compilation, Linking & Integration Challenges

Several distinct issues can block compilation, linking, and boot execution on custom Silicon Labs Series 2 hardware.

### Issue A: Compiler/Linker Float-ABI Mismatch (VFP Registers)
* **Symptom:** Linker fails during `zephyr_pre0.elf` compilation stage:
  ```text
  librail_efr32xg22_gcc_release.a(rfhal_tempcal.o) uses VFP register arguments, zephyr/zephyr_pre0.elf does not
  failed to merge target specific data
  ```
* **Cause:** The Silicon Labs proprietary radio stack (`librail`) and Link Layer controller precompiled library binaries are built using the **Hard Floating-Point Calling Convention** (`-mfloat-abi=hard`). By default, Zephyr compiles Cortex-M33 targets with a soft-float calling convention unless specified.
* **Solution:** Explicitly enable the FPU in the board's default Kconfig files (`my_bg22_board_defconfig` and `my_bg22_c112_board_defconfig`):
  ```kconfig
  CONFIG_FPU=y
  ```

### Issue B: Radio Stack Boot Assertion 66 (`SL_RAIL_ASSERT_INVALID_XTAL_FREQUENCY`)
* **Symptom:** Board flashes correctly but fails to start advertising. Directing print logs to debugging interfaces reveals the core halted inside the precompiled RAIL assertion handler:
  ```text
  Program Counter (PC) = 0x0000F5C4 (inside RAILCb_AssertFailed)
  Register R1 = 0x00000042 (66 in decimal)
  ```
* **Cause:** Error code `0x42` (66) corresponds to `SL_RAIL_ASSERT_INVALID_XTAL_FREQUENCY`. The CMSIS startup parameter `CONFIG_CMU_HFXO_FREQ` was undefined, defaulting to `0` at boot, which conflicted with the expected `38.4 MHz` radio parameters inside the precompiled stack.
* **Solution:** Ensure `CONFIG_CMU_HFXO_FREQ` is explicitly populated in the defconfigs:
  ```kconfig
  CONFIG_CMU_HFXO_FREQ=38400000
  ```

### Issue C: Clock-Tree Frequency Crash
* **Symptom:** Target CPU locks up immediately or enters a reset loop when compiling for the C112 chip if the reference board configuration is copied directly.
* **Cause:** Entry-level sub-families (like the C112) have strict hardware limits and do not support clocking peripherals and the CPU core via the DPLL multiplier.
* **Solution:** Bypass DPLL entirely in devicetree for C112, forcing the system clocks onto the HFXO oscillator block and disabling the `&hfrcodpll` node.

---

## 🔋 4. Power Optimization & Low-Power Node Sleep

By default, standard Bluetooth samples draw ~1 mA because the idle thread loops in EM0 (Active) state, and advertising intervals are set very short (100 ms). Applying the following configurations reduces consumption to **sub-100 µA** (averaging ~15–30 µA between transmission pulses).

### 1. Enable System Power Management
Include System Power Management in [prj.conf](file:///home/mihail/zephyrproject/workspace/bg22c11/prj.conf):
```kconfig
CONFIG_PM=y
```
When threads are idle, Zephyr automatically invokes the Silicon Labs Power Manager module `EMU_EnterEM2(true)` to enter Deep Sleep (EM2), shutting down HFXO and leaving only the RTCC and sleep oscillator active.

### 2. Configure Inaccurate Sleep Clock (For C112 LFRCO Design)
> [!IMPORTANT]
> Because the C112 board does not contain a high-precision 32.768kHz sleep crystal, it runs from the internal **LFRCO** RC oscillator (accuracy worse than 500 ppm). 
> By default, if the clock accuracy is worse than 500 ppm, the Bluetooth Link Layer initialization API will add an EM requirement locking the system in EM1 sleep (~1 mA) to prevent connection drifts.
>
> To bypass this restriction and allow EM2 sleep, the initialization source file [sl_btctrl_init.c](file:///home/mihail/zephyrproject/modules/hal/silabs/simplicity_sdk/protocol/bluetooth/bgstack/ll/src/sl_btctrl_init.c#L641) was modified.
>
> Specifically, inside the function `sl_btctrl_init()`, the inaccurate sleep clock configuration flag is ORed into the controller configuration struct before initialization:
> ```c
> sl_status_t sl_btctrl_init(void)
> {
>   struct sl_btctrl_config config;
> 
>   sl_btctrl_init_config(&config);
>   config.buffer_memory = SL_BT_CONTROLLER_BUFFER_MEMORY;
>   config.flags |= SL_BTCTRL_CONFIG_FLAG_USE_INACCURATE_SLEEP_CLOCK;
> 
>   return sl_btctrl_init_internal(&config);
> }
> ```

### 3. Production/Release Low-Power Settings
For deployment, compile out logging and debug consoles to eliminate driver and peripheral clock overhead:
```kconfig
# Disable consoles and logs for EM2 optimized current draw
CONFIG_LOG=n
CONFIG_CONSOLE=n
CONFIG_SERIAL=n
CONFIG_UART_CONSOLE=n
CONFIG_USE_SEGGER_RTT=n
CONFIG_RTT_CONSOLE=n
```

### 4. Headless Low-Power Optimization Profile (UART & Serial Disabled)
For absolute minimum sleep current, you can completely eliminate the UART hardware and logging/serial software overhead. 

We have created two dedicated profile files in the repository:
1. **[prj-low-power.conf](file:///home/mihail/zephyrproject/workspace/bg22c11/prj-low-power.conf)**: Compiles out the console, UART serial drivers, logging, and SEGGER RTT console.
2. **[low-power.overlay](file:///home/mihail/zephyrproject/workspace/bg22c11/low-power.overlay)**: Disables the `usart1` hardware peripheral in the Devicetree and removes the `zephyr,console` and `zephyr,shell-uart` chosen attributes.

#### Build Command using Low-Power Profile:
```bash
west build -p always -b my_bg22_board -- \
  -DEXTRA_CONF_FILE=prj-low-power.conf \
  -DEXTRA_DTC_OVERLAY_FILE=low-power.overlay \
  -DBOARD_ROOT=/home/mihail/zephyrproject/workspace/bg22c11
```

#### Memory Footprint Savings (C224 Target):
| Section | Standard Build (With RTT Logs) | Low-Power Build (No Serial/RTT) | Savings |
|---------|--------------------------------|---------------------------------|---------|
| **FLASH** | 192508 B (36.72%) | 177728 B (33.90%) | **14780 B (~15 KB)** |
| **RAM** | 25472 B (77.73%) | 22416 B (68.41%) | **3056 B (~3 KB)** |

---

## 🚀 5. How to Build, Flash, and Debug

Follow these instructions using the command line to target, flash, and debug either of the two custom boards.

### Build Commands

* **Build for C224 Board (`my_bg22_board`):**
  ```bash
  west build -p always -b my_bg22_board -- -DBOARD_ROOT=/home/mihail/zephyrproject/workspace/bg22c11
  ```
* **Build for C112 Board (`my_bg22_c112_board`):**
  ```bash
  west build -p always -b my_bg22_c112_board -- -DBOARD_ROOT=/home/mihail/zephyrproject/workspace/bg22c11
  ```

### Flash Commands
Once built, run the flashing command to invoke J-Link:
```bash
west flash
```

### Logging & Debugging via SEGGER RTT
Because custom boards are headless (lacking physical UART chips or pins), logging is routed to Segger Real-Time Transfer (RTT).

1. **Start the J-Link Connection Daemon:**
   Connect the board to the debugger via SWD and start the debugger interface:
   ```bash
   # C224 J-Link target:
   JLinkExe -device EFR32BG22C224F512GM40 -if SWD -speed 4000 -autoconnect 1

   # C112 J-Link target:
   JLinkExe -device EFR32BG22C112F352GM32 -if SWD -speed 4000 -autoconnect 1
   ```
2. **Launch RTT Client:**
   In a separate terminal tab, launch the client to capture active logs:
   ```bash
   JLinkRTTClient
   ```

Upon a successful boot, the console will print:
```text
*** Booting Zephyr OS build v4.4.0-4487-g932e9a426982 ***
Starting Beacon Demo
[00:00:00.011,108] <inf> bt_hci_core: HCI transport: efr32
[00:00:00.011,322] <inf> bt_hci_core: Identity: CC:86:EC:58:B3:9E (public)
Bluetooth initialized
Beacon started, advertising as CC:86:EC:58:B3:9E (public)
```
