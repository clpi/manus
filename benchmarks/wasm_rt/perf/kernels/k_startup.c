/* Startup probe: does nothing but prove it ran.
 *
 * Wall time on this module is (process spawn + module decode + instantiate +
 * whatever compilation the runtime does eagerly).  It is reported separately
 * from steady state because for short-lived WASM invocations it is the whole
 * cost, and it is the one axis where an interpreter can legitimately beat a
 * JIT.
 */
#include <unistd.h>

int main(void) {
    (void)!write(1, "x\n", 2);
    return 0;
}
