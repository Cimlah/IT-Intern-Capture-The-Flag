/*
 * ctf-reveal
 *
 * Setuid helper that prompts for the mentor password (no-echo), verifies it
 * against /etc/ctf/mentor.hash (an SHA-512 crypt hash produced by
 * `openssl passwd -6`), and if correct prints every FLAG_* line from
 * /etc/ctf/hub.env to stdout. On mismatch, sleeps 2s and exits 1.
 */
#define _XOPEN_SOURCE 700
#define _GNU_SOURCE
#include <crypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#define HUB_ENV "/etc/ctf/hub.env"
#define MENTOR_HASH "/etc/ctf/mentor.hash"
#define MAX_LINE 4096

static void read_password(char *buf, size_t buflen) {
    struct termios oldt, newt;
    int have_tty = (tcgetattr(STDIN_FILENO, &oldt) == 0);
    if (have_tty) {
        newt = oldt;
        newt.c_lflag &= ~(ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &newt);
    }
    if (!fgets(buf, (int)buflen, stdin)) buf[0] = '\0';
    if (have_tty) {
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
        fputc('\n', stdout);
    }
}

static int ct_equal(const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b);
    if (la != lb) return 0;
    unsigned char diff = 0;
    for (size_t i = 0; i < la; i++) diff |= (unsigned char)a[i] ^ (unsigned char)b[i];
    return diff == 0;
}

static void strip_nl(char *s) {
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) s[--n] = '\0';
}

int main(void) {
    FILE *hf = fopen(MENTOR_HASH, "r");
    if (!hf) {
        fprintf(stderr, "reveal: cannot open mentor hash\n");
        return 2;
    }
    char stored_hash[256];
    if (!fgets(stored_hash, sizeof(stored_hash), hf)) {
        fclose(hf);
        fprintf(stderr, "reveal: empty hash file\n");
        return 2;
    }
    fclose(hf);
    strip_nl(stored_hash);

    fputs("Mentor password: ", stdout);
    fflush(stdout);
    char pw[256];
    read_password(pw, sizeof(pw));
    strip_nl(pw);

    char *computed = crypt(pw, stored_hash);
    if (!computed) {
        fprintf(stderr, "reveal: crypt() failed\n");
        return 2;
    }

    if (!ct_equal(computed, stored_hash)) {
        sleep(2);
        fprintf(stderr, "Wrong password.\n");
        return 1;
    }

    FILE *f = fopen(HUB_ENV, "r");
    if (!f) {
        fprintf(stderr, "reveal: cannot open answer store\n");
        return 2;
    }
    char line[MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "FLAG_", 5) == 0) fputs(line, stdout);
    }
    fclose(f);
    return 0;
}
