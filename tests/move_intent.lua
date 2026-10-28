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
do
 local changed={peer='guest',inputReady=true,squadOwners={combat='guest',cannon='host',artillery='host'}}
 local selected=module.new({env=env,wire=changed,native={info=function()return current end},emit=function()end,request=function()return {}end})
 selected:click(20,390,s);assert(selected.actor=='combat')
 selected:click(20,470,s);assert(not selected.actor and selected.status=='That mech belongs to your teammate')
end
wire.phaseRun=true;wire.peer='host';s.revision=1;wire.inputReady=true
s.previewAction=function(_,peer,r)return peer=='host' and r.kind=='lab-punch' end
ui:update(s,false);ui:click(20,390,s);ui:click(800,600,s)
assert(ui.draft.kind=='lab-punch' and #sent==1);ui:click(20,610,s);assert(#sent==2 and sent[2].kind=='lab-punch')
local readyCount=0;wire.ready=function()readyCount=readyCount+1;wire.readyInput=false end
s.revision=2;wire.inputReady=false;wire.readyInput=true;ui:update(s,false);assert(readyCount==0)
ui:click(800,600,s);assert(readyCount==0);ui:click(20,610,s);assert(readyCount==1)
ui:click(20,610,s);assert(readyCount==1)
print('2 selected punch/readiness UI contracts passed; fake clicks only.')
do
 wire.repeatedTurns=true;wire.inputReady=true;wire.readyInput=false;wire.resetSent=false;s.phase='player3'
 local votes=0;s.canReset=function()return false,'fresh-turn-start-required' end
 wire.resetReady=function()votes=votes+1;wire.resetSent=true end
 ui:click(20,970,s);assert(votes==0 and ui.status=='fresh-turn-start-required')
 s.canReset=function()return true end;ui.actor='combat';ui.draft={}
 ui:click(20,970,s);assert(votes==1 and not ui.actor and not ui.draft)
 ui:click(20,970,s);assert(votes==1)
 wire.resetSent=false;wire.inputReady=false;ui:click(20,970,s);assert(votes==1)
 wire.repeatedTurns=false
end
do
 wire.repeatedTurns=true;wire.peer='guest';wire.inputReady=true;wire.readyInput=false;s.revision=3
 s.undoTarget=function(_,peer,actor)if peer=='guest' and actor=='artillery' then return {fromX=1,fromY=2,toX=0,toY=3}end end
 s.previewAction=function(_,peer,r)return peer=='guest' and r.kind=='undo-move' end
 ui:update(s,false);ui:click(20,890,s);assert(not ui.draft)
 ui:click(20,470,s);ui:click(20,890,s);assert(ui.draft and ui.draft.kind=='undo-move' and ui.draft.toX==0)
 local before=#sent;ui:click(20,610,s);assert(#sent==before+1 and sent[#sent].kind=='undo-move')
 wire.repeatedTurns=false
end
do
 wire.repeatedTurns=true;wire.peer='host';wire.inputReady=true;wire.readyInput=false;s.revision=3
 s.previewAction=function(_,peer,r)return peer=='host' and r.kind=='repair' and r.fromX==r.toX and r.fromY==r.toY end
 ui:update(s,false);ui:click(20,770,s);assert(not ui.draft)
 ui:click(20,390,s);ui:click(20,770,s);assert(ui.draft and ui.draft.kind=='repair')
 local before=#sent;ui:click(20,610,s);assert(#sent==before+1 and sent[#sent].kind=='repair')
 wire.repeatedTurns=false
end
do
 wire.deployment=true;wire.fullMission=true;wire.repeatedTurns=true;wire.phaseRun=true;wire.peer='guest';wire.inputReady=true;wire.readyInput=false;s.phase='player1';s.revision=4
 s.previewAction=function(_,peer,r)return peer=='guest' and r.kind=='basic-attack' end
 ui:update(s,false);ui:click(20,430,s);ui:click(20,690,s);ui:click(800,600,s)
 assert(ui.draft and ui.draft.kind=='basic-attack' and ui.draft.actor=='cannon','deployment mode must expose native attacks after launch')
 wire.deployment=false;wire.fullMission=false;wire.repeatedTurns=false;s.phase='player2'
end
do
    local inspecting=false
    local inspect={click=function(_,x)if x>=1600 then inspecting=not inspecting;return true end;return inspecting end}
    wire.peer='guest';wire.phaseRun=false;wire.inputReady=true;s.previewMove=function()return true end
    local routed=module.new({env=env,wire=wire,native={info=function()return current end},request=function()return {}end,
        emit=function()end,inspection=inspect})
    routed.actor='artillery';routed.draft={};local before=#sent
    routed:click(1610,350,s);assert(not routed.actor and not routed.draft)
    routed:click(20,610,s);assert(#sent==before,'inspection clicks cannot confirm an action')
end
