/* duo_regex_shim.c — C helper for std.regex ovector reading.
 *
 * Provides a single function to read size_t values from the PCRE2 ovector
 * pointer by index. This is needed because duo's @ffi can bind extern C
 * functions but cannot perform raw pointer arithmetic / dereference in
 * user-level code.
 *
 * Compile alongside your duo program:
 *   duo compile myapp.duo --link pcre2-8
 *   cc -c duo_regex_shim.c -o duo_regex_shim.o
 *   # then link duo_regex_shim.o into the final binary
 *
 * Or if your build system supports it:
 *   duo compile myapp.duo --link pcre2-8 --link duo_regex_shim.c
 */
#include <stddef.h>

/* Read a size_t value from a raw pointer at the given element index.
 * PCRE2's ovector is an array of PCRE2_SIZE (which is size_t) values,
 * laid out as pairs: [start0, end0, start1, end1, ...]
 */
size_t duo_read_size_t(const void* p, size_t i) {
    return ((const size_t*)p)[i];
}