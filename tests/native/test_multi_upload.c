#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern int mj_web_store_multipart_multi(const char *, const char *, const unsigned char *,
    int64_t, int64_t, int64_t, int64_t, const char *, char *, int64_t,
    int64_t *, char *, int64_t, int64_t *);

static char names[32][64], mimes[32][128];
static int64_t sizes[32], count;
static char directory[128];
static const char *ct = "multipart/form-data; charset=utf-8; boundary=MojoMulti12";

static int upload(const unsigned char *data, size_t n, int64_t per_file,
    int64_t total, int64_t files, const char *allowed) {
    memset(names, 0, sizeof(names));
    memset(mimes, 0, sizeof(mimes));
    memset(sizes, 0, sizeof(sizes));
    count = -1;
    return mj_web_store_multipart_multi(directory, ct, data, (int64_t)n,
        per_file, total, files, allowed, &names[0][0], sizeof(names[0]),
        sizes, &mimes[0][0], sizeof(mimes[0]), &count);
}

static void require_file(const char *name, const unsigned char *expected, size_t n) {
    char path[256];
    assert(strncmp(name, "upload-", 7) == 0 && strlen(name) == 43);
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    struct stat st;
    assert(stat(path, &st) == 0 && S_ISREG(st.st_mode));
    assert((st.st_mode & 0777) == 0600 && (size_t)st.st_size == n);
    int f = open(path, O_RDONLY);
    assert(f >= 0);
    unsigned char *buffer = malloc(n ? n : 1);
    assert(buffer);
    if (n) assert(read(f, buffer, n) == (ssize_t)n && memcmp(buffer, expected, n) == 0);
    free(buffer);
    close(f);
}

static int count_files(void) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "find '%s' -maxdepth 1 -type f | wc -l", directory);
    FILE *p = popen(cmd, "r");
    assert(p);
    int n = -1;
    assert(fscanf(p, "%d", &n) == 1);
    assert(pclose(p) == 0);
    return n;
}

int main(void) {
    strcpy(directory, "/tmp/mojara-multi-upload-XXXXXX");
    assert(mkdtemp(directory));
    assert(chmod(directory, 0700) == 0);
    static const unsigned char binary[] = {0, 255, 'A', '\r', '\n', '-', '-', 'M', 'o', 'j', 'o',
        'M', 'u', 'l', 't', 'i', '1', '2', 'X', '\r', '\n', 10, 0};
    static const char part1[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"documents\"; filename=\"document.pdf\"\r\nContent-Type: application/pdf\r\n\r\nPDF contents\r\n";
    static const char part2[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"documents\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\n";
    static const char part3[] = "\r\n--MojoMulti12\r\nContent-Disposition: form-data; name=\"documents\"; filename=\"archive.zip\"\r\nContent-Type: application/zip\r\n\r\nPKzip\r\n--MojoMulti12--\r\n";
    unsigned char body[4096];
    size_t n = 0;
#define APPEND(P,N) do { assert(n + (N) <= sizeof(body)); memcpy(body+n,(P),(N)); n+=(N); } while(0)
    APPEND(part1,sizeof(part1)-1);
    APPEND(part2,sizeof(part2)-1);
    APPEND(binary,sizeof(binary));
    APPEND(part3,sizeof(part3)-1);
    assert(upload(body,n,1024,4096,5,"application/pdf,image/*,application/zip") == 1);
    assert(count == 3);
    assert(sizes[0] == 12 && sizes[1] == (int64_t)sizeof(binary) && sizes[2] == 5);
    assert(strcmp(mimes[0],"application/pdf") == 0);
    assert(strcmp(mimes[1],"image/png") == 0);
    assert(strcmp(mimes[2],"application/zip") == 0);
    assert(strcmp(names[0],names[1]) && strcmp(names[1],names[2]));
    require_file(names[0],(const unsigned char*)"PDF contents",12);
    require_file(names[1],binary,sizeof(binary));
    require_file(names[2],(const unsigned char*)"PKzip",5);
    assert(count_files() == 3);
    for (int i = 0; i < 3; ++i) {
        char path[256];
        snprintf(path,sizeof(path),"%s/%.63s",directory,names[i]);
        assert(unlink(path) == 0);
    }
    assert(count_files() == 0);
    assert(upload(body,n,1024,4096,5,"image/png") == -5 && count == 0);
    assert(upload(body,n,1024,4096,2,"") == -4 && count == 0);
    assert(upload(body,n,1024,20,5,"") == -2 && count == 0);
    assert(upload(body,n,2,4096,5,"") == -2 && count == 0);
    assert(count_files() == 0);

    static const char malicious[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"documents\"; filename=\"../../passwd\"\r\n\r\nX\r\n--MojoMulti12--\r\n";
    assert(upload((const unsigned char*)malicious,strlen(malicious),1024,4096,5,"") == -1);
    static const char missing_filename[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"message\"\r\n\r\nhello\r\n--MojoMulti12--\r\n";
    assert(upload((const unsigned char*)missing_filename,strlen(missing_filename),1024,4096,5,"") == -1);
    static const char bad_end[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a\"\r\n\r\na\r\n--MojoMulti12--\r\nextra";
    assert(upload((const unsigned char*)bad_end,strlen(bad_end),1024,4096,5,"") == -1);
    assert(count_files() == 0);

    /* Reject writable/public storage even though the request is otherwise valid. */
    assert(chmod(directory, 0755) == 0);
    assert(upload(body,n,1024,4096,5,"") == -3);
    assert(count_files() == 0);
    assert(chmod(directory,0700) == 0);

    /* Empty content with a valid filename is a valid file, not a missing part. */
    static const char empty_file[] = "--MojoMulti12\r\nContent-Disposition: form-data; name=\"documents\"; filename=\"empty.txt\"\r\n\r\n\r\n--MojoMulti12--\r\n";
    assert(upload((const unsigned char*)empty_file,strlen(empty_file),1024,4096,5,"") == 1);
    assert(count == 1 && sizes[0] == 0);
    require_file(names[0],(const unsigned char*)"",0);
    char empty_path[256];
    snprintf(empty_path,sizeof(empty_path),"%s/%s",directory,names[0]);
    assert(unlink(empty_path) == 0);
    assert(rmdir(directory) == 0);
    puts("Mojara atomic multi-upload parsing, MIME policy, binary payload and storage tests passed.");
}
