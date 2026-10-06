# coldfire / mcf5407 Documentation

Welcome to the documentation for **`coldfire` / `mcf5407`**, an emulator for Motorola and Freescale ColdFire processor cores (supporting ISA_A, ISA_A+, ISA_B, ISA_C, and EMAC architectures, including MCF5407, MCF5307, and MCF5249).

---

## Documentation Sections

- **[API Specification](api.md)**  
  Comprehensive reference for the C application binary interface declared in `include/coldfire.h`. Details initialization lifecycle, execution budgeting, memory/bus callbacks, interrupt servicing, and deterministic state serialization.

- **[Sources and Architectural References](sources.md)**  
  Hardware manual citations, register decodes, chip-select configurations, and clean-room implementation rationale derived from Motorola/Freescale documentation.

---

## Architecture Overview

The core is authored in Nim and compiled to native C translation units. Downstream consumers interact exclusively through a pure C11 ABI boundary:

- **Canonical Header**:
  - `include/coldfire.h`: Primary processor core C ABI (`cf_*`).
- **Opaque Handle Context**: All emulator instances are referenced via `cf_ctx*`.
- **Zero Allocations in Critical Loops**: Step and execution functions operate strictly within caller-provided memory buffers.
- **Host Callbacks**: The host provides read/write bus callbacks and IRQ acknowledgements.
- **Deterministic State**: State snapshots can be saved and restored at arbitrary execution points.

---

## Quick Example

```c
#include "coldfire.h"
#include <stdio.h>

static uint32_t host_read(void* user, uint32_t addr, int size, cf_bus_status* status) {
    *status = CF_BUS_OK;
    return 0; // Return memory data at address
}

static void host_write(void* user, uint32_t addr, int size, uint32_t val, cf_bus_status* status) {
    *status = CF_BUS_OK;
    // Handle memory write
}

int main(void) {
    if (!cf_runtime_init()) {
        return 1;
    }

    cf_config cfg = {
        .isa = CF_ISA_A,
        .vbr_mask = 0xFFF00000,
        .user = NULL,
        .rd = host_read,
        .wr = host_write,
        .iack = NULL
    };

    cf_ctx* cpu = cf_create(&cfg);
    cf_reset(cpu, 0x00040000, 0x00000400);

    // Execute 1000 clock cycles
    uint32_t cycles_run = cf_exec(cpu, 1000);
    printf("Executed %u cycles\n", cycles_run);

    cf_destroy(cpu);
    return 0;
}
```

---

## Repository and Code

- GitHub Repository: [axiomantic/coldfire](https://github.com/axiomantic/coldfire)
- Canonical C Header: [`include/coldfire.h`](https://github.com/axiomantic/coldfire/blob/main/include/coldfire.h)
