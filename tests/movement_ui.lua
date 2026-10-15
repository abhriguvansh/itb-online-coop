local buttons,draw={},nil
local function event() return {subscribe=function()end} end
local env={Ui=function()
 local b={visible=true}
 for _,name in ipairs({'pospx','widthpx','heightpx','caption','decorate','settooltip'}) do b[name]=function(self)return self end end
 b.addTo=function(self)buttons[#buttons+1]=self;return self end
 return b
end,DecoButton=function()end,DecoAlign=function()end,DecoCaption=function()end,
GetCurrentMission=function()return {ID='Mission_Artillery'}end,
sdlext={getUiRoot=function()return {}end,isGame=function()return true end,isConsoleOpen=function()return false end},
modApi={elapsedTime=function()return 0 end,events={onWindowShown=event(),onWindowHidden=event(),onFrameDrawStart={subscribe=function(_,fn)draw=fn end}}}}
local calls=0
local function called()calls=calls+1 end
local lab={label='move lab',status='off',bridge={pollSession=function()end,pollGuard=function()end},profileAllowed=function()return true end,
arm=called,reset=called,lockInput=called,request=called,preview=function()return {}end}
local gate={update=function()end,arm=called,stop=called,status='off'}
local attack={arm=called,disarm=called,request=called,status='off'}
dofile('mod/scripts/movement_ui.lua').install(env,lab,gate,attack);draw()
local toggle=buttons[8];assert(toggle.visible);assert(toggle.onclicked(toggle,1));assert(calls==1)
-- Exercise callbacks directly after visibility/ownership changes, as a cached
-- hover can outlive the draw that hid the original control.
toggle.visible=false;assert(toggle.onclicked(toggle,1));assert(calls==1)
lab.sessionOwned=true
for _,b in ipairs(buttons) do b.visible=true;assert(b.onclicked(b,1)) end
assert(calls==1,'A stale diagnostic callback changed the protected session')
draw();for _,b in ipairs(buttons)do assert(not b.visible);assert(b.onclicked(b,1))end
assert(calls==1)
print('Diagnostic UI: standalone toggle works; hidden and session-owned stale callbacks remain consumed without actions (UI doubles).')
