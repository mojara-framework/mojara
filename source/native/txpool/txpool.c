#define _POSIX_C_SOURCE 200809L
#include "txpool.h"
#include <libpq-fe.h>
#include <mysql.h>
#include <errmsg.h>
#include <pthread.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <stdbool.h>

#define MJDB_MAX_CONNECTIONS 16
#define MJDB_MAX_PARAMS 256
#define MJDB_MAX_RESULT_ROWS 100000
#define MJDB_MAX_RESULT_BYTES (64u * 1024u * 1024u)

typedef struct {
  uint64_t token;
  pthread_t owner;
  int leased, in_transaction, broken;
  PGconn *pg;
  MYSQL *my;
} Slot;

struct mjdb_pool {
  int driver;
  unsigned int max;
  Slot *slots;
  char *dsn, *host, *user, *password, *database;
  unsigned int port;
  uint64_t next_token;
  pthread_mutex_t lock;
  pthread_cond_t available;
  char last_error[512];
};

struct mjdb_result {
  size_t rows, columns;
  uint64_t affected;
  char **names;
  char **cells;
};

static void set_error(MJDBPool *p, const char *fmt, ...) {
  va_list ap;
  pthread_mutex_lock(&p->lock);
  va_start(ap, fmt);
  vsnprintf(p->last_error, sizeof(p->last_error), fmt, ap);
  va_end(ap);
  pthread_mutex_unlock(&p->lock);
}

static MJDBPool *create_pool(int driver, unsigned int max) {
  if (max < 1 || max > MJDB_MAX_CONNECTIONS) return NULL;
  MJDBPool *p = calloc(1, sizeof(*p));
  if (!p) return NULL;
  p->slots = calloc(max, sizeof(*p->slots));
  if (!p->slots) { free(p); return NULL; }
  p->driver = driver; p->max = max;
  pthread_mutex_init(&p->lock, NULL);
  pthread_cond_init(&p->available, NULL);
  snprintf(p->last_error, sizeof(p->last_error), "no error");
  return p;
}

MJDBPool *mjdb_new_postgres(const char *dsn, unsigned int max) {
  if (!dsn || !*dsn) return NULL;
  MJDBPool *p = create_pool(1, max);
  if (!p) return NULL;
  p->dsn = strdup(dsn);
  if (!p->dsn) { mjdb_close(p); return NULL; }
  return p;
}

MJDBPool *mjdb_new_mysql(const char *host, unsigned int port, const char *user,
                         const char *password, const char *database, unsigned int max) {
  if (!host || !user || !database || !*database) return NULL;
  MJDBPool *p = create_pool(2, max);
  if (!p) return NULL;
  p->host = strdup(host); p->user = strdup(user);
  p->password = strdup(password ? password : ""); p->database = strdup(database);
  p->port = port ? port : 3306;
  if (!p->host || !p->user || !p->password || !p->database) { mjdb_close(p); return NULL; }
  return p;
}

#ifdef MJDB_INTERNAL_TEST_BACKEND
MJDBPool *mjdb_new_test(unsigned int max) { return create_pool(3, max); }
#endif

static void disconnect_slot(Slot *s) {
  if (s->pg) { PQfinish(s->pg); s->pg = NULL; }
  if (s->my) { mysql_close(s->my); s->my = NULL; }
  s->broken = 0;
}

int mjdb_close(MJDBPool *p) {
  if (!p) return MJDB_INVALID;
  pthread_mutex_lock(&p->lock);
  for (unsigned int i = 0; i < p->max; i++) {
    if (p->slots[i].leased) { pthread_mutex_unlock(&p->lock); return MJDB_BUSY; }
  }
  for (unsigned int i = 0; i < p->max; i++) disconnect_slot(&p->slots[i]);
  pthread_mutex_unlock(&p->lock);
  pthread_cond_destroy(&p->available);
  pthread_mutex_destroy(&p->lock);
  free(p->slots); free(p->dsn); free(p->host); free(p->user);
  if (p->password) memset(p->password, 0, strlen(p->password));
  free(p->password); free(p->database); free(p);
  return MJDB_OK;
}

