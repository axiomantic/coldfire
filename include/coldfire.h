/* coldfire.h - Canonical C application binary interface for the ColdFire
 * family microprocessor emulator.
 *
 * Supported ISA variants: ColdFire ISA_A, ISA_A+, ISA_B, ISA_C, with
 * optional EMAC (Enhanced Multiply-Accumulate) extensions.
 *
 * The Nim implementation exports these symbols with
 * `{.exportc: "<c name>", cdecl, dynlib.}` and both sides include this file.
 * The interface is strictly standardized to C11 / C++17 compatibility.
 *
 * What crosses: fixed-width integers, opaque pointers to context objects
 * allocated on the emulator side, raw byte buffers with explicit length,
 * and cdecl C function pointers.
 *
 * What never crosses: Nim runtime internals, garbage-collected types,
 * C++ objects, references, or exceptions.
 */

#ifndef COLDFIRE_H
#define COLDFIRE_H

#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus) && __cplusplus >= 201703L
#  define CF_MUST_USE [[nodiscard]]
#elif !defined(__cplusplus) && defined(__STDC_VERSION__) && \
      __STDC_VERSION__ >= 202311L
#  define CF_MUST_USE [[nodiscard]]
#elif defined(__GNUC__) || defined(__clang__)
#  define CF_MUST_USE __attribute__((warn_unused_result))
#else
#  define CF_MUST_USE
#endif

#if defined(__GNUC__) || defined(__clang__)
#  define CF_MUST_CHECK __attribute__((warn_unused_result))
#else
#  define CF_MUST_CHECK
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ----------------------------------------------------------- Core context */

typedef struct cf_ctx cf_ctx;

/* ---------------------------------------------------- Bus status & callbacks */

typedef enum {
	CF_BUS_OK           = 0, /* access completed normally */
	CF_BUS_UNMAPPED     = 1, /* no device decoded at this address */
	CF_BUS_SIZE_ILLEGAL = 2, /* transfer size not supported by device */
	CF_BUS_FAULT        = 3  /* device reported an internal bus fault */
} cf_bus_status;

/* `size` is operand count of bytes: 1, 2, or 4. */
typedef uint32_t (*cf_read_fn)(void* user, uint32_t addr, int size,
                               cf_bus_status* status);
typedef void (*cf_write_fn)(void* user, uint32_t addr, int size,
                            uint32_t value, cf_bus_status* status);
typedef void (*cf_iack_fn)(void* user, int level, uint8_t vector);

/* ----------------------------------------------------------- Configuration */

typedef enum {
	CF_ISA_A        = 0,
	CF_ISA_A_PLUS   = 1,
	CF_ISA_B        = 2,
	CF_ISA_C        = 3,
	CF_ISA_EMAC     = (1 << 8)
} cf_isa_variant;

typedef struct cf_config {
	cf_isa_variant isa;
	uint32_t vbr_mask;
	void* user;
	cf_read_fn rd;
	cf_write_fn wr;
	cf_iack_fn iack;
} cf_config;

/* ------------------------------------------------------- Register indexing */

enum {
	CF_REG_D0       = 0,
	CF_REG_D1       = 1,
	CF_REG_D2       = 2,
	CF_REG_D3       = 3,
	CF_REG_D4       = 4,
	CF_REG_D5       = 5,
	CF_REG_D6       = 6,
	CF_REG_D7       = 7,
	CF_REG_A0       = 8,
	CF_REG_A1       = 9,
	CF_REG_A2       = 10,
	CF_REG_A3       = 11,
	CF_REG_A4       = 12,
	CF_REG_A5       = 13,
	CF_REG_A6       = 14,
	CF_REG_A7       = 15,
	CF_REG_SR       = 16,
	CF_REG_PC       = 17,
	CF_REG_VBR      = 18,
	CF_REG_CACR     = 19,
	CF_REG_ACR0     = 20,
	CF_REG_ACR1     = 21,
	CF_REG_RAMBAR0  = 22,
	CF_REG_RAMBAR1  = 23,
	CF_REG_MBAR     = 24,
	CF_REG_ACR2     = 25,
	CF_REG_ACR3     = 26
};

#define CF_IRQ_NONE 0

/* ------------------------------------------------------------- Primary ABI */

CF_MUST_CHECK int cf_runtime_init(void);

cf_ctx* cf_create(const cf_config* config);
void cf_destroy(cf_ctx* ctx);
void cf_reset(cf_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc);

uint32_t cf_exec(cf_ctx* ctx, uint32_t max_cycles);

int cf_set_reg(cf_ctx* ctx, int index, uint32_t value);
uint32_t cf_get_reg(const cf_ctx* ctx, int index);

int cf_halted(const cf_ctx* ctx);
int cf_faulted(const cf_ctx* ctx);

void cf_set_irq(cf_ctx* ctx, int level, uint8_t vector, int autovector);

size_t cf_state_size(void);
void cf_state_save(const cf_ctx* ctx, void* dst);
void cf_state_load(cf_ctx* ctx, const void* src);

#ifdef __cplusplus
}
#endif

#endif /* COLDFIRE_H */
