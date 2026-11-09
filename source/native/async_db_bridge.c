/*
 * Mojara asynchronous database jobs: process-local, bounded, thread-safe.
 * Query parameters are always bound; SQL is trusted developer source.
 * All connection state belongs to a dedicated worker thread.
 * No process or thread is spawned per HTTP request.
 */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <stdlib.h>
#else
#include <sys/random.h>
#endif
#include <sqlite3.h>
#include <libpq-fe.h>

/* Use the platform's secure random generator for file/session identifiers. */
static ssize_t mj_secure_random(void *buffer, size_t size) {
#if defined(__APPLE__)
    arc4random_buf(buffer, size);
    return (ssize_t)size;
#else
    return getrandom(buffer, size, 0);
#endif
}

typedef struct mj_mysql_result mj_mysql_result;
extern void *mj_mysql_open(const char *, unsigned, const char *, const char *, const char *);
extern void mj_mysql_close(void *);
extern mj_mysql_result *mj_mysql_query(void *, const char *, const char *const *, int);
extern void mj_mysql_free(mj_mysql_result *);
extern size_t mj_mysql_rows(const mj_mysql_result *);
extern size_t mj_mysql_cols(const mj_mysql_result *);
extern const char *mj_mysql_col(const mj_mysql_result *, size_t);
extern int mj_mysql_is_null(const mj_mysql_result *, size_t, size_t);
extern const char *mj_mysql_cell(const mj_mysql_result *, size_t, size_t);

#define MJ_RESULT_CAP (262144u)
#define MJ_MAX_SQL (16384u)
#define MJ_MAX_PARAM (32)
#define MJ_MAX_PARAM_BYTES (65536u)
#define MJ_MAX_ROWS (512)
#define MJ_MAX_COLS (64)
#define MJ_MAX_OUTSTANDING (512)
#define MJ_RESULT_TTL_MS (120000u)

typedef struct {
    char *data;
    size_t len, cap;
    int error;
} mj_json;

typedef struct mj_async_job {
    uint64_t id;
    char *sql;
    char **params;
    int nparams;
    int state;   /* 0 queued, 1 executing, 2 success, 3 error */
    char *result;
    size_t result_len;
    uint64_t finished_ms;
    struct mj_async_job *next;
    struct mj_async_job *queue_next;
} mj_async_job;

typedef struct {
    pthread_mutex_t mu;
    pthread_cond_t cv;
    pthread_t *threads;
    int num_threads, limit, refs, stopping, outstanding;
    int driver; /* 1 SQLite, 2 PostgreSQL, 3 MySQL */
    char *cfg[5];
    mj_async_job *jobs, *front, *back;
} mj_async_pool;

static uint64_t mj_millis(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return 0;
    return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}

static char *mj_copy_n(const char *p, size_t n) {
    if (!p || n > MJ_MAX_PARAM_BYTES) return NULL;
    char *s = (char *)malloc(n + 1);
    if (!s) return NULL;
    memcpy(s, p, n);
    s[n] = '\0';
    return s;
}

static void mj_job_free(mj_async_job *j) {
    if (!j) return;
    free(j->sql);
    if (j->params)
        for (int i = 0; i < j->nparams; ++i) free(j->params[i]);
    free(j->params);
    free(j->result);
    free(j);
}

static int mj_buf_grow(mj_json *b, size_t more) {
    if (b->error || more > MJ_RESULT_CAP - b->len) { b->error = 1; return 0; }
    if (b->len + more + 1 <= b->cap) return 1;
    size_t desired = b->cap ? b->cap * 2 : 512;
    while (desired < b->len + more + 1) desired *= 2;
    if (desired > MJ_RESULT_CAP + 1) desired = MJ_RESULT_CAP + 1;
    char *next = (char *)realloc(b->data, desired);
    if (!next) { b->error = 1; return 0; }
    b->data = next; b->cap = desired;
    return 1;
}
static void mj_buf_write(mj_json *b, const char *s, size_t n) {
    if (!mj_buf_grow(b,n)) return;
    memcpy(b->data + b->len,s,n);
    b->len += n; b->data[b->len]=0;
}
static void mj_buf_put(mj_json *b, const char *s) {mj_buf_write(b,s,strlen(s));}
static void mj_buf_char(mj_json *b, char c) {mj_buf_write(b,&c,1);}
static void mj_buf_json(mj_json *b, const char *s, size_t n) {
    if (!s) { mj_buf_put(b,"null"); return; }
    mj_buf_char(b,'"');
    for (size_t i = 0; i < n && !b->error; ++i) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') { mj_buf_char(b,'\\');mj_buf_char(b,(char)c); }
        else if (c < 32) {
            static const char hex[] = "0123456789abcdef";
            char u[] = {'\\','u','0','0',hex[c>>4],hex[c&15]};
            mj_buf_write(b,u,6);
        } else {
            mj_buf_char(b,(char)c);
        }
    }
    mj_buf_char(b,'"');
}

