/* Mojara v0.13.0: opt-in, bounded PostgreSQL/MySQL read-only connection pool.
 * Linux x86_64 ABI; libpq and the existing Mojara MySQL bridge are loaded
 * dynamically, so this bridge needs no database-specific development headers.
 *
 * Each SELECT leases one connection for a synchronous query. Pool close must
 * only be invoked by an owner after producers stop creating new operations.
 * No raw connection escapes, no transactions span separate leases.
 */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MJ_NP_MAX 16
#define MJ_NP_MAX_CFG 8192
#define MJ_NP_MAX_SQL 16384
#define MJ_NP_MAX_PARAM 65536
#define MJ_NP_MAX_OUTPUT 1048576

/* Return: 1=row; 0=no row; 2=NULL; negatives are structured failures. */
enum { MJ_NP_INVALID=-1, MJ_NP_TIMEOUT=-2, MJ_NP_SQL=-3,
       MJ_NP_TOO_LARGE=-4, MJ_NP_CLOSED=-5, MJ_NP_CONNECT=-6 };

typedef struct {
    void *lib;
    void *(*connectdb)(const char *);
    int (*status)(void *);
    void (*finish)(void *);
    void *(*exec)(void *, const char *);
    void *(*execParams)(void *, const char *, int, const void *,
                        const char *const *, const int *, const int *, int);
    int (*resultStatus)(void *);
    int (*ntuples)(void *);
    int (*nfields)(void *);
    int (*getisnull)(void *, int, int);
    char *(*getvalue)(void *, int, int);
    int (*getlength)(void *, int, int);
    void (*clear)(void *);
    int (*setClientEncoding)(void *, const char *);
} pg_functions;

typedef struct {
    void *lib;
    void *(*open)(const char *, unsigned, const char *, const char *, const char *);
    void (*close)(void *);
    int (*read_only)(void *);
    void *(*query)(void *, const char *, const unsigned char *, size_t, int);
    void (*free_result)(void *);
    size_t (*rows)(void *);
    size_t (*cols)(void *);
    int (*is_null)(void *, size_t, size_t);
    const char *(*cell)(void *, size_t, size_t);
} mysql_functions;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t available;
    int driver; /* 1 = PG, 2 = MySQL */
    int capacity, wait_ms, active, waiting, peak, closing;
    void *connections[MJ_NP_MAX];
    bool leased[MJ_NP_MAX];
    uint64_t queries, waits, timeouts, failures;
    pg_functions pg;
    mysql_functions my;
} mj_np_pool;

static _Thread_local int mj_np_error;
int mj_np_last_error(void) { return mj_np_error; }
static int failure(int code) { mj_np_error = code; return code; }

/* Correct for supported Linux x86_64: data and function pointers use 64 bits. */
static int sym(void *lib, const char *name, void *destination, size_t dest_size) {
    if (dest_size != sizeof(void *)) return 0;
    void *address = dlsym(lib, name);
    if (!address) return 0;
    memcpy(destination, &address, sizeof address);
    return 1;
}
#define PG_SYM(api, field, name) (sym((api)->lib,(name),&(api)->field,sizeof((api)->field)))
#define MY_SYM(api, field, name) (sym((api)->lib,(name),&(api)->field,sizeof((api)->field)))

static int load_pg(pg_functions *p) {
    p->lib = dlopen("libpq.so.5", RTLD_NOW | RTLD_LOCAL);
    if (!p->lib) return 0;
    return PG_SYM(p,connectdb,"PQconnectdb") && PG_SYM(p,status,"PQstatus") &&
        PG_SYM(p,finish,"PQfinish") && PG_SYM(p,exec,"PQexec") &&
        PG_SYM(p,execParams,"PQexecParams") && PG_SYM(p,resultStatus,"PQresultStatus") &&
        PG_SYM(p,ntuples,"PQntuples") && PG_SYM(p,nfields,"PQnfields") &&
        PG_SYM(p,getisnull,"PQgetisnull") && PG_SYM(p,getvalue,"PQgetvalue") &&
        PG_SYM(p,getlength,"PQgetlength") && PG_SYM(p,clear,"PQclear") &&
        PG_SYM(p,setClientEncoding,"PQsetClientEncoding");
}
static int load_my(mysql_functions *m) {
    m->lib = dlopen("libmojara_mysql.so", RTLD_NOW | RTLD_LOCAL);
    if (!m->lib) return 0;
    return MY_SYM(m,open,"mj_mysql_open") && MY_SYM(m,close,"mj_mysql_close") &&
        MY_SYM(m,read_only,"mj_mysql_enable_readonly") && MY_SYM(m,query,"mj_mysql_query_flat") && MY_SYM(m,free_result,"mj_mysql_free") &&
        MY_SYM(m,rows,"mj_mysql_rows") && MY_SYM(m,cols,"mj_mysql_cols") &&
        MY_SYM(m,is_null,"mj_mysql_is_null") && MY_SYM(m,cell,"mj_mysql_cell");
}

