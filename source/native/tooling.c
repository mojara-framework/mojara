#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Mojara v0.11.1: native Linux OS primitives for the Mojo CLI.
   No shell, system(), popen(), Python or interpreted process supervisor. */
static volatile sig_atomic_t stop_requested = 0;
static void request_stop(int sig) { (void)sig; stop_requested = 1; }

int mj_tool_install_signals(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) || sigaction(SIGTERM, &action, NULL)) return -1;
    signal(SIGPIPE, SIG_IGN);
    return 0;
}
int mj_tool_should_stop(void) { return stop_requested != 0; }
void mj_tool_sleep_ms(int ms) {
    if (ms < 0 || ms > 10000) return;
    struct timespec delay = {ms / 1000, (long)(ms % 1000) * 1000000L};
    while (nanosleep(&delay, &delay) && errno == EINTR && !stop_requested) {}
}

static int allowed_source(const char *name) {
    size_t n = strlen(name);
    if (!strcmp(name, "pixi.toml")) return 1;
    const char *exts[] = {".mojo", ".c", ".h", ".html", ".css", ".js"};
    for (size_t i = 0; i < sizeof(exts)/sizeof(exts[0]); ++i) {
        size_t m = strlen(exts[i]);
        if (n > m && !strcmp(name+n-m, exts[i])) return 1;
    }
    return 0;
}
static uint64_t hash_bytes(uint64_t h, const void *bytes, size_t n) {
    const unsigned char *p = bytes;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= UINT64_C(1099511628211); }
    return h;
}
static uint64_t scan_source(const char *dir, uint64_t h, int only_native, int depth) {
    if (depth > 24) return h;
    DIR *d = opendir(dir);
    if (!d) return hash_bytes(h, "!missing", 8);
    struct dirent *e;
    /* directory enumeration order does not affect sum/xor aggregate */
    uint64_t aggregate = 0;
    while ((e = readdir(d))) {
        const char *name = e->d_name;
        if (!strcmp(name,".") || !strcmp(name,"..") || !strcmp(name,".git") ||
            !strcmp(name,".pixi") || !strcmp(name,".mojara") ||
            !strcmp(name,"benchmarks") || !strcmp(name,"__pycache__")) continue;
        if(depth==0 && !only_native && strcmp(name,"mojara") && strcmp(name,"native") &&
           strcmp(name,"templates") && strcmp(name,"static") &&
           strcmp(name,"assets") && strcmp(name,"app.mojo") &&
           strcmp(name,"pixi.toml")) continue;
        char path[PATH_MAX];
        if (snprintf(path,sizeof(path),"%s/%s",dir,name) >= (int)sizeof(path)) continue;
        struct stat st;
        if (lstat(path,&st)) continue;
        if (S_ISDIR(st.st_mode)) {
            uint64_t child = scan_source(path, UINT64_C(14695981039346656037), only_native, depth+1);
            aggregate += hash_bytes(child,name,strlen(name));
        } else if (S_ISREG(st.st_mode) && allowed_source(name)) {
            uint64_t item = hash_bytes(UINT64_C(14695981039346656037),path,strlen(path));
            item = hash_bytes(item,&st.st_size,sizeof(st.st_size));
            item = hash_bytes(item,&st.st_mtim,sizeof(st.st_mtim));
            aggregate += item;
        }
    }
    closedir(d);
    return hash_bytes(h,&aggregate,sizeof(aggregate));
}
uint64_t mj_tool_snapshot(int native_only) {
    /* Caller runs from project root. Missing native directory also hashes. */
    return scan_source(native_only ? "native" : ".", UINT64_C(14695981039346656037), native_only, 0);
}

