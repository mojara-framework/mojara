#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *mj_sp_open(const char*,int,int);
void mj_sp_close(void*);
int mj_sp_query_one_text(void*,const char*,const char*,char*,int);
int mj_sp_stats(void*,int*,int*,uint64_t*,uint64_t*);
int mj_sp_stats_extended(void*,int*,int*,int*,int*,int*,uint64_t*,uint64_t*,uint64_t*);
int mj_sp_begin_shutdown(void*);
int mj_sp_benchmark_lookup(const char*,int,const char*,const char*,char*,int);

typedef struct { void *pool; int iterations; int passed; } Work;
static void *reader(void *arg) {
    Work *job=(Work *)arg;
    char out[256];
    for (int n=0;n<job->iterations;n++) {
        int code=mj_sp_query_one_text(job->pool,
          "SELECT name FROM items WHERE id = ?", "1", out, sizeof(out));
        if (code!=1 || strcmp(out,"Mojara pooled lookup") != 0) return NULL;
    }
    job->passed=1;
    return NULL;
}
int main(void) {
    char dbname[]="/tmp/mojara-sqlpool-XXXXXX";
    int fd=mkstemp(dbname);
    assert(fd>=0); close(fd);
    sqlite3 *db=NULL;
    assert(sqlite3_open(dbname,&db)==SQLITE_OK);
    assert(sqlite3_exec(db,"CREATE TABLE items(id INTEGER PRIMARY KEY,name TEXT);"
        "INSERT INTO items VALUES(1,'Mojara pooled lookup');",NULL,NULL,NULL)==SQLITE_OK);
    sqlite3_close(db);
    void *pool=mj_sp_open(dbname,2,3000);
    assert(pool);
    char out[256];
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?","1",out,256)==1);
    assert(strcmp(out,"Mojara pooled lookup")==0);
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?","999",out,256)==0);
    assert(mj_sp_query_one_text(pool,"SELECT NULL WHERE ?='1'","1",out,256)==2);
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?","1', DROP TABLE items; --",out,256)==0);
    assert(mj_sp_query_one_text(pool,"DROP TABLE items WHERE id=?","1",out,256)<0);
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?; DROP TABLE items","1",out,256)<0);
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?","1",out,4)==-4);
    enum { THREADS=8, LOOPS=10000 };
    pthread_t threads[THREADS]; Work jobs[THREADS];
    for(int i=0;i<THREADS;i++) {
        jobs[i]=(Work){pool,LOOPS,0};
        assert(pthread_create(&threads[i],NULL,reader,&jobs[i])==0);
    }
    for(int i=0;i<THREADS;i++) {
        assert(pthread_join(threads[i],NULL)==0);
        assert(jobs[i].passed);
    }
    int capacity=0,active=0; uint64_t queries=0,timeouts=0;
    assert(mj_sp_stats(pool,&capacity,&active,&queries,&timeouts)==1);
    assert(capacity==2 && active==0 && timeouts==0);
    assert(queries>=THREADS*LOOPS);
    int waiting=0,peak=0,closing=0;
    uint64_t waits=0;
    assert(mj_sp_stats_extended(pool,&capacity,&active,&waiting,&peak,&closing,
                                &queries,&waits,&timeouts)==1);
    assert(capacity==2 && active==0 && waiting==0 && peak==2 && closing==0);
    assert(mj_sp_begin_shutdown(pool)==1);
    assert(mj_sp_begin_shutdown(pool)==1);
    assert(mj_sp_query_one_text(pool,"SELECT name FROM items WHERE id=?","1",out,256)==-5);
    assert(mj_sp_stats_extended(pool,&capacity,&active,&waiting,&peak,&closing,
                                &queries,&waits,&timeouts)==1);
    assert(closing==1 && active==0);
    mj_sp_close(pool);
    assert(mj_sp_benchmark_lookup(dbname,2,"SELECT name FROM items WHERE id=?","1",out,256)==1);
    assert(strcmp(out,"Mojara pooled lookup")==0);
    assert(mj_sp_benchmark_lookup(dbname,2,"SELECT name FROM items WHERE id=?","1",out,256)==1);
    assert(mj_sp_open("/no/such/file.sqlite",1,200)==NULL);
    unlink(dbname);
    puts("SQLite read-only bounded connection pool concurrency and safety passed.");
    return 0;
}
