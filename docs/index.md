# mcf5407 Documentation

Welcome to the documentation for **`mcf5407`**, an emulator for the Motorola MCF5407 ColdFire processor core and a functional model of the Philips ISP1181 USB device controller.

---

## Documentation Sections

- **[API Specification](api.md)**  
  Comprehensive reference for the C application binary interface declared in `include/mcf5407.h`. Details initialization lifecycle, execution budgeting, memory/bus callbacks, interrupt servicing, USB controller interfaces, and deterministic state serialization.

- **[Sources and Architectural References](sources.md)**  
  Hardware manual citations, register decodes, chip-select configurations, and clean-room implementation rationale derived from Motorola/Freescale and Philips documentation.

---

## Architecture Overview

`mcf5407` is authored in Nim and compiled to native C translation units. Downstream consumers interact exclusively through a pure C11 ABI boundary:

- **Opaque Handle Context**: All emulator instances are referenced via `mcf5407_context*`.
- **Zero Allocations in Critical Loops**: Step and execution functions operate strictly within caller-provided memory buffers.
- **Host Callbacks**: The host provides read/write bus callbacks, IRQ acknowledgements, and USB transport hooks.
- **Deterministic State**: State snapshots can be saved and restored at arbitrary execution points.

---

## Quick Example

```c
#include "mcf5407.h"
#include <stdio.h>

static uint8_t host_read8(void* user_data, uint32_t addr) {
    return 0; // Return memory at address
}

static void host_write8(void* user_data, uint32_t addr, uint8_t val) {
    // Handle memory write
}

int main(void) {
    mcf5407_callbacks cb = {
        .read8 = host_read8,
        .write8 = host_write8,
        // ... set other required callbacks
    };

    mcf5407_context* ctx = mcf5407_create(&cb, NULL);
    mcf5407_reset(ctx);

    // Execute 1000 clock cycles
    int32_t cycles_run = mcf5407_execute(ctx, 1000);
    printf("Executed %d cycles\n", cycles_run);

    mcf5407_destroy(ctx);
    return 0;
}
```

---

## Repository and Code

- GitHub Repository: [axiomantic/mcf5407](https://github.com/axiomantic/mcf5407)
- C Header Definition: [`include/mcf5407.h`](https://github.com/axiomantic/mcf5407/blob/main/include/mcf5407.h)