/* Every command is exec'd with an argv array; user input is never passed to a shell. */
static int wait_child(pid_t pid) {
    int status = 0;
    while (waitpid(pid,&status,0) == -1) {
        if (errno == EINTR) continue;
        return 127;
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 127;
}
static pid_t spawn(const char *const args[], int blocking) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (!pid) {
        /* Inherit our environment, but don't keep the parent's signal handler. */
        signal(SIGINT,SIG_DFL);
        signal(SIGTERM,SIG_DFL);
        execvp(args[0],(char *const *)args);
        fprintf(stderr,"Mojara: could not launch %s: %s\n",args[0],strerror(errno));
        _exit(127);
    }
    if (blocking) return wait_child(pid);
    return pid;
}
static int mkpath(const char *path) {
    char buf[PATH_MAX];
    if (snprintf(buf,sizeof(buf),"%s",path) >= (int)sizeof(buf)) return -1;
    for (char *p=buf+1; *p; p++) {
        if (*p=='/') { *p=0; if (mkdir(buf,0755) && errno!=EEXIST) return -1; *p='/'; }
    }
    return (mkdir(buf,0755) && errno!=EEXIST) ? -1:0;
}
static int run_gcc(const char *const args[]) { return (int)spawn(args,1); }
static int compile_native(void) {
    if (mkpath(".pixi/envs/default/lib")) return 1;
    const char *metrics[] = {"/usr/bin/gcc","-std=c11","-O2","-fPIC","-Wall","-Wextra","-Werror","-shared","-Wl,-z,nodelete","native/metrics.c","-o",".pixi/envs/default/lib/libmojara_metrics.so",NULL};
    const char *sqlite[] = {"/usr/bin/gcc","-std=c11","-O2","-fPIC","-Wall","-Wextra","-Werror","-shared","-Wl,-z,nodelete","-pthread","-I.pixi/envs/default/include","native/sqlite_read_pool.c","-L.pixi/envs/default/lib","-lsqlite3","-o",".pixi/envs/default/lib/libmojara_sqlitepool.so",NULL};
    if (access("native/metrics.c",R_OK)==0 && run_gcc(metrics)) return 2;
    if (access("native/sqlite_read_pool.c",R_OK)==0 && run_gcc(sqlite)) return 3;
    const char *web[] = {"/usr/bin/gcc","-std=c11","-O2","-fPIC","-Wall","-Wextra","-Werror","-shared","native/web.c","native/multi_upload.c","-o",".pixi/envs/default/lib/libmojara_web.so",NULL};
    if (access("native/web.c",R_OK)==0 && run_gcc(web)) return 4;
    return 0;
}
int mj_tool_prepare_env(void) {
    char cwd[PATH_MAX], combined[PATH_MAX*2];
    if(!getcwd(cwd,sizeof(cwd)))return 1;
    const char *old=getenv("LD_LIBRARY_PATH");
    if(snprintf(combined,sizeof(combined),"%s/.pixi/envs/default/lib%s%s",cwd,
                old&&*old?":":"",old&&*old?old:"")>=(int)sizeof(combined))return 2;
    return setenv("LD_LIBRARY_PATH",combined,1)!=0;
}
int mj_tool_compile_native(void) { return compile_native(); }
int mj_tool_build(const char *out) {
    if (!out || !*out || strlen(out)>PATH_MAX-1) return 2;
    const char *args[]={"mojo","build","-I",".","app.mojo","-o",out,"-Xlinker=-ldl",NULL};
    return (int)spawn(args,1);
}
int mj_tool_start_app(void) {
    const char *args[]={"mojo","-I",".","app.mojo",NULL};
    return (int)spawn(args,1);
}
int mj_tool_format(void) {
    const char *args[]={"mojo","format","app.mojo","mojara",NULL};
    return (int)spawn(args,1);
}
int mj_tool_test(void) {
    DIR *d = opendir("tests");
    if (!d) { fprintf(stderr,"Mojara: no tests/ directory\n"); return 2; }
    char **paths=NULL;
    size_t count=0;
    struct dirent *e;
    while ((e=readdir(d))) {
        size_t n=strlen(e->d_name);
        if (n<=5 || strcmp(e->d_name+n-5,".mojo")) continue;
        char path[PATH_MAX];
        if (snprintf(path,sizeof(path),"tests/%s",e->d_name)>=(int)sizeof(path)) continue;
        char *copy=strdup(path);
        if (!copy) { closedir(d); for(size_t j=0;j<count;j++)free(paths[j]); free(paths); return 2; }
        char **expanded=realloc(paths,(count+1)*sizeof(*paths));
        if (!expanded) { free(copy); closedir(d); for(size_t j=0;j<count;j++)free(paths[j]); free(paths); return 2; }
        paths=expanded;
        paths[count++]=copy;
    }
    closedir(d);
    /* Deterministic test ordering. */
    for (size_t i=0;i<count;i++) for(size_t j=i+1;j<count;j++)
        if(strcmp(paths[i],paths[j])>0){char *tmp=paths[i];paths[i]=paths[j];paths[j]=tmp;}
    int code=0;
    for(size_t i=0;i<count;i++) {
        printf("Mojara test: %s\n",paths[i]);fflush(stdout);
        const char *args[]={"mojo","-I",".",paths[i],NULL};
        code=(int)spawn(args,1);
        if(code) break;
    }
    for(size_t i=0;i<count;i++) free(paths[i]);
    free(paths);
    return code;
}
int mj_tool_command_exists(const char *name) {
    if(!name || !*name || strchr(name,'/'))return 0;
    const char *p=getenv("PATH");if(!p)return 0;
    while(*p){const char *end=strchr(p,':');size_t n=end?(size_t)(end-p):strlen(p);
        char path[PATH_MAX];if(n+strlen(name)+2<sizeof(path)){
            memcpy(path,p,n);path[n]='/';strcpy(path+n+1,name);
            if(access(path,X_OK)==0)return 1;
        }
        if(!end)break;
        p=end+1;
    }
    return 0;
}
int mj_tool_port_available(int port) {
    if(port<1 || port>65535)return 0;
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return 0;
    struct sockaddr_in addr;memset(&addr,0,sizeof(addr));
    addr.sin_family=AF_INET;addr.sin_port=htons((uint16_t)port);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    int yes=(bind(fd,(struct sockaddr*)&addr,sizeof(addr))==0);
    close(fd);return yes;
}
int mj_tool_start_server(const char *path) {
    if(!path || !*path || access(path,X_OK))return -1;
    const char *args[]={path,NULL};
    return (int)spawn(args,0);
}
int mj_tool_process_alive(int pid) {
    if(pid<=1)return 0;
    int status=0;
    pid_t got=waitpid((pid_t)pid,&status,WNOHANG);
    if(got==pid)return 0;
    if(got==-1)return 0;
    return kill((pid_t)pid,0)==0;
}
int mj_tool_stop_server(int pid,int timeout_ms) {
    if(pid<=1 || timeout_ms<50 || timeout_ms>30000)return 2;
    if(kill((pid_t)pid,SIGTERM) && errno!=ESRCH)return 3;
    int step=20;
    for(int elapsed=0;elapsed<=timeout_ms;elapsed+=step){
        if(!mj_tool_process_alive(pid))return 0;
        struct timespec delay={0,step*1000000L};nanosleep(&delay,NULL);
    }
    /* Never kill an unrelated process or force-kill a stuck server. */
    return 4;
}
int mj_tool_swap(const char *candidate,const char *current) {
    if(!candidate || !current || access(candidate,X_OK))return 2;
    if(rename(current,".mojara/dev/previous"))return 3;
    if(rename(candidate,current)) {rename(".mojara/dev/previous",current);return 4;}
    return 0;
}
int mj_tool_restore(const char *current) {
    if(rename(".mojara/dev/previous",current))return 1;
    return 0;
}
int mj_tool_unlink_previous(void){return unlink(".mojara/dev/previous") && errno!=ENOENT;}
int mj_tool_dev_dirs(void){return mkpath(".mojara/dev");}

