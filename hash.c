#include <stdio.h>
#include <stdint.h>
__attribute__((export_name("run")))
uint32_t run(void) {
  uint32_t h = 2166136261u;
  for (uint32_t i = 0; i < 200000000u; i++) {
    h ^= i; h *= 16777619u; h = (h << 13) | (h >> 19);
  }
  return h;
}
int main(void) { printf("%u\n", run()); return 0; }
