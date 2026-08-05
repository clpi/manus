#include <stdio.h>
#include <stdint.h>
static uint32_t fib(uint32_t n){return n<2?n:fib(n-1)+fib(n-2);}
int main(void){ printf("%u\n", fib(20)); return 0; }
