#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#if defined(__APPLE__)
#include <stdlib.h>
#else
#include <sys/random.h>
#endif
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/* Use the platform's secure random generator for file/session identifiers. */
static ssize_t mj_secure_random(void *buffer, size_t size) {
#if defined(__APPLE__)
    arc4random_buf(buffer, size);
    return (ssize_t)size;
#else
    return getrandom(buffer, size, 0);
#endif
}

/* Binary-safe, all-or-nothing multipart/form-data upload for Mojara.
 * Callers own the bounded input and output buffers. No client-provided name
 * is ever used as a storage path. This parser deliberately rejects nested
 * multipart parts and unknown Content-Transfer-Encoding encodings.
 *
 * Return codes: 1 success, -1 malformed, -2 size exceeded,
 * -3 storage error, -4 file-count exceeded, -5 MIME policy rejected.
 */
#define MJ_MAX_FILES 32
#define MJ_MAX_ONE (64LL * 1024 * 1024)
#define MJ_MAX_TOTAL (128LL * 1024 * 1024)
#define MJ_HEADER_LIMIT 8192
#define MJ_NAME_SLOT 64
#define MJ_MIME_SLOT 128

typedef struct {
    const unsigned char *data;
    size_t size;
    char mime[MJ_MIME_SLOT];
} mj_part;

static int boundary_character(unsigned char c) {
    return isalnum(c) || c == '\'' || c == '(' || c == ')' || c == '+' ||
           c == '_' || c == ',' || c == '-' || c == '.' || c == '/' ||
           c == ':' || c == '=' || c == '?';
}

static const char *space(const char *p) {
    while (*p == ' ' || *p == '\t') ++p;
    return p;
}

static int parse_boundary(const char *content_type, char out[72]) {
    if (!content_type || strnlen(content_type, 1024) >= 1024) return 0;
    const char *p = space(content_type);
    if (strncasecmp(p, "multipart/form-data", 19) != 0) return 0;
    p += 19;
    p = space(p);
    if (*p != ';') return 0;
    int found = 0;
    while (*p) {
        if (*p++ != ';') return 0;
        p = space(p);
        const char *key = p;
        while (isalnum((unsigned char)*p) || *p == '-' || *p == '_') ++p;
        size_t key_len = (size_t)(p - key);
        p = space(p);
        if (!key_len || *p++ != '=') return 0;
        p = space(p);
        int quoted = (*p == '"');
        if (quoted) ++p;
        const char *value = p;
        while (*p && (quoted ? (*p != '"') : (*p != ';' && *p != ' ' && *p != '\t'))) ++p;
        size_t value_len = (size_t)(p - value);
        if (quoted && *p++ != '"') return 0;
        p = space(p);
        if (*p && *p != ';') return 0;
        if (key_len == 8 && strncasecmp(key, "boundary", 8) == 0) {
            if (found || !value_len || value_len > 70) return 0;
            for (size_t i = 0; i < value_len; ++i) {
                if (!boundary_character((unsigned char)value[i])) return 0;
            }
            memcpy(out, value, value_len);
            out[value_len] = '\0';
            found = 1;
        }
    }
    return found;
}

static int header_token(unsigned char c) {
    return isalnum(c) || c == '!' || c == '#' || c == '$' || c == '%' ||
           c == '&' || c == '\'' || c == '*' || c == '+' || c == '-' ||
           c == '.' || c == '^' || c == '_' || c == '`' || c == '|' || c == '~';
}

