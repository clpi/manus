#include <stdio.h>
#include <stdint.h>
int main(void){ uint32_t s=0; for(uint32_t i=0;i<100000;i++) s=s*31u+i; printf("%u\n",s); return 0; }
