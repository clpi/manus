int main(void){unsigned long long x=0;for(unsigned long long i=0;i<50000000ULL;i++){x=x+2000000000ULL;x=x-1000000000ULL;}return (int)(x&255);}
