#include <unistd.h>
#include <string.h>
int main(void){ const char*m="via-write\n"; write(1,m,strlen(m)); return 0; }
