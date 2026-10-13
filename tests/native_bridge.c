#undef NDEBUG
#define ITB_BRIDGE_TEST
#define SDL_MAIN_HANDLED
#include <assert.h>
#include <stdio.h>
#include "../native/input_bridge.c"
/* All OS input functions are replaced before any test; no real input is sent. */
static int ok_value,top=2,kind=LUA_TNUMBER,w=1920,h=1080,mouse,key,warps,downs,ups,timer_ok=1,send_ok=1,physical;
static double args[2]={500,500};
static Uint32 clock_value;
static SDL_Window *focus=(SDL_Window*)1;
static HWND front=(HWND)2;
static WAITORTIMERCALLBACK timer_callback;
static int gettop(lua_State *L){(void)L;return top;}
static int gettype(lua_State *L,int i){(void)L;(void)i;return kind;}
static double getnum(lua_State *L,int i){(void)L;return args[i-1];}
static void push_bool(lua_State *L,int b){(void)L;ok_value=b;}
static void num(lua_State *L,double n){(void)L;(void)n;}
static void string(lua_State *L,const char *s){(void)L;(void)s;}
static SDL_Window *getfocus(void){return focus;}
static Uint32 getid(SDL_Window *p){assert(p==focus);return 7;}
static void getsize(SDL_Window *p,int *x,int *y){(void)p;*x=w;*y=h;}
static Uint32 getmouse(int *x,int *y){if(x)*x=500;if(y)*y=500;return mouse;}
static const Uint8 *getkeys(int *n){static Uint8 keys[512];memset(keys,0,sizeof(keys));keys[9]=key;*n=512;return keys;}
static Uint32 ticks(void){return clock_value;}
static SDL_bool filter(SDL_EventFilter *f,void **d){(void)f;(void)d;return SDL_FALSE;}
static SDL_bool wm_info(SDL_Window *p,SDL_SysWMinfo *wm){(void)p;wm->subsystem=SDL_SYSWM_WINDOWS;wm->info.win.window=(HWND)2;return SDL_TRUE;}
static void warp(SDL_Window *p,int x,int y){assert(p==focus && x==args[0] && y==args[1]);warps++;}
static HWND WINAPI getfront(void){return front;}
static DWORD WINAPI owner(HWND hwnd,LPDWORD pid){assert(hwnd==(HWND)2);*pid=GetCurrentProcessId();return GetCurrentThreadId();}
static int subclass_ok,forwarded,raw_cleaned;
static LPARAM extra_value;
static BOOL WINAPI subclass_fake(HWND hwnd,SUBCLASSPROC proc,UINT_PTR id,DWORD_PTR data) {
    assert(hwnd==(HWND)2 && proc==guard_proc && id==INPUT_MARKER && data==0);return subclass_ok;
}
static BOOL WINAPI remove_fake(HWND hwnd,SUBCLASSPROC proc,UINT_PTR id) {
    assert(hwnd==(HWND)2 && proc==guard_proc && id==INPUT_MARKER);return TRUE;
}
static LRESULT WINAPI next_fake(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    (void)hwnd;(void)msg;(void)wp;(void)lp;forwarded++;return 77;
}
static LRESULT WINAPI default_fake(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    (void)hwnd;(void)wp;(void)lp;assert(msg==WM_INPUT);raw_cleaned++;return 0;
}
static LPARAM WINAPI extra_fake(void){return extra_value;}
static BOOL WINAPI pin_fake(DWORD flags,LPCSTR address,HMODULE *module) {
    assert(flags==(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN));
    assert(address==(LPCSTR)guard_proc);*module=(HMODULE)4;return TRUE;
}
static LRESULT message(UINT msg,WPARAM wp){return guard_proc((HWND)2,msg,wp,0,INPUT_MARKER,0);}
static SHORT WINAPI asynchronous(int v){(void)v;return physical?0x8000:0;}
static BOOL WINAPI convert_point(HWND hwnd,LPPOINT point){assert(hwnd==(HWND)2);(void)point;return TRUE;}
static BOOL WINAPI get_cursor(LPPOINT point){point->x=500;point->y=500;return TRUE;}
static int WINAPI metric(int v){if(v==SM_CXVIRTUALSCREEN)return 1920;if(v==SM_CYVIRTUALSCREEN)return 1080;return 0;}
static UINT WINAPI send_fake(UINT count,LPINPUT input,int size){
    assert(count==1 && size==sizeof(INPUT) && input->type==INPUT_MOUSE);
    assert(input->mi.dwExtraInfo==0x49544243);
    if(!send_ok)return 0;
    if(input->mi.dwFlags==MOUSEEVENTF_LEFTDOWN)downs++;
    else if(input->mi.dwFlags==(MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK)) {
        assert(input->mi.dx==17083 && input->mi.dy==30371);warps++;
    }
    else {assert(input->mi.dwFlags==MOUSEEVENTF_LEFTUP);ups++;}
    return 1;
}
static BOOL WINAPI timer_fake(PHANDLE handle,HANDLE q,WAITORTIMERCALLBACK cb,PVOID p,DWORD due,DWORD period,ULONG flags){
    assert(!q && !p && due==80 && period==0 && flags==WT_EXECUTEONLYONCE);
    if(!timer_ok)return FALSE;
    *handle=(HANDLE)3;timer_callback=cb;return TRUE;
}
static BOOL WINAPI delete_fake(HANDLE q,HANDLE timer,HANDLE complete){assert(!q && timer==(HANDLE)3 && complete==INVALID_HANDLE_VALUE);timer_callback=NULL;return TRUE;}
static void elapsed(void){assert(timer_callback);timer_callback(NULL,FALSE);}
static void setup(void){
    guard_active=guard_owned=guard_expired=0;guarded_window=NULL;
    memset(blocked_held,0,sizeof(blocked_held));subclass_ok=1;extra_value=0;forwarded=raw_cleaned=0;
    set_subclass=subclass_fake;remove_subclass=remove_fake;next_subclass=next_fake;
    default_window=default_fake;message_extra=extra_fake;
    pin_module=pin_fake;
    armed=0;pressed=release_failed=releases=0;release_timer=NULL;timer_callback=NULL;
    clicks=warps=downs=ups=0;focus=(SDL_Window*)1;front=(HWND)2;clock_value=0;w=1920;h=1080;
    mouse=key=physical=0;timer_ok=send_ok=1;args[0]=500;args[1]=500;top=2;kind=LUA_TNUMBER;
    p_lua_gettop=gettop;p_lua_type=gettype;p_lua_tonumber=getnum;p_lua_pushboolean=push_bool;
    p_lua_pushnumber=num;p_lua_pushstring=string;p_SDL_GetKeyboardFocus=getfocus;
    p_SDL_GetWindowID=getid;p_SDL_GetWindowSize=getsize;p_SDL_GetMouseState=getmouse;
    p_SDL_GetKeyboardState=getkeys;p_SDL_GetTicks=ticks;p_SDL_GetEventFilter=filter;
    p_SDL_WarpMouseInWindow=warp;p_SDL_GetWindowWMInfo=wm_info;
    send_input=send_fake;create_timer=timer_fake;delete_timer=delete_fake;
    foreground=getfront;window_owner=owner;async_key=asynchronous;
    client_to_screen=convert_point;screen_to_client=convert_point;cursor_position=get_cursor;system_metric=metric;
}
int main(void){
    setup();begin(NULL);assert(ok_value);aim(NULL);assert(ok_value);click(NULL);
    assert(ok_value && downs==1 && ups==0 && pressed && warps==1);
    elapsed();assert(!pressed && ups==1 && releases==1);
    click(NULL);assert(ok_value && downs==2);elapsed();click(NULL);assert(!ok_value && downs==2);
    setup();key=1;begin(NULL);assert(!ok_value && !armed);
    setup();physical=1;begin(NULL);assert(!ok_value && !armed);
    setup();mouse=1;begin(NULL);assert(!ok_value && !armed);
    setup();focus=NULL;begin(NULL);assert(!ok_value && !armed);
    setup();front=NULL;begin(NULL);assert(!ok_value && !armed);
    setup();begin(NULL);clock_value=5001;click(NULL);assert(!ok_value && downs==0 && !armed);
    setup();begin(NULL);focus=NULL;click(NULL);assert(!ok_value && downs==0 && !armed);
    setup();begin(NULL);front=NULL;click(NULL);assert(!ok_value && downs==0 && !armed);
    setup();begin(NULL);w=1280;click(NULL);assert(!ok_value && downs==0 && !armed);
    setup();begin(NULL);args[0]=1920;click(NULL);assert(!ok_value && downs==0);
    setup();begin(NULL);args[0]=0.5;click(NULL);assert(!ok_value && downs==0);
    setup();begin(NULL);args[0]=502;click(NULL);assert(!ok_value && downs==0);
    setup();begin(NULL);top=1;click(NULL);assert(!ok_value && downs==0);
    setup();begin(NULL);timer_ok=0;click(NULL);assert(!ok_value && downs==1 && ups==1 && !pressed && !armed);
    setup();begin(NULL);send_ok=0;click(NULL);assert(!ok_value && downs==0 && !pressed);
    setup();begin(NULL);click(NULL);finish(NULL);assert(ups==1 && !pressed && !armed);click(NULL);assert(!ok_value && downs==1);
    setup();begin(NULL);click(NULL);send_ok=0;elapsed();assert(release_failed && !pressed);click(NULL);assert(!ok_value && downs==1);
    setup();subclass_ok=0;begin(NULL);assert(!ok_value && !armed && !guard_active);
    setup();begin(NULL);assert(guard_active && guard_owned);
    assert(message(WM_LBUTTONDOWN,0)==0 && blocked_mouse==1 && guard_tails()==1);
    assert(message(WM_LBUTTONUP,0)==0 && guard_tails()==0);
    assert(message(WM_KEYDOWN,VK_TAB)==0 && blocked_keys==1);
    assert(message(WM_CHAR,9)==0 && blocked_keys==2);
    assert(message(WM_INPUT,0)==0 && raw_cleaned==1 && forwarded==0);
    extra_value=INPUT_MARKER;assert(message(WM_MOUSEMOVE,0)==77 && passed_tagged==1);
    assert(message(WM_KEYDOWN,VK_ESCAPE)==0); /* Marker never permits keyboard. */
    extra_value=0;clock_value=5000;
    assert(message(WM_KEYDOWN,VK_TAB)==0 && !guard_active); /* Held repeat tail. */
    assert(message(WM_KEYUP,VK_TAB)==0 && blocked_held[VK_TAB]==0);
    assert(message(WM_KEYUP,VK_ESCAPE)==0 && guard_tails()==0);
    assert(message(WM_KEYDOWN,VK_TAB)==77); /* Fresh press after timeout. */
    setup();guard_begin(NULL);assert(ok_value && guard_active && !guard_owned);
    begin(NULL);assert(ok_value && guard_active);finish(NULL);assert(guard_active);
    clock_value=20000;guard_tick();assert(!guard_active && guard_expired);
    setup();begin(NULL);finish(NULL);assert(!guard_active);
    setup();begin(NULL);message(WM_KILLFOCUS,0);assert(!guard_active && !armed);
    setup();begin(NULL);assert(message(WM_CLOSE,0)==77 && guard_active);
    message(WM_NCDESTROY,0);assert(!guard_active && !guarded_window && !armed);
    puts("Native contracts passed: input submission, window guard, tagged mouse, blocked keyboard/raw input, held tails, lifecycle and time bounds.");
    return 0;
}
