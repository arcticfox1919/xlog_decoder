/* Test-only fixture generator using the original Mars C dependencies.
 * Compile with uECC.c, Mars' zlib sources and zstd common/compress sources.
 * All private keys here are PUBLIC TEST DATA, never production keys.
 * TEA adapted from Tencent Mars, Copyright (C) 2016 THL A29 Limited (MIT).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "uECC.h"
#include "zlib.h"
#include "zstd.h"

static void check_at(int ok, int line) {
    if (!ok) { fprintf(stderr, "Fixture generation failed at line %d\n", line); exit(1); }
}
#define check(ok) check_at((ok), __LINE__)

static void tea_encrypt(uint8_t *bytes, size_t length, const uint8_t *secret) {
    uint32_t k[4];
    memcpy(k, secret, sizeof(k));
    for (size_t i = 0; i + 8 <= length; i += 8) {
        uint32_t v[2], sum = 0;
        memcpy(v, bytes + i, sizeof(v));
        for (int round = 0; round < 16; ++round) {
            sum += 0x9e3779b9;
            v[0] += ((v[1] << 4) + k[0]) ^ (v[1] + sum) ^ ((v[1] >> 5) + k[1]);
            v[1] += ((v[0] << 4) + k[2]) ^ (v[0] + sum) ^ ((v[0] >> 5) + k[3]);
        }
        memcpy(bytes + i, v, sizeof(v));
    }
}

static void hex(const uint8_t *bytes, size_t size) {
    putchar('"');
    for (size_t i = 0; i < size; ++i) printf("%02x", bytes[i]);
    putchar('"');
}

/* Match the writer: two streaming flushes, with no final frame terminator. */
static size_t compress_payload(int zstd, const uint8_t *plain, size_t size, uint8_t *out) {
    size_t written = 0;
    if (zstd) {
        ZSTD_CCtx *ctx = ZSTD_createCCtx();
        check(ctx != NULL);
        check(!ZSTD_isError(ZSTD_CCtx_setParameter(ctx, ZSTD_c_compressionLevel, 3)));
        check(!ZSTD_isError(ZSTD_CCtx_setParameter(ctx, ZSTD_c_windowLog, 16)));
        for (int i = 0; i < 2; ++i) {
            size_t start = i ? size / 2 : 0;
            ZSTD_inBuffer input = {plain + start, i ? size - start : size / 2, 0};
            ZSTD_outBuffer output = {out + written, 65536 - written, 0};
            check(ZSTD_compressStream2(ctx, &output, &input, ZSTD_e_flush) == 0);
            check(input.pos == input.size);
            written += output.pos;
        }
        ZSTD_freeCCtx(ctx);
    } else {
        z_stream stream = {0};
        check(deflateInit2(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -MAX_WBITS,
                          MAX_MEM_LEVEL, Z_DEFAULT_STRATEGY) == Z_OK);
        for (int i = 0; i < 2; ++i) {
            size_t start = i ? size / 2 : 0;
            stream.next_in = (Bytef *)(plain + start);
            stream.avail_in = (uInt)(i ? size - start : size / 2);
            stream.next_out = out + written;
            stream.avail_out = (uInt)(65536 - written);
            check(deflate(&stream, Z_SYNC_FLUSH) == Z_OK && stream.avail_in == 0);
            written = 65536 - stream.avail_out;
        }
        deflateEnd(&stream);
    }
    return written;
}

int main(void) {
    /* Fixed public test keys need no random projective-coordinate blinding. */
    uECC_set_rng(NULL);
    uint8_t private_key[32] = {0}, client_key[32] = {0}, public_key[64], secret[32];
    for (int i = 0; i < 32; ++i) private_key[i] = (uint8_t)(i * 7 + 3);
    client_key[31] = 2;
    check(uECC_compute_public_key(client_key, public_key, uECC_secp256k1()));
    check(uECC_shared_secret(public_key, private_key, secret, uECC_secp256k1()));
    uint8_t plain[16384], compressed[65536], frame[65536 + 128];
    const char *line = "[I] Mars -> Dart: UTF-8 \xe4\xb8\xad\xe6\x96\x87, 16-round TEA, streaming compression.\n";
    size_t plain_size = 0;
    for (int i = 0; i < 140; ++i) {
        memcpy(plain + plain_size, line, strlen(line));
        plain_size += strlen(line);
    }
    printf("{\"privateKey\":"); hex(private_key, 32);
    printf(",\"publicKey\":"); hex(public_key, 64);
    printf(",\"plain\":"); hex(plain, plain_size);
    printf(",\"modern\":{");
    for (int magic = 6; magic <= 13; ++magic) {
        int async = magic == 7 || magic == 9 || magic == 12 || magic == 13;
        size_t size;
        if (async) size = compress_payload(magic >= 10, plain, plain_size, compressed);
        else { memcpy(compressed, plain, plain_size); size = plain_size; }
        if (magic == 7 || magic == 12) tea_encrypt(compressed, size, secret);
        memset(frame, 0, 73);
        frame[0] = (uint8_t)magic;
        frame[1] = async ? 1 : 0;
        frame[3] = 9; frame[4] = 10;
        uint32_t length = (uint32_t)size;
        memcpy(frame + 5, &length, 4);
        memcpy(frame + 9, public_key, 64);
        memcpy(frame + 73, compressed, size);
        frame[73 + size] = 0;
        if (magic != 6) putchar(',');
        printf("\"%02x\":", magic); hex(frame, size + 74);
    }
    printf("},\"tea\":[");
    for (int size = 8; size < 24; ++size) {
        for (int i = 0; i < size; ++i) compressed[i] = (uint8_t)(i * 37 + 129);
        if (size != 8) putchar(',');
        printf("{\"plain\":"); hex(compressed, size);
        tea_encrypt(compressed, size, secret);
        printf(",\"cipher\":"); hex(compressed, size); putchar('}');
    }
    printf("],\"leadingZero\":{");
    for (unsigned i = 3; ; ++i) {
        client_key[30] = (uint8_t)(i >> 8); client_key[31] = (uint8_t)i;
        check(uECC_compute_public_key(client_key, public_key, uECC_secp256k1()));
        check(uECC_shared_secret(public_key, private_key, secret, uECC_secp256k1()));
        if (secret[0] == 0) break;
    }
    printf("\"publicKey\":"); hex(public_key, 64);
    memcpy(compressed, plain, 17); tea_encrypt(compressed, 17, secret);
    printf(",\"cipher\":"); hex(compressed, 17);
    printf(",\"plain\":"); hex(plain, 17);
    puts("}}");
    return 0;
}
