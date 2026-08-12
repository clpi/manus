// Bootstrap native string helpers for direct backend gate transport.
// Delete when compiler root projection owns str relations (GAP-155).

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static char* idol_str_sub_cstr(const char* str, int64_t start, int64_t end) {
    if (!str) str = "";
    int64_t len = (int64_t)strlen(str);
    if (start < 0) start = len + start + 1;
    if (end < 0) end = len + end + 1;
    if (start < 1) start = 1;
    if (end > len) end = len;
    if (start > end || start > len || end < 1) {
        char* e = (char*)malloc(1);
        if (e) e[0] = '\0';
        return e;
    }
    int64_t sublen = end - start + 1;
    char* out = (char*)malloc((size_t)sublen + 1);
    if (!out) return (char*)str;
    memcpy(out, str + start - 1, (size_t)sublen);
    out[sublen] = '\0';
    return out;
}

const char* duo_str_sub(const char* s, int64_t i, int64_t j) {
    return idol_str_sub_cstr(s, i, j);
}

#define DUO_LP_MAXCAP 32
static int duo_lp_has_magic(const char* pat) {
    for (const char* p = pat; *p; p++) {
        if (*p == '^' || *p == '$' || *p == '.' || *p == '(' || *p == ')' ||
            *p == '%' || *p == '+' || *p == '-' || *p == '?' || *p == '*' || *p == '[') {
            return 1;
        }
    }
    return 0;
}

static int duo_lp_class_test(int c, const char** pp, const char* end) {
    const char* p = *pp;
    if (*p != '[') return 0;
    p++;
    int invert = 0;
    if (p < end && *p == '^') { invert = 1; p++; }
    if (p < end && *p == ']') {
        if (c == ']') { p++; while (p < end && *p != ']') p++; if (p < end) p++; *pp = p; return invert ? 0 : 1; }
        p++;
    }
    int found = 0;
    while (p < end && *p != ']') {
        if (*p == '%' && p + 1 < end) {
            p++;
            char spec = *p++;
            int m = 0;
            if (spec == 'a') m = isalpha(c);
            else if (spec == 'c') m = iscntrl(c);
            else if (spec == 'd') m = isdigit(c);
            else if (spec == 'l') m = islower(c);
            else if (spec == 'p') m = ispunct(c);
            else if (spec == 's') m = isspace(c);
            else if (spec == 'u') m = isupper(c);
            else if (spec == 'w') m = isalnum(c) || c == '_';
            else if (spec == 'x') m = isxdigit(c);
            else if (spec == 'z') m = c == 0;
            else m = (c == spec);
            if (m) found = 1;
        } else if (p + 2 < end && p[1] == '-') {
            char lo = *p; p += 2; char hi = *p++;
            if (lo <= c && c <= hi) found = 1;
        } else {
            if (c == *p) found = 1;
            p++;
        }
    }
    if (p < end && *p == ']') p++;
    *pp = p;
    return invert ? !found : found;
}

static int duo_lp_item_match(int c, const char** pp, const char* end) {
    const char* p = *pp;
    if (p >= end) return 0;
    if (*p == '.') { (*pp) = p + 1; return c != '\0'; }
    if (*p == '[') return duo_lp_class_test(c, pp, end);
    if (*p == '%' && p + 1 < end) {
        p++;
        char spec = *p++;
        int m = 0;
        if (spec == 'a') m = isalpha(c);
        else if (spec == 'c') m = iscntrl(c);
        else if (spec == 'd') m = isdigit(c);
        else if (spec == 'l') m = islower(c);
        else if (spec == 'p') m = ispunct(c);
        else if (spec == 's') m = isspace(c);
        else if (spec == 'u') m = isupper(c);
        else if (spec == 'w') m = isalnum(c) || c == '_';
        else if (spec == 'x') m = isxdigit(c);
        else if (spec == 'z') m = c == 0;
        else m = (c == spec);
        *pp = p;
        return m;
    }
    char lit = *p;
    (*pp) = p + 1;
    return c == lit;
}

#define DUO_LP_MAXCAP 32

