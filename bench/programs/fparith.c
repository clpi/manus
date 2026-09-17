int main(void){double x=1.5;for(long long i=0;i<2000000LL;i++){x=x*1.000001;x=x+0.5;x=x-0.25;x=x/1.0000005;}return (int)((long long)x&255);}