static int mj_json_start(mj_json *b) {mj_buf_put(b,"{\"columns\":[");return !b->error;}
static void mj_json_cols_done(mj_json *b){mj_buf_put(b,"],\"rows\":[");}
static void mj_json_end(mj_json *b){mj_buf_put(b,"]}");}
static int mj_result_sqlite(sqlite3 *db, mj_async_job *j, mj_json *b) {
    sqlite3_stmt *stmt = NULL;
    const char *end = NULL;
    if (sqlite3_prepare_v2(db,j->sql,-1,&stmt,&end)!=SQLITE_OK) return 0;
    while (end && (*end==' ' || *end=='\n' || *end=='\r' || *end=='\t' || *end==';')) ++end;
    if (end && *end) {sqlite3_finalize(stmt);return 0;}
    if (sqlite3_bind_parameter_count(stmt)!=j->nparams) {sqlite3_finalize(stmt);return 0;}
    for (int i=0;i<j->nparams;i++) {
        if(sqlite3_bind_text(stmt,i+1,j->params[i],-1,SQLITE_TRANSIENT)!=SQLITE_OK) {
            sqlite3_finalize(stmt);return 0;
        }
    }
    int cols=sqlite3_column_count(stmt);
    if (cols>MJ_MAX_COLS) {sqlite3_finalize(stmt);return 0;}
    mj_json_start(b);
    for (int c=0;c<cols;c++) {
        if(c)mj_buf_char(b,',');
        const char *name=sqlite3_column_name(stmt,c);
        mj_buf_json(b,name,strlen(name));
    }
    mj_json_cols_done(b);
    int result=0,rows=0;
    while ((result=sqlite3_step(stmt))==SQLITE_ROW) {
        if (++rows>MJ_MAX_ROWS) {sqlite3_finalize(stmt);return 0;}
        if(rows>1)mj_buf_char(b,',');
        mj_buf_char(b,'[');
        for(int c=0;c<cols;c++) {
            if(c)mj_buf_char(b,',');
            if(sqlite3_column_type(stmt,c)==SQLITE_NULL) mj_buf_put(b,"null");
            else if(sqlite3_column_type(stmt,c)==SQLITE_BLOB) {
                sqlite3_finalize(stmt);return 0;
            } else {
                const unsigned char *v=sqlite3_column_text(stmt,c);
                int len=sqlite3_column_bytes(stmt,c);
                mj_buf_json(b,(const char *)v,(size_t)len);
            }
        }
        mj_buf_char(b,']');
        if(b->error){sqlite3_finalize(stmt);return 0;}
    }
    if(result!=SQLITE_DONE){sqlite3_finalize(stmt);return 0;}
    mj_json_end(b);
    sqlite3_finalize(stmt);
    return !b->error;
}
static int mj_result_pg(PGconn *db, mj_async_job *j, mj_json *b) {
    const char *params[MJ_MAX_PARAM];
    for(int i=0;i<j->nparams;i++)params[i]=j->params[i];
    PGresult *r=PQexecParams(db,j->sql,j->nparams,NULL,params,NULL,NULL,0);
    if(!r)return 0;
    ExecStatusType status=PQresultStatus(r);
    if(status!=PGRES_TUPLES_OK && status!=PGRES_COMMAND_OK){PQclear(r);return 0;}
    int rows=PQntuples(r),cols=PQnfields(r);
    if(rows<0 || rows>MJ_MAX_ROWS || cols<0 || cols>MJ_MAX_COLS){PQclear(r);return 0;}
    mj_json_start(b);
    for(int c=0;c<cols;c++){
        if(c)mj_buf_char(b,',');
        const char *name=PQfname(r,c);
        mj_buf_json(b,name,strlen(name));
    }
    mj_json_cols_done(b);
    for(int row=0;row<rows;row++){
        if(row)mj_buf_char(b,',');
        mj_buf_char(b,'[');
        for(int col=0;col<cols;col++){
            if(col)mj_buf_char(b,',');
            if(PQgetisnull(r,row,col))mj_buf_put(b,"null");
            else mj_buf_json(b,PQgetvalue(r,row,col),(size_t)PQgetlength(r,row,col));
        }
        mj_buf_char(b,']');
        if(b->error){PQclear(r);return 0;}
    }
    mj_json_end(b);PQclear(r);
    return !b->error;
}
static int mj_result_mysql(void *db, mj_async_job *j, mj_json *b) {
    const char *params[MJ_MAX_PARAM];
    for(int i=0;i<j->nparams;i++)params[i]=j->params[i];
    mj_mysql_result *r=mj_mysql_query(db,j->sql,params,j->nparams);
    if(!r)return 0;
    size_t rows=mj_mysql_rows(r), cols=mj_mysql_cols(r);
    if(rows>MJ_MAX_ROWS || cols>MJ_MAX_COLS){mj_mysql_free(r);return 0;}
    mj_json_start(b);
    for(size_t c=0;c<cols;c++){
        if(c)mj_buf_char(b,',');
        const char *name=mj_mysql_col(r,c);
        mj_buf_json(b,name,strlen(name));
    }
    mj_json_cols_done(b);
    for(size_t row=0;row<rows;row++){
        if(row)mj_buf_char(b,',');
        mj_buf_char(b,'[');
        for(size_t col=0;col<cols;col++){
            if(col)mj_buf_char(b,',');
            if(mj_mysql_is_null(r,row,col))mj_buf_put(b,"null");
            else {
                const char *v=mj_mysql_cell(r,row,col);
                if(!v){mj_mysql_free(r);return 0;}
                mj_buf_json(b,v,strlen(v));
            }
        }
        mj_buf_char(b,']');
        if(b->error){mj_mysql_free(r);return 0;}
    }
    mj_json_end(b);mj_mysql_free(r);
    return !b->error;
}
static void mj_prune(mj_async_pool *p) {
    uint64_t now=mj_millis();
    mj_async_job **next=&p->jobs;
    while(*next) {
        mj_async_job *j=*next;
        if(j->state>=2 && now>=j->finished_ms && now-j->finished_ms>MJ_RESULT_TTL_MS) {
            *next=j->next; p->outstanding--;mj_job_free(j);
        } else next=&j->next;
    }
}
static void *mj_worker(void *arg) {
    mj_async_pool *p=(mj_async_pool *)arg;
    sqlite3 *sqlite=NULL;
    PGconn *pg=NULL;
    void *mysql=NULL;
    for(;;) {
        pthread_mutex_lock(&p->mu);
        while(!p->stopping && !p->front)pthread_cond_wait(&p->cv,&p->mu);
        if(p->stopping){pthread_mutex_unlock(&p->mu);break;}
        mj_async_job *j=p->front;
        p->front=j->queue_next;
        if(!p->front)p->back=NULL;
        j->queue_next=NULL;
        j->state=1;
        pthread_mutex_unlock(&p->mu);
        if(p->driver==1 && !sqlite) {
            if(sqlite3_open_v2(p->cfg[0],&sqlite,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,NULL)!=SQLITE_OK){
                if(sqlite)sqlite3_close(sqlite);
                sqlite=NULL;
            }
            if(sqlite) sqlite3_busy_timeout(sqlite,3000);
        } else if(p->driver==2 && !pg) {
            pg=PQconnectdb(p->cfg[0]);
            if(!pg || PQstatus(pg)!=CONNECTION_OK){if(pg)PQfinish(pg);pg=NULL;}
        } else if(p->driver==3 && !mysql) {
            mysql=mj_mysql_open(p->cfg[0],(unsigned)atoi(p->cfg[1]),p->cfg[2],p->cfg[3],p->cfg[4]);
        }
        mj_json buffer={0};
        int ok=0;
        if(p->driver==1 && sqlite) ok=mj_result_sqlite(sqlite,j,&buffer);
        if(p->driver==2 && pg) ok=mj_result_pg(pg,j,&buffer);
        if(p->driver==3 && mysql) ok=mj_result_mysql(mysql,j,&buffer);
        if(!ok) {
            if(p->driver==2 && pg && PQstatus(pg)!=CONNECTION_OK){PQfinish(pg);pg=NULL;}
            free(buffer.data);buffer.data=NULL;buffer.len=0;
        }
        pthread_mutex_lock(&p->mu);
        j->state=ok?2:3;
        j->result=buffer.data;
        j->result_len=buffer.len;
        j->finished_ms=mj_millis();
        pthread_mutex_unlock(&p->mu);
    }
    if(mysql)mj_mysql_close(mysql);
    if(pg)PQfinish(pg);
    if(sqlite)sqlite3_close(sqlite);
    return NULL;
}
/* Config is NUL-delimited (SQLite path, PG DSN, or MySQL 5 config fields).
   No credentials, SQL or query parameters are logged. */
