/* abi_stub.c - one definition, with an empty body and external linkage, of
 * every function `include/mcf5407.h` declares.
 *
 * Cases 3 and 4 of `t0_abi_header` compile and link, and linking is what
 * makes a renamed declaration a link error rather than nothing at all. `-fsyntax-only` never links, so the two header compiles
 * alone cannot catch a rename. This stub supplies a definition for every
 * name the contract declares, so the two header compiles link without the
 * real library.
 *
 * The freeze is on behaviour: every body stays empty, every return stays a
 * fixed benign value, and nothing here emulates anything. A test that needs
 * behaviour links the real library. The set of definitions is not frozen -
 * it is the contract's own published set and moves when the contract moves.
 *
 * A helper with internal linkage is allowed. A published name defined `static`
 * here would resolve nothing at the link of `t0_abi_header`, which is how such
 * a mistake reports itself.
 */

#include <stddef.h>
#include <stdint.h>

#include "coldfire.h"

int cf_runtime_init(void)
{
    return 0;
}

cf_ctx* cf_create(const cf_config* config)
{
    (void)config;
    return NULL;
}

void cf_destroy(cf_ctx* ctx)
{
    (void)ctx;
}

void cf_reset(cf_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc)
{
    (void)ctx;
    (void)initial_sp;
    (void)initial_pc;
}

uint32_t cf_exec(cf_ctx* ctx, uint32_t max_cycles)
{
    (void)ctx;
    (void)max_cycles;
    return 0u;
}

int cf_set_reg(cf_ctx* ctx, int index, uint32_t value)
{
    (void)ctx;
    (void)index;
    (void)value;
    return 0;
}

uint32_t cf_get_reg(const cf_ctx* ctx, int index)
{
    (void)ctx;
    (void)index;
    return 0u;
}

int cf_halted(const cf_ctx* ctx)
{
    (void)ctx;
    return 0;
}

int cf_faulted(const cf_ctx* ctx)
{
    (void)ctx;
    return 0;
}

void cf_set_irq(cf_ctx* ctx, int level, uint8_t vector,
                int autovector)
{
    (void)ctx;
    (void)level;
    (void)vector;
    (void)autovector;
}

size_t cf_state_size(void)
{
    return (size_t)0;
}

void cf_state_save(const cf_ctx* ctx, void* dst)
{
    (void)ctx;
    (void)dst;
}

void cf_state_load(cf_ctx* ctx, const void* src)
{
    (void)ctx;
    (void)src;
}

int cf_uart_rx_byte(cf_ctx* ctx, int channel, uint8_t byte)
{
    (void)ctx;
    (void)channel;
    (void)byte;
    return 0;
}

int cf_uart_set_tx_handler(cf_ctx* ctx, int channel, cf_uart_tx_fn fn, void* user)
{
    (void)ctx;
    (void)channel;
    (void)fn;
    (void)user;
    return 0;
}

uint8_t cf_uart_get_usr(const cf_ctx* ctx, int channel)
{
    (void)ctx;
    (void)channel;
    return (uint8_t)0;
}

void cf_timer_tick(cf_ctx* ctx, uint32_t cycles)
{
    (void)ctx;
    (void)cycles;
}

void cf_set_irq_pin(cf_ctx* ctx, int pin, int asserted)
{
    (void)ctx;
    (void)pin;
    (void)asserted;
}

int cf_intc_get_presented_level(const cf_ctx* ctx)
{
    (void)ctx;
    return 0;
}

uint8_t cf_intc_get_presented_vector(const cf_ctx* ctx)
{
    (void)ctx;
    return (uint8_t)0;
}

int cf_intc_get_presented_autovector(const cf_ctx* ctx)
{
    (void)ctx;
    return 0;
}

uint32_t cf_mbar_read(cf_ctx* ctx, uint32_t offset, int size, cf_bus_status* status)
{
    (void)ctx;
    (void)offset;
    (void)size;
    (void)status;
    return 0u;
}

void cf_mbar_write(cf_ctx* ctx, uint32_t offset, int size, uint32_t value, cf_bus_status* status)
{
    (void)ctx;
    (void)offset;
    (void)size;
    (void)value;
    (void)status;
}

void cf_sim_set_port_a_hook(cf_ctx* ctx, cf_port_a_read_fn hook, void* user)
{
    (void)ctx;
    (void)hook;
    (void)user;
}

void cf_sim_set_engine_strap(cf_ctx* ctx, int engine_strap)
{
    (void)ctx;
    (void)engine_strap;
}

