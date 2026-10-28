/* CI only. Parser boundaries; no sockets, game process or input are opened. */
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include "../native/transport.c"
static void input(const char *value){fault=0;state=2;rx_count=(unsigned)strlen(value);memcpy(rx,value,rx_count);}
int main(void){
 unsigned h=0,n=0;
 input("5\nhe");assert(packet_size(&h,&n)==0&&h==2&&n==5&&!fault);
 input("5\nhello4\nnext");assert(packet_size(&h,&n)==1&&h==2&&n==5);
 rx_count-=h+n;memmove(rx,rx+h+n,rx_count);assert(packet_size(&h,&n)==1&&n==4);
 const char *bad[]={"0\n","01\na","-1\na","1x\na","70001\n","100000\n","\n"};
 for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++){input(bad[i]);assert(packet_size(&h,&n)==-1&&fault==10&&state==4);}
 input("70000\n");assert(packet_size(&h,&n)==0&&n==70000&&!fault);
 memset(rx+rx_count,'x',70000);rx_count+=70000;assert(packet_size(&h,&n)==1&&h==6&&n==70000);
 input("1");assert(packet_size(&h,&n)==0&&!fault);
 puts("Native transport parser contracts passed; no socket or game APIs executed.");return 0;
}
