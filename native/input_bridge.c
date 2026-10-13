/* Original bounded Windows mouse input bridge. No game addresses or state writes.
 * Uses the public SDL2/Lua 5.1 ABI from separately obtained headers.
 * Input submission is NOT action completion or complete input authorization. */
#include <windows.h>
#include <stddef.h>
#include <string.h>
#include "SDL.h"
#include "SDL_syswm.h"
#include "lua.h"
#define FN(ret,name,args) static ret (__cdecl *p_##name) args
FN(int,lua_gettop,(lua_State*));
FN(int,lua_type,(lua_State*,int));
FN(lua_Number,lua_tonumber,(lua_State*,int));
FN(void,lua_pushboolean,(lua_State*,int));
FN(void,lua_pushnumber,(lua_State*,lua_Number));
FN(void,lua_pushstring,(lua_State*,const char*));
FN(void,lua_pushcclosure,(lua_State*,lua_CFunction,int));
FN(void,lua_createtable,(lua_State*,int,int));
FN(void,lua_setfield,(lua_State*,int,const char*));
FN(void,SDL_GetVersion,(SDL_version*));
FN(SDL_Window*,SDL_GetKeyboardFocus,(void));
FN(Uint32,SDL_GetWindowID,(SDL_Window*));
FN(void,SDL_GetWindowSize,(SDL_Window*,int*,int*));
FN(void,SDL_WarpMouseInWindow,(SDL_Window*,int,int));
FN(Uint32,SDL_GetMouseState,(int*,int*));
FN(const Uint8*,SDL_GetKeyboardState,(int*));
FN(Uint32,SDL_GetTicks,(void));
FN(SDL_bool,SDL_GetWindowWMInfo,(SDL_Window*,SDL_SysWMinfo*));
FN(SDL_bool,SDL_GetEventFilter,(SDL_EventFilter*,void**));
static SDL_Window *target;
static Uint32 started, window_id;
static int armed, clicks, width, height;
static HWND native_window;
static HANDLE release_timer;
static volatile LONG pressed, release_failed, releases;
/* Mock builds cannot fall back to real Windows input functions. */
#ifdef ITB_BRIDGE_TEST
#define OS_DEFAULT(name) NULL
#else
#define OS_DEFAULT(name) name
#endif
static UINT (WINAPI *send_input)(UINT,LPINPUT,int)=OS_DEFAULT(SendInput);
static BOOL (WINAPI *create_timer)(PHANDLE,HANDLE,WAITORTIMERCALLBACK,PVOID,DWORD,DWORD,ULONG)=OS_DEFAULT(CreateTimerQueueTimer);
static BOOL (WINAPI *delete_timer)(HANDLE,HANDLE,HANDLE)=OS_DEFAULT(DeleteTimerQueueTimer);
static HWND (WINAPI *foreground)(void)=OS_DEFAULT(GetForegroundWindow);
static DWORD (WINAPI *window_owner)(HWND,LPDWORD)=OS_DEFAULT(GetWindowThreadProcessId);
static SHORT (WINAPI *async_key)(int)=OS_DEFAULT(GetAsyncKeyState);
static BOOL (WINAPI *client_to_screen)(HWND,LPPOINT)=OS_DEFAULT(ClientToScreen);
static BOOL (WINAPI *screen_to_client)(HWND,LPPOINT)=OS_DEFAULT(ScreenToClient);
static BOOL (WINAPI *cursor_position)(LPPOINT)=OS_DEFAULT(GetCursorPos);
static int (WINAPI *system_metric)(int)=OS_DEFAULT(GetSystemMetrics);
static void CALLBACK release_button(PVOID context,BOOLEAN fired) {
    INPUT input; (void)context;(void)fired;
    if(InterlockedExchange(&pressed,0)) {
        memset(&input,0,sizeof(input));input.type=INPUT_MOUSE;
        input.mi.dwFlags=MOUSEEVENTF_LEFTUP;input.mi.dwExtraInfo=0x49544243;
        if(send_input(1,&input,sizeof(input))!=1) InterlockedExchange(&release_failed,1);
        else InterlockedIncrement(&releases);
    }
}
static int cleanup_press(void) {
    if(release_timer) {
        if(!delete_timer(NULL,release_timer,INVALID_HANDLE_VALUE)) {
            release_button(NULL,FALSE);InterlockedExchange(&release_failed,1);return 0;
        }
        release_timer=NULL;
    }
    release_button(NULL,FALSE);return 1;
}
static int own_foreground(void) {
    DWORD owner=0;
    return native_window && foreground()==native_window && window_owner(native_window,&owner)
        && owner==GetCurrentProcessId();
}
#include "window_guard.h"
typedef char event_size_check[sizeof(SDL_Event)==56 ? 1 : -1];
typedef char button_layout_check[offsetof(SDL_MouseButtonEvent,x)==20 ? 1 : -1];
static int result(lua_State *L,int ok,const char *message) {
    p_lua_pushboolean(L,ok); p_lua_pushstring(L,message); return 2;
}
static int held(void) {
    int count=0,i; const Uint8 *keys=p_SDL_GetKeyboardState(&count);
    const int guards[]={VK_LBUTTON,VK_RBUTTON,VK_MBUTTON,VK_CONTROL,VK_SHIFT,VK_MENU,VK_LWIN,VK_RWIN,VK_ESCAPE};
    for(unsigned j=0;j<sizeof(guards)/sizeof(guards[0]);j++) if(async_key(guards[j]) & 0x8000) return 1;
    if(!keys || count<1 || count>1024 || p_SDL_GetMouseState(NULL,NULL)) return 1;
    for(i=0;i<count;i++) if(keys[i]) return 1;
    return 0;
}
static int begin(lua_State *L) {
    SDL_EventFilter filter=NULL; void *data=NULL; SDL_SysWMinfo wm;
    guard_tick();
    if(session_state>=2)return result(L,0,"protected-session-stopped");
    if(armed) return result(L,0,"session-already-active");
    target=p_SDL_GetKeyboardFocus();
    if(!target || held()) return result(L,0,"focus-or-held-input");
    /* An unknown event filter could consume native mouse delivery. Refuse that setup. */
    if(p_SDL_GetEventFilter(&filter,&data)) return result(L,0,"existing-event-filter");
    memset(&wm,0,sizeof(wm));SDL_VERSION(&wm.version);
    if(!p_SDL_GetWindowWMInfo(target,&wm) || wm.subsystem!=SDL_SYSWM_WINDOWS)
        return result(L,0,"unsupported-window-backend");
    native_window=wm.info.win.window;
    if(!own_foreground()) return result(L,0,"wrong-foreground-process");
    if(!cleanup_press()) return result(L,0,"timer-cleanup-failed");
    InterlockedExchange(&release_failed,0);InterlockedExchange(&releases,0);
    p_SDL_GetWindowSize(target,&width,&height);
    if(width<640 || height<480 || width>8192 || height>8192) return result(L,0,"window-size");
    guard_tick();
    if(guard_active && (guarded_window!=native_window || guard_tails()))return result(L,0,"guard-window-or-held-input");
    if(!guard_active && !guard_install(5000,1)) return result(L,0,"window-guard-unavailable");
    window_id=p_SDL_GetWindowID(target); started=p_SDL_GetTicks(); clicks=0; armed=1;
    return result(L,1,"armed-for-two-clicks");
}
static int aim(lua_State *L) {
    double x,y; POINT point; INPUT input;
    guard_tick();
    if(!armed || !guard_active || guard_expired || !own_foreground() || p_SDL_GetKeyboardFocus()!=target || p_SDL_GetTicks()-started>5000 || held())
        return result(L,0,"aim-session-invalid");
    if(p_lua_gettop(L)!=2 || p_lua_type(L,1)!=LUA_TNUMBER || p_lua_type(L,2)!=LUA_TNUMBER)
        return result(L,0,"aim-coordinates-invalid");
    x=p_lua_tonumber(L,1);y=p_lua_tonumber(L,2);
    if(!(x>=0 && x<width && y>=0 && y<height) || x!=(int)x || y!=(int)y)
        return result(L,0,"aim-outside-window");
    point.x=(LONG)x;point.y=(LONG)y;
    if(!client_to_screen(native_window,&point)) return result(L,0,"client-coordinate-failed");
    int left=system_metric(SM_XVIRTUALSCREEN),top=system_metric(SM_YVIRTUALSCREEN);
    int desktop_w=system_metric(SM_CXVIRTUALSCREEN),desktop_h=system_metric(SM_CYVIRTUALSCREEN);
    if(desktop_w<1 || desktop_h<1 || point.x<left || point.y<top
        || point.x>=left+desktop_w || point.y>=top+desktop_h) return result(L,0,"outside-desktop");
    memset(&input,0,sizeof(input));input.type=INPUT_MOUSE;
    input.mi.dx=(LONG)(((double)(point.x-left)+0.5)*65536.0/desktop_w);
    input.mi.dy=(LONG)(((double)(point.y-top)+0.5)*65536.0/desktop_h);
    input.mi.dwFlags=MOUSEEVENTF_MOVE|MOUSEEVENTF_MOVE_NOCOALESCE|MOUSEEVENTF_ABSOLUTE|MOUSEEVENTF_VIRTUALDESK;
    input.mi.dwExtraInfo=0x49544243;
    if(!own_foreground() || send_input(1,&input,sizeof(input))!=1) return result(L,0,"motion-rejected");
    return result(L,1,"aimed-await-frame");
}
static int click(lua_State *L) {
    INPUT input; int x,y,w,h; double dx,dy;
    guard_tick();
    if(!armed || clicks>=2) return result(L,0,"click-budget-exhausted");
    if(!guard_active || guard_expired || !own_foreground() || pressed || release_failed || p_SDL_GetKeyboardFocus()!=target || p_SDL_GetTicks()-started>5000 || held()) {
        armed=0; return result(L,0,"focus-timeout-or-held-input");
    }
    p_SDL_GetWindowSize(target,&w,&h);
    if(w!=width || h!=height) { armed=0; return result(L,0,"window-resized"); }
    if(p_lua_gettop(L)!=2 || p_lua_type(L,1)!=LUA_TNUMBER || p_lua_type(L,2)!=LUA_TNUMBER)
        return result(L,0,"two-numeric-coordinates-required");
    dx=p_lua_tonumber(L,1);dy=p_lua_tonumber(L,2);
    if(!(dx>=0 && dx<width && dy>=0 && dy<height)) return result(L,0,"outside-window");
    x=(int)dx;y=(int)dy;
    if(dx!=x || dy!=y) return result(L,0,"integer-coordinates-required");
    clicks++; /* Never retry a partially delivered press. */
    int actual_x,actual_y;
    p_SDL_GetMouseState(&actual_x,&actual_y);
    if(actual_x<x-1 || actual_x>x+1 || actual_y<y-1 || actual_y>y+1) { armed=0;return result(L,0,"cursor-moved"); }
    POINT cursor;
    if(!cursor_position(&cursor) || !screen_to_client(native_window,&cursor)
        || cursor.x!=actual_x || cursor.y!=actual_y) { armed=0;return result(L,0,"native-cursor-moved"); }
    if(!cleanup_press()) { armed=0;return result(L,0,"timer-cleanup-failed"); }
    memset(&input,0,sizeof(input));input.type=INPUT_MOUSE;
    input.mi.dwFlags=MOUSEEVENTF_LEFTDOWN;input.mi.dwExtraInfo=0x49544243;
    if(send_input(1,&input,sizeof(input))!=1) { armed=0;return result(L,0,"mouse-down-rejected"); }
    InterlockedExchange(&pressed,1);
    /* Independent release even if the game stops advancing frames. No Lua on this worker. */
    if(!create_timer(&release_timer,NULL,release_button,NULL,80,0,WT_EXECUTEONLYONCE)) {
        release_button(NULL,FALSE);armed=0;return result(L,0,"release-timer-failed");
    }
    return result(L,1,"mouse-down-submitted-release-scheduled");
}
static int finish(lua_State *L) {
    cleanup_press();armed=0;target=NULL;
    if(guard_owned && session_state==0)guard_active=0;
    return result(L,1,"stopped");
}
static int guard_begin(lua_State *L) {
    SDL_SysWMinfo wm;
    if(armed || guard_active || session_state || held())return result(L,0,"guard-busy-or-held");
    SDL_Window *window=p_SDL_GetKeyboardFocus();
    if(!window)return result(L,0,"guard-no-focus");
    memset(&wm,0,sizeof(wm));SDL_VERSION(&wm.version);
    if(!p_SDL_GetWindowWMInfo(window,&wm) || wm.subsystem!=SDL_SYSWM_WINDOWS)
        return result(L,0,"guard-window-backend");
    native_window=wm.info.win.window;
    if(!guard_install(20000,0))return result(L,0,"guard-install-failed");
    return result(L,1,"guarded-for-20-seconds");
}
static int guard_end(lua_State *L) {
    if(session_state==1 || session_state==2) { session_fault("context-ended");return result(L,0,"session-remains-blocked"); }
    guard_active=0;guard_expired=1;return result(L,1,"guard-stopped");
}
static int session_begin(lua_State *L) {
    SDL_SysWMinfo wm;
    if(armed || guard_active || session_state || held() || guard_tails())return result(L,0,"session-busy-ended-or-held");
    SDL_Window *window=p_SDL_GetKeyboardFocus();
    if(!window)return result(L,0,"session-no-focus");
    memset(&wm,0,sizeof(wm));SDL_VERSION(&wm.version);
    if(!p_SDL_GetWindowWMInfo(window,&wm) || wm.subsystem!=SDL_SYSWM_WINDOWS)
        return result(L,0,"session-window-backend");
    native_window=wm.info.win.window;
    if(!guard_install(5000,0))return result(L,0,"session-install-failed");
    session_state=1;session_reason="protected";return result(L,1,"session-protected");
}
static int session_pulse(lua_State *L) {
    guard_tick();
    if(session_state!=1)return result(L,0,"session-not-running");
    if(!own_foreground()) { session_fault("focus-lost");return result(L,0,"session-focus-lost"); }
    if(release_failed) { session_fault("release-failed");return result(L,0,"session-release-failed"); }
    guard_started=p_SDL_GetTicks();return result(L,1,"session-healthy");
}
static int session_stop(lua_State *L) {
    session_fault("command-or-context-failed");cleanup_press();armed=0;
    return result(L,session_state==2,"session-stopped");
}
static int info(lua_State *L) {
    int mx=0,my=0;POINT cursor={0,0};
    guard_tick();
    p_SDL_GetMouseState(&mx,&my);
    p_lua_createtable(L,0,4);
    p_lua_pushnumber(L,mx);p_lua_setfield(L,-2,"mouseX");
    p_lua_pushnumber(L,my);p_lua_setfield(L,-2,"mouseY");
    if(native_window && cursor_position(&cursor) && screen_to_client(native_window,&cursor)) {
        p_lua_pushnumber(L,cursor.x);p_lua_setfield(L,-2,"cursorX");
        p_lua_pushnumber(L,cursor.y);p_lua_setfield(L,-2,"cursorY");
    }
    p_lua_pushstring(L,"itb-win32-click-v3");p_lua_setfield(L,-2,"abi");
    p_lua_pushnumber(L,session_state);p_lua_setfield(L,-2,"sessionState");
    p_lua_pushstring(L,session_reason);p_lua_setfield(L,-2,"sessionReason");
    p_lua_pushboolean(L,guard_active);p_lua_setfield(L,-2,"guardActive");
    p_lua_pushnumber(L,guard_active && !guard_expired?guard_duration-(p_SDL_GetTicks()-guard_started):0);p_lua_setfield(L,-2,"guardRemainingMs");
    p_lua_pushnumber(L,blocked_mouse);p_lua_setfield(L,-2,"blockedMouse");
    p_lua_pushnumber(L,blocked_keys);p_lua_setfield(L,-2,"blockedKeys");
    p_lua_pushnumber(L,blocked_raw);p_lua_setfield(L,-2,"blockedRaw");
    p_lua_pushnumber(L,passed_tagged);p_lua_setfield(L,-2,"passedTagged");
    p_lua_pushnumber(L,guard_tails());p_lua_setfield(L,-2,"guardHeld");
    p_lua_pushstring(L,guard_trace);p_lua_setfield(L,-2,"guardTrace");
    p_lua_pushnumber(L,sizeof(void*)*8);p_lua_setfield(L,-2,"bits");
    p_lua_pushnumber(L,clicks);p_lua_setfield(L,-2,"clicks");
    p_lua_pushboolean(L,pressed);p_lua_setfield(L,-2,"pressed");
    p_lua_pushboolean(L,release_failed);p_lua_setfield(L,-2,"releaseFailed");
    p_lua_pushnumber(L,releases);p_lua_setfield(L,-2,"releases");
    p_lua_pushboolean(L,armed);p_lua_setfield(L,-2,"armed");return 1;
}
#define LOAD(module,name) p_##name=(void*)GetProcAddress(module,#name);if(!p_##name)return 0
__declspec(dllexport) int __cdecl luaopen_itb_input(lua_State *L) {
    HMODULE lua=GetModuleHandleW(L"lua5.1.dll"),sdl=GetModuleHandleW(L"SDL2.dll");
    SDL_version version;
    if(sizeof(void*)!=4 || !lua || !sdl)return 0;
    LOAD(lua,lua_gettop);LOAD(lua,lua_type);LOAD(lua,lua_tonumber);LOAD(lua,lua_pushboolean);
    LOAD(lua,lua_pushnumber);LOAD(lua,lua_pushstring);LOAD(lua,lua_pushcclosure);
    LOAD(lua,lua_createtable);LOAD(lua,lua_setfield);
    LOAD(sdl,SDL_GetVersion);LOAD(sdl,SDL_GetKeyboardFocus);LOAD(sdl,SDL_GetWindowID);
    LOAD(sdl,SDL_GetWindowSize);LOAD(sdl,SDL_WarpMouseInWindow);LOAD(sdl,SDL_GetMouseState);
    LOAD(sdl,SDL_GetKeyboardState);LOAD(sdl,SDL_GetTicks);LOAD(sdl,SDL_GetWindowWMInfo);LOAD(sdl,SDL_GetEventFilter);
    p_SDL_GetVersion(&version);
    if(version.major!=2 || version.minor!=0 || version.patch!=10) return result(L,0,"unsupported-SDL-version");
    p_lua_createtable(L,0,4);
    p_lua_pushcclosure(L,begin,0);p_lua_setfield(L,-2,"begin");
    p_lua_pushcclosure(L,aim,0);p_lua_setfield(L,-2,"aim");
    p_lua_pushcclosure(L,click,0);p_lua_setfield(L,-2,"click");
    p_lua_pushcclosure(L,finish,0);p_lua_setfield(L,-2,"finish");
    p_lua_pushcclosure(L,info,0);p_lua_setfield(L,-2,"info");
    p_lua_pushcclosure(L,guard_begin,0);p_lua_setfield(L,-2,"guardBegin");
    p_lua_pushcclosure(L,guard_end,0);p_lua_setfield(L,-2,"guardEnd");
    p_lua_pushcclosure(L,session_begin,0);p_lua_setfield(L,-2,"sessionBegin");
    p_lua_pushcclosure(L,session_pulse,0);p_lua_setfield(L,-2,"sessionPulse");
    p_lua_pushcclosure(L,session_stop,0);p_lua_setfield(L,-2,"sessionStop");return 1;
}