static struct timespec deadline_after(int ms) {
    struct timespec until = {0, 0};
    clock_gettime(CLOCK_MONOTONIC, &until);
    until.tv_sec += ms / 1000;
    until.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (until.tv_nsec >= 1000000000L) { until.tv_nsec -= 1000000000L; ++until.tv_sec; }
    return until;
}

static void destroy(mj_np_pool *p) {
    if (!p) return;
    for (int i=0;i<p->capacity;i++) {
        if (!p->connections[i]) continue;
        if (p->driver == 1) p->pg.finish(p->connections[i]);
        else p->my.close(p->connections[i]);
    }
    if (p->pg.lib) dlclose(p->pg.lib);
    if (p->my.lib) dlclose(p->my.lib);
    pthread_cond_destroy(&p->available);
    pthread_mutex_destroy(&p->mutex);
    free(p);
}

/* Config is EXACTLY one NUL-terminated PostgreSQL DSN, or five packed
 * NUL-terminated MySQL fields: host, port, user, password, database.
 * No delimiter escaping is needed. Every byte is length checked.
 */
static int cfg_fields(const unsigned char *src, size_t len, int n, const char **out) {
    if (!src || !len || len > MJ_NP_MAX_CFG) return 0;
    size_t offset=0;
    for (int i=0;i<n;i++) {
        if (offset >= len) return 0;
        const unsigned char *end = memchr(src+offset, 0, len-offset);
        if (!end) return 0;
        out[i] = (const char *)(src+offset);
        offset = (size_t)(end-src)+1;
    }
    return offset==len;
}

void *mj_np_open(int driver, const unsigned char *config, size_t config_len,
                 int capacity, int wait_ms) {
    mj_np_error=0;
    if ((driver!=1 && driver!=2) || capacity<1 || capacity>MJ_NP_MAX ||
        wait_ms<1 || wait_ms>30000) { failure(MJ_NP_INVALID); return NULL; }
    const char *fields[5] = {0};
    if (!cfg_fields(config,config_len,driver==1?1:5,fields) || !fields[0][0]) {
        failure(MJ_NP_INVALID); return NULL;
    }
    unsigned port=0;
    if (driver==2) {
        if (!fields[2][0] || !fields[4][0] || !fields[1][0]) {
            failure(MJ_NP_INVALID); return NULL;
        }
        for (const char *c=fields[1];*c;c++) {
            if (*c<'0' || *c>'9' || port>65535U/10U) {
                failure(MJ_NP_INVALID); return NULL;
            }
            port=port*10U+(unsigned)(*c-'0');
            if (port>65535U) { failure(MJ_NP_INVALID); return NULL; }
        }
        if (port==0) { failure(MJ_NP_INVALID); return NULL; }
    }
    mj_np_pool *p=calloc(1,sizeof(*p));
    if (!p) { failure(MJ_NP_INVALID); return NULL; }
    if (pthread_mutex_init(&p->mutex,NULL)) { free(p); failure(MJ_NP_INVALID); return NULL; }
    pthread_condattr_t attr;
    if (pthread_condattr_init(&attr)) { pthread_mutex_destroy(&p->mutex); free(p); failure(MJ_NP_INVALID); return NULL; }
    int rc=pthread_condattr_setclock(&attr,CLOCK_MONOTONIC);
    if (!rc) rc=pthread_cond_init(&p->available,&attr);
    pthread_condattr_destroy(&attr);
    if (rc) { pthread_mutex_destroy(&p->mutex); free(p); failure(MJ_NP_INVALID); return NULL; }
    p->driver=driver; p->capacity=capacity; p->wait_ms=wait_ms;
    if (!(driver==1?load_pg(&p->pg):load_my(&p->my))) {
        destroy(p); failure(MJ_NP_CONNECT); return NULL;
    }
    for (int i=0;i<capacity;i++) {
        if (driver==1) {
            p->connections[i]=p->pg.connectdb(fields[0]);
            if (!p->connections[i] || p->pg.status(p->connections[i])!=0 ||
                p->pg.setClientEncoding(p->connections[i],"UTF8")!=0) {
                destroy(p); failure(MJ_NP_CONNECT); return NULL;
            }
            void *result=p->pg.exec(p->connections[i],"SET default_transaction_read_only = on");
            int ok=result && p->pg.resultStatus(result)==1;
            if (result) p->pg.clear(result);
            if (!ok) { destroy(p); failure(MJ_NP_CONNECT); return NULL; }
        } else {
            p->connections[i]=p->my.open(fields[0],port,fields[2],fields[3],fields[4]);
            if (!p->connections[i]) { destroy(p); failure(MJ_NP_CONNECT); return NULL; }
            if (p->my.read_only(p->connections[i])!=1) {
                destroy(p); failure(MJ_NP_CONNECT); return NULL;
            }
        }
    }
    return p;
}

