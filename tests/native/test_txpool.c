#include "../../source/native/txpool/txpool.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  assert(mjdb_new_postgres(NULL, 1) == NULL);
  assert(mjdb_new_postgres("x", 0) == NULL);
  assert(mjdb_new_postgres("x", 17) == NULL);
  assert(mjdb_new_mysql(NULL, 3306, "u", "p", "db", 2) == NULL);
  assert(mjdb_result_rows(NULL) == 0);
  assert(mjdb_result_columns(NULL) == 0);
  assert(mjdb_result_affected(NULL) == 0);
  assert(mjdb_result_cell(NULL, 0, 0) == NULL);
  assert(mjdb_result_is_null(NULL, 0, 0) == MJDB_INVALID);
  assert(mjdb_close(NULL) == MJDB_INVALID);
  MJDBPool *p = mjdb_new_postgres("host=127.0.0.1 port=1 connect_timeout=1 dbname=none", 2);
  assert(p);
  assert(mjdb_capacity(p) == 2);
  assert(mjdb_active_leases(p) == 0);
  uint64_t token = 99;
  assert(mjdb_acquire(p, -2, &token) == MJDB_INVALID);
  assert(mjdb_acquire(p, 0, &token) == MJDB_DB_ERROR);
  assert(token == 0);
  assert(mjdb_active_leases(p) == 0);
  assert(strstr(mjdb_last_error(p), "PostgreSQL connect") != NULL);
  assert(mjdb_begin(p, 18) == MJDB_INVALID);
  assert(mjdb_release(p, 18) == MJDB_INVALID);
  assert(mjdb_query_params(p, 18, "SELECT 1", NULL, 1, NULL) == MJDB_INVALID);
  assert(mjdb_close(p) == MJDB_OK);
  puts("Mojara txpool offline ABI and error-path tests passed.");
  return 0;
}

