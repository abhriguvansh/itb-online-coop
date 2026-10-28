-- Private opt-in command framing, shared by file bridge and in-process transport.
local M={}
local function ident(s) return type(s)=='string' and #s>0 and #s<=96 and s:match('^[%w_.:-]+$') end
function M.decode(text,session)
    assert(type(text)=='string' and #text<=70000,'wire-frame-size')
    local header,body=text:match('^([^\n]+)\n(.*)$')
    assert(header and body,'wire-header')
    local base,actor,fx,fy,tx,ty=header:match('^(.-)|([%w]+)|([%-0-7]+)|([%-0-7]+)|([0-7])|([0-7])$')
    if base then text=base..'\n'..body end
    local kind,sid,peer,revision,phase,id,witness=text:match('^([A-Z]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)\n(.*)$')
    assert(sid==session and ident(sid),'wire-session')
    local spawn=kind=='SPAWNSELECT' or kind=='SPAWNAPPLY' or kind=='SPAWNRELEASE'
    assert(spawn or kind=='SQUAD' or kind=='SQUADLOCK' or kind=='RESETREADY' or kind=='RESETCONSENT' or kind=='RESETCANCEL' or kind=='RESULTCONTINUE' or kind=='RESULTDONE' or kind=='PING' or kind=='STOP' or kind=='PROPOSE' or kind=='READY' or kind=='CONSENT' or kind=='EXEC' or kind=='DONE' or kind=='INPUT' or kind=='PREPARE','wire-kind')
    assert(peer=='host' or peer=='guest' or peer=='-','wire-peer')
    local rev=tonumber(revision);assert(rev and rev>=0 and rev<=32 and rev==math.floor(rev),'wire-revision')
    assert((phase=='-' or ident(phase)) and (id=='-' or ident(id)),'wire-context')
    assert(#witness<=65536 and not witness:find('\r') and (spawn or not witness:find('\n')),'wire-witness')
    local deploying=base and (actor=='deploycombat' or actor=='deploycannon' or actor=='deployartillery')
    local repairing=base and (actor=='repaircombat' or actor=='repaircannon' or actor=='repairartillery')
    local undoing=base and (actor=='undocombat' or actor=='undocannon' or actor=='undoartillery')
    if base then
        assert((kind=='EXEC' or kind=='PREPARE') and (deploying or repairing or undoing or actor=='combat' or actor=='cannon' or actor=='artillery' or actor=='punch' or actor=='attackcombat' or actor=='attackcannon' or actor=='attackartillery'),'wire-move')
        assert(deploying and fx=='-1' and fy=='-1' or not deploying and fx:match('^[0-7]$') and fy:match('^[0-7]$'),'wire-origin')
        assert(not repairing or fx==tx and fy==ty,'wire-repair-target')
    end
    return {kind=kind,peer=peer,revision=rev,phase=phase,id=id,witness=witness,move=base and {
        session=session,encounter='artillery-checkpoint',phase=phase,revision=rev,witness=witness,
        id=id,kind=deploying and 'deploy' or repairing and 'repair' or undoing and 'undo-move' or actor=='punch' and 'lab-punch' or actor:sub(1,6)=='attack' and 'basic-attack' or 'move',actor=undoing and actor:sub(5) or (deploying or repairing) and actor:sub(7) or actor=='punch' and 'combat' or actor:sub(1,6)=='attack' and actor:sub(7) or actor,fromX=tonumber(fx),fromY=tonumber(fy),toX=tonumber(tx),toY=tonumber(ty)} or nil}
end
function M.open(env,json,emit)
    local root=env.os.getenv('ITB_COOP_WIRE_DIR')
    if not root then return nil end
    assert(root=='C:/ITBCoopProbe/Wire','unsupported-wire-directory')
    local f=assert(env.io.open(root..'/session.txt','rb'),'wire-config-missing')
    local config=f:read(256);f:close()
    local checkpointSuffix='xp-result-checkpoint\n'
    local xpCheckpoint=config:sub(-#checkpointSuffix)==checkpointSuffix
    if xpCheckpoint then config=config:sub(1,-#checkpointSuffix-1)..'terminal-checkpoint\n' end
    local fullSuffix='full-mission\n'
    local fullMission=xpCheckpoint or config:sub(-#fullSuffix)==fullSuffix
    if fullMission and not xpCheckpoint then config=config:sub(1,-#fullSuffix-1)..'deployment\n' end
    local deploymentSuffix='deployment\n'
    local deployment=config:sub(-#deploymentSuffix)==deploymentSuffix
    if deployment then config=config:sub(1,-#deploymentSuffix-1)..'interactive-phase\n' end
    local terminalSuffix='terminal-checkpoint\n'
    local terminalCheckpoint=config:sub(-#terminalSuffix)==terminalSuffix
    if terminalCheckpoint then config=config:sub(1,-#terminalSuffix-1)..'repeated-turns\n' end
    local repeatedTurns=fullMission or config:sub(-15)=='repeated-turns\n'
    if repeatedTurns and (not fullMission or xpCheckpoint) then config=config:sub(1,-16)..'interactive-phase\n' end
    local phaseRun=config:sub(-18)=='interactive-phase\n'
    if phaseRun then config=config:sub(1,-19)..'interactive\n' end
    local interactive=config:sub(-12)=='interactive\n'
    if interactive then config=config:sub(1,-13) end
    local session,peer=config:match('^([%w-]+)\n(host)\n$')
    if not session then session,peer=config:match('^([%w-]+)\n(guest)\n$') end
    assert(ident(session) and peer,'wire-config-invalid')
    local self={fullMission=fullMission,session=session,peer=peer,root=root,rx=1,tx=1,interactive=interactive,phaseRun=phaseRun,repeatedTurns=repeatedTurns,terminalCheckpoint=terminalCheckpoint,deployment=deployment,limit=deployment and 5 or interactive and not phaseRun and 2 or 4}
    self.transport=env.ITBCoopTransport
    self.primaryMode=env.os.getenv('ITB_COOP_CHOOSE_MECHS')=='1'
    assert(not self.primaryMode or self.fullMission and self.deployment and not self.terminalCheckpoint and self.transport,'primary-mode-requires-fresh-native-mission')
    if env.os.getenv('ITB_COOP_NATIVE_TRANSPORT')=='1' then assert(self.transport,'wire-native-transport-missing') end
    local function now() return env.modApi:elapsedTime() end
    function self:send(value)
        assert(self.tx<=192,'wire-output-limit')
        value.session=self.session;value.peer=self.peer
        if self.transport then self.transport:send(value);self.tx=self.tx+1;return end
        local target=self.root..('/out-%04d.json'):format(self.tx)
        local file=assert(env.io.open(target..'.tmp','wb'),'wire-output-open')
        assert(file:write(json.encode(value)));assert(file:close())
        assert(env.os.rename(target..'.tmp',target),'wire-output-commit')
        self.tx=self.tx+1
    end
    function self:arm(context)
        if self.fullMission then assert(self.sharedXp,'shared-xp-required');self.sharedXp:healthy() end
        if self.transport then assert(self.transport:healthy(),'wire-native-transport-unavailable');self.transport.active=true end
        self.since=now();self.last=now();self.observed=0
        self:send({type='armed',revision=0,phase=context.phase,witness=context.witness,probe='0.33.0',interactive=self.interactive,phaseRun=self.phaseRun,repeatedTurns=self.repeatedTurns,terminalCheckpoint=self.terminalCheckpoint,deployment=self.deployment,fullMission=self.fullMission,primarySetup=self.primaryMode or nil,sharedXp=self.fullMission and 'itb-shared-xp-v1' or nil})
    end
    function self:propose(r)
        assert(self.interactive and self.inputReady,'wire-not-accepting-input')
        assert(r.revision==self.inputRevision and r.witness==self.inputWitness,'wire-stale-draft')
        self.inputReady=false;self.inspectionReady=false
        self:send({type='proposal',request=r})
    end
    function self:ready(s,r)
        assert(self.phaseRun and (self.readyInput or ((self.repeatedTurns or self.deployment) and self.inputReady)) and not self.readySent,'wire-not-accepting-readiness')
        assert(s:setReady(self.peer,r.phase,r.revision,r.witness,true),'wire-local-readiness-rejected')
        self.readySent=true;self.readyInput=false;self.inputReady=false
        self:send({type='ready',revision=r.revision,phase=r.phase,witness=r.witness,confirmUnused=r.kind=='end-turn' and true or nil,confirmDeployment=r.kind=='deployment-confirm' and true or nil})
    end
    function self:resetReady(s,r)
        assert(self.repeatedTurns and self.inputReady and not self.resetSent and r.kind=='reset-turn','wire-reset-unavailable')
        local ok,why=s:canReset(self.peer,r.phase,r.revision,r.witness);assert(ok,why)
        assert(s:setReady(self.peer,r.phase,r.revision,r.witness,true,'reset-turn'),'wire-reset-readiness-rejected')
        self.resetSent=true
        self:send({type='reset_ready',revision=r.revision,phase=r.phase,witness=r.witness,confirmReset=true})
    end
    function self:tick(s,request,native)
        if self.sharedXp then self.sharedXp:healthy() end
        if self.transport then assert(self.transport:healthy(),'wire-native-transport-unavailable') end
        assert(now()-self.since<(self.fullMission and 3600000 or self.repeatedTurns and 1800000 or self.interactive and 600000 or 180000),'wire-experiment-timeout')
        assert(now()-self.last<10000,'wire-heartbeat-timeout')
        for _=1,4 do
            assert(self.rx<=(self.fullMission and 4096 or self.repeatedTurns and 2048 or 1024),'wire-input-limit')
            local data
            if self.transport then data=self.transport:receive()
            else
                local f=env.io.open(self.root..('/in-%04d.txt'):format(self.rx),'rb')
                if f then data=f:read(70001);f:close() end
            end
            if not data then break end;self.rx=self.rx+1
            local m=M.decode(data,self.session);self.last=now()
            assert(m.kind~='STOP','wire-peer-or-coordinator-stopped')
            if m.kind=='SQUAD' or m.kind=='SQUADLOCK' then
                assert(self.primaryMode and self.primarySetup and not self.inputReady and not self.pending and not self.prepared,'wire-primary-context')
                self.primarySetup:receive(m,s,request())
            elseif m.kind:sub(1,6)=='RESULT' then
                assert(self.repeatedTurns and self.result and s.terminal,'wire-result-unavailable')
                if self.result:receive(m) then self.pending=nil;self.pendingKind=nil;return true end
            elseif m.kind:sub(1,5)=='SPAWN' then
                assert((self.repeatedTurns or self.deployment) and self.spawn,'wire-spawn-unavailable');self.spawn:receive(m)
            elseif m.kind~='PING' then
                assert(not self.primaryMode or self.primarySetup and self.primarySetup.locked,'wire-primary-not-locked')
                assert(not s.terminal,'wire-gameplay-after-mission-end')
                local r=request()
                assert(m.revision==s.revision and m.phase==s.phase and m.witness==r.witness,'wire-stale-context')
                if m.id=='reset-turn-'..s.revision then
                    assert(self.repeatedTurns,'wire-reset-mode');r.kind='reset-turn';r.id=m.id;r.confirmUnused=nil;r.confirmReset=true
                end
                if m.kind=='INPUT' then
                    assert(self.interactive and not self.pending,'wire-input-context')
                    self.readySent=false;self.readyInput=false;self.resetSent=false;self.resetPending=false;self.inputReady=true;self.inspectionReady=true;self.inputRevision=s.revision;self.inputWitness=r.witness
                elseif m.kind=='RESETREADY' then
                    assert(self.repeatedTurns and not self.pending and r.kind=='reset-turn','wire-reset-ready-context')
                    self.resetPending=true;self.inputReady=true;self.readyInput=false;self.inspectionReady=true
                elseif m.kind=='RESETCANCEL' then
                    self.resetSent=false;self.resetPending=false;s:clearResetReady()
                elseif m.kind=='RESETCONSENT' then
                    assert(self.resetPending and r.kind=='reset-turn' and (m.peer~=self.peer or self.resetSent),'wire-reset-consent-context')
                    assert(s:setReady(m.peer,m.phase,m.revision,m.witness,true,'reset-turn'),'wire-reset-consent-rejected')
                elseif m.kind=='PROPOSE' then
                    assert(m.peer==self.peer and m.id==r.id,'wire-proposal-owner')
                    self:send({type='proposal',request=r})
                elseif m.kind=='READY' then
                    assert((self.repeatedTurns or (self.deployment and s.revision==3) or (not self.deployment and s.revision==2)) and m.id==r.id,'wire-readiness-context')
                    if self.phaseRun then self.inputReady=false;self.readyInput=not self.readySent;self.inspectionReady=true
                    else self:send({type='ready',revision=s.revision,phase=s.phase,witness=r.witness,confirmUnused=true}) end
                elseif m.kind=='CONSENT' then
                    assert((self.repeatedTurns or (self.deployment and s.revision==3) or (not self.deployment and s.revision==2)) and m.id==r.id,'wire-consent-context')
                    assert(s:setReady(m.peer,m.phase,m.revision,m.witness,true),'wire-consent-rejected')
                elseif m.kind=='PREPARE' then
                    assert(self.interactive and (m.move or (self.phaseRun and (r.kind=='end-turn' or r.kind=='deployment-confirm' or r.kind=='reset-turn'))) and not self.pending and not self.prepared,'wire-prepare-context')
                    local preparedRequest=m.move or r
                    self.inputReady=false;self.inspectionReady=false
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
                        assert(m.move or (self.phaseRun and (r.kind=='end-turn' or r.kind=='deployment-confirm' or r.kind=='reset-turn')),'wire-command-missing');r=m.move or r;self.inputReady=false;self.inspectionReady=false
                        local p=self.prepared
                        assert(p and p.peer==m.peer and p.request==json.encode(r) and now()-p.at<5000,'wire-exec-not-prepared')
                        self.prepared=nil
                    end
                    assert(not self.pending and m.id==r.id,'wire-unexpected-command')
                    if self.fullMission then assert(self.sharedXp,'shared-xp-required');self.sharedXp:begin(self.session,r) end
                    local result=s:submit(m.peer,r)
                    assert(result.status=='pending','wire-command-rejected:'..tostring(result.reason))
                    self.pending=r.id
                    self.pendingKind=r.kind
                    if r.kind=='end-turn' or r.kind=='deployment-confirm' then self.ending=true end
                    emit('network_command_received',{peer=m.peer,request=r,fixture=true})
                elseif m.kind=='DONE' then
                    self.inspectionReady=false
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
            local xp=self.sharedXp and self.sharedXp:finish() or nil
            self:send({type='observed',id=self.pending,revision=s.revision,phase=s.phase,witness=r.witness,native=native.info(),resetRemaining=self.pendingKind=='reset-turn' and s.resetRemaining or nil,sharedXp=xp})
            self.pending=nil
            self.pendingKind=nil
        end
        return false
    end
    return self
end
return M
