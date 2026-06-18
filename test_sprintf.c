#include <stdio.h>
int main() {
    char b[32];
    double d = 3.0;
    sprintf(b, "%.17g", d);
    printf("Result: %s\n", b);
    return 0;
}
