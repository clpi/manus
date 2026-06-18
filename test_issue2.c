#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

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

static inline lua_Value lua_val_from_num(double n) {
    lua_Value v = { .type = 2, .number_kind = 2, .as = { .nval = n } };
    return v;
}

static inline double lua_to_num(lua_Value v) {
    if (v.number_kind == 1) return (double)(int64_t)v.as.nval;
    return v.as.nval;
}

static inline lua_Value lua_math_floor(lua_Value v) {
    return lua_val_from_num(floor(lua_to_num(v)));
}

static inline const char* lua_to_str(lua_Value v) {
    static char buf[32];
    sprintf(buf, "%.17g", v.as.nval);
    return buf;
}

int main() {
    lua_Value f_val = lua_math_floor(lua_val_from_num(3.7));
    printf("Result: %s\n", lua_to_str(f_val));
    return 0;
}
