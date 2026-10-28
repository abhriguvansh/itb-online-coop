local module=dofile('mod/scripts/primary_setup.lua')
local sent,installed={},0
local n={intentSerial=0,guardActive=true,sessionState=1,releaseFailed=false,armed=false,pressed=false}
local wire={peer='host',send=function(_,m)sent[#sent+1]=m end}
local s={revision=0,phase='deployment',installPrimaryOwners=function(_,owners,witness)
 assert(owners.artillery=='host' and owners.combat=='guest' and owners.cannon=='host' and witness=='board');installed=installed+1 end}
local r={revision=0,phase='deployment',witness='board'}
local setup=module.new({wire=wire,native={info=function()return n end},emit=function()end})
local function receive(kind,generation,body)setup:receive({kind=kind,peer='-',revision=0,phase='deployment',id='primary-'..generation,witness=body},s,r)end
receive('SQUAD',0,'0|-|-|-|-|0|0')
setup:click(20,610,s,r);assert(#sent==0 and installed==0)
setup:click(20,470,s,r);assert(setup.primary=='artillery' and #sent==0)
setup:click(20,690,s,r);assert(#sent==1 and sent[1].primary=='artillery' and sent[1].sharedController=='host')
receive('SQUAD',2,'2|artillery|host|artillery|host|0|0')
setup:click(20,610,s,r);assert(#sent==1 and setup:status()=='Choose different primary mechs')
receive('SQUAD',3,'3|artillery|host|combat|guest|0|0')
setup:click(20,610,s,r);assert(#sent==1 and setup:status()=='Agree on shared controller')
receive('SQUAD',4,'4|artillery|host|combat|host|0|0')
setup:click(20,610,s,r);assert(#sent==2 and sent[2].type=='primary_ready' and sent[2].generation==4)
setup:click(20,470,s,r);assert(setup.readyGeneration==4 and #sent==2,'same primary click must not invalidate approval')
receive('SQUAD',5,'5|artillery|host|cannon|host|0|0');assert(not setup.readyGeneration)
assert(not pcall(receive,'SQUADLOCK',5,'5|artillery|host|cannon|host|1|1') and installed==0)
receive('SQUAD',6,'6|artillery|host|combat|host|0|0')
setup:click(20,610,s,r);receive('SQUADLOCK',6,'6|artillery|host|combat|host|1|1')
assert(setup.locked and installed==1 and sent[#sent].type=='primary_applied' and wire.squadOwners.combat=='guest')
assert(not pcall(receive,'SQUADLOCK',6,'6|artillery|host|combat|host|1|1') and installed==1)
for _,text in ipairs({'','00|-|-|-|-|0|0','33|-|-|-|-|0|0','1|combat|host|combat|host|1|1','1|enemy|host|cannon|host|0|0','1|combat|-|-|-|0|0','1|combat|host|cannon|host|0|0\ncode'})do assert(not pcall(module.parse,text))end
for _,h in ipairs({'combat','cannon','artillery'})do for _,g in ipairs({'combat','cannon','artillery'})do if h~=g then for _,controller in ipairs({'host','guest'})do
 local v=module.parse('1|'..h..'|'..controller..'|'..g..'|'..controller..'|1|1')
 assert(v.owners[h]=='host' and v.owners[g]=='guest' and v.owners[v.sharedActor]==controller)
end end end end
print('Primary local setup: explicit choices and local approval, conflicts, changed-generation invalidation, one immutable install, all 12 assignments and data-only frame bounds (engine doubles).')
