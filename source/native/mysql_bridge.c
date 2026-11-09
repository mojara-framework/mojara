/* Mojara's small, auditable native adapter for MySQL/MariaDB prepared statements.
 * Linked to system MySQL libmysqlclient. All externally supplied data is bound, never
 * interpolated into SQL. No errors, credentials, or SQL contents are exported.
 * libmysqlclient is a separate dynamic dependency.
 */
#include <mysql.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef __typeof__(*(((MYSQL_BIND *)0)->is_null)) mj_mysql_bind_bool;


/* Per-thread, non-sensitive diagnostics for failed prepared statements. */
static _Thread_local int mj_last_stage = 0;
static _Thread_local int mj_last_code = 0;
static _Thread_local char mj_last_detail[160];
const char *mj_mysql_failure_detail(void) { return mj_last_detail; }
int mj_mysql_failure_stage(void) { return mj_last_stage; }
int mj_mysql_failure_code(void) { return mj_last_code; }

#define MJ_MAX_COLS 256
#define MJ_MAX_ROWS 100000
#define MJ_MAX_PARAM 256
#define MJ_MAX_CELL (16UL * 1024UL * 1024UL)
#define MJ_MAX_RESULT_BYTES (64UL * 1024UL * 1024UL)
#define MJ_MAX_RESULT_CELLS 500000UL

typedef struct {
    size_t rows, cols;
    char **columns;
    char **cells;
    unsigned char *nulls;
} mj_mysql_result;

static char *mj_dup(const char *p, size_t size) {
    if (!p || size > MJ_MAX_CELL || size == SIZE_MAX) return NULL;
    char *q = (char *)malloc(size + 1);
    if (!q) return NULL;
    memcpy(q, p, size);
    q[size] = '\0';
    return q;
}

void mj_mysql_free(mj_mysql_result *r) {
    if (!r) return;
    if (r->columns) {
        for (size_t c = 0; c < r->cols; ++c) free(r->columns[c]);
    }
    if (r->cells) {
        for (size_t n = 0; n < r->rows * r->cols; ++n) free(r->cells[n]);
    }
    free(r->columns);
    free(r->cells);
    free(r->nulls);
    free(r);
}