int mj_np_begin_shutdown(void *opaque) {
    if (!opaque) return 0;
    mj_np_pool *p=opaque;
    pthread_mutex_lock(&p->mutex);
    p->closing=1;
    pthread_cond_broadcast(&p->available);
    pthread_mutex_unlock(&p->mutex);
    return 1;
}
/* Owner must stop and join producer threads before close. */
void mj_np_close(void *opaque) {
    if (!opaque) return;
    mj_np_pool *p=opaque;
    pthread_mutex_lock(&p->mutex);
    p->closing=1;
    pthread_cond_broadcast(&p->available);
    while (p->active || p->waiting) pthread_cond_wait(&p->available,&p->mutex);
    pthread_mutex_unlock(&p->mutex);
    destroy(p);
}
static int take(mj_np_pool *p) {
    struct timespec deadline=deadline_after(p->wait_ms);
    pthread_mutex_lock(&p->mutex);
    for (;;) {
        if (p->closing) { pthread_mutex_unlock(&p->mutex); return MJ_NP_CLOSED; }
        for (int i=0;i<p->capacity;i++) if (!p->leased[i]) {
            p->leased[i]=true;
            p->active++;
            if (p->active>p->peak) p->peak=p->active;
            pthread_mutex_unlock(&p->mutex);
            return i;
        }
        p->waiting++; p->waits++;
        int rc=pthread_cond_timedwait(&p->available,&p->mutex,&deadline);
        p->waiting--;
        if (p->closing && !p->waiting) pthread_cond_broadcast(&p->available);
        if (rc==ETIMEDOUT) { p->timeouts++; pthread_mutex_unlock(&p->mutex); return MJ_NP_TIMEOUT; }
        if (rc) { pthread_mutex_unlock(&p->mutex); return MJ_NP_INVALID; }
    }
}
static void put(mj_np_pool *p,int slot,int status) {
    pthread_mutex_lock(&p->mutex);
    p->leased[slot]=false;
    p->active--;
    p->queries++;
    if (status<0) p->failures++;
    pthread_cond_broadcast(&p->available);
    pthread_mutex_unlock(&p->mutex);
}
static int select_only(const char *sql) {
    if (!sql) return 0;
    size_t n=strnlen(sql,MJ_NP_MAX_SQL+1);
    if (n<6 || n>MJ_NP_MAX_SQL) return 0;
    while (*sql==' ' || *sql=='\t' || *sql=='\r' || *sql=='\n') sql++;
    if (!((sql[0]=='S' || sql[0]=='s') && (sql[1]=='E'||sql[1]=='e') &&
          (sql[2]=='L'||sql[2]=='l') && (sql[3]=='E'||sql[3]=='e') &&
          (sql[4]=='C'||sql[4]=='c') && (sql[5]=='T'||sql[5]=='t'))) return 0;
    if (sql[6]!=' ' && sql[6]!='\t' && sql[6]!='\r' && sql[6]!='\n') return 0;
    return strchr(sql,';')==NULL;
}

