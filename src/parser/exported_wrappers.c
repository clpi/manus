#include <stdint.h>
#include <stdbool.h>
// Exported wrapper functions for lexer internals expected by test harness
// These wrappers expose the static inline functions defined in projection.c
// as external symbols with the names used by the Zig extern declarations.

extern int64_t compiler_lexer__fieldcol(void);
extern int64_t compiler_lexer__fieldint(void);
extern int64_t compiler_lexer___fieldintclass(void);
extern int64_t compiler_lexer__fieldlen(void);
extern int64_t compiler_lexer__fieldline(void);
extern int64_t compiler_lexer__fieldoff(void);
extern int64_t compiler_lexer__fieldfloat(void);
extern int64_t compiler_lexer__fieldkind(void);
extern int64_t compiler_lexer__duo_lexer_error_line(const char* src, const char* file, int64_t family);
extern int64_t compiler_lexer__duo_lexer_tokenize_full(const char* src, const char* file, int64_t family, int64_t out, int64_t cap, int64_t txt, int64_t txtcap);
extern int64_t compiler_lexer__duo_lexer_tokenize_all(const char* src, const char* file, int64_t family, int64_t out, int64_t cap);
extern int64_t compiler_lexer__duo_lexer_step(const char* src, const char* file, int64_t family, int64_t pos);
extern uint64_t compiler_lexer__duo_lexer_text_fingerprint(const char* src, const char* file, int64_t family);
extern uint64_t compiler_lexer__duo_lexer_kind_fingerprint(const char* src, const char* file, int64_t family);
extern int64_t compiler_lexer__sourceformcount(void);
extern const char* compiler_lexer__sourceformlaw(int64_t i);
extern const char* compiler_lexer__sourceformsuffix(int64_t i);
extern bool compiler_lexer__sourceformcanonical(int64_t i);
extern int64_t compiler_lexer__sourceentrycount(void);
extern const char* compiler_lexer__sourceentryrole(int64_t i);
extern const char* compiler_lexer__sourceentrypattern(int64_t i);
extern bool compiler_lexer__sourceequal(const char* left, const char* right);
extern bool compiler_lexer__sourcerangeequal(const char* text, int64_t start, const char* pattern);
extern bool compiler_lexer__sourceends(const char* text, const char* suffix);
extern bool compiler_lexer__sourcepathmatches(const char* path, const char* pattern);
extern const char* compiler_lexer__sourcepathrole(const char* path);
extern const char* compiler_lexer__sourcepathformlaw(const char* path);
extern const char* compiler_lexer__sourcepathformprovenance(const char* path);
extern const char* compiler_lexer__sourcefactlaw(const char* path, const char* role);
extern const char* compiler_lexer__sourcefactprovenance(const char* path, const char* role);
extern int64_t compiler_lexer__recordslots(void);
extern int64_t compiler_lexer__fieldkind(void);
extern int64_t compiler_lexer__fieldline(void);
extern int64_t compiler_lexer__fieldcol(void);
extern int64_t compiler_lexer__fieldint(void);
extern int64_t compiler_lexer__fieldoff(void);
extern int64_t compiler_lexer__fieldlen(void);
extern int64_t compiler_lexer__fieldfloat(void);
extern int64_t compiler_lexer___fieldintclass(void);
extern int64_t compiler_lexer__rejectioncount(void);
extern int64_t compiler_lexer__rejectioncode(int64_t i);
extern const char* compiler_lexer__rejectionname(int64_t code);
extern int64_t compiler_lexer__kindcount(void);
extern const char* compiler_lexer__kindname(int64_t i);

