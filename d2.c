#include <stdio.h>
#include <unistd.h>
int main(void){
  write(1,"before\n",7);
  printf("%d\n", 42);
  fflush(stdout);
  write(1,"after\n",6);
  return 0;
}