/* One bound UTF-8 text value, one returned column and first row only.
 * NULL and no row differ at the C boundary, both map to Mojo Optional.None.
 * Do not pass raw request input as SQL text; it is developer-controlled SQL.
 */
int mj_np_query_one_text(void *opaque, const char *sql, const char *param,
                         char *out, int out_capacity) {
    mj_np_error=0;
    if (!opaque || !out || !param || out_capacity<2 || out_capacity>MJ_NP_MAX_OUTPUT ||
        !select_only(sql) || strnlen(param,MJ_NP_MAX_PARAM+1)>MJ_NP_MAX_PARAM)
        return failure(MJ_NP_INVALID);
    out[0]='\0';
    mj_np_pool *p=opaque;
    int slot=take(p);
    if (slot<0) return failure(slot);
    int status=MJ_NP_SQL;
    if (p->driver==1) {
        const char *values[1]={param};
        void *result=p->pg.execParams(p->connections[slot],sql,1,NULL,values,NULL,NULL,0);
        if (result) {
            if (p->pg.resultStatus(result)==2 && p->pg.nfields(result)==1) {
                if (p->pg.ntuples(result)==0) status=0;
                else if (p->pg.getisnull(result,0,0)) status=2;
                else {
                    int n=p->pg.getlength(result,0,0);
                    char *src=p->pg.getvalue(result,0,0);
                    if (src && n>=0 && n<out_capacity && !memchr(src,'\0',(size_t)n)) {
                        memcpy(out,src,(size_t)n); out[n]='\0'; status=1;
                    } else status=MJ_NP_TOO_LARGE;
                }
            }
            p->pg.clear(result);
        }
    } else {
        size_t n=strlen(param);
        void *result=p->my.query(p->connections[slot],sql,(const unsigned char *)param,n+1,1);
        if (result) {
            if (p->my.cols(result)==1) {
                if (p->my.rows(result)==0) status=0;
                else if (p->my.is_null(result,0,0)) status=2;
                else {
                    const char *src=p->my.cell(result,0,0);
                    if (src) {
                        size_t size=strnlen(src,(size_t)out_capacity);
                        if (size<(size_t)out_capacity) {
                            memcpy(out,src,size+1); status=1;
                        } else status=MJ_NP_TOO_LARGE;
                    }
                }
            }
            p->my.free_result(result);
        }
    }
    put(p,slot,status);
    if (status<0) return failure(status);
    return status;
}

/* Stats as nine uint64s, one typed pointer across the Mojo FFI boundary.
 * capacity, in_use, waiting, peak, closing, completed, waits, timeouts, errors.
 */
int mj_np_stats(void *opaque, uint64_t *out, int count) {
    if (!opaque || !out || count<9) return 0;
    mj_np_pool *p=opaque;
    pthread_mutex_lock(&p->mutex);
    out[0]=(uint64_t)p->capacity;
    out[1]=(uint64_t)p->active;
    out[2]=(uint64_t)p->waiting;
    out[3]=(uint64_t)p->peak;
    out[4]=(uint64_t)p->closing;
    out[5]=p->queries;
    out[6]=p->waits;
    out[7]=p->timeouts;
    out[8]=p->failures;
    pthread_mutex_unlock(&p->mutex);
    return 1;
}

#ifdef MJ_NP_TESTING
int mj_np_test_hold(void *opaque,int milliseconds) {
    if (!opaque || milliseconds<1 || milliseconds>3000) return MJ_NP_INVALID;
    mj_np_pool *p=opaque;
    int slot=take(p);
    if (slot<0) return slot;
    struct timespec duration={milliseconds/1000,(long)(milliseconds%1000)*1000000L};
    while (nanosleep(&duration,&duration)==-1 && errno==EINTR) {}
    put(p,slot,1);
    return 1;
}
#endif