static int connect_slot(MJDBPool *p, Slot *s) {
#ifdef MJDB_INTERNAL_TEST_BACKEND
  if (p->driver == 3) return MJDB_OK;
#endif
  if (s->broken) disconnect_slot(s);
  if (p->driver == 1) {
    if (s->pg && PQstatus(s->pg) == CONNECTION_OK) return MJDB_OK;
    disconnect_slot(s);
    s->pg = PQconnectdb(p->dsn);
    if (!s->pg || PQstatus(s->pg) != CONNECTION_OK) {
      set_error(p, "PostgreSQL connect: %s", s->pg ? PQerrorMessage(s->pg) : "out of memory");
      disconnect_slot(s);
      return MJDB_DB_ERROR;
    }
  } else {
    if (s->my && mysql_ping(s->my) == 0) return MJDB_OK;
    disconnect_slot(s);
    s->my = mysql_init(NULL);
    if (!s->my) { set_error(p, "MySQL init failed"); return MJDB_DB_ERROR; }
    unsigned int timeout = 5;
    mysql_options(s->my, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    bool reconnect = false; /* never silently reconnect inside a transaction */
    mysql_options(s->my, MYSQL_OPT_RECONNECT, &reconnect);
    if (!mysql_real_connect(s->my, p->host, p->user, p->password,
                            p->database, p->port, NULL, 0)) {
      set_error(p, "MySQL connect: %s", mysql_error(s->my));
      disconnect_slot(s);
      return MJDB_DB_ERROR;
    }
  }
  return MJDB_OK;
}

static void deadline_after(struct timespec *out, int timeout_ms) {
  clock_gettime(CLOCK_REALTIME, out);
  out->tv_sec += timeout_ms / 1000;
  out->tv_nsec += (long)(timeout_ms % 1000) * 1000000;
  if (out->tv_nsec >= 1000000000L) { out->tv_sec++; out->tv_nsec -= 1000000000L; }
}

int mjdb_acquire(MJDBPool *p, int timeout_ms, uint64_t *out_token) {
  if (!p || !out_token || timeout_ms < -1) return MJDB_INVALID;
  *out_token = 0;
  struct timespec deadline = {0};
  if (timeout_ms > 0) deadline_after(&deadline, timeout_ms);
  pthread_mutex_lock(&p->lock);
  Slot *s = NULL;
  for (;;) {
    for (unsigned int i = 0; i < p->max; i++) {
      if (!p->slots[i].leased) { s = &p->slots[i]; break; }
    }
    if (s) break;
    if (timeout_ms == 0) { pthread_mutex_unlock(&p->lock); return MJDB_TIMEOUT; }
    int rc = timeout_ms < 0
      ? pthread_cond_wait(&p->available, &p->lock)
      : pthread_cond_timedwait(&p->available, &p->lock, &deadline);
    if (rc == ETIMEDOUT) { pthread_mutex_unlock(&p->lock); return MJDB_TIMEOUT; }
    if (rc) { pthread_mutex_unlock(&p->lock); return MJDB_DB_ERROR; }
  }
  s->leased = 1;
  s->owner = pthread_self();
  s->in_transaction = 0;
  s->token = ++p->next_token;
  if (s->token == 0) s->token = ++p->next_token;
  uint64_t token = s->token;
  pthread_mutex_unlock(&p->lock);
  int rc = connect_slot(p, s);
  if (rc != MJDB_OK) {
    pthread_mutex_lock(&p->lock);
    s->leased = 0; s->token = 0;
    pthread_cond_signal(&p->available);
    pthread_mutex_unlock(&p->lock);
    return rc;
  }
  *out_token = token;
  return MJDB_OK;
}

static int find_owned(MJDBPool *p, uint64_t token, Slot **out) {
  if (!p || !token) return MJDB_INVALID;
  pthread_mutex_lock(&p->lock);
  for (unsigned int i = 0; i < p->max; i++) {
    Slot *s = &p->slots[i];
    if (s->leased && s->token == token) {
      int ok = pthread_equal(s->owner, pthread_self());
      pthread_mutex_unlock(&p->lock);
      if (!ok) return MJDB_WRONG_THREAD;
      *out = s;
      return MJDB_OK;
    }
  }
  pthread_mutex_unlock(&p->lock);
  return MJDB_INVALID;
}

static int exec_sql(MJDBPool *p, Slot *s, const char *sql) {
#ifdef MJDB_INTERNAL_TEST_BACKEND
  if (p->driver == 3) return MJDB_OK;
#endif
  if (p->driver == 1) {
    PGresult *r = PQexec(s->pg, sql);
    if (!r) {
      set_error(p, "PostgreSQL command: %s", PQerrorMessage(s->pg)); s->broken = 1;
      return MJDB_DB_ERROR;
    }
    ExecStatusType t = PQresultStatus(r);
    int ok = t == PGRES_COMMAND_OK || t == PGRES_TUPLES_OK;
    if (!ok) set_error(p, "PostgreSQL command: %s", PQresultErrorMessage(r));
    PQclear(r);
    return ok ? MJDB_OK : MJDB_DB_ERROR;
  }
  if (mysql_real_query(s->my, sql, (unsigned long)strlen(sql))) {
    set_error(p, "MySQL command: %s", mysql_error(s->my));
    if (mysql_errno(s->my) == CR_SERVER_GONE_ERROR || mysql_errno(s->my) == CR_SERVER_LOST) s->broken = 1;
    return MJDB_DB_ERROR;
  }
  MYSQL_RES *res = mysql_store_result(s->my);
  if (res) mysql_free_result(res);
  else if (mysql_field_count(s->my) != 0) { set_error(p, "MySQL fetch: %s", mysql_error(s->my)); return MJDB_DB_ERROR; }
  return MJDB_OK;
}

int mjdb_begin(MJDBPool *p, uint64_t token) {
  Slot *s; int rc = find_owned(p, token, &s);
  if (rc) return rc;
  if (s->in_transaction) return MJDB_ALREADY_IN_TRANSACTION;
  rc = exec_sql(p, s, "BEGIN");
  if (!rc) s->in_transaction = 1;
  return rc;
}

int mjdb_commit(MJDBPool *p, uint64_t token) {
  Slot *s; int rc = find_owned(p, token, &s);
  if (rc) return rc;
  if (!s->in_transaction) return MJDB_NOT_IN_TRANSACTION;
  rc = exec_sql(p, s, "COMMIT");
  if (!rc) s->in_transaction = 0;
  else s->broken = 1; /* uncertain commit outcome; do not reuse */
  return rc;
}

int mjdb_rollback(MJDBPool *p, uint64_t token) {
  Slot *s; int rc = find_owned(p, token, &s);
  if (rc) return rc;
  if (!s->in_transaction) return MJDB_NOT_IN_TRANSACTION;
  rc = exec_sql(p, s, "ROLLBACK");
  if (!rc) s->in_transaction = 0;
  else s->broken = 1;
  return rc;
}

int mjdb_release(MJDBPool *p, uint64_t token) {
  Slot *s; int rc = find_owned(p, token, &s);
  if (rc) return rc;
  int outcome = MJDB_OK;
  if (s->in_transaction) {
    outcome = exec_sql(p, s, "ROLLBACK");
    s->in_transaction = 0;
    if (outcome != MJDB_OK) s->broken = 1;
  }
  if (s->broken) disconnect_slot(s);
  pthread_mutex_lock(&p->lock);
  s->token = 0; s->leased = 0;
  pthread_cond_signal(&p->available);
  pthread_mutex_unlock(&p->lock);
  return outcome;
}

void mjdb_result_free(MJDBResult *r) {
  if (!r) return;
  if (r->names) {
    for (size_t c = 0; c < r->columns; c++) free(r->names[c]);
  }
  if (r->cells) {
    for (size_t i = 0; i < r->rows * r->columns; i++) free(r->cells[i]);
  }
  free(r->names); free(r->cells); free(r);
}

static MJDBResult *alloc_result(size_t rows, size_t cols) {
  if (rows > MJDB_MAX_RESULT_ROWS || (cols && rows > SIZE_MAX / cols)) return NULL;
  MJDBResult *r = calloc(1, sizeof(*r));
  if (!r) return NULL;
  r->rows = rows; r->columns = cols;
  r->names = calloc(cols ? cols : 1, sizeof(char *));
  r->cells = calloc(rows && cols ? rows * cols : 1, sizeof(char *));
  if (!r->names || !r->cells) { mjdb_result_free(r); return NULL; }
  return r;
}

static MJDBResult *copy_pg(PGresult *raw) {
  size_t rows = (size_t)PQntuples(raw), cols = (size_t)PQnfields(raw);
  MJDBResult *r = alloc_result(rows, cols);
  if (!r) return NULL;
  const char *affected = PQcmdTuples(raw);
  if (affected && *affected) r->affected = strtoull(affected, NULL, 10);
  for (size_t c = 0; c < cols; c++) {
    r->names[c] = strdup(PQfname(raw, (int)c));
    if (!r->names[c]) { mjdb_result_free(r); return NULL; }
  }
  size_t used_bytes = 0;
  for (size_t row = 0; row < rows; row++) for (size_t c = 0; c < cols; c++) {
    if (PQgetisnull(raw, (int)row, (int)c)) continue;
    int len = PQgetlength(raw, (int)row, (int)c);
    if (len < 0 || (size_t)len > MJDB_MAX_RESULT_BYTES - used_bytes) {
      mjdb_result_free(r); return NULL;
    }
    used_bytes += (size_t)len;
    r->cells[row * cols + c] = strndup(PQgetvalue(raw, (int)row, (int)c), (size_t)len);
    if (!r->cells[row * cols + c]) { mjdb_result_free(r); return NULL; }
  }
  return r;
}

static MJDBResult *copy_mysql(MYSQL_RES *raw, uint64_t affected) {
  size_t rows = (size_t)mysql_num_rows(raw), cols = (size_t)mysql_num_fields(raw);
  MJDBResult *r = alloc_result(rows, cols);
  if (!r) return NULL;
  r->affected = affected;
  MYSQL_FIELD *fields = mysql_fetch_fields(raw);
  for (size_t c = 0; c < cols; c++) {
    r->names[c] = strdup(fields[c].name);
    if (!r->names[c]) { mjdb_result_free(r); return NULL; }
  }
  size_t used_bytes = 0;
  for (size_t row = 0; row < rows; row++) {
    MYSQL_ROW values = mysql_fetch_row(raw);
    unsigned long *lens = mysql_fetch_lengths(raw);
    if (!values || !lens) { mjdb_result_free(r); return NULL; }
    for (size_t c = 0; c < cols; c++) {
      if (!values[c]) continue;
      if (lens[c] > MJDB_MAX_RESULT_BYTES - used_bytes) { mjdb_result_free(r); return NULL; }
      used_bytes += lens[c];
      r->cells[row * cols + c] = strndup(values[c], lens[c]);
      if (!r->cells[row * cols + c]) { mjdb_result_free(r); return NULL; }
    }
  }
  return r;
}

static int run_query(MJDBPool *p, Slot *s, const char *sql,
                     const char *const *params, unsigned int count, MJDBResult **out) {
  *out = NULL;
  if (p->driver == 1) {
    PGresult *raw = PQexecParams(s->pg, sql, (int)count, NULL, params, NULL, NULL, 0);
    if (!raw) {
      set_error(p, "PostgreSQL query: %s", PQerrorMessage(s->pg)); s->broken = 1;
      return MJDB_DB_ERROR;
    }
    ExecStatusType status = PQresultStatus(raw);
    if (status != PGRES_TUPLES_OK && status != PGRES_COMMAND_OK) {
      set_error(p, "PostgreSQL query: %s", PQresultErrorMessage(raw));
      PQclear(raw); return MJDB_DB_ERROR;
    }
    MJDBResult *r = copy_pg(raw);
    PQclear(raw);
    if (!r) return MJDB_OUT_OF_MEMORY;
    *out = r; return MJDB_OK;
  }
  if (count == 0) {
    if (mysql_real_query(s->my, sql, (unsigned long)strlen(sql))) {
      set_error(p, "MySQL query: %s", mysql_error(s->my));
      if (mysql_errno(s->my) == CR_SERVER_GONE_ERROR || mysql_errno(s->my) == CR_SERVER_LOST) s->broken = 1;
      return MJDB_DB_ERROR;
    }
    my_ulonglong affected = mysql_affected_rows(s->my);
    MYSQL_RES *raw = mysql_store_result(s->my);
    if (!raw) {
      if (mysql_field_count(s->my)) { set_error(p, "MySQL result: %s", mysql_error(s->my)); return MJDB_DB_ERROR; }
      MJDBResult *r = alloc_result(0, 0);
      if (!r) return MJDB_OUT_OF_MEMORY;
      r->affected = affected == (my_ulonglong)-1 ? 0 : affected;
      *out = r; return MJDB_OK;
    }
    MJDBResult *r = copy_mysql(raw, affected == (my_ulonglong)-1 ? 0 : affected);
    mysql_free_result(raw);
    if (!r) return MJDB_OUT_OF_MEMORY;
    *out = r; return MJDB_OK;
  }
  MYSQL_STMT *st = mysql_stmt_init(s->my);
  if (!st) { set_error(p, "MySQL statement allocation failed"); return MJDB_DB_ERROR; }
  int rc = MJDB_DB_ERROR;
  MYSQL_BIND *bind = NULL;
  MYSQL_RES *meta = NULL;
  MYSQL_BIND *outbind = NULL;
  unsigned long *lengths = NULL;
  unsigned char *null_flags = NULL;
  unsigned char *err_flags = NULL;
  MJDBResult *r = NULL;
  if (mysql_stmt_prepare(st, sql, (unsigned long)strlen(sql))) {
    set_error(p, "MySQL prepare: %s", mysql_stmt_error(st)); goto cleanup;
  }
  if (mysql_stmt_param_count(st) != count) {
    set_error(p, "MySQL parameter count mismatch"); rc = MJDB_INVALID; goto cleanup;
  }
  bind = calloc(count, sizeof(*bind));
  if (!bind) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
  for (unsigned int i = 0; i < count; i++) {
    bind[i].buffer_type = MYSQL_TYPE_STRING;
    bind[i].buffer = (void *)(params && params[i] ? params[i] : NULL);
    bind[i].buffer_length = params && params[i] ? (unsigned long)strlen(params[i]) : 0;
    /* A NULL buffer is treated as SQL NULL by mysql_stmt_bind_param. */
    if (!params || !params[i]) bind[i].buffer_type = MYSQL_TYPE_NULL;
  }
  if (mysql_stmt_bind_param(st, bind) || mysql_stmt_execute(st)) {
    set_error(p, "MySQL execute: %s", mysql_stmt_error(st)); goto cleanup;
  }
  meta = mysql_stmt_result_metadata(st);
  if (!meta) {
    if (mysql_stmt_field_count(st) != 0) { set_error(p, "MySQL metadata: %s", mysql_stmt_error(st)); goto cleanup; }
    r = alloc_result(0, 0);
    if (!r) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
    my_ulonglong affected = mysql_stmt_affected_rows(st);
    r->affected = affected == (my_ulonglong)-1 ? 0 : affected;
    rc = MJDB_OK; goto cleanup;
  }
  if (mysql_stmt_store_result(st)) { set_error(p, "MySQL store: %s", mysql_stmt_error(st)); goto cleanup; }
  size_t cols = (size_t)mysql_num_fields(meta), rows = (size_t)mysql_stmt_num_rows(st);
  if (cols > UINT_MAX) { rc = MJDB_INVALID; goto cleanup; }
  r = alloc_result(rows, cols);
  if (!r) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
  MYSQL_FIELD *fields = mysql_fetch_fields(meta);
  for (size_t c = 0; c < cols; c++) {
    r->names[c] = strdup(fields[c].name);
    if (!r->names[c]) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
  }
  outbind = calloc(cols, sizeof(*outbind));
  lengths = calloc(cols, sizeof(*lengths));
  null_flags = calloc(cols, 1); err_flags = calloc(cols, 1);
  if (!outbind || !lengths || !null_flags || !err_flags) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
  for (size_t c = 0; c < cols; c++) {
    outbind[c].buffer_type = MYSQL_TYPE_STRING;
    outbind[c].buffer = NULL;
    outbind[c].buffer_length = 0;
    outbind[c].length = &lengths[c];
    outbind[c].is_null = (void *)&null_flags[c];
    outbind[c].error = (void *)&err_flags[c];
  }
  if (mysql_stmt_bind_result(st, outbind)) { set_error(p, "MySQL bind result: %s", mysql_stmt_error(st)); goto cleanup; }
  size_t used_bytes = 0;
  for (size_t row = 0; row < rows; row++) {
    int status = mysql_stmt_fetch(st);
    if (status != 0 && status != MYSQL_DATA_TRUNCATED) {
      set_error(p, "MySQL fetch: %s", mysql_stmt_error(st)); goto cleanup;
    }
    for (size_t c = 0; c < cols; c++) {
      if (null_flags[c]) continue;
      if (lengths[c] == ULONG_MAX || lengths[c] >= SIZE_MAX) { rc = MJDB_INVALID; goto cleanup; }
      size_t n = (size_t)lengths[c];
      if (n > MJDB_MAX_RESULT_BYTES - used_bytes) { rc = MJDB_RESULT_TOO_LARGE; goto cleanup; }
      used_bytes += n;
      char *cell = malloc(n + 1);
      if (!cell) { rc = MJDB_OUT_OF_MEMORY; goto cleanup; }
      MYSQL_BIND one = {0};
      one.buffer_type = MYSQL_TYPE_STRING;
      one.buffer = cell;
      one.buffer_length = (unsigned long)(n + 1);
      if (mysql_stmt_fetch_column(st, &one, (unsigned int)c, 0)) {
        free(cell); set_error(p, "MySQL fetch column: %s", mysql_stmt_error(st)); goto cleanup;
      }
      cell[n] = '\0';
      r->cells[row * cols + c] = cell;
    }
  }
  rc = MJDB_OK;
cleanup:
  if (meta) mysql_free_result(meta);
  free(bind); free(outbind); free(lengths); free(null_flags); free(err_flags);
  mysql_stmt_close(st);
  if (rc == MJDB_OK) *out = r;
  else mjdb_result_free(r);
  return rc;
}

int mjdb_query_params(MJDBPool *p, uint64_t token, const char *sql,
                      const char *const *params, unsigned int count, MJDBResult **out) {
  if (!p || !sql || !out || count > MJDB_MAX_PARAMS || (count && !params)) return MJDB_INVALID;
  *out = NULL;
  Slot *s; int rc = find_owned(p, token, &s);
  if (rc) return rc;
  return run_query(p, s, sql, params, count, out);
}

int mjdb_query(MJDBPool *p, uint64_t token, const char *sql, MJDBResult **out) {
  return mjdb_query_params(p, token, sql, NULL, 0, out);
}

size_t mjdb_result_rows(const MJDBResult *r) { return r ? r->rows : 0; }
size_t mjdb_result_columns(const MJDBResult *r) { return r ? r->columns : 0; }
uint64_t mjdb_result_affected(const MJDBResult *r) { return r ? r->affected : 0; }
const char *mjdb_result_column_name(const MJDBResult *r, size_t c) {
  return r && c < r->columns ? r->names[c] : NULL;
}
const char *mjdb_result_cell(const MJDBResult *r, size_t row, size_t col) {
  return r && row < r->rows && col < r->columns ? r->cells[row * r->columns + col] : NULL;
}
int mjdb_result_is_null(const MJDBResult *r, size_t row, size_t col) {
  if (!r || row >= r->rows || col >= r->columns) return MJDB_INVALID;
  return r->cells[row * r->columns + col] == NULL ? 1 : 0;
}
unsigned int mjdb_active_leases(MJDBPool *p) {
  if (!p) return 0;
  unsigned int n = 0;
  pthread_mutex_lock(&p->lock);
  for (unsigned int i = 0; i < p->max; i++) if (p->slots[i].leased) n++;
  pthread_mutex_unlock(&p->lock);
  return n;
}
unsigned int mjdb_capacity(MJDBPool *p) { return p ? p->max : 0; }
const char *mjdb_last_error(MJDBPool *p) {
  if (!p) return "invalid pool";
  static _Thread_local char snapshot[512];
  pthread_mutex_lock(&p->lock);
  memcpy(snapshot, p->last_error, sizeof(snapshot));
  pthread_mutex_unlock(&p->lock);
  return snapshot;
}
