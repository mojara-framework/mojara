#define _POSIX_C_SOURCE 200809L
#include "../../source/native/txpool/txpool.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  const char *host = getenv("MOJARA_MYSQL_HOST");
  const char *user = getenv("MOJARA_MYSQL_USER");
  const char *pass = getenv("MOJARA_MYSQL_PASSWORD");
  const char *db = getenv("MOJARA_MYSQL_DATABASE");
  if (!host || !user || !db) { puts("MySQL integration skipped"); return 0; }
  const char *port_env = getenv("MOJARA_MYSQL_PORT");
  unsigned int port = port_env ? (unsigned int)strtoul(port_env, NULL, 10) : 3306;
  MJDBPool *p = mjdb_new_mysql(host, port, user, pass, db, 2);
  assert(p);
  uint64_t lease = 0;
  int rc = mjdb_acquire(p, 3000, &lease);
  if (rc) { fprintf(stderr, "%s\n", mjdb_last_error(p)); return 2; }
  MJDBResult *r = NULL;
  rc = mjdb_query(p, lease, "SELECT 1 AS n UNION ALL SELECT 2 AS n ORDER BY n", &r);
  assert(rc == MJDB_OK && r && mjdb_result_rows(r) == 2);
  assert(strcmp(mjdb_result_cell(r, 0, 0), "1") == 0);
  assert(strcmp(mjdb_result_cell(r, 1, 0), "2") == 0);
  mjdb_result_free(r);
  const char *params[] = {"safe-input-123"};
  rc = mjdb_query_params(p, lease, "SELECT ? AS val", params, 1, &r);
  if (rc) { fprintf(stderr, "MySQL param test failed: %s\n", mjdb_last_error(p)); return 3; }
  assert(r && mjdb_result_rows(r) == 1);
  assert(strcmp(mjdb_result_cell(r, 0, 0), params[0]) == 0);
  mjdb_result_free(r);
  assert(mjdb_begin(p, lease) == MJDB_OK);
  assert(mjdb_release(p, lease) == MJDB_OK);
  assert(mjdb_close(p) == MJDB_OK);
  puts("MySQL live multirow / prepared parameter / rollback passed.");
  return 0;
}