__attribute__((visibility("default"))) int64_t _fieldcol(void) { return compiler_lexer__fieldcol(); }
__attribute__((visibility("default"))) int64_t _fieldint(void) { return compiler_lexer__fieldint(); }
__attribute__((visibility("default"))) int64_t _fieldlen(void) { return compiler_lexer__fieldlen(); }
__attribute__((visibility("default"))) int64_t _fieldline(void) { return compiler_lexer__fieldline(); }
__attribute__((visibility("default"))) int64_t _fieldoff(void) { return compiler_lexer__fieldoff(); }
__attribute__((visibility("default"))) int64_t _fieldfloat(void) { return compiler_lexer__fieldfloat(); }
__attribute__((visibility("default"))) int64_t _fieldkind(void) { return compiler_lexer__fieldkind(); }
__attribute__((visibility("default"))) int64_t _duo_lexer_error_line(const char* src, const char* file, int64_t family) { return compiler_lexer__duo_lexer_error_line(src, file, family); }
__attribute__((visibility("default"))) int64_t _duo_lexer_tokenize_full(const char* src, const char* file, int64_t family, int64_t out, int64_t cap, int64_t txt, int64_t txtcap) { return compiler_lexer__duo_lexer_tokenize_full(src, file, family, out, cap, txt, txtcap); }
__attribute__((visibility("default"))) int64_t _duo_lexer_tokenize_all(const char* src, const char* file, int64_t family, int64_t out, int64_t cap) { return compiler_lexer__duo_lexer_tokenize_all(src, file, family, out, cap); }
__attribute__((visibility("default"))) int64_t _duo_lexer_step(const char* src, const char* file, int64_t family, int64_t pos) { return compiler_lexer__duo_lexer_step(src, file, family, pos); }
__attribute__((visibility("default"))) uint64_t _duo_lexer_text_fingerprint(const char* src, const char* file, int64_t family) { return compiler_lexer__duo_lexer_text_fingerprint(src, file, family); }
__attribute__((visibility("default"))) uint64_t _duo_lexer_kind_fingerprint(const char* src, const char* file, int64_t family) { return compiler_lexer__duo_lexer_kind_fingerprint(src, file, family); }
__attribute__((visibility("default"))) int64_t _sourceformcount(void) { return compiler_lexer__sourceformcount(); }
__attribute__((visibility("default"))) const char* _sourceformlaw(int64_t i) { return compiler_lexer__sourceformlaw(i); }
__attribute__((visibility("default"))) const char* _sourceformsuffix(int64_t i) { return compiler_lexer__sourceformsuffix(i); }
__attribute__((visibility("default"))) bool _sourceformcanonical(int64_t i) { return compiler_lexer__sourceformcanonical(i); }
__attribute__((visibility("default"))) int64_t _sourceentrycount(void) { return compiler_lexer__sourceentrycount(); }
__attribute__((visibility("default"))) const char* _sourceentryrole(int64_t i) { return compiler_lexer__sourceentryrole(i); }
__attribute__((visibility("default"))) const char* _sourceentrypattern(int64_t i) { return compiler_lexer__sourceentrypattern(i); }
__attribute__((visibility("default"))) bool _sourceequal(const char* left, const char* right) { return compiler_lexer__sourceequal(left, right); }
__attribute__((visibility("default"))) bool _sourcerangeequal(const char* text, int64_t start, const char* pattern) { return compiler_lexer__sourcerangeequal(text, start, pattern); }
__attribute__((visibility("default"))) bool _sourceends(const char* text, const char* suffix) { return compiler_lexer__sourceends(text, suffix); }
__attribute__((visibility("default"))) bool _sourcepathmatches(const char* path, const char* pattern) { return compiler_lexer__sourcepathmatches(path, pattern); }
__attribute__((visibility("default"))) const char* _sourcepathrole(const char* path) { return compiler_lexer__sourcepathrole(path); }
__attribute__((visibility("default"))) const char* _sourcepathformlaw(const char* path) { return compiler_lexer__sourcepathformlaw(path); }
__attribute__((visibility("default"))) const char* _sourcepathformprovenance(const char* path) { return compiler_lexer__sourcepathformprovenance(path); }
__attribute__((visibility("default"))) const char* _sourcefactlaw(const char* path, const char* role) { return compiler_lexer__sourcefactlaw(path, role); }
__attribute__((visibility("default"))) const char* _sourcefactprovenance(const char* path, const char* role) { return compiler_lexer__sourcefactprovenance(path, role); }
__attribute__((visibility("default"))) int64_t _recordslots(void) { return compiler_lexer__recordslots(); }
__attribute__((visibility("default"))) int64_t _rejectioncount(void) { return compiler_lexer__rejectioncount(); }
__attribute__((visibility("default"))) int64_t _rejectioncode(int64_t i) { return compiler_lexer__rejectioncode(i); }
__attribute__((visibility("default"))) const char* _rejectionname(int64_t code) { return compiler_lexer__rejectionname(code); }
__attribute__((visibility("default"))) int64_t _kindcount(void) { return compiler_lexer__kindcount(); }
__attribute__((visibility("default"))) const char* _kindname(int64_t i) { return compiler_lexer__kindname(i); }
