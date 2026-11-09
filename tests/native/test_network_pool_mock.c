/* Test-only fake libpq/libmojara_mysql APIs. Never built into production. */
#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>

typedef struct { int ready; } MockConn;
typedef struct { int status, nrows, ncols, is_null, size; char *value; } MockResult;
static MockResult *new_result(int status, int rows, int cols, const char *value) {
    MockResult *r=calloc(1,sizeof(*r));
    if (!r) return NULL;
    r->status=status; r->nrows=rows; r->ncols=cols;
    r->is_null = value==NULL;
    if (value) { r->value=strdup(value); if (!r->value) { free(r); return NULL; } r->size=(int)strlen(value); }
    return r;
}
static void release(MockResult *r) { if (r) { free(r->value); free(r); } }
static MockResult *mock_query(const char *sql, const char *param, int is_pg) {
    if (!sql) return NULL;
    if (strstr(sql,"bad") || (param && strcmp(param,"error")==0)) return NULL;
    if (!param) return new_result(is_pg?1:1,0,0,NULL);
    if (!strcmp(param,"slow")) {
        struct timespec delay={0,160000000L}; nanosleep(&delay,NULL);
    }
    if (!strcmp(param,"none")) return new_result(is_pg?2:1,0,1,NULL);
    if (!strcmp(param,"null")) return new_result(is_pg?2:1,1,1,NULL);
    return new_result(is_pg?2:1,1,1,param);
}

#ifdef MOCK_PG
void *PQconnectdb(const char *dsn) {
    if (!dsn || !dsn[0] || strstr(dsn,"reject")) return NULL;
    return calloc(1,sizeof(MockConn));
}
int PQstatus(void *c) { return c?0:1; }
void PQfinish(void *c) { free(c); }
int PQsetClientEncoding(void *c, const char *v) { return (!c || strcmp(v,"UTF8"))?-1:0; }
void *PQexec(void *c, const char *sql) { return c?mock_query(sql,NULL,1):NULL; }
void *PQexecParams(void *c,const char *sql,int n,const void *types,
                   const char *const *params,const int *lengths,const int *formats,int format) {
    (void)types;(void)lengths;(void)formats;(void)format;
    return c && n==1 && params?mock_query(sql,params[0],1):NULL;
}
int PQresultStatus(void *r) { return r?((MockResult *)r)->status:0; }
int PQntuples(void *r) { return r?((MockResult *)r)->nrows:0; }
int PQnfields(void *r) { return r?((MockResult *)r)->ncols:0; }
int PQgetisnull(void *r,int row,int col) {
    (void)row;(void)col;return ((MockResult *)r)->is_null;
}
char *PQgetvalue(void *r,int row,int col) {
    (void)row;(void)col;return ((MockResult *)r)->value;
}
int PQgetlength(void *r,int row,int col) {
    (void)row;(void)col;return ((MockResult *)r)->size;
}
void PQclear(void *r) { release(r); }
#endif

#ifdef MOCK_MY
void *mj_mysql_open(const char *host,unsigned port,const char *user,
                    const char *password,const char *database) {
    (void)password;
    if (!host || !host[0] || !port || !user || !database || strstr(host,"reject")) return NULL;
    return calloc(1,sizeof(MockConn));
}
void mj_mysql_close(void *c) { free(c); }
int mj_mysql_enable_readonly(void *c) { return c?1:0; }
void *mj_mysql_query_flat(void *c,const char *sql,const unsigned char *packed,size_t n,int count) {
    if (!c) return NULL;
    if (count==0 && n==0) return mock_query(sql,NULL,0);
    if (count!=1 || !packed || n==0 || packed[n-1]!=0 ||
        strlen((const char *)packed)+1!=n) return NULL;
    return mock_query(sql,(const char *)packed,0);
}
void mj_mysql_free(void *r) { release(r); }
size_t mj_mysql_rows(void *r) { return r?(size_t)((MockResult *)r)->nrows:0; }
size_t mj_mysql_cols(void *r) { return r?(size_t)((MockResult *)r)->ncols:0; }
int mj_mysql_is_null(void *r,size_t row,size_t col) {
    (void)row;(void)col;return ((MockResult *)r)->is_null;
}
const char *mj_mysql_cell(void *r,size_t row,size_t col) {
    (void)row;(void)col;return ((MockResult *)r)->value;
}
#endif