/* Skip one pattern item (no quantifier). Returns pointer past the item. */
static const char* duo_lp_skip_item(const char* p, const char* end) {
    if (p >= end) return end;
    if (*p == '.') return p + 1;
    if (*p == '[') {
        const char* q = p + 1;
        if (q < end && *q == '^') q++;
        if (q < end && *q == ']') q++;
        while (q < end && *q != ']') {
            if (*q == '%' && q + 1 < end) q += 2;
            else q++;
        }
        if (q < end && *q == ']') q++;
        return q;
    }
    if (*p == '%' && p + 1 < end) {
        if (p[1] == 'b') return (p + 4 <= end) ? p + 4 : end;
        return p + 2;
    }
    if (*p == '(') {
        const char* q = p + 1;
        int depth = 1;
        while (q < end && depth > 0) {
            if (*q == '(') depth++;
            else if (*q == ')') depth--;
            q++;
        }
        return q;
    }
    return p + 1;
}

/* Match one occurrence of item [p, item_end) at subject offset si.
   Returns 1 on match and sets *consumed (may be >1 for %bXY). */
static int duo_lp_item_at(const char* s, size_t slen, size_t si,
                          const char* p, const char* end, size_t* consumed) {
    if (si >= slen) return 0;
    if (p >= end) return 0;
    int c = (unsigned char)s[si];
    if (*p == '.') { *consumed = 1; return c != 0; }
    if (*p == '[') {
        const char* pp = p;
        int m = duo_lp_class_test(c, &pp, end);
        *consumed = 1;
        return m;
    }
    if (*p == '%' && p + 1 < end && p[1] == 'b') {
        if (p + 3 >= end) return 0;
        char open = p[2], close = p[3];
        if (c != open) return 0;
        int depth = 1;
        size_t j = si + 1;
        while (j < slen && depth > 0) {
            if (s[j] == open) depth++;
            else if (s[j] == close) depth--;
            j++;
        }
        if (depth != 0) return 0;
        *consumed = j - si;
        return 1;
    }
    {
        const char* pp = p;
        int m = duo_lp_item_match(c, &pp, end);
        *consumed = 1;
        return m;
    }
}

/* Backtracking matcher with capture recording. Matches pattern [p, end)
   starting at subject offset si. Returns final offset or (size_t)-1.
   Capture spans appended to cap_s/cap_e; *ncap tracks the count. */
static size_t duo_lp_match_rec(const char* s, size_t slen, size_t si,
                               const char* p, const char* end,
                               size_t* cap_s, size_t* cap_e, int* ncap) {
    if (p >= end) return si;
    if (*p == '$' && p + 1 == end) return (si == slen) ? si : (size_t)-1;
    if (*p == ')') return (size_t)-1;
    if (*p == '(') {
        const char* close = p + 1;
        int depth = 1;
        while (close < end) {
            if (*close == '(') depth++;
            else if (*close == ')') { depth--; if (depth == 0) break; }
            close++;
        }
        if (close >= end) return (size_t)-1;
        const char* after = close + 1;
        char op = (after < end) ? *after : '\0';
        if (op == '*' || op == '+' || op == '-' || op == '?') {
            /* quantified capture group: the group records its LAST iteration */
            const char* rest = after + 1;
            size_t maxn = 0;
            size_t* poss = malloc((slen - si + 1) * sizeof(size_t));
            if (!poss) return (size_t)-1;
            poss[0] = si;
            size_t cur = si;
            while (cur < slen) {
                int save = *ncap;
                size_t r = duo_lp_match_rec(s, slen, cur, p + 1, close, cap_s, cap_e, ncap);
                if (r == (size_t)-1 || r == cur) { *ncap = save; break; }
                cur = r;
                maxn++;
                poss[maxn] = cur;
            }
            size_t minn = (op == '+') ? 1 : 0;
            size_t maxc = (op == '?') ? (maxn > 0 ? 1 : 0) : maxn;
            if (maxc < minn) { free(poss); return (size_t)-1; }
            size_t res = (size_t)-1;
            size_t slot = (size_t)*ncap;
            if (op == '-') {
                for (size_t n = minn; n <= maxc; n++) {
                    int save = *ncap;
                    cap_s[slot] = poss[0];
                    cap_e[slot] = poss[n];
                    *ncap = (int)slot + 1;
                    size_t r = duo_lp_match_rec(s, slen, poss[n], rest, end, cap_s, cap_e, ncap);
                    if (r != (size_t)-1) { res = r; break; }
                    *ncap = save;
                }
            } else {
                size_t n = maxc;
                while (1) {
                    int save = *ncap;
                    cap_s[slot] = poss[0];
                    cap_e[slot] = poss[n];
                    *ncap = (int)slot + 1;
                    size_t r = duo_lp_match_rec(s, slen, poss[n], rest, end, cap_s, cap_e, ncap);
                    if (r != (size_t)-1) { res = r; break; }
                    *ncap = save;
                    if (n == minn) break;
                    n--;
                }
            }
            free(poss);
            return res;
        }
        cap_s[*ncap] = si;
        size_t r = duo_lp_match_rec(s, slen, si, p + 1, close, cap_s, cap_e, ncap);
        if (r == (size_t)-1) return (size_t)-1;
        cap_e[*ncap] = r;
        (*ncap)++;
        return duo_lp_match_rec(s, slen, r, after, end, cap_s, cap_e, ncap);
    }
    {
        const char* item_end = duo_lp_skip_item(p, end);
        if (item_end == p) return (size_t)-1;
        char op = (item_end < end) ? *item_end : '\0';
        if (op == '*' || op == '+' || op == '-' || op == '?') {
            const char* rest = item_end + 1;
            size_t maxn = 0;
            size_t* poss = malloc((slen - si + 1) * sizeof(size_t));
            if (!poss) return (size_t)-1;
            poss[0] = si;
            size_t cur = si;
            while (cur < slen) {
                size_t consumed;
                if (!duo_lp_item_at(s, slen, cur, p, item_end, &consumed)) break;
                cur += consumed;
                maxn++;
                poss[maxn] = cur;
            }
            size_t minn = (op == '+') ? 1 : 0;
            size_t maxc = (op == '?') ? (maxn > 0 ? 1 : 0) : maxn;
            if (maxc < minn) { free(poss); return (size_t)-1; }
            size_t res = (size_t)-1;
            if (op == '-') {
                for (size_t n = minn; n <= maxc; n++) {
                    int save = *ncap;
                    size_t r = duo_lp_match_rec(s, slen, poss[n], rest, end, cap_s, cap_e, ncap);
                    if (r != (size_t)-1) { res = r; break; }
                    *ncap = save;
                }
            } else {
                size_t n = maxc;
                while (1) {
                    int save = *ncap;
                    size_t r = duo_lp_match_rec(s, slen, poss[n], rest, end, cap_s, cap_e, ncap);
                    if (r != (size_t)-1) { res = r; break; }
                    *ncap = save;
                    if (n == minn) break;
                    n--;
                }
            }
            free(poss);
            return res;
        }
        if (si >= slen) return (size_t)-1;
        size_t consumed;
        if (!duo_lp_item_at(s, slen, si, p, item_end, &consumed)) return (size_t)-1;
        return duo_lp_match_rec(s, slen, si + consumed, item_end, end, cap_s, cap_e, ncap);
    }
}