static int safe_name(const char *name) {
    if(!name)return 0;
    size_t n=strlen(name);
    if(n<1||n>64)return 0;
    for(size_t i=0;i<n;i++) {
        char c=name[i];int alpha=(c>='a'&&c<='z')||(c>='A'&&c<='Z');
        int digit=(c>='0'&&c<='9');
        if(!alpha && (i==0 || (!digit && c!='-' && c!='_')))return 0;
    }return 1;
}
static int copy_file(const char *src,const char *dst) {
    int from=open(src,O_RDONLY|O_NOFOLLOW);if(from<0)return -1;
    struct stat st;if(fstat(from,&st)||!S_ISREG(st.st_mode)){close(from);return -1;}
    int to=open(dst,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,st.st_mode&0777);
    if(to<0){close(from);return -1;}
    char block[32768];ssize_t n;int ok=0;
    while((n=read(from,block,sizeof(block)))>0){ssize_t off=0;
        while(off<n){ssize_t wr=write(to,block+off,(size_t)(n-off));if(wr<=0){ok=-1;break;}off+=wr;}
        if(ok)break;
    }
    if(n<0)ok=-1;
    if(close(to))ok=-1;
    close(from);
    return ok;
}
static int copy_dir(const char *src,const char *dst,int depth) {
    if(depth>25 || mkdir(dst,0755))return -1;
    DIR *d=opendir(src);if(!d)return -1;
    int result=0;struct dirent *ent;
    while((ent=readdir(d))) {
        const char *name=ent->d_name;
        if(!strcmp(name,".")||!strcmp(name,"..")||!strcmp(name,".git")||
           !strcmp(name,".pixi")||!strcmp(name,".mojara"))continue;
        char childsrc[PATH_MAX],childdst[PATH_MAX];
        if(snprintf(childsrc,sizeof(childsrc),"%s/%s",src,name)>=(int)sizeof(childsrc) ||
           snprintf(childdst,sizeof(childdst),"%s/%s",dst,name)>=(int)sizeof(childdst)){result=-1;break;}
        struct stat st;if(lstat(childsrc,&st)){result=-1;break;}
        if(S_ISDIR(st.st_mode))result=copy_dir(childsrc,childdst,depth+1);
        else if(S_ISREG(st.st_mode))result=copy_file(childsrc,childdst);
        else result=-1;
        if(result)break;
    }
    closedir(d);return result;
}
static void discard_tree(const char *path,int depth) {
    if(depth>30)return;
    struct stat st;if(lstat(path,&st))return;
    if(!S_ISDIR(st.st_mode)){unlink(path);return;}
    DIR *d=opendir(path);if(!d)return;
    struct dirent *e;
    while((e=readdir(d)))if(strcmp(e->d_name,".")&&strcmp(e->d_name,"..")){
        char dst[PATH_MAX];if(snprintf(dst,sizeof(dst),"%s/%s",path,e->d_name)<(int)sizeof(dst))discard_tree(dst,depth+1);
    }
    closedir(d);rmdir(path);
}
static int source_root(char *buf,size_t cap) {
    ssize_t n=readlink("/proc/self/exe",buf,cap-1);if(n<0||n>=(ssize_t)(cap-1))return -1;
    buf[n]=0;
    char *slash=strrchr(buf,'/');if(!slash)return -1;*slash=0; /* .mojara/bin */
    slash=strrchr(buf,'/');if(!slash)return -1;*slash=0; /* .mojara */
    slash=strrchr(buf,'/');if(!slash)return -1;*slash=0; /* project */
    return 0;
}
int mj_tool_scaffold(const char *name,int is_api) {
    if(!safe_name(name) || (is_api!=0&&is_api!=1))return 2;
    struct stat target_stat;
    if(lstat(name,&target_stat)==0 || errno!=ENOENT)return 3;
    char root[PATH_MAX];if(source_root(root,sizeof(root)))return 4;
    char staging[PATH_MAX];
    if(snprintf(staging,sizeof(staging),".%s.mojara-XXXXXX",name)>=(int)sizeof(staging))return 2;
    if(!mkdtemp(staging))return 5;
    int status=0;
    const char *dirs[]={"mojara","native","scaffolds","static","templates"};
    for(int i=0;i<5 && !status;i++){
        char src[PATH_MAX],dst[PATH_MAX];
        if(snprintf(src,sizeof(src),"%s/%s",root,dirs[i])>=(int)sizeof(src)||
            snprintf(dst,sizeof(dst),"%s/%s",staging,dirs[i])>=(int)sizeof(dst))status=6;
        else if(copy_dir(src,dst,0))status=6;
    }
    char src[PATH_MAX],dst[PATH_MAX];
    const char *chosen=is_api?"api":"web";
    const char *filenames[]={"app.mojo","pixi.toml","README.md",".gitignore"};
    for(int i=0;i<4&&!status;i++){
        if(snprintf(src,sizeof(src),"%s/scaffolds/%s/%s",root,chosen,filenames[i])>=(int)sizeof(src)||
            snprintf(dst,sizeof(dst),"%s/%s",staging,filenames[i])>=(int)sizeof(dst))status=7;
        else if(copy_file(src,dst))status=7;
    }
    if(!status){
        if(snprintf(dst,sizeof(dst),"%s/.mojara/bin",staging)>=(int)sizeof(dst)||mkpath(dst))status=8;
        if(snprintf(dst,sizeof(dst),"%s/.mojara/native",staging)>=(int)sizeof(dst)||mkpath(dst))status=8;
    }
    if(!status){
        if(snprintf(src,sizeof(src),"%s/.mojara/bin/mojara",root)>=(int)sizeof(src)||
            snprintf(dst,sizeof(dst),"%s/.mojara/bin/mojara",staging)>=(int)sizeof(dst)||copy_file(src,dst))status=9;
        if(snprintf(src,sizeof(src),"%s/.mojara/native/libmojara_tooling.so",root)>=(int)sizeof(src)||
            snprintf(dst,sizeof(dst),"%s/.mojara/native/libmojara_tooling.so",staging)>=(int)sizeof(dst)||copy_file(src,dst))status=9;
    }
    if(!status && rename(staging,name))status=10;
    if(status){discard_tree(staging,0);fprintf(stderr,"Mojara: cannot scaffold project (stage %d)\n",status);}
    return status;
}