MYSQL *mj_mysql_open(const char *host, unsigned port, const char *user,
                     const char *password, const char *database) {
    if (!host || !user || !password || !database) return NULL;
    MYSQL *db = mysql_init(NULL);
    if (!db) return NULL;
    unsigned int timeout = 5;
    mysql_options(db, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    if (!mysql_real_connect(db, host, user, password, database, port, NULL, 0)) {
        mysql_close(db);
        return NULL;
    }
    if (mysql_set_character_set(db, "utf8mb4") != 0) {
        mysql_close(db);
        return NULL;
    }
    return db;
}

void mj_mysql_close(MYSQL *db) { if (db) mysql_close(db); }
/* Session-wide read-only transaction mode. This is trusted constant SQL,
 * deliberately sent via mysql_query because SET TRANSACTION is not safely
 * portable across all MySQL prepared-statement dialects. */
int mj_mysql_enable_readonly(MYSQL *db) {
    if (!db) return 0;
    return mysql_query(db, "SET SESSION TRANSACTION READ ONLY") == 0;
}
/* Transaction control uses the native API, not prepared SQL: START TRANSACTION
 * is not preparable across all MySQL server versions. Caller owns nesting.
 * action 1 = begin, 2 = commit, 3 = rollback. Returns 1 on success.
 */
int mj_mysql_tx(MYSQL *db, int action) {
    if (!db) return 0;
    if (action == 1) return mysql_autocommit(db, 0) == 0;
    if (action == 2) {
        if (mysql_commit(db) != 0) return 0;
        return mysql_autocommit(db, 1) == 0;
    }
    if (action == 3) {
        if (mysql_rollback(db) != 0) return 0;
        return mysql_autocommit(db, 1) == 0;
    }
    return 0;
}


/* Returns a detached result, including for DDL/DML (0 rows and columns).
 * On failure returns NULL. No error message contains credentials or SQL.
 * Only string-valued, non-NULL input parameters are accepted by this ABI.
 */
mj_mysql_result *mj_mysql_query(MYSQL *db, const char *sql,
                                const char *const *params, int count) {
    if (!db || !sql || count < 0 || count > MJ_MAX_PARAM) return NULL;
    mj_last_stage = 0;
    mj_last_code = 0;
    mj_last_detail[0] = '\0';
    size_t sql_len = strlen(sql);
    if (!sql_len || sql_len > 1048576UL) return NULL;
    MYSQL_STMT *st = mysql_stmt_init(db);
    if (!st) return NULL;
    mj_mysql_result *r = NULL;
    MYSQL_RES *meta = NULL;
    MYSQL_BIND *input = NULL;
    /* Own parameter bytes in this C invocation until mysql_stmt_execute ends. */
    char **parameter_copies = NULL;
    unsigned long *input_lengths = NULL;
    MYSQL_BIND *output = NULL;
    unsigned long *lengths = NULL;
    mj_mysql_bind_bool *is_null = NULL;
    /* A live output buffer is necessary even when actual values are read
     * subsequently with mysql_stmt_fetch_column().  A NULL/zero-length
     * result binding is not portable across Connector/C versions. */
    unsigned char *mj_mysql_probe_buffers = NULL;
    mj_mysql_bind_bool *output_truncated = NULL;
    int ok = 0;
    int stage = 1;

    stage = 2;
    if (mysql_stmt_prepare(st, sql, (unsigned long)sql_len) != 0) goto done;
    stage = 3;
    if (mysql_stmt_param_count(st) != (unsigned long)count) goto done;
    if (count) {
        if (!params) goto done;
        parameter_copies = (char **)calloc((size_t)count, sizeof(*parameter_copies));
        if (!parameter_copies) goto done;
        input = (MYSQL_BIND *)calloc((size_t)count, sizeof(*input));
        input_lengths = (unsigned long *)calloc((size_t)count, sizeof(*input_lengths));
        if (!input || !input_lengths) goto done;
        for (int i = 0; i < count; ++i) {
            if (!params[i]) goto done;
            size_t len = strlen(params[i]);
            if (len > MJ_MAX_CELL) goto done;
            parameter_copies[i] = mj_dup(params[i], len);
            if (!parameter_copies[i]) goto done;
            input_lengths[i] = (unsigned long)len;
            input[i].buffer_type = MYSQL_TYPE_STRING;
            input[i].buffer = parameter_copies[i];
            input[i].buffer_length = (unsigned long)len;
            input[i].length = &input_lengths[i];
        }
        stage = 4;
        if (mysql_stmt_bind_param(st, input) != 0) goto done;
    }
    stage = 5;
    if (mysql_stmt_execute(st) != 0) goto done;
    r = (mj_mysql_result *)calloc(1, sizeof(*r));
    if (!r) goto done;
    stage = 6;
    meta = mysql_stmt_result_metadata(st);
    if (!meta) {
        if (mysql_stmt_field_count(st) != 0) goto done;
        ok = 1;
        goto done;
    }
    r->cols = mysql_num_fields(meta);
    if (!r->cols || r->cols > MJ_MAX_COLS) goto done;
    r->columns = (char **)calloc(r->cols, sizeof(char *));
    output = (MYSQL_BIND *)calloc(r->cols, sizeof(*output));
    lengths = (unsigned long *)calloc(r->cols, sizeof(*lengths));
    is_null = (mj_mysql_bind_bool *)calloc(r->cols, sizeof(*is_null));
    mj_mysql_probe_buffers = (unsigned char *)calloc(r->cols, sizeof(*mj_mysql_probe_buffers));
    output_truncated = (mj_mysql_bind_bool *)calloc(r->cols, sizeof(*output_truncated));
    if (!r->columns || !output || !lengths || !is_null ||
        !mj_mysql_probe_buffers || !output_truncated) goto done;
    MYSQL_FIELD *fields = mysql_fetch_fields(meta);
    size_t used = 0;
    for (size_t c = 0; c < r->cols; ++c) {
        /* A binary column may not contain valid UTF-8; reject binary data
         * until byte-array results are explicitly supported in Mojo. */
        if (fields[c].charsetnr == 63 &&
            (fields[c].type == MYSQL_TYPE_STRING ||
             fields[c].type == MYSQL_TYPE_VAR_STRING ||
             fields[c].type == MYSQL_TYPE_VARCHAR ||
             fields[c].type == MYSQL_TYPE_TINY_BLOB ||
             fields[c].type == MYSQL_TYPE_BLOB ||
             fields[c].type == MYSQL_TYPE_MEDIUM_BLOB ||
             fields[c].type == MYSQL_TYPE_LONG_BLOB)) goto done;
        r->columns[c] = mj_dup(fields[c].name, strlen(fields[c].name));
        if (!r->columns[c]) goto done;
        output[c].buffer_type = MYSQL_TYPE_STRING;
        /* Fetch one byte into a real buffer.  The length field reports
         * full size and fetch_column retrieves it safely below. */
        output[c].buffer = &mj_mysql_probe_buffers[c];
        output[c].buffer_length = 1;
        output[c].length = &lengths[c];
        output[c].is_null = &is_null[c];
        output[c].error = &output_truncated[c];
    }
    stage = 7;
    if (mysql_stmt_bind_result(st, output) != 0) goto done;
    /* Stream rows: mysql_stmt_store_result would buffer unbounded data. */
    while (1) {
        stage = 8;
        int code = mysql_stmt_fetch(st);
        if (code == MYSQL_NO_DATA) break;
        if (code != 0 && code != MYSQL_DATA_TRUNCATED) goto done;
        if (r->rows == MJ_MAX_ROWS) goto done;
        size_t old_items = r->rows * r->cols;
        size_t new_items = old_items + r->cols;
        if (new_items > SIZE_MAX / sizeof(char *) || new_items > MJ_MAX_RESULT_CELLS) goto done;
        char **new_cells = (char **)realloc(r->cells, new_items * sizeof(char *));
        if (!new_cells) goto done;
        r->cells = new_cells;
        memset(r->cells + old_items, 0, r->cols * sizeof(char *));
        unsigned char *new_nulls = (unsigned char *)realloc(r->nulls, new_items);
        if (!new_nulls) goto done;
        r->nulls = new_nulls;
        memset(r->nulls + old_items, 0, r->cols);
        ++r->rows;
        for (size_t c = 0; c < r->cols; ++c) {
            size_t pos = old_items + c;
            if (is_null[c]) {
                r->nulls[pos] = 1;
                continue;
            }
            size_t len = lengths[c];
            if (len > MJ_MAX_CELL || used + len > MJ_MAX_RESULT_BYTES) goto done;
            char *buf = (char *)malloc(len + 1);
            if (!buf) goto done;
            /* Fetch the complete string (including values beyond buffer size). */
            MYSQL_BIND single;
            memset(&single, 0, sizeof(single));
            single.buffer_type = MYSQL_TYPE_STRING;
            single.buffer = buf;
            single.buffer_length = (unsigned long)(len + 1);
            unsigned long actual = 0;
            single.length = &actual;
            stage = 9;
            if (mysql_stmt_fetch_column(st, &single, (unsigned int)c, 0) != 0 || actual != len) {
                free(buf);
                goto done;
            }
            buf[len] = '\0';
            /* Text-only result ABI does not support embedded NUL/bytea. */
            if (memchr(buf, '\0', len)) {
                free(buf);
                goto done;
            }
            r->cells[pos] = buf;
            used += len;
        }
    }
    ok = 1;
done:
    if (!ok) {
        /* Read diagnostics before mysql_stmt_close destroys the handle. */
        mj_last_stage = stage;
        mj_last_code = (int)(st ? mysql_stmt_errno(st) : mysql_errno(db));
        /* Connector/C-generated protocol diagnostics only. Avoid including
         * SQL or parameters in error messages; 2027 is a client error. */
        if (st && (mj_last_code == 2027 || (mj_last_code == 1366 && getenv("MOJARA_TEST_MYSQL")))) {
            const char *err = mysql_stmt_error(st);
            if (err) {
                size_t n = strlen(err);
                if (n >= sizeof(mj_last_detail)) n = sizeof(mj_last_detail) - 1;
                for (size_t k = 0; k < n; ++k) {
                    unsigned char ch = (unsigned char)err[k];
                    mj_last_detail[k] = (ch >= 32 && ch <= 126) ? (char)ch : ' ';
                }
                mj_last_detail[n] = '\0';
            }
        }
    }
    if (meta) mysql_free_result(meta);
    if (st) mysql_stmt_close(st);
    if (parameter_copies) {
        for (int i = 0; i < count; ++i) free(parameter_copies[i]);
        free(parameter_copies);
    }
    free(input);
    free(input_lengths);
    free(output);
    free(lengths);
    free(is_null);
    free(mj_mysql_probe_buffers);
    free(output_truncated);
    if (!ok) {
        mj_mysql_free(r);
        return NULL;
    }
    return r;
}

/* Safe FFI entrypoint: Mojo passes one NUL-delimited byte array, not a
 * pointer array whose ownership information was stripped by an Int cast.
 * Construct parameter pointers in C while the backing Mojo array is live.
 * mj_mysql_query copies inputs into C-owned memory before execution.
 * Reject malformed layouts instead of reading beyond the supplied span.
 */
mj_mysql_result *mj_mysql_query_flat(MYSQL *db, const char *sql,
                                      const unsigned char *packed,
                                      size_t packed_size, int count) {
    if (count < 0 || count > MJ_MAX_PARAM) return NULL;
    if (count == 0) {
        if (packed_size != 0) return NULL;
        return mj_mysql_query(db, sql, NULL, 0);
    }
    if (!packed || packed_size == 0 ||
        packed_size > MJ_MAX_RESULT_BYTES) return NULL;
    const char **ptrs = (const char **)calloc((size_t)count, sizeof(*ptrs));
    if (!ptrs) return NULL;
    size_t off = 0;
    int valid = 1;
    for (int i = 0; i < count; ++i) {
        if (off >= packed_size) { valid = 0; break; }
        size_t n = 0;
        while (n < packed_size - off && packed[off + n] != 0) ++n;
        if (n >= packed_size - off || n > MJ_MAX_CELL) {
            valid = 0;
            break;
        }
        ptrs[i] = (const char *)(packed + off);
        off += n + 1;
    }
    if (off != packed_size) valid = 0;
    mj_mysql_result *result = NULL;
    if (valid) result = mj_mysql_query(db, sql, ptrs, count);
    free(ptrs);
    return result;
}

size_t mj_mysql_rows(const mj_mysql_result *r) { return r ? r->rows : 0; }
size_t mj_mysql_cols(const mj_mysql_result *r) { return r ? r->cols : 0; }
const char *mj_mysql_col(const mj_mysql_result *r, size_t c) {
    return r && c < r->cols ? r->columns[c] : NULL;
}
int mj_mysql_is_null(const mj_mysql_result *r, size_t row, size_t col) {
    return !r || row >= r->rows || col >= r->cols || r->nulls[row * r->cols + col];
}
const char *mj_mysql_cell(const mj_mysql_result *r, size_t row, size_t col) {
    return !r || row >= r->rows || col >= r->cols ? NULL : r->cells[row * r->cols + col];
}
