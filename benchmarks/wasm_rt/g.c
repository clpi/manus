#include <stdlib.h>
#include <string.h>
__attribute__((export_name("go"))) int go(void){
  volatile char* p = malloc(400000);   // forces memory.grow
  if(!p) return -1;
  memset((void*)p, 7, 400000);
  int s=0; for(int i=0;i<400000;i+=997) s+=p[i];
  return s;
}
int main(void){ return 0; }
