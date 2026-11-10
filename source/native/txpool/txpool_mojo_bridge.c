#include "txpool.h"
#include <stddef.h>
#include <stdint.h>

/* ABI-stable, fixed arity entrypoints for Mojo 1.2's dynamic C FFI. */
MJDBPool *mjx_postgres(const char *dsn, unsigned int capacity) {
    return mjdb_new_postgres(dsn, capacity);
}
MJDBPool *mjx_mysql(const char *host, unsigned int port, const char *user,
                    const char *password, const char *database, unsigned int capacity) {
    return mjdb_new_mysql(host, port, user, password, database, capacity);
}
int mjx_close(MJDBPool *pool) { return mjdb_close(pool); }
int mjx_acquire(MJDBPool *pool, int ms, uint64_t *token) {
    return mjdb_acquire(pool, ms, token);
}
int mjx_release(MJDBPool *pool, uint64_t token) { return mjdb_release(pool, token); }
int mjx_begin(MJDBPool *pool, uint64_t token) { return mjdb_begin(pool, token); }
int mjx_commit(MJDBPool *pool, uint64_t token) { return mjdb_commit(pool, token); }
int mjx_rollback(MJDBPool *pool, uint64_t token) { return mjdb_rollback(pool, token); }
int mjx_query0(MJDBPool *pool, uint64_t token, const char *sql, MJDBResult **r) {
    return mjdb_query(pool, token, sql, r);
}
int mjx_query1(MJDBPool *pool, uint64_t token, const char *sql, const char *a,
               MJDBResult **r) {
    const char *params[1] = {a};
    return mjdb_query_params(pool, token, sql, params, 1, r);
}
int mjx_query2(MJDBPool *pool, uint64_t token, const char *sql, const char *a,
               const char *b, MJDBResult **r) {
    const char *params[2] = {a, b};
    return mjdb_query_params(pool, token, sql, params, 2, r);
}
int mjx_query3(MJDBPool *pool, uint64_t token, const char *sql, const char *a,
               const char *b, const char *c, MJDBResult **r) {
    const char *params[3] = {a, b, c};
    return mjdb_query_params(pool, token, sql, params, 3, r);
}
void mjx_result_free(MJDBResult *r) { mjdb_result_free(r); }
size_t mjx_rows(const MJDBResult *r) { return mjdb_result_rows(r); }
size_t mjx_columns(const MJDBResult *r) { return mjdb_result_columns(r); }
uint64_t mjx_affected(const MJDBResult *r) { return mjdb_result_affected(r); }
const char *mjx_column_name(const MJDBResult *r, size_t c) { return mjdb_result_column_name(r, c); }
const char *mjx_cell(const MJDBResult *r, size_t row, size_t col) {
    return mjdb_result_cell(r, row, col);
}
int mjx_is_null(const MJDBResult *r, size_t row, size_t col) {
    return mjdb_result_is_null(r, row, col);
}
unsigned int mjx_capacity(MJDBPool *p) { return mjdb_capacity(p); }
unsigned int mjx_active(MJDBPool *p) { return mjdb_active_leases(p); }
const char *mjx_last_error(MJDBPool *p) { return mjdb_last_error(p); }
