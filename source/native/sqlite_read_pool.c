/* Mojara v0.10.3: optional bounded SQLite read-only connection pool.
 * Each synchronous query leases exactly one connection. No SQLite pointers
 * or prepared statements cross the Mojo/C boundary. This is intentionally
 * NOT a transactional pool, nor a replacement for DbClient.
 */
#define _POSIX_C_SOURCE 200809L
#include <sqlite3.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#define MJ_SP_MAX_CONNECTIONS 32
#define MJ_SP_MAX_SQL 16384
#define MJ_SP_MAX_PARAM 65536
#define MJ_SP_MAX_OUTPUT 1048576

typedef struct mj_sqlite_read_pool {
    pthread_mutex_t mutex;
    pthread_cond_t available;
    sqlite3 *connections[MJ_SP_MAX_CONNECTIONS];
    bool leased[MJ_SP_MAX_CONNECTIONS];
    int capacity;
    int active;
    int waiting;
    int peak_active;
    int closing;
    int wait_ms;
    uint64_t total_queries;
    uint64_t timeouts;
    uint64_t waits;
} mj_sqlite_read_pool;

/* Stable codes: 1 = row, 0 = no row, 2 = SQL NULL, all negatives = errors. */
enum { MJ_SP_INVALID = -1, MJ_SP_TIMEOUT = -2, MJ_SP_SQL = -3,
       MJ_SP_TOO_LARGE = -4, MJ_SP_CLOSED = -5 };

static _Thread_local int last_code;
static int fail(int code) { last_code = code; return code; }
int mj_sp_last_code(void) { return last_code; }

static struct timespec wait_deadline(int ms) {
    struct timespec end = {0, 0};
#if defined(__APPLE__)
    clock_gettime(CLOCK_REALTIME, &end);
#else
    clock_gettime(CLOCK_MONOTONIC, &end);
#endif
    end.tv_sec += ms / 1000;
    end.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (end.tv_nsec >= 1000000000L) { end.tv_nsec -= 1000000000L; end.tv_sec++; }
    return end;
}

static void dispose_pool(mj_sqlite_read_pool *pool) {
    if (!pool) return;
    for (int i = 0; i < pool->capacity; ++i) {
        if (pool->connections[i]) sqlite3_close(pool->connections[i]);
    }
    pthread_cond_destroy(&pool->available);
    pthread_mutex_destroy(&pool->mutex);
    free(pool);
}

void *mj_sp_open(const char *path, int max_connections, int wait_ms) {
    last_code = 0;
    if (!path || !path[0] || strcmp(path, ":memory:") == 0 ||
        strlen(path) > 4096 || max_connections < 1 ||
        max_connections > MJ_SP_MAX_CONNECTIONS || wait_ms < 1 || wait_ms > 30000) {
        fail(MJ_SP_INVALID);
        return NULL;
    }
    mj_sqlite_read_pool *pool = calloc(1, sizeof(*pool));
    if (!pool) { fail(MJ_SP_INVALID); return NULL; }
    if (pthread_mutex_init(&pool->mutex, NULL)) { free(pool); fail(MJ_SP_INVALID); return NULL; }
    pthread_condattr_t attr;
    if (pthread_condattr_init(&attr)) {
        pthread_mutex_destroy(&pool->mutex); free(pool); fail(MJ_SP_INVALID); return NULL;
    }
#if defined(__APPLE__)
    /* Darwin's default pthread condition variable clock is realtime. */
    int rc = pthread_cond_init(&pool->available, &attr);
#else
    int rc = pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
    if (rc == 0) rc = pthread_cond_init(&pool->available, &attr);
#endif
    pthread_condattr_destroy(&attr);
    if (rc != 0) { pthread_mutex_destroy(&pool->mutex); free(pool); fail(MJ_SP_INVALID); return NULL; }
    pool->capacity = max_connections;
    pool->wait_ms = wait_ms;
    for (int i = 0; i < max_connections; ++i) {
        sqlite3 *db = NULL;
        rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
        if (rc != SQLITE_OK) {
            if (db) sqlite3_close(db);
            dispose_pool(pool);
            fail(MJ_SP_SQL);
            return NULL;
        }
        pool->connections[i] = db;
        sqlite3_busy_timeout(db, wait_ms);
        rc = sqlite3_exec(db, "PRAGMA query_only = ON", NULL, NULL, NULL);
        if (rc != SQLITE_OK) { dispose_pool(pool); fail(MJ_SP_SQL); return NULL; }
    }
    return pool;
}

