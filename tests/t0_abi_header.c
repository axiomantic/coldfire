/* t0_abi_header.c - case 3 of the registered test `t0_abi_header`.
 *
 * The two mechanisms are different failures on purpose:
 *
 *   - one `_Static_assert` for each declared TYPE, so a deleted or renamed
 *     type is a COMPILE error;
 *   - address-of expressions, written out below as a FIXED LIST and
 *     not derived from what the header happens to hold, so a MISSING
 *     declaration is a compile error and a RENAMED one is a LINK error
 *     against `abi_stub.c`.
 *
 * The fixed list is the point. An assertion written as "one address-of
 * expression for each declared function" takes its assertion set from the
 * artifact under test, so a header missing four declarations satisfies it.
 *
 * Each pointer also carries the EXACT declared signature, so a changed
 * parameter type or a changed return type is an initialisation diagnostic
 * under `-Werror` rather than a silent pass.
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

#include <stddef.h>
#include <stdint.h>

#include "coldfire.h"
#include "isp1181.h"
#include "mcf5407.h"

/* The opaque context types. */
_Static_assert(sizeof(cf_ctx*) == sizeof(void*),
               "cf_ctx must be declared as an opaque context type");
_Static_assert(sizeof(mcf5407_ctx*) == sizeof(void*),
               "mcf5407_ctx must be declared as an opaque context type");
_Static_assert(sizeof(isp1181_ctx*) == sizeof(void*),
               "isp1181_ctx must be declared as an opaque context type");

/* The bus status enumeration. */
_Static_assert(sizeof(cf_bus_status) >= 1u,
               "cf_bus_status must be declared as a type");
_Static_assert(CF_BUS_OK == 0, "CF_BUS_OK must be 0");
_Static_assert(CF_BUS_UNMAPPED == 1, "CF_BUS_UNMAPPED must be 1");
_Static_assert(CF_BUS_SIZE_ILLEGAL == 2,
               "CF_BUS_SIZE_ILLEGAL must be 2");
_Static_assert(CF_BUS_FAULT == 3, "CF_BUS_FAULT must be 3");
_Static_assert(CF_IRQ_NONE == 0, "CF_IRQ_NONE must be 0");

/* The function-pointer types. */
_Static_assert(sizeof(cf_read_fn) == sizeof(void (*)(void)),
               "cf_read_fn must be a function-pointer type");
_Static_assert(sizeof(cf_write_fn) == sizeof(void (*)(void)),
               "cf_write_fn must be a function-pointer type");
_Static_assert(sizeof(cf_iack_fn) == sizeof(void (*)(void)),
               "cf_iack_fn must be a function-pointer type");
_Static_assert(sizeof(isp1181_irq_fn) == sizeof(void (*)(void)),
               "isp1181_irq_fn must be a function-pointer type");
_Static_assert(sizeof(isp1181_tx_fn) == sizeof(void (*)(void)),
               "isp1181_tx_fn must be a function-pointer type");

/* ------------------------------------------------ the address-of expressions */

int main(void)
{
    int (*const volatile p01)(void) = &cf_runtime_init;
    cf_ctx* (*const volatile p02)(const cf_config*) = &cf_create;
    void (*const volatile p03)(cf_ctx*) = &cf_destroy;
    void (*const volatile p04)(cf_ctx*, uint32_t, uint32_t) = &cf_reset;
    uint32_t (*const volatile p05)(cf_ctx*, uint32_t) = &cf_exec;
    void (*const volatile p06)(cf_ctx*, int, uint8_t, int) = &cf_set_irq;
    size_t (*const volatile p07)(void) = &cf_state_size;
    void (*const volatile p08)(const cf_ctx*, void*) = &cf_state_save;
    void (*const volatile p09)(cf_ctx*, const void*) = &cf_state_load;

    isp1181_ctx* (*const volatile p10)(void*, isp1181_irq_fn,
                              isp1181_tx_fn) = &isp1181_create;
    void (*const volatile p11)(isp1181_ctx*) = &isp1181_destroy;
    uint8_t (*const volatile p12)(isp1181_ctx*, uint32_t) = &isp1181_read;
    void (*const volatile p13)(isp1181_ctx*, uint32_t, uint8_t) = &isp1181_write;
    int (*const volatile p14)(isp1181_ctx*, int, const uint8_t*,
                     size_t) = &isp1181_rx;
    void (*const volatile p15)(isp1181_ctx*, uint32_t) = &isp1181_tick;
    size_t (*const volatile p16)(void) = &isp1181_state_size;
    void (*const volatile p17)(const isp1181_ctx*, void*) = &isp1181_state_save;
    void (*const volatile p18)(isp1181_ctx*, const void*) = &isp1181_state_load;

    /* Every one is counted, so that no declaration can be
     * dropped from the list above without changing the result. The
     * comparison is over the VARIABLES and not over the function names,
     * because the address of a function is never null and a compiler says
     * so under `-Wall`. */
    int found = 0;
    found += (p01 != NULL);
    found += (p02 != NULL);
    found += (p03 != NULL);
    found += (p04 != NULL);
    found += (p05 != NULL);
    found += (p06 != NULL);
    found += (p07 != NULL);
    found += (p08 != NULL);
    found += (p09 != NULL);
    found += (p10 != NULL);
    found += (p11 != NULL);
    found += (p12 != NULL);
    found += (p13 != NULL);
    found += (p14 != NULL);
    found += (p15 != NULL);
    found += (p16 != NULL);
    found += (p17 != NULL);
    found += (p18 != NULL);

    if (found != 18) {
        return 1;
    }
    return 0;
}
