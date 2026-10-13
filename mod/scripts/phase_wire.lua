-- Private, opt-in TCP experiment mailbox. No executable payloads or socket ABI changes.
local M={}
local function ident(s) return type(s)=='string' and #s>0 and #s<=96 and s:match('^[%w_.:-]+$') end
function M.decode(text,session)
    assert(type(text)=='string' and #text<=70000,'wire-frame-size')
    local header,body=text:match('^([^\n]+)\n(.*)$')
    assert(header and body,'wire-header')
    local base,actor,fx,fy,tx,ty=header:match('^(.-)|([%w]+)|([0-7])|([0-7])|([0-7])|([0-7])$')
    if base then text=base..'\n'..body end
    local kind,sid,peer,revision,phase,id,witness=text:match('^([A-Z]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)\n(.*)$')
    assert(sid==session and ident(sid),'wire-session')
    assert(kind=='PING' or kind=='STOP' or kind=='PROPOSE' or kind=='READY' or kind=='CONSENT' or kind=='EXEC' or kind=='DONE' or kind=='INPUT','wire-kind')
    assert(peer=='host' or peer=='guest' or peer=='-','wire-peer')
    local rev=tonumber(revision);assert(rev and rev>=0 and rev<=4 and rev==math.floor(rev),'wire-revision')
    assert((phase=='-' or ident(phase)) and (id=='-' or ident(id)),'wire-context')
    assert(#witness<=65536 and not witness:find('[\r\n]'),'wire-witness')
    if base then assert(kind=='EXEC' and (actor=='combat' or actor=='cannon' or actor=='artillery'),'wire-move') end
    return {kind=kind,peer=peer,revision=rev,phase=phase,id=id,witness=witness,move=base and {
        session=session,encounter='artillery-checkpoint',phase=phase,revision=rev,witness=witness,
        id=id,kind='move',actor=actor,fromX=tonumber(fx),fromY=tonumber(fy),toX=tonumber(tx),toY=tonumber(ty)} or nil}
end
function M.open(env,json,emit)
    local root=env.os.getenv('ITB_COOP_WIRE_DIR')
    if not root then return nil end
    assert(root=='C:/ITBCoopProbe/Wire','unsupported-wire-directory')
    local f=assert(env.io.open(root..'/session.txt','rb'),'wire-config-missing')
    local config=f:read(256);f:close()
    local interactive=config:sub(-12)=='interactive\n'
    if interactive then config=config:sub(1,-13) end
    local session,peer=config:match('^([%w-]+)\n(host)\n$')
    if not session then session,peer=config:match('^([%w-]+)\n(guest)\n$') end
    assert(ident(session) and peer,'wire-config-invalid')
    local self={session=session,peer=peer,root=root,rx=1,tx=1,interactive=interactive,limit=interactive and 2 or 4}
    local function now() return env.modApi:elapsedTime() end
    function self:send(value)
        assert(self.tx<=32,'wire-output-limit')
        value.session=self.session;value.peer=self.peer
        local target=self.root..('/out-%04d.json'):format(self.tx)
        local file=assert(env.io.open(target..'.tmp','wb'),'wire-output-open')
        assert(file:write(json.encode(value)));assert(file:close())
        assert(env.os.rename(target..'.tmp',target),'wire-output-commit')
        self.tx=self.tx+1
    end
    function self:arm(context)
        self.since=now();self.last=now();self.observed=0
        self:send({type='armed',revision=0,phase=context.phase,witness=context.witness,probe='0.11.0',interactive=self.interactive})
    end
    function self:propose(r)
        assert(self.interactive and self.inputReady,'wire-not-accepting-input')
        assert(r.revision==self.inputRevision and r.witness==self.inputWitness,'wire-stale-draft')
        self.inputReady=false
        self:send({type='proposal',request=r})
    end
    function self:tick(s,request,native)
        assert(now()-self.since<(self.interactive and 600000 or 180000),'wire-experiment-timeout')
        assert(now()-self.last<10000,'wire-heartbeat-timeout')
        for _=1,4 do
            assert(self.rx<=1024,'wire-input-limit')
            local f=env.io.open(self.root..('/in-%04d.txt'):format(self.rx),'rb')
            if not f then break end
            local data=f:read(70001);f:close();self.rx=self.rx+1
            local m=M.decode(data,self.session);self.last=now()
            assert(m.kind~='STOP','wire-peer-or-coordinator-stopped')
            if m.kind~='PING' then
                local r=request()
                assert(m.revision==s.revision and m.phase==s.phase and m.witness==r.witness,'wire-stale-context')
                if m.kind=='INPUT' then
                    assert(self.interactive and not self.pending,'wire-input-context')
                    self.inputReady=true;self.inputRevision=s.revision;self.inputWitness=r.witness
                elseif m.kind=='PROPOSE' then
                    assert(m.peer==self.peer and m.id==r.id,'wire-proposal-owner')
                    self:send({type='proposal',request=r})
                elseif m.kind=='READY' then
                    assert(s.revision==2 and m.id=='end-turn','wire-readiness-context')
                    self:send({type='ready',revision=s.revision,phase=s.phase,witness=r.witness,confirmUnused=true})
                elseif m.kind=='CONSENT' then
                    assert(s.revision==2 and m.id=='end-turn','wire-consent-context')
                    assert(s:setReady(m.peer,m.phase,m.revision,m.witness,true),'wire-consent-rejected')
                elseif m.kind=='EXEC' then
                    if self.interactive then assert(m.move,'wire-move-missing');r=m.move;self.inputReady=false end
                    assert(not self.pending and m.id==r.id,'wire-unexpected-command')
                    local result=s:submit(m.peer,r)
                    assert(result.status=='pending','wire-command-rejected:'..tostring(result.reason))
                    self.pending=r.id
                    if r.kind=='end-turn' then self.ending=true end
                    emit('network_command_received',{peer=m.peer,request=r,fixture=true})
                elseif m.kind=='DONE' then
                    assert(s.revision==self.limit and not self.pending,'wire-premature-finish')
                    self:send({type='complete',revision=self.limit,witness=r.witness,native=native.info()})
                    return true
                end
            end
        end
        if self.pending and s.revision==self.observed+1 then
            local r=request();self.observed=s.revision
            self:send({type='observed',id=self.pending,revision=s.revision,phase=s.phase,witness=r.witness,native=native.info()})
            self.pending=nil
        end
        return false
    end
    return self
end
return M
