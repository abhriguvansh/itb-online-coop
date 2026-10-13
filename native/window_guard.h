/* Game-window-only diagnostic. No global hooks or gameplay state writes.
 * Runs on the window thread, before SDL's window procedure. The marker separates
 * cooperative input sources; it is not authentication against a malicious process. */
#include <commctrl.h>
#include <stdio.h>
#define INPUT_MARKER ((ULONG_PTR)0x49544243)
static BOOL (WINAPI *set_subclass)(HWND,SUBCLASSPROC,UINT_PTR,DWORD_PTR)=OS_DEFAULT(SetWindowSubclass);
static BOOL (WINAPI *remove_subclass)(HWND,SUBCLASSPROC,UINT_PTR)=OS_DEFAULT(RemoveWindowSubclass);
static LRESULT (WINAPI *next_subclass)(HWND,UINT,WPARAM,LPARAM)=OS_DEFAULT(DefSubclassProc);
static LRESULT (WINAPI *default_window)(HWND,UINT,WPARAM,LPARAM)=OS_DEFAULT(DefWindowProcW);
static LPARAM (WINAPI *message_extra)(void)=OS_DEFAULT(GetMessageExtraInfo);
static BOOL (WINAPI *pin_module)(DWORD,LPCSTR,HMODULE*)=OS_DEFAULT(GetModuleHandleExA);
static HWND guarded_window;
static int guard_active, guard_owned, guard_expired;
static Uint32 guard_started,guard_duration;
static unsigned blocked_mouse,blocked_keys,passed_tagged,blocked_raw;
static unsigned char blocked_held[256];
static char guard_trace[2048];
static unsigned guard_trace_count;
static int guard_tails(void) {
    int n=0;for(int i=0;i<256;i++)n+=blocked_held[i]!=0;return n;
}
static void guard_tick(void) {
    if(guard_active && p_SDL_GetTicks()-guard_started>=guard_duration) {
        guard_active=0;guard_expired=1;
    }
}
static LRESULT CALLBACK guard_proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp,UINT_PTR id,DWORD_PTR data) {
    int key=-1,down=0,up=0,mouse_message=0,key_message=0;
    (void)data;
    guard_tick();
    if(msg==WM_NCDESTROY) {
        guard_active=0;armed=0;guarded_window=NULL;
        memset(blocked_held,0,sizeof(blocked_held));
        remove_subclass(hwnd,guard_proc,id);
        return next_subclass(hwnd,msg,wp,lp);
    }
    if(msg==WM_KILLFOCUS) { guard_active=0;guard_expired=1;armed=0; }
    switch(msg) {
    case WM_KEYDOWN:case WM_SYSKEYDOWN: down=1;key_message=1;key=wp<256?(int)wp:-1;break;
    case WM_KEYUP:case WM_SYSKEYUP: up=1;key_message=1;key=wp<256?(int)wp:-1;break;
    case WM_CHAR:case WM_SYSCHAR:case WM_DEADCHAR:case WM_SYSDEADCHAR:case WM_UNICHAR:
        key_message=1;break;
    case WM_LBUTTONDOWN:case WM_LBUTTONDBLCLK:down=1;key=VK_LBUTTON;mouse_message=1;break;
    case WM_LBUTTONUP:up=1;key=VK_LBUTTON;mouse_message=1;break;
    case WM_RBUTTONDOWN:case WM_RBUTTONDBLCLK:down=1;key=VK_RBUTTON;mouse_message=1;break;
    case WM_RBUTTONUP:up=1;key=VK_RBUTTON;mouse_message=1;break;
    case WM_MBUTTONDOWN:case WM_MBUTTONDBLCLK:down=1;key=VK_MBUTTON;mouse_message=1;break;
    case WM_MBUTTONUP:up=1;key=VK_MBUTTON;mouse_message=1;break;
    case WM_XBUTTONDOWN:case WM_XBUTTONDBLCLK:down=1;key=HIWORD(wp)==XBUTTON1?VK_XBUTTON1:VK_XBUTTON2;mouse_message=1;break;
    case WM_XBUTTONUP:up=1;key=HIWORD(wp)==XBUTTON1?VK_XBUTTON1:VK_XBUTTON2;mouse_message=1;break;
    case WM_MOUSEMOVE:case WM_MOUSEWHEEL:case WM_MOUSEHWHEEL:mouse_message=1;break;
    }
    /* Allow only the bridge's mouse message family, never tagged keyboard input.
     * Releases may still be queued when finish() disarms the command. */
    if(guard_active && mouse_message && guard_trace_count<16) {
        size_t used=strlen(guard_trace);
        snprintf(guard_trace+used,sizeof(guard_trace)-used,"%u:%d,%d:%lx;",msg,
            (int)(short)LOWORD(lp),(int)(short)HIWORD(lp),(unsigned long)message_extra());
        guard_trace_count++;
    }
    if((ULONG_PTR)message_extra()==INPUT_MARKER &&
        (msg==WM_MOUSEMOVE || msg==WM_LBUTTONDOWN || msg==WM_LBUTTONUP)) {
        if(guard_active)passed_tagged++;
        return next_subclass(hwnd,msg,wp,lp);
    }
    if((mouse_message || key_message) &&
        (guard_active || (key>=0 && blocked_held[key]) || (key_message && key<0 && guard_tails()))) {
        if(key>=0) { if(down)blocked_held[key]=1;else if(up)blocked_held[key]=0; }
        if(mouse_message)blocked_mouse++;else blocked_keys++;
        return (msg==WM_XBUTTONDOWN || msg==WM_XBUTTONUP || msg==WM_XBUTTONDBLCLK)?TRUE:0;
    }
    if(guard_active && msg==WM_INPUT) {
        blocked_raw++;
        /* DefWindowProc performs raw-input cleanup without forwarding to SDL. */
        return default_window(hwnd,msg,wp,lp);
    }
    return next_subclass(hwnd,msg,wp,lp);
}
static int guard_install(Uint32 duration,int owned) {
    DWORD owner=0;
    if(!own_foreground() || window_owner(native_window,&owner)!=GetCurrentThreadId()
        || owner!=GetCurrentProcessId() || guard_tails())return 0;
    if(guarded_window && guarded_window!=native_window)return 0;
    if(!guarded_window) {
        HMODULE module=NULL;
        /* A Lua module handle may otherwise disappear before the window callback.
         * Keep this tiny DLL resident until process exit; never call Lua here. */
        if(!pin_module(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
            (LPCSTR)guard_proc,&module))return 0;
        if(!set_subclass(native_window,guard_proc,INPUT_MARKER,0))return 0;
        guarded_window=native_window;
    }
    guard_active=1;guard_owned=owned;guard_expired=0;
    guard_started=p_SDL_GetTicks();guard_duration=duration;
    blocked_mouse=blocked_keys=passed_tagged=blocked_raw=0;
    guard_trace[0]=0;guard_trace_count=0;
    return 1;
}
