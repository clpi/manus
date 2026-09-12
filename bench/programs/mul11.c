int main(void){unsigned long long x=1;for(unsigned long long i=0;i<50000000ULL;i++){x=x*11ULL;x=x+1ULL;}return (int)(x&255);}
