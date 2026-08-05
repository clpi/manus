#include <unistd.h>
#include <stdint.h>
// Reproduce musl's fmt_u digit loop WITHOUT printf.
int main(void){
  char buf[32]; char* p = buf+31; *p = '\n';
  uint64_t x = 4242;
  do { *--p = '0' + (char)(x % 10); x /= 10; } while (x);
  write(1, p, (size_t)(buf+32-p));
  return 0;
}
