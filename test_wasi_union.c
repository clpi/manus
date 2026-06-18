#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t type;
    uint8_t number_kind;
    union {
        bool bval;
        double nval;
        const char* sval;
        void* tval;
        void* fval;
    } as;
} lua_Value;

static inline lua_Value lua_val_from_int(int64_t n) {
    lua_Value v = { .type = 2, .number_kind = 1, .as = { .nval = (double)n } };
    return v;
}

int main() {
    lua_Value min_val = lua_val_from_int(3);
    printf("Result double: %.17g\n", min_val.as.nval);
    printf("Result int: %lld\n", *(long long*)&min_val.as.nval);
    return 0;
}
