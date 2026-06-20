# Copyright (c) 2026 Mihail
# SPDX-License-Identifier: Apache-2.0

board_runner_args(jlink "--device=EFR32BG22C112F352GM32" "--reset-after-load")
include(${ZEPHYR_BASE}/boards/common/jlink.board.cmake)

board_runner_args(silabs_commander "--device=${CONFIG_SOC}")
include(${ZEPHYR_BASE}/boards/common/silabs_commander.board.cmake)
