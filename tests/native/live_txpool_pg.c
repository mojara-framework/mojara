#define _POSIX_C_SOURCE 200809L
#include "../../source/native/txpool/txpool.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  const char *dsn = getenv("MOJARA_TEST_POSTGRES_DSN");
  if (!dsn || !*dsn) { puts("PostgreSQL integration skipped"); return 0; }
  MJDBPool *p = mjdb_new_postgres(dsn, 2);
  assert(p);
  uint64_t lease = 0;
  int rc = mjdb_acquire(p, 3000, &lease);
  if (rc) { fprintf(stderr, "%s\n", mjdb_last_error(p)); return 2; }
  MJDBResult *r = NULL;
  rc = mjdb_query(p, lease, "SELECT 1 AS n UNION ALL SELECT 2 AS n ORDER BY n", &r);
  assert(rc == MJDB_OK && r && mjdb_result_rows(r) == 2);
  assert(strcmp(mjdb_result_column_name(r, 0), "n") == 0);
  assert(strcmp(mjdb_result_cell(r, 0, 0), "1") == 0);
  assert(strcmp(mjdb_result_cell(r, 1, 0), "2") == 0);
  mjdb_result_free(r);
  const char *params[] = {"user-input-123"};
  r = NULL;
  rc = mjdb_query_params(p, lease, "SELECT $1::text AS val", params, 1, &r);
  assert(rc == MJDB_OK && mjdb_result_rows(r) == 1);
  assert(strcmp(mjdb_result_cell(r, 0, 0), params[0]) == 0);
  mjdb_result_free(r);
  assert(mjdb_begin(p, lease) == MJDB_OK);
  assert(mjdb_query(p, lease, "SELECT 3", &r) == MJDB_OK);
  mjdb_result_free(r);
  assert(mjdb_release(p, lease) == MJDB_OK); /* rollback */
  assert(mjdb_active_leases(p) == 0);
  assert(mjdb_close(p) == MJDB_OK);
  puts("PostgreSQL live multirow / parameter / lease / rollback passed.");
  return 0;
}
