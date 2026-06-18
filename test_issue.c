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

static inline double lua_to_num(lua_Value v) {
    if (v.number_kind == 1) return (double)(int64_t)v.as.nval;
    return v.as.nval;
}

static inline lua_Value lua_math_min(lua_Value m, lua_Value n) {
    return lua_to_num(m) < lua_to_num(n) ? m : n;
}

static inline const char* lua_to_str(lua_Value v) {
    static char buf[32];
    sprintf(buf, "%.17g", v.as.nval);
    return buf;
}

int main() {
    lua_Value min_val = lua_math_min(lua_val_from_int(3), lua_val_from_int(8));
    printf("Result: %s\n", lua_to_str(min_val));
    return 0;
}
