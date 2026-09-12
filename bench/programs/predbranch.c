int main(void){unsigned long long t=0;for(unsigned long long o=0;o<3000000ULL;o++){unsigned long long h=o/2ULL,d=h*2ULL,x=o-d,j=0;while(j<x){t++;j=x;}}return (int)(t&255);}
