/* isp1181.h - C application binary interface for the Philips ISP1181 USB
 * device controller model.
 *
 * The Nim implementation exports these symbols with
 * `{.exportc: "<c name>", cdecl, dynlib.}` and both sides include this file.
 * The interface is strictly standardized to C11 / C++17 compatibility.
 */

#ifndef ISP1181_H
#define ISP1181_H

#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus) && __cplusplus >= 201703L
#  define ISP1181_MUST_USE [[nodiscard]]
#elif !defined(__cplusplus) && defined(__STDC_VERSION__) && \
      __STDC_VERSION__ >= 202311L
#  define ISP1181_MUST_USE [[nodiscard]]
#elif defined(__GNUC__) || defined(__clang__)
#  define ISP1181_MUST_USE __attribute__((warn_unused_result))
#else
#  define ISP1181_MUST_USE
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct isp1181_ctx isp1181_ctx;

typedef void (*isp1181_irq_fn)(void* user, int asserted);
typedef void (*isp1181_tx_fn)(void* user, int endpoint,
                              const uint8_t* data, size_t len);

#define ISP1181_BACKEND_STUB 0
#define ISP1181_BACKEND_FULL_MODEL 1

isp1181_ctx* isp1181_create(void* user, isp1181_irq_fn irq, isp1181_tx_fn tx);
void isp1181_destroy(isp1181_ctx* ctx);
uint8_t isp1181_read(isp1181_ctx* ctx, uint32_t addr);
void isp1181_write(isp1181_ctx* ctx, uint32_t addr, uint8_t value);

ISP1181_MUST_USE
int isp1181_rx(isp1181_ctx* ctx, int endpoint, const uint8_t* data, size_t len);
int isp1181_setup(isp1181_ctx* ctx, const uint8_t* data, size_t len);
int isp1181_in_token(isp1181_ctx* ctx, int endpoint);

int isp1181_set_backend(isp1181_ctx* ctx, int backend);
void isp1181_tick(isp1181_ctx* ctx, uint32_t sof_frames);

ISP1181_MUST_USE size_t isp1181_log_written(const isp1181_ctx* ctx);
ISP1181_MUST_USE size_t isp1181_log_retained(const isp1181_ctx* ctx);
ISP1181_MUST_USE size_t isp1181_log_line(const isp1181_ctx* ctx, size_t index,
                                         char* dst, size_t capacity);

ISP1181_MUST_USE size_t isp1181_config_slots(void);
ISP1181_MUST_USE int isp1181_config_slot(const isp1181_ctx* ctx, size_t slot,
                                         uint8_t* value);
ISP1181_MUST_USE int isp1181_slot_buffer(const isp1181_ctx* ctx, size_t slot,
                                         size_t* max_packet_bytes,
                                         size_t* buffer_count);
ISP1181_MUST_USE size_t isp1181_report(const isp1181_ctx* ctx, char* dst,
                                       size_t capacity);

size_t isp1181_state_size(void);
void isp1181_state_save(const isp1181_ctx* ctx, void* dst);
void isp1181_state_load(isp1181_ctx* ctx, const void* src);

#ifdef __cplusplus
}
#endif

#endif /* ISP1181_H */
