int main(void){unsigned long long x=1;for(unsigned long long i=0;i<50000000ULL;i++){x=x*3ULL;x=x+7ULL;x=x-2ULL;}return (int)(x&255);}
