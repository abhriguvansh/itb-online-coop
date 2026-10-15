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
    local spawn=kind=='SPAWNSELECT' or kind=='SPAWNAPPLY' or kind=='SPAWNRELEASE'
    assert(spawn or kind=='RESULTCONTINUE' or kind=='RESULTDONE' or kind=='PING' or kind=='STOP' or kind=='PROPOSE' or kind=='READY' or kind=='CONSENT' or kind=='EXEC' or kind=='DONE' or kind=='INPUT' or kind=='PREPARE','wire-kind')
    assert(peer=='host' or peer=='guest' or peer=='-','wire-peer')
    local rev=tonumber(revision);assert(rev and rev>=0 and rev<=32 and rev==math.floor(rev),'wire-revision')
    assert((phase=='-' or ident(phase)) and (id=='-' or ident(id)),'wire-context')
    assert(#witness<=65536 and not witness:find('\r') and (spawn or not witness:find('\n')),'wire-witness')
    if base then assert((kind=='EXEC' or kind=='PREPARE') and (actor=='combat' or actor=='cannon' or actor=='artillery' or actor=='punch' or actor=='attackcombat' or actor=='attackcannon' or actor=='attackartillery'),'wire-move') end
    return {kind=kind,peer=peer,revision=rev,phase=phase,id=id,witness=witness,move=base and {
        session=session,encounter='artillery-checkpoint',phase=phase,revision=rev,witness=witness,
        id=id,kind=actor=='punch' and 'lab-punch' or actor:sub(1,6)=='attack' and 'basic-attack' or 'move',actor=actor=='punch' and 'combat' or actor:sub(1,6)=='attack' and actor:sub(7) or actor,fromX=tonumber(fx),fromY=tonumber(fy),toX=tonumber(tx),toY=tonumber(ty)} or nil}
end
function M.open(env,json,emit)
    local root=env.os.getenv('ITB_COOP_WIRE_DIR')
    if not root then return nil end
    assert(root=='C:/ITBCoopProbe/Wire','unsupported-wire-directory')
    local f=assert(env.io.open(root..'/session.txt','rb'),'wire-config-missing')
    local config=f:read(256);f:close()
    local terminalSuffix='terminal-checkpoint\n'
    local terminalCheckpoint=config:sub(-#terminalSuffix)==terminalSuffix
    if terminalCheckpoint then config=config:sub(1,-#terminalSuffix-1)..'repeated-turns\n' end
    local repeatedTurns=config:sub(-15)=='repeated-turns\n'
    if repeatedTurns then config=config:sub(1,-16)..'interactive-phase\n' end
    local phaseRun=config:sub(-18)=='interactive-phase\n'
    if phaseRun then config=config:sub(1,-19)..'interactive\n' end
    local interactive=config:sub(-12)=='interactive\n'
    if interactive then config=config:sub(1,-13) end
    local session,peer=config:match('^([%w-]+)\n(host)\n$')
    if not session then session,peer=config:match('^([%w-]+)\n(guest)\n$') end
    assert(ident(session) and peer,'wire-config-invalid')
    local self={session=session,peer=peer,root=root,rx=1,tx=1,interactive=interactive,phaseRun=phaseRun,repeatedTurns=repeatedTurns,terminalCheckpoint=terminalCheckpoint,limit=interactive and not phaseRun and 2 or 4}
    local function now() return env.modApi:elapsedTime() end
    function self:send(value)
        assert(self.tx<=192,'wire-output-limit')
        value.session=self.session;value.peer=self.peer
        local target=self.root..('/out-%04d.json'):format(self.tx)
        local file=assert(env.io.open(target..'.tmp','wb'),'wire-output-open')
        assert(file:write(json.encode(value)));assert(file:close())
        assert(env.os.rename(target..'.tmp',target),'wire-output-commit')
        self.tx=self.tx+1
    end
    function self:arm(context)
        self.since=now();self.last=now();self.observed=0
        self:send({type='armed',revision=0,phase=context.phase,witness=context.witness,probe='0.17.0',interactive=self.interactive,phaseRun=self.phaseRun,repeatedTurns=self.repeatedTurns,terminalCheckpoint=self.terminalCheckpoint})
    end
    function self:propose(r)
        assert(self.interactive and self.inputReady,'wire-not-accepting-input')
        assert(r.revision==self.inputRevision and r.witness==self.inputWitness,'wire-stale-draft')
        self.inputReady=false
        self:send({type='proposal',request=r})
    end
    function self:ready(s,r)
        assert(self.phaseRun and (self.readyInput or (self.repeatedTurns and self.inputReady)) and not self.readySent,'wire-not-accepting-readiness')
        assert(s:setReady(self.peer,r.phase,r.revision,r.witness,true),'wire-local-readiness-rejected')
        self.readySent=true;self.readyInput=false;self.inputReady=false
        self:send({type='ready',revision=r.revision,phase=r.phase,witness=r.witness,confirmUnused=true})
    end
    function self:tick(s,request,native)
        assert(now()-self.since<(self.repeatedTurns and 1500000 or self.interactive and 600000 or 180000),'wire-experiment-timeout')
        assert(now()-self.last<10000,'wire-heartbeat-timeout')
        for _=1,4 do
            assert(self.rx<=(self.repeatedTurns and 2048 or 1024),'wire-input-limit')
            local f=env.io.open(self.root..('/in-%04d.txt'):format(self.rx),'rb')
            if not f then break end
            local data=f:read(70001);f:close();self.rx=self.rx+1
            local m=M.decode(data,self.session);self.last=now()
            assert(m.kind~='STOP','wire-peer-or-coordinator-stopped')
            if m.kind:sub(1,6)=='RESULT' then
                assert(self.repeatedTurns and self.result and s.terminal,'wire-result-unavailable')
                if self.result:receive(m) then self.pending=nil;self.pendingKind=nil;return true end
            elseif m.kind:sub(1,5)=='SPAWN' then
                assert(self.repeatedTurns and self.spawn,'wire-spawn-unavailable');self.spawn:receive(m)
            elseif m.kind~='PING' then
                assert(not s.terminal,'wire-gameplay-after-mission-end')
                local r=request()
                assert(m.revision==s.revision and m.phase==s.phase and m.witness==r.witness,'wire-stale-context')
                if m.kind=='INPUT' then
                    assert(self.interactive and not self.pending,'wire-input-context')
                    self.readySent=false;self.readyInput=false;self.inputReady=true;self.inputRevision=s.revision;self.inputWitness=r.witness
                elseif m.kind=='PROPOSE' then
                    assert(m.peer==self.peer and m.id==r.id,'wire-proposal-owner')
                    self:send({type='proposal',request=r})
                elseif m.kind=='READY' then
                    assert((self.repeatedTurns or s.revision==2) and m.id==r.id,'wire-readiness-context')
                    if self.phaseRun then self.inputReady=false;self.readyInput=not self.readySent
                    else self:send({type='ready',revision=s.revision,phase=s.phase,witness=r.witness,confirmUnused=true}) end
                elseif m.kind=='CONSENT' then
                    assert((self.repeatedTurns or s.revision==2) and m.id==r.id,'wire-consent-context')
                    assert(s:setReady(m.peer,m.phase,m.revision,m.witness,true),'wire-consent-rejected')
                elseif m.kind=='PREPARE' then
                    assert(self.interactive and (m.move or (self.phaseRun and r.kind=='end-turn')) and not self.pending and not self.prepared,'wire-prepare-context')
                    local preparedRequest=m.move or r
                    self.inputReady=false
                    local ok,reason
                    if self.phaseRun then ok,reason=s:previewAction(m.peer,preparedRequest) else ok,reason=s:previewMove(m.peer,preparedRequest) end
                    assert(ok,'wire-prepare-rejected:'..tostring(reason))
                    local n=native.info()
                    assert(n.guardActive and n.sessionState==1 and not n.releaseFailed and not n.armed and not n.pressed,'wire-prepare-protection')
                    self.prepared={peer=m.peer,request=json.encode(preparedRequest),at=now()}
                    self:send({type='prepared',origin=m.peer,request=preparedRequest,native=n})
                    emit('network_command_prepared',{peer=m.peer,id=m.id,revision=s.revision})
                elseif m.kind=='EXEC' then
                    if self.interactive then
                        assert(m.move or (self.phaseRun and r.kind=='end-turn'),'wire-command-missing');r=m.move or r;self.inputReady=false
                        local p=self.prepared
                        assert(p and p.peer==m.peer and p.request==json.encode(r) and now()-p.at<5000,'wire-exec-not-prepared')
                        self.prepared=nil
                    end
                    assert(not self.pending and m.id==r.id,'wire-unexpected-command')
                    local result=s:submit(m.peer,r)
                    assert(result.status=='pending','wire-command-rejected:'..tostring(result.reason))
                    self.pending=r.id
                    self.pendingKind=r.kind
                    if r.kind=='end-turn' then self.ending=true end
                    emit('network_command_received',{peer=m.peer,request=r,fixture=true})
                elseif m.kind=='DONE' then
                    assert(not self.repeatedTurns and s.revision==self.limit and not self.pending,'wire-premature-finish')
                    self:send({type='complete',revision=s.revision,witness=r.witness,native=native.info()})
                    return true
                end
            end
        end
        if s.terminal then
            assert(self.result and self.pendingKind=='end-turn' and self.pending==s.terminal.id,'wire-result-command-missing')
            self.result:update();return false
        end
        if self.spawn then self.spawn:tick() end
        if self.pending and s.revision==self.observed+1 then
            local r=request();self.observed=s.revision
            self:send({type='observed',id=self.pending,revision=s.revision,phase=s.phase,witness=r.witness,native=native.info()})
            self.pending=nil
            self.pendingKind=nil
        end
        return false
    end
    return self
end
return M
