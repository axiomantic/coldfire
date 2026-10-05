# mcf5407

An emulator for the Motorola MCF5407 ColdFire processor and a functional model of the Philips ISP1181 USB device controller.

The core implementation is authored in Nim, exposing a pure C application binary interface (ABI) declared in [`include/mcf5407.h`](include/mcf5407.h). The library can be consumed either by compiling the original Nim sources or by building directly from pre-generated, platform-native C translation units requiring only a standard C11 compiler.

---

## Key Features

- **Pure C11 ABI Boundary**: Communicates strictly via standard types, opaque context pointers, and C function pointers. No Nim runtime internals, garbage collector handles, or C++ virtual tables cross the interface.
- **Dual Build Modes**:
  - **Native Nim Mode**: Drives the pinned Nim compiler directly via CMake for active core development.
  - **Pre-Generated C Distribution**: Downstream consumers do **not** require a Nim installation. Standard C11 builds are supported on macOS, Linux x86_64, and Windows x86_64.
- **ColdFire V4 Core Emulation**: Accurate instruction decoding, arithmetic logic unit (ALU), move control operations (`MOVEC`), supervisor registers (VBR, CACR, ACR0–3, RAMBAR0–1, MBAR), cycle-budgeted execution, bus fault handling, and prioritized multi-level interrupt servicing.
- **ISP1181 USB Device Controller**: Complete endpoint register file, double-buffered FIFOs, setup packet handling, OUT/IN token processing, and diagnostic ring logging.
- **Deterministic State Serialization**: Full snapshot capture and restore for deterministic replay and state persistence.

---

## Pre-Generated C Distribution

To ensure frictionless integration into consumer projects without introducing a Nim toolchain dependency, `mcf5407` includes pre-generated C translation units in `c_src/`:

```
c_src/
├── common/
│   └── nimbase.h          # Minimal C runtime definitions
├── macos/                 # Clang / Darwin C11 translation units
├── linux_x86_64/          # GCC / Linux x86_64 C11 translation units
└── windows_x86_64/        # MSVC / Windows x86_64 C11 translation units
```

### Automatic Fallback and Explicit Selection

CMake automatically checks for the `nim` compiler on your `PATH`:
- If `nim` is present and matches the pinned version in [`.nim-version`](.nim-version), CMake defaults to compiling from Nim sources.
- If `nim` is absent, CMake automatically falls back to compiling from the pre-generated C sources in `c_src/`.
- To explicitly force the C distribution even when Nim is installed, pass `-DMCF5407_USE_C_DIST=ON`.

### Updating C Sources (Maintainers)

When modifying core Nim sources in `src/`, maintainers regenerate the C distribution using the provided shell script:

```bash
./tools/generate_c_dist.sh
```

This script verifies that the installed Nim compiler version matches [`.nim-version`](.nim-version), runs `nim c --compileOnly` for each supported platform target, and copies `nimbase.h` into `c_src/common/`.

---

## CMake Integration

### CMake Options

| Option | Default | Description |
|---|---|---|
| `MCF5407_USE_C_DIST` | `OFF` (or `ON` if `nim` missing) | Compiles `libmcf5407` directly from `c_src/` using standard C11. |

### Consuming via `FetchContent`

```cmake
include(FetchContent)

FetchContent_Declare(
    mcf5407
    GIT_REPOSITORY https://github.com/axiomantic/mcf5407.git
    GIT_TAG        main # Or pinned commit hash
)

# Optional: Force pre-generated C distribution (no Nim dependency required)
set(MCF5407_USE_C_DIST ON CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(mcf5407)

# Link against your application or plugin target
target_link_libraries(my_emulator PRIVATE mcf5407::mcf5407)
```

### Consuming via `add_subdirectory`

```cmake
add_subdirectory(path/to/mcf5407)
target_link_libraries(my_emulator PRIVATE mcf5407::mcf5407)
```

The exported target `mcf5407::mcf5407` automatically propagates the include directory for [`include/mcf5407.h`](include/mcf5407.h).

---

## Quick API Overview

The C interface is defined in [`include/mcf5407.h`](include/mcf5407.h). Full documentation is available in the [API Documentation Guide](docs/api.md) and the [Interactive Web Documentation](docs/index.html).

### Initialization and Execution Lifecycle

```c
#include "mcf5407.h"

// 1. Initialize runtime primitives once (idempotent, thread-safe)
if (!mcf5407_runtime_init()) {
    // Handle initialization failure
}

// 2. Instantiate core with memory callbacks and user context
mcf5407_ctx* cpu = mcf5407_create(board_ptr, board_read, board_write, board_iack);

// 3. Reset processor with initial stack pointer and program counter
mcf5407_reset(cpu, 0x00040000, 0x00000400);

// 4. Execute for a quantum (instruction-boundary accurate)
uint32_t cycles_spent = mcf5407_exec(cpu, 1000);

// 5. Inspect execution status
if (mcf5407_halted(cpu)) {
    if (mcf5407_faulted(cpu)) {
        // Core encountered an illegal instruction, bus error, or trap
    }
}

// 6. Tear down context
mcf5407_destroy(cpu);
```

### ISP1181 USB Controller Lifecycle

```c
// Instantiate controller model
isp1181_ctx* usb = isp1181_create(board_ptr, on_usb_irq, on_usb_tx);

// Activate full device emulation model
isp1181_set_backend(usb, MCF5407_ISP1181_BACKEND_FULL_MODEL);

// Deliver host packet to endpoint FIFO
int accepted = isp1181_rx(usb, 1, packet_data, packet_len);

// Advance 1 ms USB SOF frame
isp1181_tick(usb, 1);

isp1181_destroy(usb);
```

---

## Building and Testing

### 1. Pre-Generated C Distribution Build

Requires only CMake 3.26+ and a standard C11/C++17 compiler (GCC, Clang, or MSVC):

```bash
cmake -S . -B build-cdist -DMCF5407_USE_C_DIST=ON
cmake --build build-cdist --parallel
ctest --test-dir build-cdist -R t0_ --no-tests=error --output-on-failure
```

### 2. Native Nim Development Build

Requires CMake 3.26+ and the exact Nim compiler specified in [`.nim-version`](.nim-version):

```bash
# Narrow test suite (T0 aggregate)
cmake --preset t0
cmake --build --preset t0
ctest --preset t0

# Full test suite (including ColdFire instruction conformance corpus)
cmake --preset full
cmake --build --preset full
ctest --preset full
```

---

## Detailed Documentation

- [API Specification (Markdown)](docs/api.md): Complete function, callback, and type reference.
- [API Specification (HTML / GitHub Pages)](docs/index.html): Responsive, self-contained technical documentation page.
- [Sources and Architectural Decisions](docs/sources.md): Citations, manual cross-references, and design rationale.
- [Nim Toolchain Policy](docs/nim-version.md): Compiler version pinning and upgrading ceremony.
- [Cycle Scheduling](docs/avoiding-cycles.md): Architectural decisions regarding instruction timing.

---

## Licence

MIT. See [`LICENSE`](LICENSE).

**Clean-Room Implementation Notice**: This repository is developed under strict clean-room discipline with respect to GPL and LGPL code. No code from GPL/LGPL emulators or models is copied, transliterated, or referenced as an implementation template. All hardware behaviors are derived directly from Freescale/Motorola datasheets, Philips semiconductor manuals, and empirical hardware measurements.