/* Request no more leases and wake up threads waiting for a connection.
 * Caller must own and retain the pool until all producer threads are joined. */
int mj_sp_begin_shutdown(void *opaque) {
    if (!opaque) return 0;
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    pthread_mutex_lock(&pool->mutex);
    pool->closing = 1;
    pthread_cond_broadcast(&pool->available);
    pthread_mutex_unlock(&pool->mutex);
    return 1;
}

/* The owning thread must stop launching queries before calling close.
 * Waits for already-entered queries AND waiting leases to exit before freeing. */
void mj_sp_close(void *opaque) {
    if (!opaque) return;
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    pthread_mutex_lock(&pool->mutex);
    pool->closing = 1;
    pthread_cond_broadcast(&pool->available);
    while (pool->active != 0 || pool->waiting != 0)
        pthread_cond_wait(&pool->available, &pool->mutex);
    pthread_mutex_unlock(&pool->mutex);
    dispose_pool(pool);
}

static int lease(mj_sqlite_read_pool *pool) {
    struct timespec deadline = wait_deadline(pool->wait_ms);
    pthread_mutex_lock(&pool->mutex);
    for (;;) {
        if (pool->closing) { pthread_mutex_unlock(&pool->mutex); return MJ_SP_CLOSED; }
        for (int i = 0; i < pool->capacity; ++i) {
            if (!pool->leased[i]) {
                pool->leased[i] = true;
                pool->active++;
                if (pool->active > pool->peak_active) pool->peak_active = pool->active;
                pthread_mutex_unlock(&pool->mutex);
                return i;
            }
        }
        pool->waiting++;
        pool->waits++;
        int rc = pthread_cond_timedwait(&pool->available, &pool->mutex, &deadline);
        pool->waiting--;
        if (pool->closing && pool->waiting == 0) pthread_cond_broadcast(&pool->available);
        if (rc == ETIMEDOUT) {
            pool->timeouts++;
            pthread_mutex_unlock(&pool->mutex);
            return MJ_SP_TIMEOUT;
        }
        if (rc) { pthread_mutex_unlock(&pool->mutex); return MJ_SP_INVALID; }
    }
}

static void give_back(mj_sqlite_read_pool *pool, int index) {
    pthread_mutex_lock(&pool->mutex);
    pool->leased[index] = false;
    pool->active--;
    pool->total_queries++;
    pthread_cond_broadcast(&pool->available);
    pthread_mutex_unlock(&pool->mutex);
}

/* One parameter, one UTF-8 field, first row only. No NUL output and no
 * implicit truncation. Caller owns the supplied output buffer. */
int mj_sp_query_one_text(void *opaque, const char *sql, const char *param,
                         char *out, int capacity) {
    last_code = 0;
    if (!opaque || !sql || !param || !out || capacity < 2 ||
        capacity > MJ_SP_MAX_OUTPUT || strnlen(sql, MJ_SP_MAX_SQL + 1) > MJ_SP_MAX_SQL ||
        strnlen(param, MJ_SP_MAX_PARAM + 1) > MJ_SP_MAX_PARAM) return fail(MJ_SP_INVALID);
    out[0] = '\0';
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    int index = lease(pool);
    if (index < 0) return fail(index);
    sqlite3 *db = pool->connections[index];
    sqlite3_stmt *stmt = NULL;
    int answer = MJ_SP_SQL;
    const char *tail = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, &tail);
    if (rc != SQLITE_OK || !stmt) goto done;
    /* Reject stacked SQL, writes, DDL and wrong binding arity. */
    for (const char *p = tail; p && *p; ++p) {
        if (*p != ' ' && *p != '\n' && *p != '\r' && *p != '\t' && *p != ';') goto done;
    }
    if (!sqlite3_stmt_readonly(stmt) || sqlite3_bind_parameter_count(stmt) != 1 ||
        sqlite3_column_count(stmt) != 1) goto done;
    rc = sqlite3_bind_text(stmt, 1, param, -1, SQLITE_TRANSIENT);
    if (rc != SQLITE_OK) goto done;
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE) { answer = 0; goto done; }
    if (rc != SQLITE_ROW) goto done;
    if (sqlite3_column_type(stmt, 0) == SQLITE_NULL) { answer = 2; goto done; }
    const unsigned char *data = sqlite3_column_text(stmt, 0);
    int length = sqlite3_column_bytes(stmt, 0);
    if (!data || length < 0) goto done;
    if (length >= capacity) { answer = MJ_SP_TOO_LARGE; goto done; }
    if (memchr(data, '\0', (size_t)length)) goto done;
    memcpy(out, data, (size_t)length);
    out[length] = '\0';
    answer = 1;
