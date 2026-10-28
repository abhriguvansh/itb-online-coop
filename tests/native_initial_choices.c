/* CI only. RNG and protection functions are doubles; no game or input APIs run. */
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "../native/initial_choices.c"
static int calls,raw=123,flush_ok=1,protect_ok=1;
static int __cdecl fake_rand(void){calls++;return raw;}
static BOOL WINAPI fake_protect(LPVOID p,SIZE_T n,DWORD flags,PDWORD prior){
    (void)p;(void)n;(void)flags;*prior=PAGE_EXECUTE_READ;return protect_ok;
}
static BOOL WINAPI fake_flush(HANDLE h,LPCVOID p,SIZE_T n){(void)h;(void)p;(void)n;return flush_ok;}
static void reset(void){
    count=calls=fault=overflow=installed=sealed=0;live_mask=0;replaying=1;expected_count=19;
    owner=GetCurrentThreadId();original_rand=fake_rand;raw=123;
    for(int i=0;i<19;i++)choices[i]=(struct choice){i<17?0:i==17?2:1,42+i,i<17?32768:i==17?3:9};
}
int main(void){
    reset();for(int i=0;i<19;i++)assert(draw(i<17?0:i==17?2:1,i<17?32768:i==17?3:9)==42+i);
    assert(calls==19&&count==19&&!fault&&entries[18].value==123&&entries[18].applied==60);
    assert(draw(0,32768)==123&&fault==8&&calls==20);
    reset();assert(draw(1,9)==123&&fault==8);assert(draw(0,32768)==123&&calls==2);
    reset();count=18;assert(draw(1,8)==123&&fault==8);
    reset();replaying=0;assert(draw(0,32768)==123&&calls==1&&!fault);
    reset();count=128;assert(draw(0,32768)==123&&calls==1&&fault==4&&overflow);
    reset();owner++;assert(draw(0,32768)==123&&calls==1&&fault==3);
    assert(valid_choice(19,0,0,LUA_TNUMBER,LUA_TNUMBER,0,32768));
    assert(valid_choice(19,18,1,LUA_TNUMBER,LUA_TNUMBER,32767,9));
    assert(valid_choice(19,17,2,LUA_TNUMBER,LUA_TNUMBER,123,3));
    assert(!valid_choice(19,19,3,LUA_TNUMBER,LUA_TNUMBER,123,100));
    assert(!valid_choice(19,0,0,LUA_TNUMBER,LUA_TNUMBER,NAN,32768));
    assert(!valid_choice(19,0,0,LUA_TNUMBER,LUA_TNUMBER,0.5,32768));
    assert(!valid_choice(19,0,0,LUA_TSTRING,LUA_TNUMBER,0,32768));
    assert(!valid_choice(19,17,0,LUA_TNUMBER,LUA_TNUMBER,0,32768));
    assert(valid_choice(20,18,3,LUA_TNUMBER,LUA_TNUMBER,8055,100));
    assert(valid_choice(20,19,1,LUA_TNUMBER,LUA_TNUMBER,20506,9));
    assert(!valid_choice(20,18,1,LUA_TNUMBER,LUA_TNUMBER,123,9));
    assert(!valid_choice(20,19,3,LUA_TNUMBER,LUA_TNUMBER,123,100));
    assert(!valid_choice(21,0,0,LUA_TNUMBER,LUA_TNUMBER,123,32768));
    reset();expected_count=20;choices[18]=(struct choice){3,8055,100};choices[19]=(struct choice){1,20506,9};
    for(int i=0;i<20;i++)assert(draw(choices[i].kind,choices[i].limit)==choices[i].value);
    assert(calls==20&&count==20&&!fault&&entries[18].value==123&&entries[18].applied==8055);
    reset();game=calloc(5697536,1);assert(game);protect_page=fake_protect;flush_cache=fake_flush;
    for(int i=0;i<2;i++){memcpy(saved[i],expected[i],5);memcpy(patched[i],"\xe8\x01\x02\x03\x04",5);memcpy(game+sites[i],saved[i],5);}
    assert(patch(0,saved[0],patched[0],1)&&live_mask==1&&installed);
    flush_ok=0;assert(!patch(1,saved[1],patched[1],1)&&live_mask==3);
    flush_ok=1;restore_hooks();assert(!live_mask&&!installed&&!fault);
    assert(!memcmp(game+sites[0],saved[0],5)&&!memcmp(game+sites[1],saved[1],5));
    protect_ok=0;assert(!patch(0,saved[0],patched[0],1)&&!live_mask);
    protect_ok=1;assert(patch(0,saved[0],patched[0],1));game[sites[0]]=0;restore_hooks();
    assert(fault==7&&live_mask==1&&installed);
    /* Shared XP consumes one original draw, with a separate exact command ticket. */
    reset();xp_fault=xp_count=0;xp_active=1;strcpy(xp_context,"fixture-session/player3/27/end-turn-27");
    int first,again,other;assert(xp_ticket(xp_context,0,&first)&&xp_ticket(xp_context,0,&again)&&first==again);
    assert(xp_ticket(xp_context,1,&other)&&other>=0&&other<=32767);
    assert(xp_draw(3)==first&&calls==1&&xp_count==1&&xp_entries[0].raw==123&&xp_entries[0].limit==3);
    assert(xp_draw(4)==123&&calls==2&&xp_fault==2&&xp_count==1);
    xp_fault=0;xp_count=128;assert(xp_draw(3)==123&&calls==3&&xp_fault==2);
    xp_fault=0;xp_count=0;owner++;assert(xp_draw(3)==123&&calls==4&&xp_fault==1);owner--;
    xp_active=0;xp_fault=0;memcpy(game+0x18f321,xp_expected,5);memcpy(xp_saved,xp_expected,5);memcpy(xp_patched,"\xe8\x01\x02\x03\x04",5);
    assert(xp_patch(xp_saved,xp_patched,1)&&xp_active);assert(xp_patch(xp_patched,xp_saved,0)&&!xp_active);
    free(game);puts("Initial-choice and shared-XP native contracts passed (CI doubles; no game proof).");return 0;
}
