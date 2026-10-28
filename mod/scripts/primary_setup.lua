-- Bounded data-only setup for one fresh stock Tides battle; no rotation/save writes.
local M={}
local actors={combat=true,cannon=true,artillery=true}
local labels={combat='Combat',cannon='Cannon',artillery='Artillery'}
local function peer(v)return v=='host' or v=='guest'end
function M.parse(text)
    assert(type(text)=='string' and #text<=128,'primary-frame-size')
    local generation,h,hc,g,gc,hr,gr=text:match('^(%d+)|([a-z%-]+)|([a-z%-]+)|([a-z%-]+)|([a-z%-]+)|([01])|([01])$')
    local n=tonumber(generation);assert(n and n<=32 and tostring(n)==generation,'primary-frame-generation')
    local function choice(a,c)
        if a=='-' and c=='-' then return nil end
        assert(actors[a] and peer(c),'primary-frame-choice');return {primary=a,sharedController=c}
    end
    local choices={host=choice(h,hc),guest=choice(g,gc)}
    local valid=choices.host and choices.guest and h~=g and hc==gc
    assert(valid or hr=='0' and gr=='0','primary-frame-ready-conflict')
    local owners,shared
    if valid then
        owners={[h]='host',[g]='guest'}
        for a in pairs(actors)do if a~=h and a~=g then shared=a;owners[a]=hc end end
    end
    return {generation=n,choices=choices,ready={host=hr=='1',guest=gr=='1'},owners=owners,sharedActor=shared}
end
function M.new(o)
    local self={}
    local function context(s,r)
        local n=o.native.info()
        assert(not s.stopped and s.revision==0 and s.phase=='deployment' and r.revision==0 and r.phase=='deployment'
            and n.guardActive and n.sessionState==1 and not n.releaseFailed and not n.armed and not n.pressed,'primary-local-context')
        return {revision=0,phase='deployment',witness=r.witness,native=n}
    end
    function self:send(s,r,fields)
        local m=context(s,r);for k,v in pairs(fields)do m[k]=v end;o.wire:send(m)
    end
    function self:receive(m,s,r)
        context(s,r)
        assert(not self.locked and m.peer=='-' and m.revision==0 and m.phase=='deployment','primary-wire-context')
        local v=M.parse(m.witness)
        assert(m.id=='primary-'..v.generation and (not self.offer or v.generation>=self.offer.generation),'primary-wire-stale')
        if self.offer and v.generation~=self.offer.generation then self.readyGeneration=nil end
        self.offer=v
        if m.kind=='SQUADLOCK' then
            local own=v.choices[o.wire.peer]
            assert(v.owners and v.ready.host and v.ready.guest and self.readyGeneration==v.generation
                and own and own.primary==self.primary and own.sharedController==self.sharedController,'primary-lock-not-approved-locally')
            s:installPrimaryOwners(v.owners,r.witness)
            self.locked=true;o.wire.squadOwners=v.owners
            self:send(s,r,{type='primary_applied',generation=v.generation,owners=v.owners})
            o.emit('primary_setup_locked',{generation=v.generation,owners=v.owners,sharedActor=v.sharedActor,scope='one-fresh-battle-no-rotation'})
        else assert(m.kind=='SQUAD','primary-wire-kind') end
    end
    function self:click(x,y,s,r)
        if self.locked or not self.offer or x<8 or x>=298 then return end
        context(s,r)
        local a=y>=380 and y<416 and 'combat' or y>=420 and y<456 and 'cannon' or y>=460 and y<496 and 'artillery'
        if a and a==self.primary then return end
        if a or y>=680 and y<716 then
            if a then self.primary=a else self.sharedController=self.sharedController=='host' and 'guest' or 'host' end
            self.readyGeneration=nil
            if self.primary and self.sharedController then
                self:send(s,r,{type='primary_choice',primary=self.primary,sharedController=self.sharedController})
                o.emit('primary_setup_choice',{primary=self.primary,sharedController=self.sharedController,peer=o.wire.peer})
            end
        elseif y>=600 and y<636 then
            local v=self.offer;local own=v.choices[o.wire.peer]
            if not v.owners or not own or own.primary~=self.primary or own.sharedController~=self.sharedController or self.readyGeneration==v.generation then return end
            self.readyGeneration=v.generation;self:send(s,r,{type='primary_ready',generation=v.generation,confirm=true})
            o.emit('primary_setup_ready',{peer=o.wire.peer,generation=v.generation,owners=v.owners})
        end
    end
    function self:status()
        if not self.offer then return 'Waiting for teammate setup' end
        if not self.primary then return 'Choose your primary mech' end
        if not self.sharedController then return 'Choose first shared controller' end
        local v=self.offer;local h,g=v.choices.host,v.choices.guest
        if not h or not g then return 'Waiting for teammate choices' end
        if h.primary==g.primary then return 'Choose different primary mechs' end
        if h.sharedController~=g.sharedController then return 'Agree on shared controller' end
        return self.readyGeneration==v.generation and 'Approved; waiting for teammate' or 'Review both choices; approve below'
    end
    function self:caption(actor)
        local h=self.offer and self.offer.choices.host;local g=self.offer and self.offer.choices.guest
        if self.offer and self.offer.sharedActor==actor then return labels[actor]..' shared: '..self.offer.owners[actor] end
        return labels[actor]..(self.primary==actor and ' [you]' or '')..(h and h.primary==actor and ' host' or '')..(g and g.primary==actor and ' guest' or '')
    end
    return self
end
return M
