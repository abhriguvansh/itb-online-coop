local wire=dofile('mod/scripts/phase_wire.lua')
local valid='EXEC|test-session|guest|0|player2|artillery\n{"state":"bounded"}'
assert(wire.decode(valid,'test-session').id=='artillery')
assert(not pcall(wire.decode,valid,'other-session'))
assert(not pcall(wire.decode,valid:gsub('EXEC','EVAL'),'test-session'))
assert(not pcall(wire.decode,valid:gsub('|0|','|0.5|'),'test-session'))
assert(not pcall(wire.decode,valid..'\nsecond-frame','test-session'))
assert(not pcall(wire.decode,string.rep('x',70001),'test-session'))
local dynamic='EXEC|test-session|guest|0|player2|move-guest-1|artillery|0|3|0|2\n{}'
local move=wire.decode(dynamic,'test-session').move
assert(move.actor=='artillery' and move.fromX==0 and move.fromY==3 and move.toY==2 and move.kind=='move')
assert(not pcall(wire.decode,dynamic:gsub('artillery','enemy'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('|0|3|0|2','|0|3|8|2'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('EXEC','INPUT'),'test-session'))
print('10 mailbox framing contracts passed; no game or filesystem execution implied.')
local json=dofile('mod/scripts/json.lua')
local function runtime(phaseRun)
    local root='C:/ITBCoopProbe/Wire';local files={[root..'/session.txt']='test-session\nguest\n'..(phaseRun=='repeat' and 'repeated-turns\n' or phaseRun and 'interactive-phase\n' or 'interactive\n')}
    local clock,previews,submits=0,0,0
    local env={os={getenv=function()return root end,rename=function(a,b)files[b]=files[a];files[a]=nil;return true end},
        modApi={elapsedTime=function()return clock end},io={open=function(p,mode)
            if mode=='rb' and not files[p] then return nil end
            return {read=function()return files[p]end,write=function(_,v)files[p]=v;return true end,close=function()return true end}
        end}}
    local w=wire.open(env,json,function()end);local r=wire.decode(dynamic,'test-session').move
    local s={revision=0,phase='player2',previewMove=function()previews=previews+1;return true end,
        submit=function()submits=submits+1;return {status='pending'} end}
    local native={info=function()return {guardActive=true,sessionState=1,releaseFailed=false,armed=false,pressed=false}end}
    w:arm(r)
    return {w=w,s=s,r=r,native=native,files=files,root=root,add=function(text)files[root..('/in-%04d.txt'):format(w.rx)]=text end,
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

local punch=wire.decode('PREPARE|test-session|host|1|player2|attack-host-1|punch|3|3|2|3\n{}','test-session').move
assert(punch.kind=='lab-punch' and punch.actor=='combat')
f=runtime(true);assert(f.w.phaseRun and f.w.interactive and f.w.limit==4)
f.s.revision=2;f.r.revision=2;f.r.id='end-turn';f.r.kind='end-turn';f.r.confirmUnused=true
local consents={};f.s.setReady=function(_,peer)consents[peer]=true;return true end
f.s.previewAction=function()return consents.host and consents.guest end
f.add('READY|test-session|-|2|player2|end-turn\n{}');f.tick()
assert(f.w.readyInput and not f.files[f.root..'/out-0002.json'])
f.w:ready(f.s,f.r);assert(not f.w.readyInput and f.files[f.root..'/out-0002.json']:find('ready'))
assert(not pcall(function()f.w:ready(f.s,f.r)end))
f.add('CONSENT|test-session|host|2|player2|end-turn\n{}');f.tick()
f.add('PREPARE|test-session|host|2|player2|end-turn\n{}');f.tick();assert(f.w.prepared)
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