static int parse_disposition(const char *value) {
    const char *p = space(value);
    if (strncasecmp(p, "form-data", 9) != 0) return 0;
    p += 9;
    p = space(p);
    int has_name = 0, has_filename = 0;
    while (*p) {
        if (*p++ != ';') return 0;
        p = space(p);
        const char *key = p;
        while (header_token((unsigned char)*p)) ++p;
        size_t key_len = (size_t)(p - key);
        p = space(p);
        if (!key_len || *p++ != '=') return 0;
        p = space(p);
        int quoted = *p == '"';
        if (quoted) ++p;
        const char *start = p;
        while (*p && (quoted ? (*p != '"') : (*p != ';' && *p != ' ' && *p != '\t'))) {
            unsigned char c = (unsigned char)*p;
            if (c == '\\' || c == '/' || c < 32 || c == 127) {
                if (key_len == 8 && strncasecmp(key, "filename", 8) == 0) return 0;
            }
            ++p;
        }
        size_t value_len = (size_t)(p - start);
        if (quoted && *p++ != '"') return 0;
        p = space(p);
        if (*p && *p != ';') return 0;
        if (key_len == 4 && strncasecmp(key, "name", 4) == 0) {
            if (has_name || !value_len || value_len > 120) return 0;
            has_name = 1;
        } else if (key_len == 8 && strncasecmp(key, "filename", 8) == 0) {
            if (has_filename || !value_len || value_len > 255) return 0;
            has_filename = 1;
        }
    }
    return has_name && has_filename;
}

static int validate_mime(char *out, const char *value) {
    const char *p = space(value);
    size_t n = 0;
    int slashes = 0;
    while (*p && *p != ';' && *p != ' ' && *p != '\t') {
        unsigned char c = (unsigned char)*p++;
        if (c == '/') ++slashes;
        else if (!(isalnum(c) || c == '-' || c == '+' || c == '.' || c == '_')) return 0;
        if (++n >= MJ_MIME_SLOT) return 0;
        out[n-1] = (char)tolower(c);
    }
    out[n] = '\0';
    return n >= 3 && slashes == 1 && out[0] != '/' && out[n - 1] != '/';
}

static int parse_headers(const unsigned char *start, size_t length, char mime[MJ_MIME_SLOT]) {
    if (!length || length > MJ_HEADER_LIMIT) return 0;
    for (size_t i = 0; i < length; ++i) {
        unsigned char c = start[i];
        if (c == 0 || c == 127 || (c < 32 && c != '\r' && c != '\n' && c != '\t')) return 0;
    }
    int disposition = 0, content_type = 0;
    strcpy(mime, "application/octet-stream");
    size_t offset = 0;
    while (offset < length) {
        const unsigned char *end = memmem(start + offset, length - offset, "\r\n", 2);
        size_t n = end ? (size_t)(end - (start + offset)) : length - offset;
        if (!n || n >= MJ_HEADER_LIMIT) return 0;
        char line[MJ_HEADER_LIMIT + 1];
        memcpy(line, start + offset, n);
        line[n] = '\0';
        char *colon = strchr(line, ':');
        if (!colon) return 0;
        *colon = '\0';
        const char *value = space(colon + 1);
        if (strcasecmp(line, "Content-Disposition") == 0) {
            if (disposition++ || !parse_disposition(value)) return 0;
        } else if (strcasecmp(line, "Content-Type") == 0) {
            if (content_type++ || !validate_mime(mime, value)) return 0;
        } else if (strcasecmp(line, "Content-Transfer-Encoding") == 0) {
            /* No transformation is performed. Encoded multipart uploads
             * are not accepted as already-decoded binary file data. */
            return 0;
        }
        offset += n + (end ? 2 : 0);
    }
    return disposition == 1;
}

static int mime_allowed(const char *mime, const char *policy) {
    if (!policy || !*policy) return 1;
    if (strnlen(policy, 1025) >= 1025) return 0;
    const char *p = policy;
    while (*p) {
        p = space(p);
        const char *begin = p;
        while (*p && *p != ',') ++p;
        const char *end = p;
        while (end > begin && (end[-1] == ' ' || end[-1] == '\t')) --end;
        size_t n = (size_t)(end - begin);
        if (n && n < MJ_MIME_SLOT) {
            size_t mlen = strlen(mime);
            if (n == mlen && strncasecmp(begin, mime, n) == 0) return 1;
            if (n >= 3 && begin[n-1] == '*' && begin[n-2] == '/' &&
                strncasecmp(begin, mime, n-1) == 0) return 1;
        }
        if (*p == ',') ++p;
    }
    return 0;
}