mj_async_pool *mj_asyncdb_open(int driver,const unsigned char *cfg,size_t cfg_len,int workers,int limit) {
    if(driver<1||driver>3||!cfg||cfg_len<2||cfg_len>8192||
       workers<1||workers>16||limit<workers||limit>MJ_MAX_OUTSTANDING)return NULL;
    int fields=(driver==3)?5:1;
    char *copies[5]={0};
    size_t off=0;
    for(int i=0;i<fields;i++){
        if(off>=cfg_len)goto fail;
        size_t n=0;
        while(n<cfg_len-off && cfg[off+n])n++;
        if(n==0||n>=cfg_len-off)goto fail;
        copies[i]=mj_copy_n((const char *)cfg+off,n);
        if(!copies[i])goto fail;
        off+=n+1;
    }
    if(off!=cfg_len)goto fail;
    if(driver==3) {
        long port=strtol(copies[1],NULL,10);
        if(port<1||port>65535)goto fail;
    }
    mj_async_pool *p=(mj_async_pool *)calloc(1,sizeof(*p));
    if(!p)goto fail;
    if(pthread_mutex_init(&p->mu,NULL)) {free(p);goto fail;}
    if(pthread_cond_init(&p->cv,NULL)){pthread_mutex_destroy(&p->mu);free(p);goto fail;}
    p->driver=driver;p->num_threads=0;p->limit=limit;p->refs=1;
    for(int i=0;i<fields;i++){p->cfg[i]=copies[i];copies[i]=NULL;}
    p->threads=(pthread_t *)calloc((size_t)workers,sizeof(pthread_t));
    if(!p->threads){p->stopping=1;goto close_pool;}
    for(int i=0;i<workers;i++){
        if(pthread_create(&p->threads[i],NULL,mj_worker,p)) {
            p->stopping=1;
            pthread_cond_broadcast(&p->cv);
            goto close_pool;
        }
        p->num_threads++;
    }
    return p;
close_pool:
    for(int i=0;i<p->num_threads;i++)pthread_join(p->threads[i],NULL);
    free(p->threads);
    for(int i=0;i<5;i++)free(p->cfg[i]);
    pthread_cond_destroy(&p->cv);
    pthread_mutex_destroy(&p->mu);
    free(p);
fail:
    for(int i=0;i<5;i++)free(copies[i]);
    return NULL;
}
int mj_asyncdb_retain(mj_async_pool *p) {
    if(!p)return 0;
    pthread_mutex_lock(&p->mu);
    if(p->stopping){pthread_mutex_unlock(&p->mu);return 0;}
    p->refs++;
    pthread_mutex_unlock(&p->mu);
    return 1;
}
void mj_asyncdb_release(mj_async_pool *p) {
    if(!p)return;
    pthread_mutex_lock(&p->mu);
    if(--p->refs>0){pthread_mutex_unlock(&p->mu);return;}
    p->stopping=1;
    pthread_cond_broadcast(&p->cv);
    pthread_mutex_unlock(&p->mu);
    for(int i=0;i<p->num_threads;i++)pthread_join(p->threads[i],NULL);
    mj_async_job *j=p->jobs;
    while(j){mj_async_job *next=j->next;mj_job_free(j);j=next;}
    for(int i=0;i<5;i++)free(p->cfg[i]);
    free(p->threads);
    pthread_cond_destroy(&p->cv);
    pthread_mutex_destroy(&p->mu);
    free(p);
}
uint64_t mj_asyncdb_submit(mj_async_pool *p,const char *sql,
    const unsigned char *packed,size_t packed_size,int nparams) {
    if(!p||!sql||!sql[0]||strlen(sql)>MJ_MAX_SQL||
       nparams<0||nparams>MJ_MAX_PARAM||
       packed_size>MJ_MAX_PARAM_BYTES) return 0;
    mj_async_job *j=(mj_async_job *)calloc(1,sizeof(*j));
    if(!j)return 0;
    j->sql=strdup(sql);
    if(!j->sql)goto fail;
    j->nparams=nparams;
    if(nparams>0){
        if(!packed||packed_size==0)goto fail;
        j->params=(char **)calloc((size_t)nparams,sizeof(char *));
        if(!j->params)goto fail;
        size_t offset=0;
        for(int i=0;i<nparams;i++){
            if(offset>=packed_size)goto fail;
            size_t n=0;
            while(n<packed_size-offset && packed[offset+n])n++;
            if(n>=packed_size-offset)goto fail;
            j->params[i]=mj_copy_n((const char *)packed+offset,n);
            if(!j->params[i])goto fail;
            offset+=n+1;
        }
        if(offset!=packed_size)goto fail;
    } else if(packed_size!=0)goto fail;
    pthread_mutex_lock(&p->mu);
    mj_prune(p);
    if(p->stopping||p->outstanding>=p->limit){pthread_mutex_unlock(&p->mu);goto fail;}
    /* Public job IDs are random and unguessable; never expose sequential
       queue positions, even when an application uses the IDs in HTTP URLs. */
    int unique=0;
    for (int attempt=0;attempt<8 && !unique;attempt++) {
        uint64_t candidate=0;
        if(mj_secure_random(&candidate,sizeof(candidate),0)!=(ssize_t)sizeof(candidate))
            break;
        candidate &= UINT64_C(0x7fffffffffffffff);
        if(!candidate)continue;
        unique=1;
        for(mj_async_job *other=p->jobs;other;other=other->next)
            if(other->id==candidate){unique=0;break;}
        if(unique)j->id=candidate;
    }
    if(!unique){pthread_mutex_unlock(&p->mu);goto fail;}
    j->next=p->jobs;p->jobs=j;
    if(p->back)p->back->queue_next=j;
    else p->front=j;
    p->back=j;
    p->outstanding++;
    pthread_cond_signal(&p->cv);
    pthread_mutex_unlock(&p->mu);
    return j->id;
fail:
    mj_job_free(j);
    return 0;
}
/* 0 queued/running, 1 success, 2 error, -1 unknown or expired. */
int mj_asyncdb_status(mj_async_pool *p,uint64_t id) {
    if(!p||!id)return -1;
    pthread_mutex_lock(&p->mu);
    mj_prune(p);
    int state=-1;
    for(mj_async_job *j=p->jobs;j;j=j->next)if(j->id==id){
        state=j->state==2?1:j->state==3?2:0;break;
    }
    pthread_mutex_unlock(&p->mu);
    return state;
}
/* -1 unknown, 0 pending, 1 success, 2 failed, -2 destination too small.
   On success/error the job is consumed; output always JSON on success. */
