local wire=dofile('mod/scripts/phase_wire.lua')
local valid='EXEC|test-session|guest|0|player2|artillery\n{"state":"bounded"}'
assert(wire.decode(valid,'test-session').id=='artillery')
assert(not pcall(wire.decode,valid,'other-session'))
assert(not pcall(wire.decode,valid:gsub('EXEC','EVAL'),'test-session'))
assert(not pcall(wire.decode,valid:gsub('|0|','|0.5|'),'test-session'))
assert(not pcall(wire.decode,valid..'\nsecond-frame','test-session'))
local spawnFrame='SPAWNAPPLY|test-session|host|3|player2|spawn-1\nScorpion1|123|5|3|4,2;\n{}\n{}'
assert(wire.decode(spawnFrame,'test-session').witness=='Scorpion1|123|5|3|4,2;\n{}\n{}')
assert(not pcall(wire.decode,spawnFrame:gsub('SPAWNAPPLY','EXEC'),'test-session'))
assert(not pcall(wire.decode,string.rep('x',70001),'test-session'))
local dynamic='EXEC|test-session|guest|0|player2|move-guest-1|artillery|0|3|0|2\n{}'
local move=wire.decode(dynamic,'test-session').move
assert(move.actor=='artillery' and move.fromX==0 and move.fromY==3 and move.toY==2 and move.kind=='move')
assert(not pcall(wire.decode,dynamic:gsub('artillery','enemy'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('|0|3|0|2','|0|3|8|2'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('EXEC','INPUT'),'test-session'))
print('10 mailbox framing contracts passed; no game or filesystem execution implied.')
for _,actor in ipairs({'combat','cannon','artillery'})do
 local text='PREPARE|test-session|guest|1|player2|undo-guest-1|undo'..actor..'|0|2|0|3\n{}'
 local r=wire.decode(text,'test-session').move
 assert(r.kind=='undo-move' and r.actor==actor and r.fromY==2 and r.toY==3)
end
do
 local r='PREPARE|test-session|guest|3|player3|repair-guest-1|repairartillery|0|3|0|3\n{}'
 local v=wire.decode(r,'test-session').move;assert(v.kind=='repair' and v.actor=='artillery')
 assert(not pcall(wire.decode,r:gsub('|0|3|0|3','|0|3|1|3'),'test-session'))
end
local json=dofile('mod/scripts/json.lua')
local function runtime(phaseRun,direct)
    local root='C:/ITBCoopProbe/Wire';local files={[root..'/session.txt']='test-session\nguest\n'..(phaseRun=='xp' and 'xp-result-checkpoint\n' or phaseRun=='full' and 'full-mission\n' or phaseRun=='deploy' and 'deployment\n' or phaseRun=='repeat' and 'repeated-turns\n' or phaseRun and 'interactive-phase\n' or 'interactive\n')}
    local clock,previews,submits=0,0,0
    local env={os={getenv=function()return root end,rename=function(a,b)files[b]=files[a];files[a]=nil;return true end},
        modApi={elapsedTime=function()return clock end},io={open=function(p,mode)
            if mode=='rb' and not files[p] then return nil end
            return {read=function()return files[p]end,write=function(_,v)files[p]=v;return true end,close=function()return true end}
        end}}
    local transport=direct and {out={},incoming={},available=true} or nil
    if transport then
        function transport:healthy()return self.available end
        function transport:send(v)self.out[#self.out+1]=v end
        function transport:receive()return table.remove(self.incoming,1)end
        env.ITBCoopTransport=transport
    end
    local w=wire.open(env,json,function()end);local r=wire.decode(dynamic,'test-session').move
    if w.fullMission then w.sharedXp={healthy=function()end,begin=function()end,finish=function()return {abi='itb-shared-xp-v1',context='fixture',entries=json.array()}end} end
    local s={revision=0,phase='player2',previewMove=function()previews=previews+1;return true end,
        submit=function()submits=submits+1;return {status='pending'} end}
    local native={info=function()return {guardActive=true,sessionState=1,releaseFailed=false,armed=false,pressed=false}end}
    w:arm(r)
    return {w=w,s=s,r=r,native=native,files=files,root=root,transport=transport,add=function(text)
            if transport then transport.incoming[#transport.incoming+1]=text else files[root..('/in-%04d.txt'):format(w.rx)]=text end
        end,
        tick=function()return w:tick(s,function()return r end,native)end,
        elapsed=function(ms)clock=clock+ms end,counts=function()return previews,submits end}
end
local f=runtime();f.add(dynamic);assert(not pcall(f.tick));local _,n=f.counts();assert(n==0)
f=runtime();f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();local p,n=f.counts();assert(p==1 and n==0 and f.w.prepared)
assert(f.files[f.root..'/out-0002.json']:find('prepared'))
f.add(dynamic);f.tick();p,n=f.counts();assert(n==1 and not f.w.prepared)
f=runtime();f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();f.elapsed(5000);f.add(dynamic);assert(not pcall(f.tick));_,n=f.counts();assert(n==0)
f=runtime();f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();f.add(dynamic:gsub('|0|3|0|2','|0|3|0|1'));assert(not pcall(f.tick));_,n=f.counts();assert(n==0)
f=runtime();f.s.previewMove=function()return false,'protection-unavailable'end;f.add(dynamic:gsub('EXEC','PREPARE'));assert(not pcall(f.tick));assert(not f.w.prepared and not f.files[f.root..'/out-0002.json'])
f=runtime();f.native.info=function()return {guardActive=true,sessionState=1,releaseFailed=false,armed=true,pressed=false}end;f.add(dynamic:gsub('EXEC','PREPARE'));assert(not pcall(f.tick));assert(not f.w.prepared and not f.files[f.root..'/out-0002.json'])
f=runtime();f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();f.add(dynamic:gsub('EXEC','PREPARE'));assert(not pcall(f.tick));_,n=f.counts();assert(n==0)
f=runtime();f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();f.s.revision=1;f.add(dynamic);assert(not pcall(f.tick));_,n=f.counts();assert(n==0)
print('8 runtime prepare/execute contracts passed; in-memory mailbox and game doubles only.')
f=runtime(nil,true);assert(f.transport.active and f.transport.out[1].type=='armed')
f.add(dynamic:gsub('EXEC','PREPARE'));f.tick();assert(f.transport.out[2].type=='prepared')
f.add(dynamic);f.tick();local _,directSubmits=f.counts();assert(directSubmits==1)
for name in pairs(f.files)do assert(name==f.root..'/session.txt')end
f=runtime(nil,true);f.transport.available=false;assert(not pcall(f.tick));local _,blocked=f.counts();assert(blocked==0)
assert(not pcall(function()f.w:arm(f.r)end))
print('Direct transport shares preparation/execution and health refusal without message files (transport/game doubles).')

local punch=wire.decode('PREPARE|test-session|host|1|player2|attack-host-1|punch|3|3|2|3\n{}','test-session').move
assert(punch.kind=='lab-punch' and punch.actor=='combat')
f=runtime(true);assert(f.w.phaseRun and f.w.interactive and f.w.limit==4)
f.s.revision=2;f.r.revision=2;f.r.id='end-turn';f.r.kind='end-turn';f.r.confirmUnused=true
local consents={};f.s.setReady=function(_,peer)consents[peer]=true;return true end
f.s.previewAction=function()return consents.host and consents.guest end
f.add('READY|test-session|-|2|player2|end-turn\n{}');f.tick()
assert(f.w.readyInput and f.w.inspectionReady and not f.files[f.root..'/out-0002.json'])
f.w:ready(f.s,f.r);assert(not f.w.readyInput and f.w.inspectionReady and f.files[f.root..'/out-0002.json']:find('ready'))
assert(not pcall(function()f.w:ready(f.s,f.r)end))
f.add('CONSENT|test-session|host|2|player2|end-turn\n{}');f.tick()
f.add('PREPARE|test-session|host|2|player2|end-turn\n{}');f.tick();assert(f.w.prepared and not f.w.inspectionReady)
f.add('EXEC|test-session|host|2|player2|end-turn\n{}');f.tick();local _,n=f.counts();assert(n==1 and f.w.ending)
print('3 selected-phase framing/readiness contracts passed; fake mailbox only.')
f=runtime('repeat');assert(f.w.repeatedTurns and f.w.phaseRun and f.w.interactive)
f.s.revision=5;f.s.phase='player3';f.r.revision=5;f.r.phase='player3';f.r.id='end-turn-5';f.r.kind='end-turn'
local readiness=0;f.s.setReady=function()readiness=readiness+1;return true end
f.add('INPUT|test-session|-|5|player3|-\n{}');f.tick();assert(f.w.inputReady and not f.w.readySent)
f.w:ready(f.s,f.r);assert(readiness==1 and not f.w.inputReady)
f.add('READY|test-session|-|5|player3|end-turn-5\n{}');f.tick();assert(not f.w.readyInput)
assert(not pcall(function()f.w:ready(f.s,f.r)end))
f.add('CONSENT|test-session|host|5|player3|end-turn-5\n{}');f.tick();assert(readiness==2)
print('Repeated-turn mailbox config and fresh readiness passed (in-memory doubles).')
f=runtime('repeat');f.s.canReset=function()return true end
local resetVotes={};f.s.setReady=function(_,peer,phase,revision,witness,confirm,kind)assert(confirm and kind=='reset-turn');resetVotes[peer]=true;return true end
f.s.clearResetReady=function()resetVotes={}end
f.s.previewAction=function()return resetVotes.host and resetVotes.guest end
f.add('INPUT|test-session|-|0|player2|-\n{}');f.tick()
local reset={id='reset-turn-0',kind='reset-turn',revision=0,phase='player2',witness='{}',confirmReset=true}
f.w:resetReady(f.s,reset);assert(f.w.resetSent and resetVotes.guest)
assert(not pcall(function()f.w:resetReady(f.s,reset)end))
f.add('RESETREADY|test-session|-|0|player2|reset-turn-0\n{}');f.tick();assert(f.w.resetPending)
f.add('RESETCANCEL|test-session|-|0|player2|reset-turn-0\n{}');f.tick();assert(not f.w.resetPending and not f.w.resetSent and not resetVotes.guest)
f.w:resetReady(f.s,reset);f.add('RESETREADY|test-session|-|0|player2|reset-turn-0\n{}');f.tick()
for _,peer in ipairs({'host','guest'})do f.add('RESETCONSENT|test-session|'..peer..'|0|player2|reset-turn-0\n{}');f.tick()end
f.add('PREPARE|test-session|host|0|player2|reset-turn-0\n{}');f.tick();assert(f.w.prepared and not f.w.inputReady)
f.add('EXEC|test-session|host|0|player2|reset-turn-0\n{}');f.tick();local _,resetSubmits=f.counts();assert(resetSubmits==1 and f.w.pendingKind=='reset-turn')
print('Typed Reset consent, cancellation and the existing fresh prepare/execute path passed (transport doubles).')
do
    local blocked=runtime('repeat')
    blocked.s.setReady=function()error('coordinator must not create missing local Reset consent')end
    blocked.add('INPUT|test-session|-|0|player2|-\n{}');blocked.tick()
    blocked.add('RESETREADY|test-session|-|0|player2|reset-turn-0\n{}');blocked.tick()
    blocked.add('RESETCONSENT|test-session|guest|0|player2|reset-turn-0\n{}')
    local ok,why=pcall(blocked.tick);local _,submitted=blocked.counts()
    assert(not ok and tostring(why):find('wire%-reset%-consent%-context') and submitted==0 and not blocked.w.prepared)
end
print('Coordinator Reset consent cannot replace the runtime own local Reset approval; zero submissions (transport doubles).')
f=runtime('repeat');f.s.revision=4;f.s.phase='player4';f.r.revision=4;f.r.phase='player4'
f.add('DONE|test-session|-|4|player4|-\n{}')
assert(not pcall(f.tick),'repeated run must not claim mission completion at player4')

for _,actor in ipairs({'combat','cannon','artillery'}) do
 local r=dofile('mod/scripts/phase_wire.lua').decode('PREPARE|s1|guest|0|player2|attack-guest-1|attack'..actor..'|1|5|1|3\n{}','s1')
 assert(r.move.kind=='basic-attack' and r.move.actor==actor and r.move.toY==3)
end
print('Three basic-weapon wire aliases passed (decoder only).')
f=runtime();f.add('INPUT|test-session|-|0|player2|-\n{}');f.tick();assert(f.w.inputReady and f.w.inspectionReady)
f.w:propose(f.r);assert(not f.w.inputReady and not f.w.inspectionReady)
print('Inspection lease follows explicit input/readiness barriers and closes on proposal/preparation (in-memory mailbox).')
f=runtime('repeat');f.elapsed(1500100);f.w.last=1500100;assert(not f.tick(),'healthy operator session may continue past 25 minutes')
f.elapsed(299900);f.w.last=1800000;assert(not pcall(f.tick),'30-minute repeated-turn budget remains bounded')
f=runtime();f.elapsed(600000);f.w.last=600000;assert(not pcall(f.tick),'short interactive experiment limit remains unchanged')
f=runtime('full');f.elapsed(1800000);f.w.last=1800000;assert(not f.tick(),'full mission may continue past 30 minutes')
f.elapsed(1799999);f.w.last=3599999;assert(not f.tick());f.elapsed(1);f.w.last=3600000
assert(not pcall(f.tick),'full mission remains bounded at 60 minutes')
f=runtime('full');f.elapsed(10000);assert(not pcall(f.tick),'full mission still rejects stale coordinator heartbeat')
f=runtime('full');f.w.rx=4096;assert(not f.tick());f.w.rx=4097;assert(not pcall(f.tick),'full mission input frames remain bounded')
print('Full-mission operator budget is bounded at 60 minutes; repeated-turn, heartbeat and preparation deadlines are unchanged (clock doubles).')
f=runtime('deploy');assert(f.w.deployment and f.w.phaseRun and f.w.interactive and f.w.limit==5 and not f.w.repeatedTurns)
local placement='EXEC|test-session|host|0|deployment|move-host-1|deploycombat|-1|-1|1|4\n{}'
local p=wire.decode(placement,'test-session').move;assert(p.kind=='deploy' and p.actor=='combat' and p.fromX==-1 and p.fromY==-1)
assert(not pcall(wire.decode,placement:gsub('deploycombat','combat'),'test-session'))
assert(not pcall(wire.decode,placement:gsub('|%-1|%-1|','|0|0|'),'test-session'))
print('Deployment config and exact off-board origins are separate from normal move framing (mailbox doubles).')
do
 local files={['C:/ITBCoopProbe/Wire/session.txt']='full-session\nguest\nfull-mission\n'}
 local env={os={getenv=function()return 'C:/ITBCoopProbe/Wire'end},io={open=function(p)return files[p] and {read=function()return files[p]end,close=function()end}end}}
 local w=wire.open(env,{},function()end)
 assert(w.fullMission and w.deployment and w.repeatedTurns and w.phaseRun and w.interactive)
end

do local w=runtime('xp',true).w;assert(w.fullMission and w.terminalCheckpoint and not w.deployment and w.repeatedTurns and w.interactive and w.phaseRun) end
