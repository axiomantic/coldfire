/* mcf5407.h - Compatibility alias layer forwarding to coldfire.h and isp1181.h.
 *
 * This header preserves backward compatibility for existing consumers
 * by providing inline wrappers and type aliases that forward directly to
 * the canonical ColdFire C ABI (include/coldfire.h) and USB controller
 * model (include/isp1181.h).
 */

#ifndef MCF5407_H
#define MCF5407_H

#include "coldfire.h"
#include "isp1181.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Context & status types */
typedef cf_ctx mcf5407_ctx;
typedef cf_bus_status mcf5407_bus_status;

#define MCF5407_BUS_OK           CF_BUS_OK
#define MCF5407_BUS_UNMAPPED     CF_BUS_UNMAPPED
#define MCF5407_BUS_SIZE_ILLEGAL CF_BUS_SIZE_ILLEGAL
#define MCF5407_BUS_FAULT        CF_BUS_FAULT

typedef cf_read_fn mcf5407_read_fn;
typedef cf_write_fn mcf5407_write_fn;
typedef cf_iack_fn mcf5407_iack_fn;

#define MCF5407_IRQ_NONE CF_IRQ_NONE
#define MCF5407_MUST_CHECK CF_MUST_CHECK
#define MCF5407_MUST_USE CF_MUST_USE

/* Inline forwarding layer */

static inline int mcf5407_runtime_init(void) {
	return cf_runtime_init();
}

static inline mcf5407_ctx* mcf5407_create(void* user,
                                          mcf5407_read_fn rd,
                                          mcf5407_write_fn wr,
                                          mcf5407_iack_fn iack) {
	cf_config cfg;
	cfg.isa = CF_ISA_A;
	cfg.vbr_mask = 0xFFFFFFFFu;
	cfg.user = user;
	cfg.rd = rd;
	cfg.wr = wr;
	cfg.iack = iack;
	return cf_create(&cfg);
}

static inline void mcf5407_destroy(mcf5407_ctx* ctx) {
	cf_destroy(ctx);
}

static inline void mcf5407_reset(mcf5407_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc) {
	cf_reset(ctx, initial_sp, initial_pc);
}

static inline uint32_t mcf5407_exec(mcf5407_ctx* ctx, uint32_t max_cycles) {
	return cf_exec(ctx, max_cycles);
}

static inline int mcf5407_set_reg(mcf5407_ctx* ctx, int index, uint32_t value) {
	return cf_set_reg(ctx, index, value);
}

static inline uint32_t mcf5407_get_reg(const mcf5407_ctx* ctx, int index) {
	return cf_get_reg(ctx, index);
}

static inline int mcf5407_halted(const mcf5407_ctx* ctx) {
	return cf_halted(ctx);
}

static inline int mcf5407_faulted(const mcf5407_ctx* ctx) {
	return cf_faulted(ctx);
}

static inline void mcf5407_set_irq(mcf5407_ctx* ctx, int level, uint8_t vector, int autovector) {
	cf_set_irq(ctx, level, vector, autovector);
}

static inline size_t mcf5407_state_size(void) {
	return cf_state_size();
}

static inline void mcf5407_state_save(const mcf5407_ctx* ctx, void* dst) {
	cf_state_save(ctx, dst);
}

static inline void mcf5407_state_load(mcf5407_ctx* ctx, const void* src) {
	cf_state_load(ctx, src);
}

#ifdef __cplusplus
}
#endif

#endif /* MCF5407_H */
