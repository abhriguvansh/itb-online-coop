/* Opt-in, bounded nonblocking TCP for the isolated two-guest experiment.
 * No hooks, input, game-state writes, DNS, listening socket or reconnection. */
#include <winsock2.h>
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include "lua.h"
#define FN(ret,name,args) static ret (__cdecl *p_##name) args
FN(void,lua_createtable,(lua_State*,int,int));
FN(void,lua_pushnumber,(lua_State*,lua_Number));
FN(void,lua_pushboolean,(lua_State*,int));
FN(void,lua_pushstring,(lua_State*,const char*));
FN(void,lua_pushlstring,(lua_State*,const char*,size_t));
FN(void,lua_pushnil,(lua_State*));
FN(void,lua_setfield,(lua_State*,int,const char*));
FN(void,lua_pushcclosure,(lua_State*,lua_CFunction,int));
FN(int,lua_type,(lua_State*,int));
FN(lua_Number,lua_tonumber,(lua_State*,int));
FN(const char*,lua_tolstring,(lua_State*,int,size_t*));
#define MAX_PACKET 70000u
#define MAX_RX (MAX_PACKET*2u+16u)
#define MAX_TX 280002u
static SOCKET channel=INVALID_SOCKET;
static DWORD owner,started;
static int attempted,state,fault,wsa;
/* state: 0 disabled, 1 connecting, 2 connected, 3 closed, 4 fault. */
static char rx[MAX_RX],tx[MAX_TX];
static unsigned rx_count,tx_count,packet_count,sent_count;
static void close_channel(void){
    if(channel!=INVALID_SOCKET){closesocket(channel);channel=INVALID_SOCKET;}
    if(wsa){WSACleanup();wsa=0;}
}
static void fail(int code){if(!fault)fault=code;state=4;close_channel();}
/* Validate framing before making any Lua value. A complete payload may contain LF. */
static int packet_size(unsigned *header,unsigned *length){
    unsigned n=0,i=0;
    while(i<rx_count&&rx[i]!='\n'){
        if(i>=5||rx[i]<'0'||rx[i]>'9'||(i&&rx[0]=='0')){fail(10);return -1;}
        n=n*10u+(unsigned)(rx[i]-'0');i++;
    }
    if(i==rx_count)return 0;
    if(!i||!n||n>MAX_PACKET){fail(10);return -1;}
    *header=i+1;*length=n;return rx_count>=*header+n?1:0;
}
static int allowed_process(void){
    WCHAR path[MAX_PATH],opt[8];
    return sizeof(void*)==4&&GetModuleFileNameW(NULL,path,MAX_PATH)&&
        !wcscmp(path,L"C:\\ITBCoopProbe\\GameVerified\\Breach.exe")&&
        GetEnvironmentVariableW(L"ITB_COOP_NATIVE_TRANSPORT",opt,8)==1&&opt[0]=='1';
}
static void pump(void){
    if(GetCurrentThreadId()!=owner){fail(2);return;}
    if(state==1){
        fd_set writable,errors;struct timeval immediate={0,0};
        FD_ZERO(&writable);FD_ZERO(&errors);FD_SET(channel,&writable);FD_SET(channel,&errors);
        int ready=select(0,NULL,&writable,&errors,&immediate),error=0;int size=sizeof(error);
        if(ready==SOCKET_ERROR){fail(3);return;}
        if(ready){
            if(getsockopt(channel,SOL_SOCKET,SO_ERROR,(char*)&error,&size)||error||FD_ISSET(channel,&errors)){fail(3);return;}
            state=2;
        }else if((DWORD)(GetTickCount()-started)>5000){fail(4);return;}
    }
    if(state!=2)return;
    for(unsigned i=0;i<4&&tx_count;i++){
        int n=send(channel,tx,(int)(tx_count>65536?65536:tx_count),0);
        if(n==SOCKET_ERROR){if(WSAGetLastError()!=WSAEWOULDBLOCK)fail(5);break;}
        if(n<=0){fail(5);break;}
        tx_count-=(unsigned)n;memmove(tx,tx+n,tx_count);
    }
    for(unsigned i=0;i<4&&state==2&&rx_count<MAX_RX;i++){
        unsigned room=MAX_RX-rx_count;if(room>32768)room=32768;
        int n=recv(channel,rx+rx_count,(int)room,0);
        if(n==SOCKET_ERROR){if(WSAGetLastError()!=WSAEWOULDBLOCK)fail(6);break;}
        if(!n){state=3;close_channel();break;}
        rx_count+=(unsigned)n;
    }
}
static int info(lua_State *L){
    p_lua_createtable(L,0,7);
    p_lua_pushstring(L,"itb-transport-v1");p_lua_setfield(L,-2,"abi");
    p_lua_pushnumber(L,state);p_lua_setfield(L,-2,"state");
    p_lua_pushnumber(L,fault);p_lua_setfield(L,-2,"fault");
    p_lua_pushnumber(L,tx_count);p_lua_setfield(L,-2,"pendingTx");
    p_lua_pushnumber(L,rx_count);p_lua_setfield(L,-2,"pendingRx");
    p_lua_pushnumber(L,packet_count);p_lua_setfield(L,-2,"received");
    p_lua_pushnumber(L,sent_count);p_lua_setfield(L,-2,"queued");return 1;
}
static int open_channel(lua_State *L){
    if(attempted)return info(L);
    attempted=1;owner=GetCurrentThreadId();started=GetTickCount();
    lua_Number port=p_lua_tonumber(L,1);
    if(!allowed_process()||p_lua_type(L,1)!=LUA_TNUMBER||!(port>=1&&port<=65535)||port!=(int)port){fail(1);return info(L);}
    WSADATA data;if(WSAStartup(MAKEWORD(2,2),&data)){fail(3);return info(L);}wsa=1;
    channel=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);u_long nonblocking=1;int no_delay=1;
    if(channel==INVALID_SOCKET||ioctlsocket(channel,FIONBIO,&nonblocking)||setsockopt(channel,IPPROTO_TCP,TCP_NODELAY,(char*)&no_delay,sizeof(no_delay))){fail(3);return info(L);}
    struct sockaddr_in address;memset(&address,0,sizeof(address));address.sin_family=AF_INET;
    address.sin_port=htons((unsigned short)port);address.sin_addr.s_addr=htonl(0x0a000202u); /* Existing NAT host only. */
    int result=connect(channel,(struct sockaddr*)&address,sizeof(address));
    if(!result)state=2;else if(WSAGetLastError()==WSAEWOULDBLOCK)state=1;else fail(3);
    return info(L);
}
static int queue_message(lua_State *L){
    size_t n=0;const char *text=p_lua_tolstring(L,1,&n);
    int valid=GetCurrentThreadId()==owner&&state==2&&!fault&&p_lua_type(L,1)==LUA_TSTRING&&text&&n&&n<=140000&&
        n+1<=MAX_TX-tx_count&&!memchr(text,'\n',n)&&!memchr(text,'\r',n)&&sent_count<4300;
    if(!valid){fail(7);p_lua_pushboolean(L,0);return 1;}
    memcpy(tx+tx_count,text,n);tx_count+=(unsigned)n;tx[tx_count++]='\n';sent_count++;
    p_lua_pushboolean(L,1);return 1;
}
static int poll_channel(lua_State *L){
    if(!fault&&(state==1||state==2))pump();
    unsigned header=0,length=0;
    if(!fault&&packet_size(&header,&length)==1){
        if(++packet_count>4096){fail(8);p_lua_pushnil(L);return 1;}
        p_lua_pushlstring(L,rx+header,length);rx_count-=header+length;memmove(rx,rx+header+length,rx_count);return 1;
    }
    p_lua_pushnil(L);return 1;
}
static int stop(lua_State *L){close_channel();if(!fault)state=3;return info(L);}
#define LOAD(name) p_##name=(void*)GetProcAddress(lua,#name);if(!p_##name)return 0
__declspec(dllexport) int __cdecl luaopen_itb_transport(lua_State *L){
    HMODULE lua=GetModuleHandleW(L"lua5.1.dll");if(!lua||sizeof(void*)!=4)return 0;
    LOAD(lua_createtable);LOAD(lua_pushnumber);LOAD(lua_pushboolean);LOAD(lua_pushstring);LOAD(lua_pushlstring);
    LOAD(lua_pushnil);LOAD(lua_setfield);LOAD(lua_pushcclosure);LOAD(lua_type);LOAD(lua_tonumber);LOAD(lua_tolstring);
    p_lua_createtable(L,0,5);
    p_lua_pushcclosure(L,open_channel,0);p_lua_setfield(L,-2,"open");
    p_lua_pushcclosure(L,queue_message,0);p_lua_setfield(L,-2,"send");
    p_lua_pushcclosure(L,poll_channel,0);p_lua_setfield(L,-2,"poll");
    p_lua_pushcclosure(L,info,0);p_lua_setfield(L,-2,"info");
    p_lua_pushcclosure(L,stop,0);p_lua_setfield(L,-2,"close");return 1;
}
