/* tests/t_peripheral_c_abi.cpp - test suite for canonical on-chip peripheral C ABI.
 *
 * Exercises the published C ABI contract declared in include/coldfire.h:
 *   - DUART0 (rx FIFO, status register, tx callback)
 *   - Timers (tick advancement, reference match, ICR assertion and clearing)
 *   - Interrupt Controller (external pin assert/deassert, dynamic IRQPAR mapping, level/vector queries)
 *   - MBAR internal access & SIM (port A hook, engine strap, access width validation)
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "coldfire.h"

namespace {

int g_passCount = 0;
int g_failCount = 0;

void checkImpl(bool ok, const char* label, const char* details = nullptr) {
	if (ok) {
		printf("PASSED  %s\n", label);
		++g_passCount;
	} else {
		printf("FAILED  %s%s%s\n", label, details ? " : " : "", details ? details : "");
		++g_failCount;
	}
}

#define CHECK(cond, label) checkImpl((cond), (label))

struct DummyBoard {
	uint8_t mem[0x1000] = {};
};

uint32_t dummyRead(void* user, uint32_t addr, int size, cf_bus_status* status) {
	auto* b = static_cast<DummyBoard*>(user);
	if (addr + uint32_t(size) > sizeof(b->mem)) {
		*status = CF_BUS_UNMAPPED;
		return 0;
	}
	*status = CF_BUS_OK;
	uint32_t res = 0;
	for (int i = 0; i < size; ++i) {
		res = (res << 8) | uint32_t(b->mem[addr + i]);
	}
	return res;
}

void dummyWrite(void* user, uint32_t addr, int size, uint32_t val, cf_bus_status* status) {
	auto* b = static_cast<DummyBoard*>(user);
	if (addr + uint32_t(size) > sizeof(b->mem)) {
		*status = CF_BUS_UNMAPPED;
		return;
	}
	*status = CF_BUS_OK;
	for (int i = 0; i < size; ++i) {
		const int shift = (size - 1 - i) * 8;
		b->mem[addr + i] = uint8_t((val >> shift) & 0xFFu);
	}
}

struct TxRecord {
	void* user = nullptr;
	int channel = -1;
	uint8_t byte = 0;
	int count = 0;
};

void onTx(void* user, int channel, uint8_t byte) {
	auto* rec = static_cast<TxRecord*>(user);
	rec->user = user;
	rec->channel = channel;
	rec->byte = byte;
	rec->count++;
}

struct PortARecord {
	uint16_t value = 0;
	int count = 0;
};

uint16_t onPortA(void* user) {
	auto* rec = static_cast<PortARecord*>(user);
	rec->count++;
	return rec->value;
}

void testDuart(cf_ctx* ctx) {
	cf_bus_status st = CF_BUS_OK;

	// Null context and invalid channel checks
	CHECK(cf_uart_rx_byte(nullptr, CF_UART_CH0, 0x11) == -1, "DUART: rx_byte with null ctx returns -1");
	CHECK(cf_uart_rx_byte(ctx, -1, 0x11) == -1, "DUART: rx_byte with channel -1 returns -1");
	CHECK(cf_uart_rx_byte(ctx, 2, 0x11) == -1, "DUART: rx_byte with channel 2 returns -1");
	CHECK(cf_uart_get_usr(nullptr, CF_UART_CH0) == 0, "DUART: get_usr with null ctx returns 0");
	CHECK(cf_uart_get_usr(ctx, 3) == 0, "DUART: get_usr with channel 3 returns 0");

	// Initial state: receiver disabled, so rx returns -2
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0x11) == -2, "DUART: rx_byte with receiver disabled returns -2");

	// Enable receiver via UCR (MBAR+0x1C8, cmd 0x01)
	cf_mbar_write(ctx, 0x1C8, 1, 0x01, &st);
	CHECK(st == CF_BUS_OK, "DUART: enable Rx via UCR succeeds");

	// Enable Rx interrupt in UIMR (MBAR+0x1D4, bit 1 = 0x02)
	cf_mbar_write(ctx, 0x1D4, 1, 0x02, &st);
	// Map UART0 to Level 5 via ICR4 (MBAR+0x050)
	cf_mbar_write(ctx, 0x050, 1, 0x14, &st);
	// Program UIVR vector to 0x42 (MBAR+0x1F0)
	cf_mbar_write(ctx, 0x1F0, 1, 0x42, &st);
	CHECK(st == CF_BUS_OK, "DUART: write UIVR vector 0x42 succeeds");

	// Feed first byte
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0xAA) == 0, "DUART: rx_byte 1 succeeds");
	uint8_t usr = cf_uart_get_usr(ctx, CF_UART_CH0);
	CHECK((usr & 0x01u) != 0, "DUART: USR RxRDY bit set after 1 byte");
	CHECK((usr & 0x02u) == 0, "DUART: USR FFULL bit clear after 1 byte");
	CHECK(cf_intc_get_presented_level(ctx) == 5, "DUART: interrupt presented at level 5");
	CHECK(cf_intc_get_presented_vector(ctx) == 0x42, "DUART: interrupt presented with vector 0x42");

	// Feed remaining 3 bytes into 4-byte FIFO
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0xBB) == 0, "DUART: rx_byte 2 succeeds");
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0xCC) == 0, "DUART: rx_byte 3 succeeds");
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0xDD) == 0, "DUART: rx_byte 4 succeeds");
	usr = cf_uart_get_usr(ctx, CF_UART_CH0);
	CHECK((usr & 0x01u) != 0, "DUART: USR RxRDY bit set when full");
	CHECK((usr & 0x02u) != 0, "DUART: USR FFULL bit set when full (4 bytes)");

	// 5th byte overflows
	CHECK(cf_uart_rx_byte(ctx, CF_UART_CH0, 0xEE) == -2, "DUART: rx_byte 5 returns -2 on overflow");

	// Read first byte from URB (MBAR+0x1CC)
	uint32_t val = cf_mbar_read(ctx, 0x1CC, 1, &st);
	CHECK(st == CF_BUS_OK && val == 0xAA, "DUART: read URB returns 0xAA");
	usr = cf_uart_get_usr(ctx, CF_UART_CH0);
	CHECK((usr & 0x02u) == 0, "DUART: USR FFULL cleared after read");
	CHECK((usr & 0x01u) != 0, "DUART: USR RxRDY still set with 3 bytes left");

	// Read remaining 3 bytes
	CHECK(cf_mbar_read(ctx, 0x1CC, 1, &st) == 0xBB, "DUART: read URB byte 2 == 0xBB");
	CHECK(cf_mbar_read(ctx, 0x1CC, 1, &st) == 0xCC, "DUART: read URB byte 3 == 0xCC");
	CHECK(cf_mbar_read(ctx, 0x1CC, 1, &st) == 0xDD, "DUART: read URB byte 4 == 0xDD");
	usr = cf_uart_get_usr(ctx, CF_UART_CH0);
	CHECK((usr & 0x01u) == 0, "DUART: USR RxRDY cleared after FIFO emptied");
	CHECK(cf_intc_get_presented_level(ctx) == 0, "DUART: interrupt deasserted after FIFO emptied");

	// Tx Handler tests
	TxRecord txRec;
	CHECK(cf_uart_set_tx_handler(nullptr, CF_UART_CH0, onTx, &txRec) == -1, "DUART: set_tx_handler null ctx returns -1");
	CHECK(cf_uart_set_tx_handler(ctx, 2, onTx, &txRec) == -1, "DUART: set_tx_handler invalid channel returns -1");
	CHECK(cf_uart_set_tx_handler(ctx, CF_UART_CH0, onTx, &txRec) == 0, "DUART: set_tx_handler succeeds");

	// Enable transmitter via UCR (MBAR+0x1C8, cmd 0x04)
	cf_mbar_write(ctx, 0x1C8, 1, 0x04, &st);
	usr = cf_uart_get_usr(ctx, CF_UART_CH0);
	CHECK((usr & 0x04u) != 0, "DUART: USR TxRDY set when transmitter enabled");

	// Write to UTB (MBAR+0x1CC)
	cf_mbar_write(ctx, 0x1CC, 1, 0x90, &st);
	CHECK(st == CF_BUS_OK, "DUART: write UTB completes");
	CHECK(txRec.count == 1, "DUART: tx callback invoked once");
	CHECK(txRec.channel == CF_UART_CH0, "DUART: tx callback received channel 0");
	CHECK(txRec.byte == 0x90, "DUART: tx callback received byte 0x90");
}

void testTimers(cf_ctx* ctx) {
	cf_bus_status st = CF_BUS_OK;

	// Reset Timer 1: TMR1 (MBAR+0x140) prescaler 0, ORI=1, RST=1 -> 0x0013
	cf_mbar_write(ctx, 0x140, 2, 0x0013, &st);
	// TRR1 (MBAR+0x144) reference = 5
	cf_mbar_write(ctx, 0x144, 2, 0x0005, &st);
	// ICR1 (MBAR+0x04D) = Level 6 (0x18)
	cf_mbar_write(ctx, 0x04D, 1, 0x18, &st);

	// Tick 4 cycles: TCN should be 4, no interrupt
	cf_timer_tick(ctx, 4);
	CHECK(cf_intc_get_presented_level(ctx) == 0, "Timer: no interrupt before reference match");

	// Tick 2 more cycles: TCN reaches 5, match occurs!
	cf_timer_tick(ctx, 2);
	CHECK(cf_intc_get_presented_level(ctx) == 6, "Timer: interrupt asserted at level 6 on match");

	// Verify TER1 (MBAR+0x151) has REF bit 1 set
	uint32_t ter = cf_mbar_read(ctx, 0x151, 1, &st);
	CHECK((ter & 0x02u) != 0, "Timer: TER1 REF bit is set");

	// Clear TER1 by writing 1 to bit 1
	cf_mbar_write(ctx, 0x151, 1, 0x02, &st);
	CHECK(cf_intc_get_presented_level(ctx) == 0, "Timer: interrupt deasserts after clearing TER1");
}

void testInterruptController(cf_ctx* ctx) {
	cf_bus_status st = CF_BUS_OK;

	// External pin 2 (IRQ3) assertion
	cf_set_irq_pin(ctx, CF_IRQ_PIN_3, 1);
	CHECK(cf_intc_get_presented_level(ctx) == 3, "INTC: IRQ3 asserts at default level 3");
	CHECK(cf_intc_get_presented_autovector(ctx) == 0, "INTC: autovector disabled by default when AVR is 0");

	// Enable autovectoring for Level 3 via AVR (MBAR+0x04B, bit 3 = 0x08)
	cf_mbar_write(ctx, 0x04B, 1, 0x08, &st);
	CHECK(st == CF_BUS_OK, "INTC: write AVR bit 3 succeeds");
	CHECK(cf_intc_get_presented_autovector(ctx) == 1, "INTC: external pin presents autovector with AVR bit 3 set");

	// Dynamic remapping via IRQPAR (MBAR+0x006): set bit 1 to map IRQ3 to level 6
	cf_mbar_write(ctx, 0x006, 1, 0x02, &st);
	CHECK(cf_intc_get_presented_level(ctx) == 6, "INTC: IRQ3 dynamically remapped to level 6 via IRQPAR");
	// Level 6 does not autovector when AVR bit 6 is clear
	CHECK(cf_intc_get_presented_autovector(ctx) == 0, "INTC: level 6 does not autovector when AVR bit 6 is clear");

	// Set AVR bit 6 (0x40 | 0x08 = 0x48)
	cf_mbar_write(ctx, 0x04B, 1, 0x48, &st);
	CHECK(cf_intc_get_presented_autovector(ctx) == 1, "INTC: level 6 presents autovector with AVR bit 6 set");

	// Deassert pin
	cf_set_irq_pin(ctx, CF_IRQ_PIN_3, 0);
	CHECK(cf_intc_get_presented_level(ctx) == 0, "INTC: deasserting IRQ3 clears presented level");

	// Reset IRQPAR and AVR
	cf_mbar_write(ctx, 0x006, 1, 0x00, &st);
	cf_mbar_write(ctx, 0x04B, 1, 0x00, &st);
}

void testSimAndMbar(cf_ctx* ctx) {
	cf_bus_status st = CF_BUS_OK;

	// Port A read hook
	PortARecord portARec{0xFEFF, 0}; // bit 9 clear, other bits high
	cf_sim_set_port_a_hook(ctx, onPortA, &portARec);
	uint32_t padat = cf_mbar_read(ctx, 0x248, 2, &st);
	CHECK(st == CF_BUS_OK, "SIM: read PADAT completes");
	CHECK(padat == 0xFCFFu, "SIM: PADAT returns rowBits with strap bit 9 cleared (0xFEFF & ~0x0200 = 0xFCFF)");
	CHECK(portARec.count == 1, "SIM: 16-bit word read of PADAT invokes hook exactly once");

	// 8-bit reads of PADAT high and low bytes
	portARec.count = 0;
	uint32_t padatHi = cf_mbar_read(ctx, 0x248, 1, &st);
	CHECK(st == CF_BUS_OK && padatHi == 0xFCu, "SIM: read PADAT high byte (0xFC)");
	CHECK(portARec.count == 1, "SIM: 8-bit read of PADAT high byte invokes hook once");

	portARec.count = 0;
	uint32_t padatLo = cf_mbar_read(ctx, 0x249, 1, &st);
	CHECK(st == CF_BUS_OK && padatLo == 0xFFu, "SIM: read PADAT low byte (0xFF)");
	CHECK(portARec.count == 1, "SIM: 8-bit read of PADAT low byte invokes hook once");

	// Engine strap configuration
	cf_sim_set_engine_strap(ctx, 1);
	uint32_t uipcr = cf_mbar_read(ctx, 0x1D0, 1, &st);
	CHECK(st == CF_BUS_OK && (uipcr & 0x01u) == 0x01u, "SIM: engine strap set makes UIPCR bit 0 high");

	cf_sim_set_engine_strap(ctx, 0);
	uipcr = cf_mbar_read(ctx, 0x1D0, 1, &st);
	CHECK(st == CF_BUS_OK && (uipcr & 0x01u) == 0x00u, "SIM: engine strap cleared makes UIPCR bit 0 low");

	// Access size validations
	// CSAR0 accepts 2 bytes
	cf_mbar_read(ctx, 0x080, 2, &st);
	CHECK(st == CF_BUS_OK, "MBAR: 2-byte access to CSAR0 accepted");

	// CSMR0 accepts 4 bytes
	cf_mbar_read(ctx, 0x084, 4, &st);
	CHECK(st == CF_BUS_OK, "MBAR: 4-byte access to CSMR0 accepted");

	// INTC register (ICR0 at 0x04C) requires 1 byte
	cf_mbar_read(ctx, 0x04C, 1, &st);
	CHECK(st == CF_BUS_OK, "MBAR: 1-byte access to ICR0 accepted");

	cf_mbar_read(ctx, 0x04C, 2, &st);
	CHECK(st == CF_BUS_SIZE_ILLEGAL, "MBAR: 2-byte access to ICR0 rejected with CF_BUS_SIZE_ILLEGAL");

	// UART register requires 1 byte
	cf_mbar_read(ctx, 0x1C0, 2, &st);
	CHECK(st == CF_BUS_SIZE_ILLEGAL, "MBAR: 2-byte access to UART rejected with CF_BUS_SIZE_ILLEGAL");

	// Unmapped offset (>= 0x400)
	cf_mbar_read(ctx, 0x400, 1, &st);
	CHECK(st == CF_BUS_UNMAPPED, "MBAR: access at 0x400 rejected with CF_BUS_UNMAPPED");
	cf_mbar_read(ctx, 0x800, 4, &st);
	CHECK(st == CF_BUS_UNMAPPED, "MBAR: access at 0x800 rejected with CF_BUS_UNMAPPED");
}

} // namespace

int main() {
	DummyBoard board;
	cf_config cfg = {};
	cfg.isa = CF_ISA_A;
	cfg.user = &board;
	cfg.rd = dummyRead;
	cfg.wr = dummyWrite;

	cf_ctx* ctx = cf_create(&cfg);
	if (!ctx) {
		printf("FAILED: cf_create returned null\n");
		return 1;
	}

	cf_reset(ctx, 0x1000, 0x400);

	testDuart(ctx);
	testTimers(ctx);
	testInterruptController(ctx);
	testSimAndMbar(ctx);

	cf_destroy(ctx);

	printf("\nSummary: %d passed, %d failed\n", g_passCount, g_failCount);
	return (g_failCount == 0) ? 0 : 1;
}
