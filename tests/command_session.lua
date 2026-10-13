local session=dofile('experiments/command_session.lua')
local moveFixture=dofile('tests/fixtures/movement.lua')
local passed=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); passed=passed+1 end
local function list(v) return {size=function() return #v end,index=function(_,i) return v[i] end} end
local function fixture()
    local e=moveFixture('ui')
    e.healthy=true; e.witness='partial-board:0'; e.moveCalls=0; e.attackCalls=0; e.records={}
    local function pawn(id,kind,x,y,team)
        local p={pos={x=x,y=y},hp=3,active=true}
        p.GetId=function()return id end; p.GetType=function()return kind end
        p.GetSpace=function()return p.pos end; p.GetHealth=function()return p.hp end
        p.GetTeam=function()return team end; p.IsActive=function()return p.active end
        p.IsPowered=function()return true end; p.GetPoweredWeapons=function()return {'Prime_Punchmech'} end
        for _,k in ipairs({'IsBusy','IsMovementSpent','IsUndoPossible','IsBoosted','IsDead','IsFrozen','IsAcid','IsFire','IsShield','IsArmor','IsGuarding'}) do p[k]=function()return false end end
        return p
    end
    e.actor=pawn(0,'PunchMech',3,3,1); e.target=pawn(101,'Hornet1',2,3,6)
    e.actor.FireWeapon=function(_,p,index) e.attackCalls=e.attackCalls+1;assert(p.x==2 and p.y==3 and index==1);if e.throwAttack then error('uncertain')end;return nil end
    local pawns={[0]=e.actor,[1]=pawn(1,'TankMech',1,5,1),[2]=e.pawn,[100]=pawn(100,'ArchiveArtillery',0,0,1),[101]=e.target}
    e.friendlies={0,1,2,100}
    e.Board.GetPawn=function(_,id)return pawns[id]end
    e.Board.GetPawns=function()return list(e.friendlies)end
    e.Prime_Punchmech={Damage=2,GetTargetArea=function()return list({{x=2,y=3}})end}
    local o={env=e,session='s1',encounter='enc1',phase='player2',players={'host','guest'},
        entities={combat={pawnId=0,owner='host',commandable=true},cannon={pawnId=1,owner='guest',commandable=true},
            artillery={pawnId=2,owner='guest',commandable=true},missionAlly={pawnId=100,owner='host',commandable=true}},
        movement=dofile('mod/scripts/movement.lua'),attack=dofile('mod/scripts/attack.lua'),json=dofile('mod/scripts/json.lua'),gate={active=false},
        bridge={start=function()e.moveCalls=e.moveCalls+1;return true end,update=function()return true end,stop=function()end},
        capture=function()return {gridPower=4},true end,guardHealthy=function()return e.healthy end,witness=function()return e.witness end,
        emit=function(k,d)e.records[#e.records+1]={kind=k,data=d}end}
    local function request(kind,id)
        local attack=kind=='lab-punch'
        return {id=id or 'r1',session='s1',encounter='enc1',phase='player2',revision=0,witness=e.witness,kind=kind or 'move',
            actor=attack and 'combat' or 'artillery',fromX=attack and 3 or 1,fromY=3,toX=attack and 2 or 1,toY=attack and 3 or 2}
    end
    return e,o,request
end
local function completeMove(e,s)
    e.pawn.position={x=1,y=2};e.pawn.spent=true
    s:skillEvent('onSkillStart',e.pawn,'Move');s:skillEvent('onSkillEnd',e.pawn,'Move')
    for i=1,3 do e.clock=e.clock+100;s:update()end
end
local function completeAttack(e,s)
    s:skillEvent('onSkillStart',e.actor,'Prime_Punchmech');e.actor.active=false;e.target.hp=1;e.target.pos={x=1,y=3}
    s:skillEvent('onSkillEnd',e.actor,'Prime_Punchmech')
    for i=1,3 do e.clock=e.clock+100;s:update()end
end
test('guest movement then host punch use real diagnostic modules and one revision stream',function()
    local e,o,r=fixture();local s=session.new(o);local a=r();assert(s:submit('guest',a).status=='pending')
    assert(s:submit('guest',a).status=='duplicate' and e.moveCalls==1)
    completeMove(e,s);assert(s.revision==1 and not s.stopped)
    local b=r('lab-punch','r2');b.revision=1;assert(s:submit('host',b).status=='pending');completeAttack(e,s)
    assert(s.revision==2 and not s.stopped and e.attackCalls==1)
    assert(s:submit('host',b).originalStatus=='observed' and e.attackCalls==1)
    assert(s:checkpoint()==nil)
end)
for _,case in ipairs({
    {'unknown peer',function(r)return 'intruder' end},
    {'wrong owner',function(r)return 'host' end},
    {'stale revision',function(r)r.revision=1 end},
    {'stale observation',function(r)r.witness='old' end},
    {'wrong session',function(r)r.session='s2' end},
    {'wrong encounter',function(r)r.encounter='enc2' end},
    {'wrong phase',function(r)r.phase='enemy' end},
    {'unknown entity',function(r)r.actor='none' end},
    {'malformed coordinate',function(r)r.toX=0/0 end},
    {'unknown field',function(r)r.code='anything' end},
}) do test('reject '..case[1]..' before dispatch',function()
    local e,o,r=fixture();local s=session.new(o);local req=r();local peer=case[2](req) or 'guest'
    assert(s:submit(peer,req).status=='rejected' and e.moveCalls==0 and e.attackCalls==0)
end)end
test('busy request and stale draft require a fresh request ID and current intent',function()
    local e,o,r=fixture();local s=session.new(o);s:submit('guest',r())
    local b=r('lab-punch','r2');assert(s:submit('host',b).reason=='command-pending-renew-intent')
    completeMove(e,s);assert(s:submit('host',b).status=='duplicate' and e.attackCalls==0)
    b.id='r3';assert(s:submit('host',b).reason=='stale-revision-renew-intent')
    b.revision=1;assert(s:submit('host',b).reason=='request-id-conflict')
    b.id='r4';assert(s:submit('host',b).status=='pending' and e.attackCalls==1)
end)
test('caller mutation cannot change in-flight request or duplicate identity',function()
    local e,o,r=fixture();local s=session.new(o);local a=r();s:submit('guest',a);a.toX=7
    assert(s:submit('guest',a).reason=='request-id-conflict' and e.moveCalls==1);completeMove(e,s);assert(s.revision==1)
end)
test('movement uncertainty prevents subsequent attack',function()
    local e,o,r=fixture();local s=session.new(o);s:submit('guest',r());e.clock=5100;s:update()
    assert(s.stopped);assert(s:submit('host',r('lab-punch','next')).status=='rejected' and e.attackCalls==0)
end)
test('attack exception prevents subsequent movement and duplicate retry',function()
    local e,o,r=fixture();e.throwAttack=true;local s=session.new(o);local a=r('lab-punch')
    assert(s:submit('host',a).status=='uncertain' and s.stopped and e.attackCalls==1)
    assert(s:submit('host',a).status=='duplicate');assert(s:submit('guest',r('move','next')).status=='rejected' and e.moveCalls==0)
end)
test('loss of protection latches stop for both paths even if protection returns',function()
    local e,o,r=fixture();local s=session.new(o);s:submit('guest',r());e.healthy=false;s:update();e.healthy=true
    assert(s.stopped and s:submit('host',r('lab-punch','next')).status=='rejected' and e.attackCalls==0)
end)
test('new friendly or omitted mission ally blocks admission',function()
    for _,omit in ipairs({true,false})do
        local e,o,r=fixture();if omit then o.entities.missionAlly=nil else e.friendlies[#e.friendlies+1]=102 end
        local s=session.new(o);assert(s:submit('guest',r()).reason=='friendly-inventory-changed' and e.moveCalls==0)
    end
end)
test('mission ally remains in ownership model without pretending movement supports it',function()
    local e,o,r=fixture();local s=session.new(o);local a=r();a.actor='missionAlly'
    assert(s:submit('guest',a).reason=='actor-not-owned');a.id='r2'
    assert(s:submit('host',a).status=='rejected' and not s.stopped and e.moveCalls==0)
end)
test('existing punch target and movement restrictions remain enforced',function()
    local e,o,r=fixture();local s=session.new(o);local a=r('lab-punch');a.toX=4
    assert(s:submit('host',a).reason=='unsupported-punch-scenario' and e.attackCalls==0)
    a=r('lab-punch','r2');e.target.hp=2;assert(s:submit('host',a).status=='rejected' and e.attackCalls==0)
end)
test('one punch per process safeguard is retained',function()
    local e,o,r=fixture();local s=session.new(o);s:submit('host',r('lab-punch'));completeAttack(e,s)
    e.actor.active=true;e.target.hp=3;e.target.pos={x=2,y=3};local a=r('lab-punch','r2');a.revision=1
    assert(s:submit('host',a).status=='rejected' and e.attackCalls==1)
end)
test('read failure and evidence failure stop rather than dispatch',function()
    for _,key in ipairs({'witness','emit','guardHealthy'})do
        local e,o,r=fixture();o[key]=function()error('failure')end;local s=session.new(o)
        s:submit('guest',r());assert(s.stopped and e.moveCalls==0 and e.attackCalls==0)
    end
end)
test('bounded records never evict and admit an old request again',function()
    local e,o,r=fixture();local s=session.new(o)
    for i=1,128 do local a=r('move','r'..i);a.revision=9;assert(s:submit('guest',a).status=='rejected')end
    assert(s:submit('guest',r('move','overflow')).status=='stopped' and e.moveCalls==0)
end)
test('overlapping timed gate prevents either action path',function()
    local e,o,r=fixture();o.gate.active=true;local s=session.new(o)
    assert(s:submit('guest',r()).reason=='diagnostic-gate-overlap' and e.moveCalls==0)
    assert(s:submit('host',r('lab-punch','r2')).status=='rejected' and e.attackCalls==0)
end)
test('observation changing during validation cannot silently retarget a command',function()
    local e,o,r=fixture();local s=session.new(o);local a=r()
    e.Board.GetReachable=function()e.witness='partial-board:changed';return list({{x=1,y=2}})end
    assert(s:submit('guest',a).reason=='stale-observation-renew-intent' and e.moveCalls==0)
    assert(a.witness=='partial-board:0' and a.toX==1 and a.toY==2)
end)
test('bridge failure shares uncertainty without a second dispatch',function()
    local e,o,r=fixture();o.bridge.start=function()e.moveCalls=e.moveCalls+1;error('possible-click')end
    local s=session.new(o);local a=r();assert(s:submit('guest',a).status=='uncertain' and s.stopped)
    assert(s:submit('guest',a).status=='duplicate' and e.moveCalls==1)
    assert(s:submit('host',r('lab-punch','r2')).status=='rejected' and e.attackCalls==0)
end)
test('failure of pre-engine evidence aborts both actual diagnostic request bodies',function()
    for _,kind in ipairs({'move','lab-punch'})do
        local e,o,r=fixture();o.emit=function(k)if k=='move_requested' or k=='attack_requested' then error('disk-full')end end
        local s=session.new(o);assert(s:submit(kind=='move' and 'guest' or 'host',r(kind)).status=='uncertain')
        assert(s.stopped and e.moveCalls==0 and e.attackCalls==0)
    end
end)
print('Shared command session contracts: '..passed..' passed (real Lua diagnostics, mocked game/guard).')