done:
    if (stmt && sqlite3_finalize(stmt) != SQLITE_OK && answer >= 0) answer = MJ_SP_SQL;
    give_back(pool, index);
    last_code = answer < 0 ? answer : 0;
    return answer;
}

int mj_sp_stats(void *opaque, int *capacity, int *active,
                uint64_t *queries, uint64_t *timeouts) {
    if (!opaque || !capacity || !active || !queries || !timeouts) return 0;
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    pthread_mutex_lock(&pool->mutex);
    *capacity = pool->capacity;
    *active = pool->active;
    *queries = pool->total_queries;
    *timeouts = pool->timeouts;
    pthread_mutex_unlock(&pool->mutex);
    return 1;
}

/* Optional detailed statistics. Snapshot is internally consistent while
 * holding pool->mutex. A released pool pointer must never be reused. */
int mj_sp_stats_extended(void *opaque, int *capacity, int *active, int *waiting,
                         int *peak_active, int *closing, uint64_t *queries,
                         uint64_t *waits, uint64_t *timeouts) {
    if (!opaque || !capacity || !active || !waiting || !peak_active || !closing ||
        !queries || !waits || !timeouts) return 0;
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    pthread_mutex_lock(&pool->mutex);
    *capacity = pool->capacity;
    *active = pool->active;
    *waiting = pool->waiting;
    *peak_active = pool->peak_active;
    *closing = pool->closing;
    *queries = pool->total_queries;
    *waits = pool->waits;
    *timeouts = pool->timeouts;
    pthread_mutex_unlock(&pool->mutex);
    return 1;
}

/* A single opt-in process-lifetime pool for benchmark routes. Every call
 * uses the same immutable file path. Only enabled by example application.
 * General applications should create an explicit pool via mj_sp_open(). */
static pthread_mutex_t global_mutex = PTHREAD_MUTEX_INITIALIZER;
static mj_sqlite_read_pool *global_pool;
static char global_path[4097];

int mj_sp_benchmark_lookup(const char *path, int connections,
                           const char *sql, const char *param,
                           char *out, int capacity) {
    if (!path || strlen(path) > 4096) return fail(MJ_SP_INVALID);
    pthread_mutex_lock(&global_mutex);
    if (!global_pool) {
        global_pool = mj_sp_open(path, connections, 3000);
        if (global_pool) memcpy(global_path, path, strlen(path) + 1);
    }
    mj_sqlite_read_pool *pool = global_pool;
    int valid = pool && strcmp(path, global_path) == 0 &&
                connections == pool->capacity;
    pthread_mutex_unlock(&global_mutex);
    if (!valid) return fail(MJ_SP_INVALID);
    return mj_sp_query_one_text(pool, sql, param, out, capacity);
}

__attribute__((destructor)) static void shutdown_benchmark_pool(void) {
    if (global_pool) mj_sp_close(global_pool);
}

#ifdef MJ_SP_TESTING
/* Exercise begin_shutdown + close waiting on a real occupied lease.
 * This function is excluded from the production shared object. */
int mj_sp_test_hold(void *opaque, int milliseconds) {
    if (!opaque || milliseconds < 1 || milliseconds > 3000) return MJ_SP_INVALID;
    mj_sqlite_read_pool *pool = (mj_sqlite_read_pool *)opaque;
    int slot = lease(pool);
    if (slot < 0) return slot;
    struct timespec left = { milliseconds / 1000,
                             (long)(milliseconds % 1000) * 1000000L };
    while (nanosleep(&left, &left) == -1 && errno == EINTR) {}
    give_back(pool, slot);
    return 1;
}
#endif
