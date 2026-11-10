#ifndef MOJARA_TXPOOL_H
#define MOJARA_TXPOOL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mjdb_pool MJDBPool;
typedef struct mjdb_result MJDBResult;

enum {
  MJDB_OK = 0,
  MJDB_INVALID = -1,
  MJDB_TIMEOUT = -2,
  MJDB_DB_ERROR = -3,
  MJDB_WRONG_THREAD = -4,
  MJDB_NOT_IN_TRANSACTION = -5,
  MJDB_ALREADY_IN_TRANSACTION = -6,
  MJDB_BUSY = -7,
  MJDB_OUT_OF_MEMORY = -8,
  MJDB_RESULT_TOO_LARGE = -9
};

/* Every acquired token is tied to one thread; never pass it across threads. */
#ifdef MJDB_INTERNAL_TEST_BACKEND
MJDBPool *mjdb_new_test(unsigned int max_connections);
#endif
MJDBPool *mjdb_new_postgres(const char *dsn, unsigned int max_connections);
MJDBPool *mjdb_new_mysql(const char *host, unsigned int port, const char *user,
                        const char *password, const char *database,
                        unsigned int max_connections);
/* Only succeeds when all leases are returned. On BUSY, pool remains usable. */
int mjdb_close(MJDBPool *pool);
int mjdb_acquire(MJDBPool *pool, int timeout_ms, uint64_t *out_token);
int mjdb_release(MJDBPool *pool, uint64_t token);
int mjdb_begin(MJDBPool *pool, uint64_t token);
int mjdb_commit(MJDBPool *pool, uint64_t token);
int mjdb_rollback(MJDBPool *pool, uint64_t token);
int mjdb_query(MJDBPool *pool, uint64_t token, const char *sql, MJDBResult **out_result);
/* PostgreSQL uses $1, $2,...; MySQL uses ?, ?, ...; NULL params are SQL NULL. */
int mjdb_query_params(MJDBPool *pool, uint64_t token, const char *sql,
                      const char *const *params, unsigned int param_count,
                      MJDBResult **out_result);
void mjdb_result_free(MJDBResult *result);
size_t mjdb_result_rows(const MJDBResult *result);
size_t mjdb_result_columns(const MJDBResult *result);
uint64_t mjdb_result_affected(const MJDBResult *result);
const char *mjdb_result_column_name(const MJDBResult *result, size_t col);
/* NULL signals SQL NULL or invalid coordinates; use mjdb_result_is_null to distinguish. */
const char *mjdb_result_cell(const MJDBResult *result, size_t row, size_t col);
int mjdb_result_is_null(const MJDBResult *result, size_t row, size_t col);
unsigned int mjdb_active_leases(MJDBPool *pool);
unsigned int mjdb_capacity(MJDBPool *pool);
/* Error buffer belongs to pool and can change on another thread; copy immediately. */
const char *mjdb_last_error(MJDBPool *pool);

#ifdef __cplusplus
}
#endif
#endif
