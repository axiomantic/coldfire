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

/* ========================================================================= */
/* On-Chip Peripherals & Hardware Interfacing                                */
/* ========================================================================= */

/* ----------------------------------------------------------------- DUART0 */

#define CF_UART_CH0  0  /* Channel A (UART0) - MIDI In/Out in gearmulator (MBAR + 0x1C0) */
#define CF_UART_CH1  1  /* Channel B (UART1) - Auxiliary / unused (MBAR + 0x200) */

/* Transmit callback: invoked synchronously when the firmware writes a byte
 * to the transmitter buffer (UTB) while the transmitter is enabled.
 */
typedef void (*cf_uart_tx_fn)(void* user, int channel, uint8_t byte);

/* Feed an incoming byte into the receiver FIFO (depth 4) of the specified channel.
 * Sets USR RxRDY (bit 0) and FFULL (bit 1 if FIFO reaches 4 bytes).
 * Triggers interrupt via INTC (ICR4 for CH0, vector 0x42) if enabled by UIMR.
 * Returns 0 on success, or negative error code:
 *   -1: invalid channel index or null ctx
 *   -2: receiver disabled or FIFO overflow (character dropped)
 */
int cf_uart_rx_byte(cf_ctx* ctx, int channel, uint8_t byte);

/* Register a transmit handler callback for the specified channel.
 * Returns 0 on success, or -1 on invalid channel or null ctx.
 */
int cf_uart_set_tx_handler(cf_ctx* ctx, int channel, cf_uart_tx_fn fn, void* user);

/* Read the UART Status Register (USR) for the specified channel.
 * Bit 0: RxRDY (at least one character in receiver FIFO)
 * Bit 1: FFULL (receiver FIFO is full, 4 characters)
 * Bit 2: TxRDY (transmitter buffer empty and ready for next character)
 * Bit 3: TxEMP (transmitter completely empty)
 * Returns USR byte, or 0 if channel is invalid or ctx is null.
 */
uint8_t cf_uart_get_usr(const cf_ctx* ctx, int channel);

/* ----------------------------------------------------------------- Timers */

/* Advance on-chip general purpose timers (Timer 1 at MBAR+0x140, Timer 2 at MBAR+0x180)
 * by the specified number of input clock cycles.
 * Each enabled timer advances its prescaler and counter (TCNn);
 * on reference match (TCNn == TRRn), TERn[REF] is set and, if TMRn[ORI] is set,
 * asserts internal interrupt (ICR1 for Timer 1, ICR2 for Timer 2).
 */
void cf_timer_tick(cf_ctx* ctx, uint32_t cycles);

/* --------------------------------------------------- Interrupt Controller */

/* Hardware external interrupt pin encodings (MCF5307 / MCF5407 UM Table 8-4 / Table 9-4) */
typedef enum {
	CF_IRQ_PIN_7 = 0, /* IRQ7: fixed at interrupt level 7 (NMI) */
	CF_IRQ_PIN_5 = 1, /* IRQ5: level 5 (or level 4 if IRQPAR[2] is set) */
	CF_IRQ_PIN_3 = 2, /* IRQ3: level 3 (or level 6 if IRQPAR[1] is set) - USB ISP1181 */
	CF_IRQ_PIN_1 = 3  /* IRQ1: level 1 (or level 2 if IRQPAR[0] is set) */
} cf_irq_pin;

/* Assert or deassert an external interrupt pin.
 * `pin`: hardware pin index (0..3, or CF_IRQ_PIN_*).
 * `asserted`: non-zero to assert the pin, 0 to deassert.
 * The on-chip 2-tier interrupt controller updates external pending state,
 * arbitrates against internal peripheral sources (Timers, UARTs, DMA, MBUS),
 * applies IRQPAR level mapping, evaluates AVR autovector bits,
 * and presents the winning level/vector to the CPU core.
 */
void cf_set_irq_pin(cf_ctx* ctx, int pin, int asserted);

/* Query the currently presented interrupt state from the on-chip interrupt controller.
 * Provided for observability, test verification, and debugging.
 */
int cf_intc_get_presented_level(const cf_ctx* ctx);
uint8_t cf_intc_get_presented_vector(const cf_ctx* ctx);
int cf_intc_get_presented_autovector(const cf_ctx* ctx);

/* ------------------------------------------------- MBAR Internal Bus & SIM */

/* Direct access to on-chip peripheral registers mapped within the 4-Kbyte MBAR window.
 * `offset`: MBAR-relative byte offset (0x000 .. 0xFFF).
 * `size`: operand width in bytes (1, 2, or 4).
 * `status`: pointer to bus status output (CF_BUS_OK, CF_BUS_SIZE_ILLEGAL, etc.).
 *
 * Register Map:
 *   0x000..0x03F: SIM (RSR, SYPCR, SWIVR, SWSR, PAR, IRQPAR, PLLCR, MPARK)
 *   0x040..0x05F: INTC (IPR, IMR, AVR at 0x04B, ICR0..11 at 0x04C..0x057)
 *   0x080..0x0DF: Chip Selects (CSAR0..7, CSMR0..7, CSCR0..7)
 *   0x100..0x13F: DRAM Controller (DCR, DACR0/1, DMR0/1)
 *   0x140..0x17F: Timer 1 (TMR, TRR, TCR, TCN, TER at 0x151)
 *   0x180..0x1BF: Timer 2 (TMR, TRR, TCR, TCN, TER at 0x191)
 *   0x1C0..0x1FF: DUART Channel 0 (UART0)
 *   0x200..0x23F: DUART Channel 1 (UART1)
 *   0x240..0x27F: Parallel Port (PADDR at 0x244, PADAT at 0x248)
 *   0x280..0x2BF: M-Bus / I2C Controller
 */
uint32_t cf_mbar_read(cf_ctx* ctx, uint32_t offset, int size, cf_bus_status* status);
void cf_mbar_write(cf_ctx* ctx, uint32_t offset, int size, uint32_t value, cf_bus_status* status);

/* Front Panel Port A read hook: allows consumer board to supply dynamic
 * row bits for PADAT (MBAR+0x248) button/encoder scanning.
 */
typedef uint16_t (*cf_port_a_read_fn)(void* user);
void cf_sim_set_port_a_hook(cf_ctx* ctx, cf_port_a_read_fn hook, void* user);

/* Hardware strap configuration:
 * `engine_strap`: if 1, sets UIPCR1 bit 0 (engine model strap active)
 * and write-protects PADAT bit 9.
 */
void cf_sim_set_engine_strap(cf_ctx* ctx, int engine_strap);

#ifdef __cplusplus
}
#endif

#endif /* COLDFIRE_H */
