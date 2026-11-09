#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

void *mj_np_open(int,const unsigned char *,size_t,int,int);
int mj_np_query_one_text(void *,const char *,const char *,char *,int);
int mj_np_begin_shutdown(void *);
void mj_np_close(void *);
int mj_np_stats(void *,uint64_t *,int);
int mj_np_test_hold(void *,int);

typedef struct {void *p; int rc;} worker;
static void *hold_thread(void *v) {
    worker *w=v; w->rc=mj_np_test_hold(w->p,160); return NULL;
}
static void test_pool(int driver) {
    const char pg_cfg[]={"host=mock"};
    const char my_cfg[]={"host" "\0" "3306" "\0" "user" "\0" "" "\0" "db"};
    const unsigned char *cfg=(const unsigned char *)(driver==1?pg_cfg:my_cfg);
    size_t cfg_len=driver==1?sizeof(pg_cfg):sizeof(my_cfg);
    void *p=mj_np_open(driver,cfg,cfg_len,1,35);
    assert(p);
    const char *sql=driver==1?"SELECT $1":"SELECT ?";
    char result[128];
    assert(mj_np_query_one_text(p,sql,"O'Brien",result,sizeof(result))==1);
    assert(strcmp(result,"O'Brien")==0);
    assert(mj_np_query_one_text(p,sql,"none",result,sizeof(result))==0);
    assert(mj_np_query_one_text(p,sql,"null",result,sizeof(result))==2);
    assert(mj_np_query_one_text(p,sql,"error",result,sizeof(result))==-3);
    assert(mj_np_query_one_text(p,"DELETE FROM users WHERE id=?","1",result,sizeof(result))==-1);
    assert(mj_np_query_one_text(p,"SELECT ?; DROP TABLE t","1",result,sizeof(result))==-1);
    assert(mj_np_query_one_text(p,sql,"some long text",result,4)==-4);
    worker w={p,0};pthread_t t;
    assert(pthread_create(&t,NULL,hold_thread,&w)==0);
    struct timespec delay={0,20000000L};nanosleep(&delay,NULL);
    assert(mj_np_query_one_text(p,sql,"timeout",result,sizeof(result))==-2);
    uint64_t stats[9]={0};
    assert(mj_np_stats(p,stats,9)==1);
    assert(stats[0]==1 && stats[3]==1 && stats[7]>=1);
    assert(pthread_join(t,NULL)==0);
    assert(w.rc==1);
    assert(mj_np_begin_shutdown(p)==1);
    assert(mj_np_query_one_text(p,sql,"closed",result,sizeof(result))==-5);
    assert(mj_np_stats(p,stats,9)==1);
    assert(stats[4]==1 && stats[1]==0 && stats[5]>=6 && stats[8]>=2);
    mj_np_close(p);
}
int main(void) {
    assert(!mj_np_open(1,(const unsigned char *)"",1,2,100));
    assert(!mj_np_open(1,(const unsigned char *)"a",1,2,100));
    assert(!mj_np_open(2,(const unsigned char *)"a\0b",4,2,100));
    assert(!mj_np_open(1,(const unsigned char *)"test",5,17,100));
    test_pool(1);test_pool(2);
    puts("Mojara mocked PostgreSQL/MySQL bounded read pool concurrency and safety passed.");
    return 0;
}
