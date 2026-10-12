/* Original bounded SDL input bridge. No game addresses, hooks or state writes.
 * Uses the public SDL2/Lua 5.1 ABI from separately obtained headers.
 * Queue delivery is NOT action completion or complete input authorization. */
#include <windows.h>
#include <stddef.h>
#include <string.h>
#include "SDL.h"
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
FN(int,SDL_PeepEvents,(SDL_Event*,int,SDL_eventaction,Uint32,Uint32));
FN(SDL_bool,SDL_GetEventFilter,(SDL_EventFilter*,void**));
static SDL_Window *target;
static Uint32 started, window_id;
static int armed, clicks, width, height;
typedef char event_size_check[sizeof(SDL_Event)==56 ? 1 : -1];
typedef char button_layout_check[offsetof(SDL_MouseButtonEvent,x)==20 ? 1 : -1];
static int result(lua_State *L,int ok,const char *message) {
    p_lua_pushboolean(L,ok); p_lua_pushstring(L,message); return 2;
}
static int held(void) {
    int count=0,i; const Uint8 *keys=p_SDL_GetKeyboardState(&count);
    if(!keys || count<1 || count>1024 || p_SDL_GetMouseState(NULL,NULL)) return 1;
    for(i=0;i<count;i++) if(keys[i]) return 1;
    return 0;
}
static int begin(lua_State *L) {
    SDL_EventFilter filter=NULL; void *data=NULL;
    if(armed) return result(L,0,"session-already-active");
    target=p_SDL_GetKeyboardFocus();
    if(!target || held()) return result(L,0,"focus-or-held-input");
    /* An unknown event filter could transform/drop our batch. Do not bypass it. */
    if(p_SDL_GetEventFilter(&filter,&data)) return result(L,0,"existing-event-filter");
    p_SDL_GetWindowSize(target,&width,&height);
    if(width<640 || height<480 || width>8192 || height>8192) return result(L,0,"window-size");
    window_id=p_SDL_GetWindowID(target); started=p_SDL_GetTicks(); clicks=0; armed=1;
    return result(L,1,"armed-for-two-clicks");
}
static int aim(lua_State *L) {
    double x,y;
    if(!armed || p_SDL_GetKeyboardFocus()!=target || p_SDL_GetTicks()-started>5000 || held())
        return result(L,0,"aim-session-invalid");
    if(p_lua_gettop(L)!=2 || p_lua_type(L,1)!=LUA_TNUMBER || p_lua_type(L,2)!=LUA_TNUMBER)
        return result(L,0,"aim-coordinates-invalid");
    x=p_lua_tonumber(L,1);y=p_lua_tonumber(L,2);
    if(!(x>=0 && x<width && y>=0 && y<height) || x!=(int)x || y!=(int)y)
        return result(L,0,"aim-outside-window");
    p_SDL_WarpMouseInWindow(target,(int)x,(int)y);
    return result(L,1,"aimed-await-frame");
}
static int click(lua_State *L) {
    SDL_Event events[3]; int x,y,w,h,count; double dx,dy;
    if(!armed || clicks>=2) return result(L,0,"click-budget-exhausted");
    if(p_SDL_GetKeyboardFocus()!=target || p_SDL_GetTicks()-started>5000 || held()) {
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
    if(actual_x!=x || actual_y!=y) { armed=0;return result(L,0,"cursor-moved"); }
    memset(events,0,sizeof(events));
    /* The loader caches hoveredchild on motion, not on a button event. */
    events[0].motion.type=SDL_MOUSEMOTION;events[0].motion.windowID=window_id;
    events[0].motion.x=x;events[0].motion.y=y;events[0].motion.timestamp=p_SDL_GetTicks();
    events[1].button.type=SDL_MOUSEBUTTONDOWN;events[2].button.type=SDL_MOUSEBUTTONUP;
    for(int i=1;i<3;i++) {
        events[i].button.windowID=window_id;events[i].button.timestamp=p_SDL_GetTicks();
        events[i].button.which=0;events[i].button.button=SDL_BUTTON_LEFT;
        events[i].button.state=i==1?SDL_PRESSED:SDL_RELEASED;
        events[i].button.clicks=1;events[i].button.x=x;events[i].button.y=y;
    }
    count=p_SDL_PeepEvents(events,3,SDL_ADDEVENT,0,0);
    if(count!=3) armed=0;
    p_lua_pushboolean(L,count==3);p_lua_pushnumber(L,count);return 2;
}
static int finish(lua_State *L) { armed=0;target=NULL;return result(L,1,"stopped"); }
static int info(lua_State *L) {
    p_lua_createtable(L,0,4);
    p_lua_pushstring(L,"itb-sdl-click-v1");p_lua_setfield(L,-2,"abi");
    p_lua_pushnumber(L,sizeof(void*)*8);p_lua_setfield(L,-2,"bits");
    p_lua_pushnumber(L,clicks);p_lua_setfield(L,-2,"clicks");
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
    LOAD(sdl,SDL_GetKeyboardState);LOAD(sdl,SDL_GetTicks);LOAD(sdl,SDL_PeepEvents);LOAD(sdl,SDL_GetEventFilter);
    p_SDL_GetVersion(&version);
    if(version.major!=2 || version.minor!=0 || version.patch!=10) return result(L,0,"unsupported-SDL-version");
    p_lua_createtable(L,0,4);
    p_lua_pushcclosure(L,begin,0);p_lua_setfield(L,-2,"begin");
    p_lua_pushcclosure(L,aim,0);p_lua_setfield(L,-2,"aim");
    p_lua_pushcclosure(L,click,0);p_lua_setfield(L,-2,"click");
    p_lua_pushcclosure(L,finish,0);p_lua_setfield(L,-2,"finish");
    p_lua_pushcclosure(L,info,0);p_lua_setfield(L,-2,"info");return 1;
}
