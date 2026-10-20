/* Original, opt-in bootstrap for one pinned disposable-game fixture.
 * Four verified CALL sites consume their original draw once, then return an agreed
 * normal draw before native code commits the choice. No seed/board/save writes.
 * This is not a general RNG API. See docs/command-session.md (probe 0.21.0). */
#include <windows.h>
#include <wincrypt.h>
#include <stdint.h>
#include <string.h>
#include "lua.h"
#define FN(ret,name,args) static ret (__cdecl *p_##name) args
FN(void,lua_createtable,(lua_State*,int,int));
FN(void,lua_pushnumber,(lua_State*,lua_Number));
FN(void,lua_pushboolean,(lua_State*,int));
FN(void,lua_pushstring,(lua_State*,const char*));
FN(void,lua_setfield,(lua_State*,int,const char*));
FN(void,lua_rawseti,(lua_State*,int,int));
FN(void,lua_pushcclosure,(lua_State*,lua_CFunction,int));
FN(int,lua_type,(lua_State*,int));
FN(size_t,lua_objlen,(lua_State*,int));
FN(void,lua_rawgeti,(lua_State*,int,int));
FN(void,lua_getfield,(lua_State*,int,const char*));
FN(lua_Number,lua_tonumber,(lua_State*,int));
FN(const char*,lua_tolstring,(lua_State*,int,size_t*));
FN(void,lua_settop,(lua_State*,int));
static unsigned char *game;
static int (__cdecl *original_rand)(void);
static DWORD owner;
static int installed,fault,overflow,replaying,expected_count,sealed,attempted;
struct choice {int kind,value,limit;};
static struct choice choices[128];
struct entry { int kind,value,limit,applied; DWORD tick; };
static struct entry entries[128];
static int count;
static unsigned char saved[4][5],patched[4][5];
static DWORD page_protection[4];
static unsigned live_mask;
static BOOL (WINAPI *protect_page)(LPVOID,SIZE_T,DWORD,PDWORD)=VirtualProtect;
static BOOL (WINAPI *flush_cache)(HANDLE,LPCVOID,SIZE_T)=FlushInstructionCache;
static const DWORD sites[4]={0x0f5f22,0x172462,0x201c1c,0x201caa};
static const unsigned char expected[4][11]={{0xe8,0xef,0x1f,0x29,0,0x89,0x86,0x80,0,0,0},{0xe8,0xaf,0x5a,0x21,0,0x99,0xf7,0xff,0x8b,0x7c,0xd6},{0xe8,0xf5,0x62,0x18,0x0,0x99,0xf7,0xfb,0x8b,0xda,0x8b},{0xe8,0x67,0x62,0x18,0x0,0x99,0xb9,0x64,0x0,0x0,0x0}};
static int verify_file(void) {
    WCHAR path[MAX_PATH]; BYTE data[65536],hash[32]; DWORD got,n=32; int ok=0;
    HCRYPTPROV prov=0;HCRYPTHASH h=0;HANDLE file=INVALID_HANDLE_VALUE;
    static const BYTE expected_hash[32]={0x31,0xfe,0x35,0x26,0x55,0x98,0x23,0x98,0xfb,0x3e,0xe8,0xb0,0xbb,0xe8,0x0e,0xfd,0x5d,0x65,0xe3,0xa9,0xaa,0x11,0xe3,0xdc,0x39,0xd0,0x36,0x43,0x54,0x49,0x3f,0xe9};
    if(!GetModuleFileNameW(NULL,path,MAX_PATH) || wcscmp(path,L"C:\\ITBCoopProbe\\GameVerified\\Breach.exe"))return 0;
    file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)goto done;
    if(!CryptAcquireContextW(&prov,NULL,NULL,PROV_RSA_AES,CRYPT_VERIFYCONTEXT) || !CryptCreateHash(prov,CALG_SHA_256,0,0,&h))goto done;
    for(;;){if(!ReadFile(file,data,sizeof(data),&got,NULL))goto done;if(!got)break;if(!CryptHashData(h,data,got,0))goto done;}
    ok=CryptGetHashParam(h,HP_HASHVAL,hash,&n,0) && n==32 && !memcmp(hash,expected_hash,32);
 done: if(h)CryptDestroyHash(h);if(prov)CryptReleaseContext(prov,0);if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);return ok;
}
static int patch(unsigned index,const unsigned char *before,const unsigned char *after,int applying) {
    DWORD prior,ignored;unsigned char *site=game+sites[index];
    if(memcmp(site,before,5) || !protect_page(site,5,PAGE_EXECUTE_READWRITE,&prior))return 0;
    memcpy(site,after,5);
    if(applying){page_protection[index]=prior;live_mask|=1u<<index;}
    else live_mask&=~(1u<<index);
    installed=live_mask!=0;
    int ok=flush_cache(GetCurrentProcess(),site,5)!=0;
    if(!protect_page(site,5,applying?prior:page_protection[index],&ignored))ok=0;
    return ok;
}
static int draw(int kind,int limit) {
    int value=original_rand();
    if(GetCurrentThreadId()!=owner){fault=3;return value;}
    if(count>=128){overflow=1;fault=4;return value;}
    if(value<0||value>32767||limit<1||limit>32768)fault=5;
    int applied=value;
    if(replaying && !fault){
        if(count>=expected_count || choices[count].kind!=kind || choices[count].limit!=limit)fault=8;
        else applied=choices[count].value;
    }
    entries[count].applied=applied;
    entries[count].kind=kind;entries[count].value=value;entries[count].limit=limit;entries[count].tick=GetTickCount();count++;
    return applied;
}
__attribute__((used,noinline)) static int __cdecl arrival_draw(int limit){return draw(2,limit);}
__attribute__((naked)) static int __cdecl arrival_hook(void){__asm__ volatile("pushl %ebx\n\tcalll _arrival_draw\n\taddl $4,%esp\n\tretl");}
static int __cdecl special_draw(void){return draw(3,100);}
static int __cdecl ai_draw(void){return draw(0,32768);}
__attribute__((used,noinline)) static int __cdecl pod_draw(int limit){return draw(1,limit);}
__attribute__((naked)) static int __cdecl pod_hook(void){__asm__ volatile("pushl %edi\n\tcalll _pod_draw\n\taddl $4,%esp\n\tretl");}
static int valid_choice(size_t i,int kind,int vt,int lt,lua_Number v,lua_Number limit){
    return i<19 && kind==(i<17?0:i==17?2:1) && vt==LUA_TNUMBER && lt==LUA_TNUMBER
        && v>=0 && v<=32767 && (int)v==v && limit==(i<17?32768:i==17?3:9);
}
static void restore_hooks(void){
    for(unsigned i=0;i<4;i++)if(live_mask&(1u<<i))if(!patch(i,patched[i],saved[i],0))fault=7;
}
static void field_num(lua_State *L,const char *key,int v){p_lua_pushnumber(L,v);p_lua_setfield(L,-2,key);}
static void field_bool(lua_State *L,const char *key,int v){p_lua_pushboolean(L,v);p_lua_setfield(L,-2,key);}
static int info(lua_State *L) {
    p_lua_createtable(L,0,10);p_lua_pushstring(L,"itb-initial-choices-v1");p_lua_setfield(L,-2,"abi");field_bool(L,"installed",installed);field_num(L,"fault",fault);field_bool(L,"overflow",overflow);field_num(L,"count",count);
    p_lua_createtable(L,count,0);
    for(int i=0;i<count;i++){p_lua_createtable(L,0,4);p_lua_pushstring(L,entries[i].kind==0?"ai-constructor":entries[i].kind==1?"pod-select":entries[i].kind==2?"pod-delivery":"pod-special");p_lua_setfield(L,-2,"kind");field_num(L,"value",entries[i].value);field_num(L,"limit",entries[i].limit);field_num(L,"tick",entries[i].tick);field_num(L,"applied",entries[i].applied);p_lua_rawseti(L,-2,i+1);}
    p_lua_setfield(L,-2,"entries");field_bool(L,"passThrough",!replaying);field_bool(L,"sealed",sealed);field_num(L,"expectedCount",expected_count);return 1;
}
static int install(lua_State *L) {
    WCHAR opt[16];
    if(attempted || fault)return info(L);
    DWORD nopt=GetEnvironmentVariableW(L"ITB_COOP_INITIAL_CHOICES",opt,16);
    if(!nopt)return info(L);
    attempted=1;
    if(nopt>=16 || (wcscmp(opt,L"capture")&&wcscmp(opt,L"replay")) ||
        ((p_lua_type(L,1)==LUA_TTABLE)!=(wcscmp(opt,L"replay")==0))){fault=11;return info(L);}
    if(p_lua_type(L,1)==LUA_TTABLE){
        size_t n=p_lua_objlen(L,1);if(n!=19){fault=9;return info(L);}
        for(size_t i=0;i<n;i++){
            p_lua_rawgeti(L,1,(int)i+1);if(p_lua_type(L,-1)!=LUA_TTABLE){fault=9;return info(L);}
            p_lua_getfield(L,-1,"kind");const char *k=p_lua_tolstring(L,-1,NULL);
            int kind=k&&!strcmp(k,"ai-constructor")?0:k&&!strcmp(k,"pod-select")?1:k&&!strcmp(k,"pod-delivery")?2:-1;p_lua_settop(L,-2);
            p_lua_getfield(L,-1,"value");lua_Number v=p_lua_tonumber(L,-1);int vt=p_lua_type(L,-1);p_lua_settop(L,-2);
            p_lua_getfield(L,-1,"limit");lua_Number limit=p_lua_tonumber(L,-1);int lt=p_lua_type(L,-1);p_lua_settop(L,-2);
            if(!valid_choice(i,kind,vt,lt,v,limit)){fault=9;return info(L);}
            choices[i]=(struct choice){kind,(int)v,(int)limit};p_lua_settop(L,-2);
        }
        expected_count=(int)n;replaying=1;
    }
    owner=GetCurrentThreadId();game=(unsigned char*)GetModuleHandleW(NULL);
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)game;
    if(!game || dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<64 || dos->e_lfanew>4096){fault=1;return info(L);}
    IMAGE_NT_HEADERS32 *pe=(IMAGE_NT_HEADERS32*)(game+dos->e_lfanew);
    if(sizeof(void*)!=4 || dos->e_magic!=IMAGE_DOS_SIGNATURE || pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_I386 || pe->FileHeader.TimeDateStamp!=1710319986 || pe->OptionalHeader.SizeOfImage!=5697536 || !verify_file()){fault=1;return info(L);}
    if(memcmp(game+0x387f16,"\xe8\x17\x6e\0\0\x69\x48\x18\xfd\x43\x03\0",12)){fault=2;return info(L);}
    void *hooks[4]={(void*)ai_draw,(void*)pod_hook,(void*)arrival_hook,(void*)special_draw};
    for(unsigned i=0;i<4;i++){
        if(memcmp(game+sites[i],expected[i],11)){fault=2;return info(L);}
        memcpy(saved[i],game+sites[i],5);patched[i][0]=0xe8;
        uint32_t displacement=(uint32_t)(uintptr_t)hooks[i]-(uint32_t)(uintptr_t)(game+sites[i]+5);memcpy(patched[i]+1,&displacement,4);
    }
    original_rand=(void*)(game+0x387f16);
    if(!patch(0,saved[0],patched[0],1) || !patch(1,saved[1],patched[1],1) || !patch(2,saved[2],patched[2],1) || !patch(3,saved[3],patched[3],1)){
        fault=6;
        restore_hooks();
        return info(L);
    }
    installed=1;return info(L);
}
static int restore(lua_State *L){
    if(replaying && count!=expected_count)fault=10;
    if(installed){
        if(GetCurrentThreadId()!=owner){fault=3;return info(L);}
        restore_hooks();
        sealed=replaying&&!fault&&!live_mask;
    }
    return info(L);
}
#define LOAD(name) p_##name=(void*)GetProcAddress(lua,#name);if(!p_##name)return 0
__declspec(dllexport) int __cdecl luaopen_itb_initial_choices(lua_State *L){
 HMODULE lua=GetModuleHandleW(L"lua5.1.dll");if(!lua||sizeof(void*)!=4)return 0;
 LOAD(lua_type);LOAD(lua_objlen);LOAD(lua_rawgeti);LOAD(lua_getfield);LOAD(lua_tonumber);LOAD(lua_tolstring);LOAD(lua_settop);LOAD(lua_createtable);LOAD(lua_pushnumber);LOAD(lua_pushboolean);LOAD(lua_pushstring);LOAD(lua_setfield);LOAD(lua_rawseti);LOAD(lua_pushcclosure);
 p_lua_createtable(L,0,3);p_lua_pushcclosure(L,install,0);p_lua_setfield(L,-2,"install");p_lua_pushcclosure(L,info,0);p_lua_setfield(L,-2,"info");p_lua_pushcclosure(L,restore,0);p_lua_setfield(L,-2,"restore");return 1;
}
