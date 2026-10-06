/* t0_abi_header.cpp - case 4 of the registered test `t0_abi_header`.
 *
 * The C++ half of the same assertion. It makes the same address-of
 * expressions and the same per-type assertions THROUGH `extern "C"`, which
 * `include/mcf5407.h` supplies for a C++ translation unit. That linkage is
 * what makes this file link against `abi_stub.c`, a C translation unit, and
 * what makes a rename a link error here too rather than a mangled symbol
 * nobody looks for.
 *
 * The C++ build is what makes the forbidden list testable. A C++ reference
 * parameter, a namespace, a template, an overload, a C++ object or a
 * reference in the header is either a syntax error in the C build of case 3
 * or a diagnostic under `-Wall -Wextra -pedantic -Werror`.
 * Nothing here catches an exception, because nothing may throw one across
 * this boundary in either direction.
 *
 * Each pointer is `volatile`. A read of a volatile object must happen, which
 * is what forces the initialiser to be materialised and the relocation
 * against the named function to survive into the link. Without it the
 * comparisons below are `&function != NULL`, which an optimising compiler
 * folds to true: measured at `-O2`, all eighteen address-of expressions were
 * eliminated and the executable linked with no reference to any of them, so a
 * renamed declaration -- the fault cases 3 and 4 exist to catch -- linked
 * clean. The check then held only at `-O0` and reported a pass at every other
 * optimisation level.
 */

#include <cstddef>
#include <cstdint>

#include "coldfire.h"

static_assert(sizeof(cf_ctx*) == sizeof(void*),
              "cf_ctx must be declared as an opaque context type");

static_assert(sizeof(cf_bus_status) >= 1u,
              "cf_bus_status must be declared as a type");
static_assert(CF_BUS_OK == 0, "CF_BUS_OK must be 0");
static_assert(CF_BUS_UNMAPPED == 1, "CF_BUS_UNMAPPED must be 1");
static_assert(CF_BUS_SIZE_ILLEGAL == 2,
              "CF_BUS_SIZE_ILLEGAL must be 2");
static_assert(CF_BUS_FAULT == 3, "CF_BUS_FAULT must be 3");

static_assert(CF_IRQ_NONE == 0, "CF_IRQ_NONE must be 0");

static_assert(sizeof(cf_read_fn) == sizeof(void (*)()),
              "cf_read_fn must be a function-pointer type");
static_assert(sizeof(cf_write_fn) == sizeof(void (*)()),
              "cf_write_fn must be a function-pointer type");
static_assert(sizeof(cf_iack_fn) == sizeof(void (*)()),
              "cf_iack_fn must be a function-pointer type");
static_assert(sizeof(cf_uart_tx_fn) == sizeof(void (*)()),
              "cf_uart_tx_fn must be a function-pointer type");
static_assert(sizeof(cf_port_a_read_fn) == sizeof(void (*)()),
              "cf_port_a_read_fn must be a function-pointer type");

/* The peripheral enumerations and constants. */
static_assert(sizeof(cf_irq_pin) >= 1u, "cf_irq_pin must be declared as a type");
static_assert(CF_IRQ_PIN_7 == 0, "CF_IRQ_PIN_7 must be 0");
static_assert(CF_IRQ_PIN_5 == 1, "CF_IRQ_PIN_5 must be 1");
static_assert(CF_IRQ_PIN_3 == 2, "CF_IRQ_PIN_3 must be 2");
static_assert(CF_IRQ_PIN_1 == 3, "CF_IRQ_PIN_1 must be 3");
static_assert(CF_UART_CH0 == 0, "CF_UART_CH0 must be 0");
static_assert(CF_UART_CH1 == 1, "CF_UART_CH1 must be 1");

/* ------------------------------------------------ the address-of expressions
 *
 * Each pointer variable carries `extern "C"` linkage through the type it is
 * declared with, because the header declares every one of these functions
 * inside its `extern "C"` block.
 */

int main()
{
    int (*const volatile p01)() = &cf_runtime_init;
    cf_ctx* (*const volatile p02)(const cf_config*) = &cf_create;
    void (*const volatile p03)(cf_ctx*) = &cf_destroy;
    void (*const volatile p04)(cf_ctx*, uint32_t, uint32_t) = &cf_reset;
    uint32_t (*const volatile p05)(cf_ctx*, uint32_t) = &cf_exec;
    void (*const volatile p06)(cf_ctx*, int, uint8_t, int) = &cf_set_irq;
    size_t (*const volatile p07)() = &cf_state_size;
    void (*const volatile p08)(const cf_ctx*, void*) = &cf_state_save;
    void (*const volatile p09)(cf_ctx*, const void*) = &cf_state_load;
    int (*const volatile p10)(cf_ctx*, int, uint8_t) = &cf_uart_rx_byte;
    int (*const volatile p11)(cf_ctx*, int, cf_uart_tx_fn, void*) = &cf_uart_set_tx_handler;
    uint8_t (*const volatile p12)(const cf_ctx*, int) = &cf_uart_get_usr;
    void (*const volatile p13)(cf_ctx*, uint32_t) = &cf_timer_tick;
    void (*const volatile p14)(cf_ctx*, int, int) = &cf_set_irq_pin;
    int (*const volatile p15)(const cf_ctx*) = &cf_intc_get_presented_level;
    uint8_t (*const volatile p16)(const cf_ctx*) = &cf_intc_get_presented_vector;
    int (*const volatile p17)(const cf_ctx*) = &cf_intc_get_presented_autovector;
    uint32_t (*const volatile p18)(cf_ctx*, uint32_t, int, cf_bus_status*) = &cf_mbar_read;
    void (*const volatile p19)(cf_ctx*, uint32_t, int, uint32_t, cf_bus_status*) = &cf_mbar_write;
    void (*const volatile p20)(cf_ctx*, cf_port_a_read_fn, void*) = &cf_sim_set_port_a_hook;
    void (*const volatile p21)(cf_ctx*, int) = &cf_sim_set_engine_strap;

    int found = 0;
    found += (p01 != nullptr);
    found += (p02 != nullptr);
    found += (p03 != nullptr);
    found += (p04 != nullptr);
    found += (p05 != nullptr);
    found += (p06 != nullptr);
    found += (p07 != nullptr);
    found += (p08 != nullptr);
    found += (p09 != nullptr);
    found += (p10 != nullptr);
    found += (p11 != nullptr);
    found += (p12 != nullptr);
    found += (p13 != nullptr);
    found += (p14 != nullptr);
    found += (p15 != nullptr);
    found += (p16 != nullptr);
    found += (p17 != nullptr);
    found += (p18 != nullptr);
    found += (p19 != nullptr);
    found += (p20 != nullptr);
    found += (p21 != nullptr);

    if (found != 21) {
        return 1;
    }
    return 0;
}
