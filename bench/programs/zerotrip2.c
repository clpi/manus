int main(void){unsigned long long t=0;for(unsigned long long o=0;o<10000000ULL;o++){unsigned long long b=o/10000000ULL,i=5;while(i<b){t++;i++;}}return (int)(t&255);}
