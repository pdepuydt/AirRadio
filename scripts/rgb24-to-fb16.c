/* Pack RGB24 (R,G,B) into RGB565LE and write a full framebuffer.
 * usage: rgb24-to-fb16 RGB24_PATH OUT_PATH WIDTH HEIGHT STRIDE_BYTES
 * OUT_PATH is /dev/fb0 or a regular file (for checks).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    const char *in_path, *out_path;
    unsigned width, height, stride;
    size_t in_need, out_need, n;
    unsigned char *rgb = NULL, *fb = NULL;
    FILE *in = NULL;
    int out = -1, rc = 1;
    unsigned y, x;

    if (argc != 6) {
        fprintf(stderr, "usage: %s RGB24 OUT WIDTH HEIGHT STRIDE\n", argv[0]);
        return 2;
    }
    in_path = argv[1];
    out_path = argv[2];
    width = (unsigned)strtoul(argv[3], NULL, 10);
    height = (unsigned)strtoul(argv[4], NULL, 10);
    stride = (unsigned)strtoul(argv[5], NULL, 10);
    if (width == 0 || height == 0 || stride < width * 2) {
        fprintf(stderr, "bad geometry %ux%u stride %u\n", width, height, stride);
        return 2;
    }

    in_need = (size_t)width * height * 3;
    out_need = (size_t)stride * height;
    rgb = malloc(in_need);
    fb = calloc(1, out_need);
    if (!rgb || !fb) {
        fprintf(stderr, "out of memory\n");
        goto done;
    }

    in = fopen(in_path, "rb");
    if (!in) {
        fprintf(stderr, "open %s: %s\n", in_path, strerror(errno));
        goto done;
    }
    n = fread(rgb, 1, in_need, in);
    if (n != in_need) {
        fprintf(stderr, "short RGB24 read (%zu of %zu)\n", n, in_need);
        goto done;
    }

    for (y = 0; y < height; y++) {
        const unsigned char *src = rgb + (size_t)y * width * 3;
        unsigned char *dst = fb + (size_t)y * stride;
        for (x = 0; x < width; x++) {
            unsigned r = src[0], g = src[1], b = src[2];
            uint16_t pix = (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
            dst[0] = (unsigned char)(pix & 0xFF);
            dst[1] = (unsigned char)(pix >> 8);
            src += 3;
            dst += 2;
        }
    }

    {
        struct stat st;
        int flags = O_WRONLY | O_CREAT | O_TRUNC;
        if (stat(out_path, &st) == 0 && S_ISCHR(st.st_mode))
            flags = O_RDWR;
        out = open(out_path, flags, 0644);
    }
    if (out < 0) {
        fprintf(stderr, "open %s: %s\n", out_path, strerror(errno));
        goto done;
    }
    n = 0;
    while (n < out_need) {
        ssize_t w = write(out, fb + n, out_need - n);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            fprintf(stderr, "write %s: %s\n", out_path, strerror(errno));
            goto done;
        }
        n += (size_t)w;
    }
    rc = 0;

done:
    if (in)
        fclose(in);
    if (out >= 0)
        close(out);
    free(rgb);
    free(fb);
    return rc;
}
