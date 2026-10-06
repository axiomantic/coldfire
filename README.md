# coldfire

A modular, high-performance emulator for Motorola and Freescale ColdFire processors (MCF5407, MCF5307, MCF5249) and a functional model of the Philips ISP1181 USB device controller.

The core implementation is authored in Nim, exposing a pure C application binary interface (ABI) declared in [`include/coldfire.h`](include/coldfire.h) and [`include/isp1181.h`](include/isp1181.h). Downstream consumers can consume the library either by compiling the original Nim sources or by building directly from pre-generated, platform-native C translation units requiring only a standard C11 compiler.

---

## Key Features

- **Pure C11 ABI Boundary**: Communicates strictly via standard types, opaque context pointers, and C function pointers. No Nim runtime internals, garbage collector handles, or C++ virtual tables cross the interface.
- **Header Architecture**:
  - [`include/coldfire.h`](include/coldfire.h): Canonical ColdFire processor API (`cf_*`).
  - [`include/isp1181.h`](include/isp1181.h): Dedicated Philips ISP1181 USB controller API (`isp1181_*`).
- **Supported Architecture & ISA Variants**:
  - **ColdFire ISA_A**: MCF5307 and baseline V3 architectural features.
  - **ColdFire ISA_A+**: MCF5249, MCF5272 with hardware divider and enhanced MAC support.
  - **ColdFire ISA_B**: MCF5407 V4 core with dual-issue superscalar pipeline semantics, branch prediction, and supervisor extensions.
  - **ColdFire ISA_C & EMAC**: Extended Multiply-Accumulate unit instructions and pipeline registers.
- **Dual Build Modes**:
  - **Native Nim Mode**: Drives the pinned Nim compiler directly via CMake for active core development.
  - **Pre-Generated C Distribution**: Downstream consumers do **not** require a Nim installation. Standard C11 builds are supported on macOS, Linux x86_64, and Windows x86_64.
- **Philips ISP1181 USB Device Controller**: Complete endpoint register file, double-buffered FIFOs, setup packet handling, OUT/IN token processing, and diagnostic ring logging.
- **Deterministic State Serialization**: Full snapshot capture and restore for deterministic replay and state persistence.

---

## Pre-Generated C Distribution

To ensure frictionless integration into consumer projects without introducing a Nim toolchain dependency, pre-generated C translation units are provided in `c_src/`:

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
- To explicitly force the C distribution even when Nim is installed, pass `-DCOLDFIRE_USE_C_DIST=ON`.

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
| `COLDFIRE_USE_C_DIST` | `OFF` (or `ON` if `nim` missing) | Compiles `libcoldfire` directly from `c_src/` using standard C11. |

### Exported Targets

- `coldfire::coldfire` (canonical target)

### Consuming via `FetchContent`

```cmake
include(FetchContent)

FetchContent_Declare(
    coldfire
    GIT_REPOSITORY https://github.com/axiomantic/coldfire.git
    GIT_TAG        main # Or pinned commit hash
)

# Optional: Force pre-generated C distribution (no Nim dependency required)
set(COLDFIRE_USE_C_DIST ON CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(coldfire)

# Link against your application or plugin target
target_link_libraries(my_emulator PRIVATE coldfire::coldfire)
```

### Consuming via `add_subdirectory`

```cmake
add_subdirectory(path/to/coldfire)
target_link_libraries(my_emulator PRIVATE coldfire::coldfire)
```

The exported target automatically propagates the include directory for `coldfire.h` and `isp1181.h`.

---

## Quick API Overview

Full documentation is available in the [API Documentation Guide](docs/api.md).

### Processor Core Lifecycle (`coldfire.h`)

```c
#include "coldfire.h"

// 1. Initialize runtime primitives once (idempotent, thread-safe)
if (!cf_runtime_init()) {
    // Handle initialization failure
}

// 2. Configure processor core parameters
cf_config cfg = {
    .isa = CF_ISA_A,               // Or CF_ISA_B, CF_ISA_A_PLUS, etc.
    .vbr_mask = 0xFFF00000,        // Hardware VBR alignment mask
    .user = board_ptr,
    .rd = board_read,
    .wr = board_write,
    .iack = board_iack
};

// 3. Instantiate core
cf_ctx* cpu = cf_create(&cfg);

// 4. Reset processor with initial stack pointer and program counter
cf_reset(cpu, 0x00040000, 0x00000400);

// 5. Execute for a quantum (instruction-boundary accurate)
uint32_t cycles_spent = cf_exec(cpu, 1000);

// 6. Inspect execution status
if (cf_halted(cpu)) {
    if (cf_faulted(cpu)) {
        // Core encountered an illegal instruction, bus error, or unhandled trap
    }
}

// 7. Tear down context
cf_destroy(cpu);
```

### ISP1181 USB Controller Lifecycle (`isp1181.h`)

```c
#include "isp1181.h"

// Instantiate controller model
isp1181_ctx* usb = isp1181_create(board_ptr, on_usb_irq, on_usb_tx);

// Activate full device emulation model
isp1181_set_backend(usb, ISP1181_BACKEND_FULL_MODEL);

// Deliver host packet to endpoint FIFO
int accepted = isp1181_rx(usb, 1, packet_data, packet_len);

// Advance 1 ms USB SOF frame
isp1181_tick(usb, 1);

isp1181_destroy(usb);
```

## Building and Testing

### 1. Pre-Generated C Distribution Build

Requires only CMake 3.26+ and a standard C11/C++17 compiler (GCC, Clang, or MSVC):

```bash
cmake -S . -B build-cdist -DCOLDFIRE_USE_C_DIST=ON
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

- [Online Documentation (GitHub Pages)](https://axiomantic.github.io/coldfire/): Live rendered documentation portal.
- [API Specification](docs/api.md): Complete function, callback, and type reference.
- [Sources and Architectural References](docs/sources.md): Hardware manual citations, register decodes, and design rationale.

---

## Licence

MIT. See [`LICENSE`](LICENSE).

**Clean-Room Implementation Notice**: This repository is developed under strict clean-room discipline with respect to GPL and LGPL code. No code from GPL/LGPL emulators or models is copied, transliterated, or referenced as an implementation template. All hardware behaviors are derived directly from Freescale/Motorola datasheets, Philips semiconductor manuals, and empirical hardware measurements.