int mj_asyncdb_take(mj_async_pool *p,uint64_t id,unsigned char *out,size_t capacity,size_t *length) {
    if(!p||!id||!length)return -1;
    pthread_mutex_lock(&p->mu);
    mj_prune(p);
    mj_async_job **link=&p->jobs;
    while(*link && (*link)->id!=id)link=&(*link)->next;
    if(!*link){pthread_mutex_unlock(&p->mu);return -1;}
    mj_async_job *j=*link;
    if(j->state<2){pthread_mutex_unlock(&p->mu);return 0;}
    *length=j->result_len;
    if(j->state==2 && (!out||capacity<j->result_len+1)){
        pthread_mutex_unlock(&p->mu);return -2;
    }
    int result=j->state==2?1:2;
    if(result==1){memcpy(out,j->result,j->result_len);out[j->result_len]=0;}
    *link=j->next;
    p->outstanding--;
    pthread_mutex_unlock(&p->mu);
    mj_job_free(j);
    return result;
}
int mj_asyncdb_discard(mj_async_pool *p,uint64_t id) {
    if(!p||!id)return -1;
    pthread_mutex_lock(&p->mu);
    mj_async_job **link=&p->jobs;
    while(*link&&(*link)->id!=id)link=&(*link)->next;
    if(!*link){pthread_mutex_unlock(&p->mu);return -1;}
    mj_async_job *j=*link;
    if(j->state<2){pthread_mutex_unlock(&p->mu);return 0;}
    *link=j->next;p->outstanding--;
    pthread_mutex_unlock(&p->mu);mj_job_free(j);return 1;
}
