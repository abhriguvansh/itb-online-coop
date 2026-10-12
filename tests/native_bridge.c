#undef NDEBUG
#define SDL_MAIN_HANDLED
/* Native boundary contracts with SDL/Lua doubles; never loads or controls a game. */
#include <assert.h>
#include <stdio.h>
#include "../native/input_bridge.c"
static int ok_value,top=2,kind=LUA_TNUMBER,w=1920,h=1080,mouse=0,key=0,queue_result=3,queued,warps;
static double args[2]={500,500},number;
static Uint32 clock_value;
static SDL_Window *focus=(SDL_Window*)1;
static const char *message;
static SDL_Event recorded[3];
static int gettop(lua_State *L){(void)L;return top;}
static int gettype(lua_State *L,int i){(void)L;(void)i;return kind;}
static double getnum(lua_State *L,int i){(void)L;return args[i-1];}
static void push_bool(lua_State *L,int b){(void)L;ok_value=b;}
static void num(lua_State *L,double n){(void)L;number=n;}
static void string(lua_State *L,const char *s){(void)L;message=s;}
static SDL_Window *getfocus(void){return focus;}
static Uint32 getid(SDL_Window *p){assert(p==focus);return 7;}
static void getsize(SDL_Window *p,int *x,int *y){(void)p;*x=w;*y=h;}
static Uint32 getmouse(int *x,int *y){if(x)*x=500;if(y)*y=500;return mouse;}
static const Uint8 *getkeys(int *n){static Uint8 keys[512];memset(keys,0,sizeof(keys));keys[9]=key;*n=512;return keys;}
static Uint32 ticks(void){return clock_value;}
static SDL_bool filter(SDL_EventFilter *f,void **d){(void)f;(void)d;return SDL_FALSE;}
static void warp(SDL_Window *p,int x,int y){assert(p==focus && x==args[0] && y==args[1]);warps++;}
static int queue(SDL_Event *e,int n,SDL_eventaction a,Uint32 lo,Uint32 hi){
    (void)lo;(void)hi;assert(n==3 && a==SDL_ADDEVENT);memcpy(recorded,e,sizeof(recorded));queued++;return queue_result;
}
static void setup(void){
    armed=0;clicks=0;queued=warps=0;focus=(SDL_Window*)1;clock_value=0;w=1920;h=1080;
    mouse=key=0;queue_result=3;args[0]=500;args[1]=500;top=2;kind=LUA_TNUMBER;message=NULL;
    p_lua_gettop=gettop;p_lua_type=gettype;p_lua_tonumber=getnum;p_lua_pushboolean=push_bool;
    p_lua_pushnumber=num;p_lua_pushstring=string;p_SDL_GetKeyboardFocus=getfocus;
    p_SDL_GetWindowID=getid;p_SDL_GetWindowSize=getsize;p_SDL_GetMouseState=getmouse;
    p_SDL_GetKeyboardState=getkeys;p_SDL_GetTicks=ticks;p_SDL_GetEventFilter=filter;
    p_SDL_WarpMouseInWindow=warp;p_SDL_PeepEvents=queue;
}
int main(void){
    setup();begin(NULL);assert(ok_value);aim(NULL);assert(ok_value);click(NULL);assert(ok_value && queued==1 && warps==1 && number==3);
    assert(recorded[0].type==SDL_MOUSEMOTION && recorded[0].motion.x==500);
    assert(recorded[1].type==SDL_MOUSEBUTTONDOWN && recorded[2].type==SDL_MOUSEBUTTONUP);
    assert(recorded[1].button.state==SDL_PRESSED && recorded[2].button.state==SDL_RELEASED);
    assert(recorded[1].button.windowID==7 && recorded[2].button.x==500 && recorded[1].button.clicks==1);
    click(NULL);assert(ok_value);click(NULL);assert(!ok_value && queued==2);
    setup();key=1;begin(NULL);assert(!ok_value && !armed);
    setup();mouse=1;begin(NULL);assert(!ok_value && !armed);
    setup();focus=NULL;begin(NULL);assert(!ok_value && !armed);
    setup();begin(NULL);clock_value=5001;click(NULL);assert(!ok_value && queued==0 && !armed);
    setup();begin(NULL);focus=NULL;click(NULL);assert(!ok_value && queued==0 && !armed);
    setup();begin(NULL);w=1280;click(NULL);assert(!ok_value && queued==0 && !armed);
    setup();begin(NULL);args[0]=1920;click(NULL);assert(!ok_value && queued==0);
    setup();begin(NULL);args[0]=0.5;click(NULL);assert(!ok_value && queued==0);
    setup();begin(NULL);top=1;click(NULL);assert(!ok_value && queued==0);
    setup();begin(NULL);queue_result=1;click(NULL);assert(!ok_value && queued==1 && !armed);
    click(NULL);assert(!ok_value && queued==1);
    setup();begin(NULL);finish(NULL);click(NULL);assert(!ok_value && queued==0);
    puts("Native bridge contracts passed: event pair, budget, held inputs, focus, timeout, resize, bounds, partial queue, stop.");
    return 0;
}
