#define _GNU_SOURCE
#if defined(__APPLE__)
/* Expose Darwin extensions such as arc4random_buf with POSIX feature macros. */
#define _DARWIN_C_SOURCE 1
#endif
#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <stdlib.h>
#else
#include <sys/random.h>
#endif
#include <fcntl.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <ctype.h>

/* Use the platform's secure random generator for file/session identifiers. */
static ssize_t mj_secure_random(void *buffer, size_t size) {
#if defined(__APPLE__)
    arc4random_buf(buffer, size);
    return (ssize_t)size;
#else
    return getrandom(buffer, size, 0);
#endif
}

/* Small binary-safe filesystem boundary for Mojara. The application supplies
 * trusted directories; client input never becomes a filesystem path. */
static int safe_name(const char *name) {
    size_t n = name ? strnlen(name, 121) : 0;
    if (!n || n > 120 || name[0] == '.') return 0;
    for (size_t i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)name[i];
        if (!(isalnum(c) || c == '.' || c == '-' || c == '_')) return 0;
    }
    return 1;
}

/* Returns 1=success, 0=missing/unsafe, -2=too large. */
int mj_web_read_static(const char *directory, const char *name,
                       unsigned char *out, int64_t capacity, int64_t *length) {
    if (length) *length = 0;
    if (!directory || !safe_name(name) || !out || !length || capacity < 1 ||
        capacity > 32 * 1024 * 1024) return 0;
    int d = open(directory, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    if (d < 0) return 0;
    int f = openat(d, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    close(d);
    if (f < 0) return 0;
    struct stat st;
    if (fstat(f, &st) || !S_ISREG(st.st_mode) || st.st_size < 0) {
        close(f); return 0;
    }
    if (st.st_size > capacity) { close(f); return -2; }
    size_t count = (size_t)st.st_size;
    size_t got = 0;
    while (got < count) {
        ssize_t n = read(f, out + got, count - got);
        if (n <= 0) { close(f); return 0; }
        got += (size_t)n;
    }
    close(f);
    *length = (int64_t)got;
    return 1;
}

static int is_boundary_char(unsigned char c) {
    return isalnum(c) || c == '\'' || c == '(' || c == ')' ||
        c == '+' || c == '_' || c == ',' || c == '-' || c == '.' ||
        c == '/' || c == ':' || c == '=' || c == '?';
}

static int multipart_boundary(const char *content_type, char out[72]) {
    if (!content_type || strncmp(content_type, "multipart/form-data;", 20)) return 0;
    if (strnlen(content_type, 512) == 512) return 0;
    const char *p = strstr(content_type + 20, "boundary=");
    if (!p) return 0;
    p += 9;
    int quoted = (*p == '"');
    if (quoted) ++p;
    size_t n = 0;
    while (*p && ((quoted && *p != '"') || (!quoted && *p != ';' && *p != ' '))) {
        if (n >= 70 || !is_boundary_char((unsigned char)*p)) return 0;
        out[n++] = *p++;
    }
    if (quoted && *p != '"') return 0;
    out[n] = 0;
    return n > 0;
}

static int validate_content_disposition(const unsigned char *start, size_t n) {
    if (n < 48 || n > 4096) return 0;
    char header[4097];
    memcpy(header, start, n);
    header[n] = '\0';
    if (!strstr(header, "Content-Disposition: form-data;")) return 0;
    if (!strstr(header, "name=\"file\"")) return 0;
    const char *fn = strstr(header, "filename=\"");
    if (!fn) return 0;
    fn += 10;
    const char *end = strchr(fn, '"');
    if (!end || end == fn || end - fn > 120) return 0;
    for (const char *p = fn; p < end; ++p) {
        unsigned char c = (unsigned char)*p;
        if (c == '/' || c == '\\' || c < 32 || c == 127) return 0;
    }
    return 1;
}

/* 1=stored, -1=malformed, -2=too large, -3=filesystem/security failure.
 * Only one file part; generated non-executable name; no client filename used. */
int mj_web_store_multipart(const char *directory, const char *content_type,
                           const unsigned char *body, int64_t body_size,
                           int64_t max_file_bytes, char *out_name,
                           int64_t out_name_capacity, int64_t *out_file_bytes) {
    if (out_name && out_name_capacity > 0) out_name[0] = 0;
    if (out_file_bytes) *out_file_bytes = 0;
    if (!directory || !body || !out_name || out_name_capacity < 48 ||
        !out_file_bytes || body_size < 1 || max_file_bytes < 1 || max_file_bytes > 16 * 1024 * 1024)
        return -1;
    if (body_size > max_file_bytes + 8192) return -2;
    char boundary[72];
    if (!multipart_boundary(content_type, boundary)) return -1;
    char opener[76], closer[84];
    int open_len = snprintf(opener, sizeof(opener), "--%s\r\n", boundary);
    int close_len = snprintf(closer, sizeof(closer), "\r\n--%s--\r\n", boundary);
    if (open_len <= 0 || close_len <= 0 || open_len >= (int)sizeof(opener) ||
        close_len >= (int)sizeof(closer)) return -1;
    size_t n = (size_t)body_size;
    if (n < (size_t)open_len + 4 + (size_t)close_len ||
        memcmp(body, opener, (size_t)open_len)) return -1;
    const unsigned char *headers = body + open_len;
    const unsigned char *head_end = memmem(headers, n - (size_t)open_len, "\r\n\r\n", 4);
    if (!head_end || !validate_content_disposition(headers, (size_t)(head_end - headers)))
        return -1;
    const unsigned char *file_start = head_end + 4;
    size_t remains = n - (size_t)(file_start - body);
    const unsigned char *tail = memmem(file_start, remains, closer, (size_t)close_len);
    if (!tail || (size_t)(tail - body) + (size_t)close_len != n) return -1;
    /* Only a single file part is supported. Reject a second delimiter. */
    char next_part[80];
    int part_len = snprintf(next_part, sizeof(next_part), "\r\n--%s\r\n", boundary);
    if (part_len <= 0 || part_len >= (int)sizeof(next_part) ||
        memmem(file_start, (size_t)(tail - file_start), next_part, (size_t)part_len))
        return -1;
    size_t file_size = (size_t)(tail - file_start);
    if (file_size > (size_t)max_file_bytes) return -2;
    int d = open(directory, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    if (d < 0) return -3;
    struct stat dir_stat;
    if (fstat(d, &dir_stat) || dir_stat.st_uid != geteuid() ||
        (dir_stat.st_mode & 0077) != 0) { close(d); return -3; }
    unsigned char random_bytes[16];
    if (mj_secure_random(random_bytes, sizeof(random_bytes)) != sizeof(random_bytes)) {
        close(d); return -3;
    }
    const char hex[] = "0123456789abcdef";
    char generated[48];
    memcpy(generated, "upload-", 7);
    for (int i = 0; i < 16; ++i) {
        generated[7 + i * 2] = hex[random_bytes[i] >> 4];
        generated[8 + i * 2] = hex[random_bytes[i] & 15];
    }
    memcpy(generated + 39, ".bin", 5);
    int f = openat(d, generated, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (f < 0) { close(d); return -3; }
    size_t written = 0;
    while (written < file_size) {
        ssize_t part = write(f, file_start + written, file_size - written);
        if (part <= 0) {
            close(f);
            unlinkat(d, generated, 0);
            close(d);
            return -3;
        }
        written += (size_t)part;
    }
    if (close(f)) { unlinkat(d, generated, 0); close(d); return -3; }
    close(d);
    memcpy(out_name, generated, 44);
    *out_file_bytes = (int64_t)file_size;
    return 1;
}
