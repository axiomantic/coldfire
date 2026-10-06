# ColdFire & ISP1181 C API Specification

This document specifies the C application binary interface (ABI) exposed by the ColdFire emulator and ISP1181 USB controller via [`include/coldfire.h`](../include/coldfire.h) and [`include/isp1181.h`](../include/isp1181.h), along with the backward compatibility layer in [`include/mcf5407.h`](../include/mcf5407.h).

The interface is strictly standardized to C11 / C++17 compatibility. No Nim runtime internals, garbage collector pointers, or C++ language constructs cross this boundary.

---

## Table of Contents

1. [Runtime Initialization](#1-runtime-initialization)
2. [ColdFire Core API (`coldfire.h`)](#2-coldfire-core-api-coldfireh)
   - [Context & Configuration Types](#context--configuration-types)
   - [Memory & Bus Callbacks](#memory--bus-callbacks)
   - [Core Lifecycle](#core-lifecycle)
   - [Execution & Stepping](#execution--stepping)
   - [Register Access](#register-access)
   - [Halt & Fault Inspection](#halt--fault-inspection)
   - [Interrupt Controller](#interrupt-controller)
   - [State Serialization](#state-serialization)
3. [Philips ISP1181 USB Controller API (`isp1181.h`)](#3-philips-isp1181-usb-controller-api-isp1181h)
   - [Controller Context & Callbacks](#controller-context--callbacks)
   - [Lifecycle & Backend Selection](#lifecycle--backend-selection)
   - [Bus Interface](#bus-interface)
   - [USB Packet Transactions](#usb-packet-transactions)
   - [Timer & Frame Timing](#timer--frame-timing)
   - [Endpoint Geometry & Configuration](#endpoint-geometry--configuration)
   - [Diagnostics & Audit Logging](#diagnostics--audit-logging)
   - [USB State Serialization](#usb-state-serialization)
4. [Migrating from `mcf5407` (Compatibility Transition Guide)](#4-migrating-from-mcf5407-compatibility-transition-guide)
   - [Header Separation](#header-separation)
   - [Symbol Mapping Reference](#symbol-mapping-reference)
5. [Complete C Integration Example](#5-complete-c-integration-example)

---

## 1. Runtime Initialization

The library uses a thread-safe, idempotent initialization mechanism.

```c
CF_MUST_CHECK int cf_runtime_init(void);
```

- **Returns**: `1` if the runtime is successfully initialized and ready for use; `0` if an initialization failure or timeout occurred.
- **Behavior**: Multiple calls from any thread are safe. If an initial initialization attempt fails or stalls, the function records a terminal failure, outputs a diagnostic line to `stderr`, and returns `0` on all subsequent invocations.
- **Fail-Safe Guarantee**: Downstream constructors (`cf_create`, `isp1181_create`) query this status internally and return `NULL` if initialization did not complete.

---

## 2. ColdFire Core API (`coldfire.h`)

### Context & Configuration Types

The core execution context is opaque:

```c
typedef struct cf_ctx cf_ctx;
typedef cf_ctx coldfire_t;
```

#### ISA Variants

```c
typedef enum cf_isa_variant {
    CF_ISA_A      = 0,     /* Baseline ColdFire ISA_A (MCF5307, etc.) */
    CF_ISA_A_PLUS = 1,     /* ColdFire ISA_A+ (MCF5249, MCF5272, etc.) */
    CF_ISA_B      = 2,     /* ColdFire ISA_B (MCF5407 superscalar V4 core) */
    CF_ISA_C      = 3,     /* ColdFire ISA_C */
    CF_ISA_EMAC   = 0x100  /* Extended MAC / DSP instructions mask */
} cf_isa_variant;
```

#### Core Configuration Structure

```c
typedef struct cf_config {
    cf_isa_variant isa;       /* Target ISA architecture */
    uint32_t       vbr_mask;  /* Hardware VBR alignment mask (e.g. 0xFFF00000) */
    void*          user;      /* Host user context pointer passed to callbacks */
    cf_read_fn     rd;        /* Memory bus read callback */
    cf_write_fn    wr;        /* Memory bus write callback */
    cf_iack_fn     iack;      /* Interrupt acknowledge callback */
} cf_config;
```

### Memory & Bus Callbacks

Memory space is external to the core. The host platform supplies three callbacks governing bus read, bus write, and interrupt acknowledge cycles:

```c
typedef enum cf_bus_status {
    CF_BUS_OK           = 0, /* Access completed normally */
    CF_BUS_UNMAPPED     = 1, /* Address not decoded by any device */
    CF_BUS_SIZE_ILLEGAL = 2, /* Address decoded, but transfer size not supported */
    CF_BUS_FAULT        = 3  /* Target device reported an internal bus error */
} cf_bus_status;

typedef uint32_t (*cf_read_fn)(void* user, uint32_t addr, int size, cf_bus_status* status);
typedef void (*cf_write_fn)(void* user, uint32_t addr, int size, uint32_t value, cf_bus_status* status);
typedef void (*cf_iack_fn)(void* user, int level, uint8_t vector);
```

#### Callback Semantics
- `size`: The operand transfer width in bytes: `1` (byte), `2` (word), or `4` (longword).
- `status`: Out-parameter initialized by the core to `CF_BUS_OK` before the callback is invoked. If the board returns any non-OK status, the core aborts the instruction and raises an access fault exception.
- `cf_iack_fn`: Called immediately after the exception stack frame is constructed and prior to executing the first handler instruction. Edge-triggered interrupt sources should be acknowledged here.

### Core Lifecycle

```c
cf_ctx* cf_create(const cf_config* config);
void cf_destroy(cf_ctx* ctx);
void cf_reset(cf_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc);
```

- `cf_create`: Allocates a new CPU instance configured by `config`. Returns `NULL` if memory allocation fails, if `config` is `NULL`, or if the runtime is uninitialized.
- `cf_destroy`: Frees all resources allocated to the context. Safe to call with `NULL`.
- `cf_reset`: Restores the core to hardware reset state:
  - Sets the stack pointer `a7` to `initial_sp`.
  - Sets the program counter `pc` to `initial_pc`.
  - Sets the Status Register (SR) interrupt mask to level 7 (all interrupts masked).
  - Clears all internal control registers (VBR, CACR, ACR0–3, RAMBAR0–1, MBAR) to zero.
  - Inhibits interrupt sampling during execution of the first instruction at `initial_pc`.

### Execution & Stepping

```c
uint32_t cf_exec(cf_ctx* ctx, uint32_t max_cycles);
```

- **Parameters**: `max_cycles` specifies the execution cycle budget.
- **Returns**: The actual number of CPU clock cycles consumed.
- **Instruction Boundary Semantics**: Execution stops only at an instruction boundary. Consequently, the return value may exceed `max_cycles` by up to the cycle duration of the final instruction executed. Callers tracking a strict timebase should carry `spent - max_cycles` into the subsequent invocation.
- Returns `0` immediately if the core is halted, if `ctx` is `NULL`, or if `max_cycles` is `0`.

### Register Access

```c
int cf_set_reg(cf_ctx* ctx, int index, uint32_t value);
uint32_t cf_get_reg(const cf_ctx* ctx, int index);
```

#### Canonical Register Constants (`coldfire.h`)

| Identifier | Value | Target Register | Description |
|---|---|---|---|
| `CF_REG_D0 .. CF_REG_D7` | `0 .. 7` | `d0 .. d7` | 32-bit Data Registers |
| `CF_REG_A0 .. CF_REG_A7` | `8 .. 15` | `a0 .. a7` | 32-bit Address Registers (`a7` is the stack pointer) |
| `CF_REG_SP` | `15` | `a7 / SP` | Stack Pointer alias |
| `CF_REG_SR` | `16` | `SR` | Status Register (Condition codes + Supervisor state) |
| `CF_REG_PC` | `17` | `PC` | Program Counter (Read-only via `cf_get_reg`) |
| `CF_REG_VBR` | `18` | `VBR` | Vector Base Register |
| `CF_REG_CACR` | `19` | `CACR` | Cache Control Register |
| `CF_REG_ACR0` | `20` | `ACR0` | Access Control Register 0 (Data space) |
| `CF_REG_ACR1` | `21` | `ACR1` | Access Control Register 1 (Data space) |
| `CF_REG_RAMBAR0` | `22` | `RAMBAR0` | On-chip SRAM Base Address Register 0 |
| `CF_REG_RAMBAR1` | `23` | `RAMBAR1` | On-chip SRAM Base Address Register 1 |
| `CF_REG_MBAR` | `24` | `MBAR` | Module Base Address Register |
| `CF_REG_ACR2` | `25` | `ACR2` | Access Control Register 2 (Instruction space) |
| `CF_REG_ACR3` | `26` | `ACR3` | Access Control Register 3 (Instruction space) |

`cf_set_reg` returns `1` on success, or `0` if `index` is out of range or read-only (such as `CF_REG_PC`).

### Halt & Fault Inspection

```c
int cf_halted(const cf_ctx* ctx);
int cf_faulted(const cf_ctx* ctx);
```

- `cf_halted`: Returns `1` if execution has halted (due to an unrecoverable fault or explicit stop condition) and cannot proceed without a reset.
- `cf_faulted`: Returns `1` if the halt condition resulted from an unhandled trap, bus fault, illegal instruction, unaligned access, or divide-by-zero.

### Interrupt Controller

```c
#define CF_IRQ_NONE 0

void cf_set_irq(cf_ctx* ctx, int level, uint8_t vector, int autovector);
```

- `level`: Interrupt priority level `1` through `7`, or `CF_IRQ_NONE` (`0`) to clear.
- `vector`: Interrupt vector index (used when `autovector == 0`).
- `autovector`: If non-zero, the core generates the vector automatically based on `level` (`24 + level`).
- **Semantics**:
  - Levels 1–6 are level-sensitive: the presentation persists until updated.
  - Level 7 is edge-triggered (Non-Maskable Interrupt): the core latches a transition to level 7 and clears the latch when the interrupt is serviced.

### State Serialization

```c
size_t cf_state_size(void);
void cf_state_save(const cf_ctx* ctx, void* dst);
void cf_state_load(cf_ctx* ctx, const void* src);
```

- `cf_state_size`: Returns the exact byte buffer size required to serialize core state (145 bytes payload + header/checksum).
- `cf_state_save`: Serializes internal registers, pipeline latches, interrupt states, and cycle counters into `dst`.
- `cf_state_load`: Deserializes saved state from `src`.

---

## 3. Philips ISP1181 USB Controller API (`isp1181.h`)

Declared in [`include/isp1181.h`](../include/isp1181.h).

### Controller Context & Callbacks

```c
typedef struct isp1181_ctx isp1181_ctx;

typedef void (*isp1181_irq_fn)(void* user, int asserted);
typedef void (*isp1181_tx_fn)(void* user, int endpoint, const uint8_t* data, size_t len);
```

- `isp1181_irq_fn`: Notifies host of USB interrupt pin state transitions (`asserted == 1` or `0`).
- `isp1181_tx_fn`: Called synchronously when the firmware validates an IN buffer and transmits a packet to the host.

### Lifecycle & Backend Selection

```c
#define ISP1181_BACKEND_STUB 0
#define ISP1181_BACKEND_FULL_MODEL 1

isp1181_ctx* isp1181_create(void* user, isp1181_irq_fn irq, isp1181_tx_fn tx);
void isp1181_destroy(isp1181_ctx* ctx);

int isp1181_set_backend(isp1181_ctx* ctx, int backend);
```

- The controller starts in `ISP1181_BACKEND_STUB` mode (inert, reads return `0x00`).
- Switching to `ISP1181_BACKEND_FULL_MODEL` activates register decoding, FIFO models, and interrupt generation.

### Bus Interface

Direct register access via the CPU bus (typically mapped into ColdFire Chip Select space, e.g. CS3):

```c
uint8_t isp1181_read(isp1181_ctx* ctx, uint32_t addr);
void isp1181_write(isp1181_ctx* ctx, uint32_t addr, uint8_t value);
```

- `addr`: Address line A0 selects data (`0`) versus command/register index (`1`).

### USB Packet Transactions

Driven by the host USB bus controller:

```c
ISP1181_MUST_USE
int isp1181_rx(isp1181_ctx* ctx, int endpoint, const uint8_t* data, size_t len);

int isp1181_setup(isp1181_ctx* ctx, const uint8_t* data, size_t len);

int isp1181_in_token(isp1181_ctx* ctx, int endpoint);
```

- `isp1181_rx`: Delivers an OUT packet from host to the specified endpoint FIFO. Returns `1` if accepted, `0` if rejected (FIFO full or disabled).
- `isp1181_setup`: Delivers an 8-byte SETUP packet to Endpoint 0 OUT. Flushes pending control buffers and resets endpoint status. Returns `1` on acceptance.
- `isp1181_in_token`: Delivers an IN token from the host. If data is validated in the endpoint FIFO, the model invokes `isp1181_tx_fn` and returns `1`; returns `0` (NAK) if no data is pending.

### Timer & Frame Timing

```c
void isp1181_tick(isp1181_ctx* ctx, uint32_t sof_frames);
```

- Advances the internal USB frame counter by `sof_frames` Start-of-Frame units (1 ms per frame).

### Endpoint Geometry & Configuration

```c
ISP1181_MUST_USE size_t isp1181_config_slots(void);

ISP1181_MUST_USE int isp1181_config_slot(const isp1181_ctx* ctx, size_t slot, uint8_t* value);

ISP1181_MUST_USE int isp1181_slot_buffer(const isp1181_ctx* ctx, size_t slot,
                                         size_t* max_packet_bytes,
                                         size_t* buffer_count);
```

- `isp1181_config_slot`: Reads raw `DcEndpointConfiguration` byte (EPDIR, FIFOEN, DBLBUF, FFOSZ).
- `isp1181_slot_buffer`: Returns decoded buffer geometry: maximum packet size in bytes and FIFO depth (1 or 2 for double buffering).

### Diagnostics & Audit Logging

The model maintains an internal bounded trace log recording dropped packets, unrecognized commands, or invalid states:

```c
ISP1181_MUST_USE size_t isp1181_log_written(const isp1181_ctx* ctx);
ISP1181_MUST_USE size_t isp1181_log_retained(const isp1181_ctx* ctx);
ISP1181_MUST_USE size_t isp1181_log_line(const isp1181_ctx* ctx, size_t index, char* dst, size_t capacity);
ISP1181_MUST_USE size_t isp1181_report(const isp1181_ctx* ctx, char* dst, size_t capacity);
```

- `isp1181_report`: Generates a formatted ASCII diagnostic summary of endpoint configurations and log events.
- Automatic Teardown Report: Setting the environment variable `ISP1181_REPORT=<filepath>` (or `MCF5407_ISP1181_REPORT=<filepath>`) causes `isp1181_destroy` to append a full diagnostic report upon termination.

### USB State Serialization

```c
size_t isp1181_state_size(void);
void isp1181_state_save(const isp1181_ctx* ctx, void* dst);
void isp1181_state_load(isp1181_ctx* ctx, const void* src);
```

---

## 4. Migrating from `mcf5407` (Compatibility Transition Guide)

The monolithic `include/mcf5407.h` header has been decoupled into two dedicated domain headers:
1. `include/coldfire.h`: ColdFire processor core emulation.
2. `include/isp1181.h`: Philips ISP1181 USB device controller.

[`include/mcf5407.h`](../include/mcf5407.h) remains fully supported as a transparent, inline compatibility layer. Existing code bases will compile without modification or link disruption.

### Header Separation

When refactoring downstream code to adopt the canonical headers:

```c
/* Legacy single header include */
#include "mcf5407.h"

/* Modern modular includes */
#include "coldfire.h"  /* For ColdFire core */
#include "isp1181.h"   /* If USB controller emulation is required */
```

### Symbol Mapping Reference

| Legacy `mcf5407` Symbol | Canonical `coldfire` / `isp1181` Symbol | Notes |
|---|---|---|
| `mcf5407_ctx` | `cf_ctx` | `typedef cf_ctx mcf5407_ctx;` |
| `mcf5407_bus_status` | `cf_bus_status` | `typedef cf_bus_status mcf5407_bus_status;` |
| `MCF5407_BUS_OK` | `CF_BUS_OK` | `#define MCF5407_BUS_OK CF_BUS_OK` |
| `MCF5407_BUS_UNMAPPED` | `CF_BUS_UNMAPPED` | `#define MCF5407_BUS_UNMAPPED CF_BUS_UNMAPPED` |
| `MCF5407_BUS_SIZE_ILLEGAL` | `CF_BUS_SIZE_ILLEGAL` | `#define MCF5407_BUS_SIZE_ILLEGAL CF_BUS_SIZE_ILLEGAL` |
| `MCF5407_BUS_FAULT` | `CF_BUS_FAULT` | `#define MCF5407_BUS_FAULT CF_BUS_FAULT` |
| `MCF5407_IRQ_NONE` | `CF_IRQ_NONE` | `#define MCF5407_IRQ_NONE CF_IRQ_NONE` |
| `mcf5407_runtime_init()` | `cf_runtime_init()` | Static inline wrapper |
| `mcf5407_create(u, rd, wr, iack)` | `cf_create(&cfg)` | Inline wrapper constructs `cf_config` with `CF_ISA_A` and default mask |
| `mcf5407_destroy(ctx)` | `cf_destroy(ctx)` | Static inline wrapper |
| `mcf5407_reset(ctx, sp, pc)` | `cf_reset(ctx, sp, pc)` | Static inline wrapper |
| `mcf5407_exec(ctx, cycles)` | `cf_exec(ctx, cycles)` | Static inline wrapper |
| `mcf5407_set_reg(ctx, idx, val)` | `cf_set_reg(ctx, idx, val)` | Static inline wrapper |
| `mcf5407_get_reg(ctx, idx)` | `cf_get_reg(ctx, idx)` | Static inline wrapper |
| `mcf5407_halted(ctx)` | `cf_halted(ctx)` | Static inline wrapper |
| `mcf5407_faulted(ctx)` | `cf_faulted(ctx)` | Static inline wrapper |
| `mcf5407_set_irq(ctx, l, v, av)` | `cf_set_irq(ctx, l, v, av)` | Static inline wrapper |
| `mcf5407_state_size()` | `cf_state_size()` | Static inline wrapper |
| `mcf5407_state_save(ctx, dst)` | `cf_state_save(ctx, dst)` | Static inline wrapper |
| `mcf5407_state_load(ctx, src)` | `cf_state_load(ctx, src)` | Static inline wrapper |
| `MCF5407_ISP1181_BACKEND_STUB` | `ISP1181_BACKEND_STUB` | Forwarded define |
| `MCF5407_ISP1181_BACKEND_FULL_MODEL` | `ISP1181_BACKEND_FULL_MODEL` | Forwarded define |

---

## 5. Complete C Integration Example

```c
#include "coldfire.h"
#include "isp1181.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t ram[1024 * 1024]; // 1MB RAM
    isp1181_ctx* usb;
} Machine;

static uint32_t bus_read(void* user, uint32_t addr, int size, cf_bus_status* status) {
    Machine* m = (Machine*)user;
    if (addr + size <= sizeof(m->ram)) {
        uint32_t val = 0;
        for (int i = 0; i < size; ++i) {
            val = (val << 8) | m->ram[addr + i];
        }
        return val;
    }
    *status = CF_BUS_UNMAPPED;
    return 0;
}

static void bus_write(void* user, uint32_t addr, int size, uint32_t value, cf_bus_status* status) {
    Machine* m = (Machine*)user;
    if (addr + size <= sizeof(m->ram)) {
        for (int i = size - 1; i >= 0; --i) {
            m->ram[addr + i] = (uint8_t)(value & 0xFF);
            value >>= 8;
        }
        return;
    }
    *status = CF_BUS_UNMAPPED;
}

static void bus_iack(void* user, int level, uint8_t vector) {
    printf("Acknowledged IRQ level %d, vector %u\n", level, vector);
}

int main(void) {
    if (!cf_runtime_init()) {
        fprintf(stderr, "Failed to initialize ColdFire runtime\n");
        return 1;
    }

    Machine machine = {0};

    // Initialize reset vector: Initial SP = 0x00080000, Initial PC = 0x00000400
    machine.ram[0] = 0x00; machine.ram[1] = 0x08; machine.ram[2] = 0x00; machine.ram[3] = 0x00;
    machine.ram[4] = 0x00; machine.ram[5] = 0x00; machine.ram[6] = 0x04; machine.ram[7] = 0x00;

    // Place a NOP opcode at 0x400: 0x4E71
    machine.ram[0x400] = 0x4E;
    machine.ram[0x401] = 0x71;

    cf_config cfg = {
        .isa = CF_ISA_A,
        .vbr_mask = 0xFFF00000,
        .user = &machine,
        .rd = bus_read,
        .wr = bus_write,
        .iack = bus_iack
    };

    cf_ctx* cpu = cf_create(&cfg);
    if (!cpu) {
        fprintf(stderr, "Failed to create CPU context\n");
        return 1;
    }

    cf_reset(cpu, 0x00080000, 0x00000400);

    uint32_t spent = cf_exec(cpu, 100);
    printf("Executed %u cycles. PC = 0x%08X\n", spent, cf_get_reg(cpu, CF_REG_PC));

    cf_destroy(cpu);
    return 0;
}
```