/* Try to match pattern at/after start. Returns 1 with match span + captures. */
static int duo_lp_match_caps(const char* s, size_t slen, size_t start,
                             const char* pat, const char* pat_end,
                             size_t* ms, size_t* me,
                             size_t* cap_s, size_t* cap_e, int* ncap) {
    int anchored = 0;
    if (pat < pat_end && *pat == '^') { anchored = 1; pat++; }
    if (anchored) {
        if (start != 0) return 0;
        *ncap = 0;
        size_t r = duo_lp_match_rec(s, slen, 0, pat, pat_end, cap_s, cap_e, ncap);
        if (r == (size_t)-1) return 0;
        *ms = 0; *me = r;
        return 1;
    }
    for (size_t i = start; i <= slen; i++) {
        *ncap = 0;
        size_t r = duo_lp_match_rec(s, slen, i, pat, pat_end, cap_s, cap_e, ncap);
        if (r != (size_t)-1) { *ms = i; *me = r; return 1; }
    }
    return 0;
}

static char* idol_str_dup(const char* s, size_t len) {
    char* out = (char*)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, s, len);
    out[len] = '\0';
    return out;
}

int idol_str_has(const char* hay, const char* needle) {
    if (!hay) hay = "";
    if (!needle || needle[0] == '\0') return 0;
    return strstr(hay, needle) != NULL ? 1 : 0;
}

char* idol_str_match(const char* s, const char* pat) {
    if (!s || !pat) return NULL;
    size_t slen = strlen(s);
    size_t ms = 0, me = 0;
    size_t cap_s[DUO_LP_MAXCAP], cap_e[DUO_LP_MAXCAP];
    int ncap = 0;
    if (!duo_lp_match_caps(s, slen, 0, pat, pat + strlen(pat), &ms, &me, cap_s, cap_e, &ncap))
        return NULL;
    if (ncap > 0) return idol_str_dup(s + cap_s[0], cap_e[0] - cap_s[0]);
    return idol_str_dup(s + ms, me - ms);
}
