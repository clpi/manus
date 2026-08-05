#include <stdint.h>

extern int64_t duo_native_add(int64_t a, int64_t b);

int main(void) {
    return (int)duo_native_add(20, 22);
}
