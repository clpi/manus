// indirect.c — gated benchmark oracle: indirect calls.
// Gate: function definitions + indirect calls in the Idol subset.
// Semantics frozen: 3M dispatches through a 4-entry table, exit = acc & 255.
typedef unsigned long long u64;
static u64 f0(u64 x){return x+1;} static u64 f1(u64 x){return x*3;}
static u64 f2(u64 x){return x^0x9e37;} static u64 f3(u64 x){return x-7;}
int main(void){
    u64 (*tab[4])(u64)={f0,f1,f2,f3};
    u64 acc=0,x=1;
    for(u64 i=0;i<3000000ULL;i++){acc+=tab[i&3](x);x=acc+1;}
    return (int)(acc&255);
}
