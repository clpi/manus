int main(void){unsigned long long x=0;for(unsigned long long i=0;i<50000000ULL;i++){x=x+5000ULL;x=x-4000ULL;}return (int)(x&255);}
