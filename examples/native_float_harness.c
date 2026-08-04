#include <stdint.h>
extern double duo_fadd(double a, double b);
extern double duo_fmul(double a, double b);
/* 20.0 + 22.0 = 42.0 ; 2.0 * 3.0 = 6.0 ; sum = 48.0 -> exit 48 */
int main(void) {
    return (int)(duo_fadd(20.0, 22.0) + duo_fmul(2.0, 3.0));
}
