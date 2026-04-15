/*
 * ctf-verify TASK_ID ANSWER
 *
 * Setuid helper: reads /etc/ctf/hub.env (root-only), finds FLAG_<TASK_ID>=...,
 * normalizes both expected and submitted values (trim + lowercase), and does a
 * constant-time comparison. Exits 0 on match, 1 on mismatch, 2 on error.
 *
 * Never prints the expected value. Adds a 300ms sleep on mismatch to slow
 * local brute-force attempts against small search spaces (e.g. task02 ports).
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HUB_ENV "/etc/ctf/hub.env"
#define MAX_LINE 4096

static size_t normalize(char *s) {
    size_t n = strlen(s);
    size_t lead = 0;
    while (lead < n && isspace((unsigned char)s[lead])) lead++;
    if (lead) memmove(s, s + lead, n - lead + 1);
    n = strlen(s);
    while (n > 0 && isspace((unsigned char)s[n - 1])) { s[--n] = '\0'; }
    for (size_t i = 0; i < n; i++) s[i] = (char)tolower((unsigned char)s[i]);
    return n;
}

static int ct_equal(const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b);
    if (la != lb) return 0;
    unsigned char diff = 0;
    for (size_t i = 0; i < la; i++) diff |= (unsigned char)a[i] ^ (unsigned char)b[i];
    return diff == 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: ctf-verify TASK_ID ANSWER\n");
        return 2;
    }
    const char *task_id = argv[1];

    char answer[MAX_LINE];
    strncpy(answer, argv[2], sizeof(answer) - 1);
    answer[sizeof(answer) - 1] = '\0';
    normalize(answer);

    char key[64];
    snprintf(key, sizeof(key), "FLAG_%s=", task_id);
    for (char *p = key + 5; *p && *p != '='; p++) *p = (char)toupper((unsigned char)*p);
    size_t keylen = strlen(key);

    FILE *f = fopen(HUB_ENV, "r");
    if (!f) {
        fprintf(stderr, "verify: cannot open answer store\n");
        return 2;
    }

    char line[MAX_LINE];
    int match = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, key, keylen) != 0) continue;
        char *val = line + keylen;
        size_t vl = strlen(val);
        while (vl > 0 && (val[vl - 1] == '\n' || val[vl - 1] == '\r')) val[--vl] = '\0';
        char norm[MAX_LINE];
        strncpy(norm, val, sizeof(norm) - 1);
        norm[sizeof(norm) - 1] = '\0';
        normalize(norm);
        if (ct_equal(norm, answer)) match = 1;
        break;
    }
    fclose(f);

    if (!match) {
        usleep(300 * 1000);
        return 1;
    }
    return 0;
}
