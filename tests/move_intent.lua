local module=dofile('mod/scripts/move_intent.lua')
local sent,events={},{}
local wire={peer='guest',inputReady=true,propose=function(_,r)sent[#sent+1]=r end}
local env={screenPointToTile=function()return {x=1,y=1}end,Board={GetPawn=function()return {GetSpace=function()return {x=0,y=3}end}end}}
local current={intentSerial=0,guardActive=true,sessionState=1}
local s={revision=0,previewMove=function()return true end}
local ui=module.new({env=env,wire=wire,native={info=function()return current end},
    emit=function(k)events[#events+1]=k end,request=function(kind,id,actor,fx,fy,tx,ty)
        return {kind=kind,id=id,actor=actor,fromX=fx,fromY=fy,toX=tx,toY=ty,revision=s.revision,witness='state'} end})
ui:update(s,false)
ui:click(20,390,s);assert(not ui.actor and #sent==0) -- teammate selection rejected
ui:click(20,470,s);assert(ui.actor=='artillery')
ui:click(800,600,s);assert(ui.draft.toX==1 and #sent==0) -- draft does not execute
ui:click(20,650,s);assert(not ui.draft and #sent==0) -- cancel is local
ui:click(20,470,s);ui:click(800,600,s)
s.previewMove=function()return false,'stale-draft-renew-intent' end
ui:click(20,610,s);assert(not ui.draft and #sent==0)
s.previewMove=function()return true end
ui:click(800,600,s);ui:click(20,610,s);assert(#sent==1 and sent[1].actor=='artillery')
wire.inputReady=false;ui:click(20,470,s);assert(not ui.actor and #sent==1)
wire.inputReady=true;ui:click(20,470,s);ui:click(800,600,s)
s.revision=1;ui:update(s,false);assert(not ui.draft and not ui.actor)
current.intentSerial=2;current.intentX=20;current.intentY=470;ui:update(s,false)
assert(not ui.actor and #sent==1) -- dropped/multiple clicks never become intent
print('8 interactive intent contracts passed; blocked-input and game behavior require live verification.')