/* Returns next valid MIME boundary, ignoring boundary-like binary payloads. */
static const unsigned char *next_boundary(const unsigned char *from,
                                           const unsigned char *end,
                                           const char *delimiter, size_t delimiter_len) {
    while (from < end) {
        const unsigned char *candidate = memmem(from, (size_t)(end-from),
                                                  delimiter, delimiter_len);
        if (!candidate) return NULL;
        const unsigned char *suffix = candidate + delimiter_len;
        if (end-suffix >= 2 && ((suffix[0] == '\r' && suffix[1] == '\n') ||
                                (suffix[0] == '-' && suffix[1] == '-'))) return candidate;
        from = candidate + 1;
    }
    return NULL;
}

static int generated_file(int d, char name[48]) {
    static const char hex[] = "0123456789abcdef";
    for (int tries = 0; tries < 5; ++tries) {
        unsigned char random[16];
        if (mj_secure_random(random, sizeof(random)) != (ssize_t)sizeof(random)) return -1;
        memcpy(name, "upload-", 7);
        for (int i = 0; i < 16; ++i) {
            name[7 + 2*i] = hex[random[i] >> 4];
            name[8 + 2*i] = hex[random[i] & 15];
        }
        memcpy(name + 39, ".bin", 5);
        int fd = openat(d, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (fd >= 0) return fd;
        if (errno != EEXIST) return -1;
    }
    return -1;
}

int mj_web_store_multipart_multi(
    const char *directory, const char *content_type,
    const unsigned char *body, int64_t body_size,
    int64_t max_file_bytes, int64_t max_total_bytes, int64_t max_files,
    const char *allowed_mimes,
    char *out_names, int64_t name_stride, int64_t *out_sizes,
    char *out_mimes, int64_t mime_stride, int64_t *out_count
) {
    if (out_count) *out_count = 0;
    if (!directory || !body || !out_names || !out_sizes || !out_mimes || !out_count ||
        body_size <= 0 || max_file_bytes < 1 || max_file_bytes > MJ_MAX_ONE ||
        max_total_bytes < 1 || max_total_bytes > MJ_MAX_TOTAL ||
        max_files < 1 || max_files > MJ_MAX_FILES ||
        name_stride < MJ_NAME_SLOT || mime_stride < MJ_MIME_SLOT) return -1;
    if (body_size > max_total_bytes + max_files * (MJ_HEADER_LIMIT + 128) + 128) return -2;
    char boundary[72];
    if (!parse_boundary(content_type, boundary)) return -1;
    char open_delim[76], next_delim[76];
    int olen = snprintf(open_delim, sizeof(open_delim), "--%s\r\n", boundary);
    int dlen = snprintf(next_delim, sizeof(next_delim), "\r\n--%s", boundary);
    if (olen <= 0 || dlen <= 0 || olen >= (int)sizeof(open_delim) ||
        dlen >= (int)sizeof(next_delim)) return -1;
    const unsigned char *end = body + (size_t)body_size;
    if (end - body < olen || memcmp(body, open_delim, (size_t)olen) != 0) return -1;
    const unsigned char *p = body + olen;
    mj_part *parts = calloc((size_t)max_files, sizeof(*parts));
    if (!parts) return -3;
    size_t payload_total = 0;
    int64_t count = 0;
    int result = -1;
    for (;;) {
        if (count >= max_files) { result = -4; goto done; }
        const unsigned char *head_end = memmem(p, (size_t)(end - p), "\r\n\r\n", 4);
        if (!head_end || head_end - p > MJ_HEADER_LIMIT) goto done;
        if (!parse_headers(p, (size_t)(head_end - p), parts[count].mime)) goto done;
        if (!mime_allowed(parts[count].mime, allowed_mimes)) { result = -5; goto done; }
        const unsigned char *start = head_end + 4;
        const unsigned char *delimiter = next_boundary(start, end, next_delim, (size_t)dlen);
        if (!delimiter) goto done;
        size_t file_size = (size_t)(delimiter - start);
        if (file_size > (size_t)max_file_bytes || file_size > (size_t)max_total_bytes - payload_total) {
            result = -2; goto done;
        }
        parts[count].data = start;
        parts[count].size = file_size;
        payload_total += file_size;
        ++count;
        p = delimiter + dlen;
        if (end - p < 2) goto done;
        if (p[0] == '-' && p[1] == '-') {
            p += 2;
            if (p == end || (end - p == 2 && p[0] == '\r' && p[1] == '\n')) break;
            goto done;
        }
        if (p[0] != '\r' || p[1] != '\n') goto done;
        p += 2;
    }
    if (!count) goto done;
    int d = open(directory, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
    if (d < 0) { result = -3; goto done; }
    struct stat st;
    if (fstat(d, &st) != 0 || !S_ISDIR(st.st_mode) ||
        st.st_uid != geteuid() || (st.st_mode & 0077) != 0) {
        close(d); result = -3; goto done;
    }
    char created[MJ_MAX_FILES][48] = {{0}};
    int64_t created_count = 0;
    result = 1;
    for (int64_t i = 0; i < count; ++i) {
        char name[48] = {0};
        int fd = generated_file(d, name);
        if (fd < 0) { result = -3; break; }
        /* Record the path immediately so failures while writing can unlink it. */
        memcpy(created[i], name, sizeof(name));
        ++created_count;
        size_t written = 0;
        while (written < parts[i].size) {
            ssize_t n = write(fd, parts[i].data + written, parts[i].size - written);
            if (n <= 0) { result = -3; break; }
            written += (size_t)n;
        }
        if (close(fd) != 0) result = -3;
        if (result != 1) break;
        memcpy(out_names + i * name_stride, name, 44);
        out_sizes[i] = (int64_t)parts[i].size;
        size_t mn = strlen(parts[i].mime);
        memcpy(out_mimes + i * mime_stride, parts[i].mime, mn + 1);
    }
    if (result != 1) {
        for (int64_t i = 0; i < created_count; ++i) unlinkat(d, created[i], 0);
        for (int64_t i = 0; i < count; ++i) {
            out_names[i * name_stride] = 0;
            out_mimes[i * mime_stride] = 0;
            out_sizes[i] = 0;
        }
    } else {
        *out_count = count;
    }
    close(d);
done:
    free(parts);
    return result;
}


/* Small Mojo FFI surface for atomic uploads. Passing the 14-argument parser
 * entrypoint directly from Mojo can mis-handle the stacked C ABI arguments.
 * All output fits into one caller-owned, length-checked byte array:
 *   byte 0: count (0..32)
 *   bytes 8 + i*200: 64-byte NUL-terminated generated name
 *   bytes 72 + i*200: 128-byte NUL-terminated MIME
 *   bytes 200 + i*200: uint64 file length, little-endian
 * No raw user filename is written to this buffer.
 */
int mj_web_store_multipart_multi_compact(
    const char *directory, const char *content_type,
    const unsigned char *body, int64_t body_size,
    const int64_t *limits, const char *allowed_mimes,
    unsigned char *result, int64_t result_capacity
) {
    if (!limits || !result) return -1;
    const int64_t max_file_bytes = limits[0];
    const int64_t max_total_bytes = limits[1];
    const int64_t max_files = limits[2];
    if (max_files < 1 || max_files > MJ_MAX_FILES ||
        result_capacity < 8 + 200 * max_files) return -1;
    memset(result, 0, (size_t)(8 + 200 * max_files));
    char names[MJ_MAX_FILES][MJ_NAME_SLOT] = {{0}};
    char mimes[MJ_MAX_FILES][MJ_MIME_SLOT] = {{0}};
    int64_t sizes[MJ_MAX_FILES] = {0};
    int64_t count = 0;
    int status = mj_web_store_multipart_multi(
        directory, content_type, body, body_size,
        max_file_bytes, max_total_bytes, max_files, allowed_mimes,
        &names[0][0], MJ_NAME_SLOT, sizes,
        &mimes[0][0], MJ_MIME_SLOT, &count);
    if (status != 1) return status;
    if (count <= 0 || count > max_files) return -3;
    result[0] = (unsigned char)count;
    for (int64_t i = 0; i < count; ++i) {
        size_t offset = 8 + (size_t)i * 200;
        memcpy(result + offset, names[i], MJ_NAME_SLOT);
        memcpy(result + offset + MJ_NAME_SLOT, mimes[i], MJ_MIME_SLOT);
        uint64_t length = (uint64_t)sizes[i];
        for (int j = 0; j < 8; ++j) {
            result[offset + 192 + (size_t)j] = (unsigned char)(length & 255);
            length >>= 8;
        }
    }
    return 1;
}

/* Inline control and output buffer: 6-argument x86_64 SysV ABI bridge.
 * Layout is documented in mojara/web.mojo. All offsets and capacity are
 * checked before reading configuration or writing output. Preserve the
 * earlier compact function for backward compatibility.
 *
 * The buffer includes a fixed 1025-byte zero-terminated allowlist and
 * enough result space for the protocol maximum of 32 files. The caller
 * supplies a capacity, so the bridge does not infer it from a pointer.
 */
int mj_web_store_multipart_multi_inline(
    const char *directory, const char *content_type,
    const unsigned char *body, int64_t body_size,
    unsigned char *control_and_result, int64_t capacity
) {
    enum { HEADER_SIZE = 24, POLICY_SIZE = 1025,
           OUTPUT_OFFSET = HEADER_SIZE + POLICY_SIZE,
           OUTPUT_SIZE = 8 + 200 * MJ_MAX_FILES,
           BUFFER_SIZE = OUTPUT_OFFSET + OUTPUT_SIZE };
    if (!control_and_result || capacity < BUFFER_SIZE) return -1;
    int64_t limits[3];
    for (int i = 0; i < 3; ++i) {
        uint64_t value = 0;
        for (int j = 0; j < 8; ++j) {
            value |= (uint64_t)control_and_result[i * 8 + j] << (j * 8);
        }
        if (value > INT64_MAX) return -1;
        limits[i] = (int64_t)value;
    }
    if (limits[0] < 1 || limits[0] > MJ_MAX_ONE ||
        limits[1] < 1 || limits[1] > MJ_MAX_TOTAL ||
        limits[2] < 1 || limits[2] > MJ_MAX_FILES) return -1;
    const char *policy = (const char *)(control_and_result + HEADER_SIZE);
    if (!memchr(policy, 0, POLICY_SIZE)) return -1;
    unsigned char *result = control_and_result + OUTPUT_OFFSET;
    memset(result, 0, OUTPUT_SIZE);
    char names[MJ_MAX_FILES][MJ_NAME_SLOT] = {{0}};
    char mimes[MJ_MAX_FILES][MJ_MIME_SLOT] = {{0}};
    int64_t sizes[MJ_MAX_FILES] = {0};
    int64_t count = 0;
    int status = mj_web_store_multipart_multi(
        directory, content_type, body, body_size,
        limits[0], limits[1], limits[2], policy,
        &names[0][0], MJ_NAME_SLOT, sizes,
        &mimes[0][0], MJ_MIME_SLOT, &count);
    if (status != 1) return status;
    if (count <= 0 || count > limits[2]) return -3;
    result[0] = (unsigned char)count;
    for (int64_t i = 0; i < count; ++i) {
        size_t offset = 8 + (size_t)i * 200;
        memcpy(result + offset, names[i], MJ_NAME_SLOT);
        memcpy(result + offset + MJ_NAME_SLOT, mimes[i], MJ_MIME_SLOT);
        uint64_t length = (uint64_t)sizes[i];
        for (int j = 0; j < 8; ++j) {
            result[offset + 192 + (size_t)j] = (unsigned char)(length & 255);
            length >>= 8;
        }
    }
    return 1;
}
