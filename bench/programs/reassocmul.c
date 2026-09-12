int main(void){unsigned long long x=3ULL;for(unsigned long long i=0;i<50000000ULL;i++){x=x*3ULL;x=x*5ULL;x=x+1ULL;}return (int)(x&255);}
