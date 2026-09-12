int main(void){long long x=12345LL;for(long long i=0;i<50000000LL;i++){x=x+7LL;x=x+9000LL;x=x-3LL;}return (int)((unsigned long long)x&255);}
