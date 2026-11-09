#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

extern int mj_web_read_static(const char*,const char*,unsigned char*,int64_t,int64_t*);
extern int mj_web_store_multipart(const char*,const char*,const unsigned char*,int64_t,int64_t,char*,int64_t,int64_t*);

int main(void) {
    char workspace[]="/tmp/mojara-web-regression-XXXXXX";
    assert(mkdtemp(workspace));
    char path[512]; snprintf(path,sizeof(path),"%s/a.txt",workspace);
    int f=open(path,O_CREAT|O_WRONLY|O_EXCL,0600);assert(f>=0);
    assert(write(f,"Hello",5)==5);close(f);
    unsigned char buf[128]={0};int64_t got=-1;
    assert(mj_web_read_static(workspace,"a.txt",buf,128,&got)==1);
    assert(got==5 && memcmp(buf,"Hello",5)==0);
    assert(mj_web_read_static(workspace,"../a.txt",buf,128,&got)==0);
    assert(mj_web_read_static(workspace,".secret",buf,128,&got)==0);
    assert(mj_web_read_static(workspace,"a.txt",buf,2,&got)==-2);
    char evil[512];snprintf(evil,sizeof(evil),"%s/evil.txt",workspace);
    assert(symlink("/etc/passwd",evil)==0);
    assert(mj_web_read_static(workspace,"evil.txt",buf,128,&got)==0);
    const char *body="--boundary_123\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello world\r\n--boundary_123--\r\n";
    char saved[64]; int64_t file_bytes=0;
    int result=mj_web_store_multipart(workspace,"multipart/form-data; boundary=boundary_123",(const unsigned char*)body,(int64_t)strlen(body),1024,saved,sizeof(saved),&file_bytes);
    assert(result==1 && file_bytes==11);
    assert(strncmp(saved,"upload-",7)==0 && strstr(saved,".bin"));
    char generated_path[512];snprintf(generated_path,sizeof(generated_path),"%s/%s",workspace,saved);
    struct stat st;assert(stat(generated_path,&st)==0 && S_ISREG(st.st_mode));
    assert((st.st_mode&0777)==0600 && st.st_size==11);
    assert(mj_web_store_multipart(workspace,"multipart/form-data; boundary=boundary_123",(const unsigned char*)body,(int64_t)strlen(body),3,saved,sizeof(saved),&file_bytes)==-2);
    const char *bad="--boundary_123\r\nContent-Disposition: form-data; name=\"file\"; filename=\"../../evil\"\r\n\r\nbad\r\n--boundary_123--\r\n";
    assert(mj_web_store_multipart(workspace,"multipart/form-data; boundary=boundary_123",(const unsigned char*)bad,(int64_t)strlen(bad),1024,saved,sizeof(saved),&file_bytes)==-1);
    const char *multi="--boundary_123\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a\"\r\n\r\nhi\r\n--boundary_123\r\nContent-Disposition: form-data; name=\"file\"; filename=\"b\"\r\n\r\nno\r\n--boundary_123--\r\n";
    assert(mj_web_store_multipart(workspace,"multipart/form-data; boundary=boundary_123",(const unsigned char*)multi,(int64_t)strlen(multi),1024,saved,sizeof(saved),&file_bytes)==-1);
    unlink(generated_path);unlink(evil);unlink(path);rmdir(workspace);
    puts("Mojara static and private multipart upload regression passed.");
}
