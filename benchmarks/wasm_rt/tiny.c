#include <stdio.h>
#include <stdint.h>
static uint32_t fib(uint32_t n){return n<2?n:fib(n-1)+fib(n-2);}
int main(void){
  uint32_t s=0; for(uint32_t i=0;i<100000;i++) s=s*31u+i;
  printf("%u %u\n", s, fib(20));
  return 0;
}
