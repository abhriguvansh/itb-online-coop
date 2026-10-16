-- Restricted local inspection. Never forwards input, submits an effect or grants ownership.
local M={}
local function same(a,b) return a and b and a.x==b.x and a.y==b.y end
local function point(p) return {x=p.x,y=p.y} end
local weapons={combat={id=0,type='PunchMech',skill='Prime_Punchmech',label='Titan Fist'},
    cannon={id=1,type='TankMech',skill='Brute_Tankmech',label='Taurus Cannon'},
    artillery={id=2,type='ArtiMech',skill='Ranged_Artillerymech',label='Artemis Artillery'}}
local function off(v) return v==nil or v==false or v==0 end
function M.new(o)
    local env=o.env
    local self={enabled=false,lines={},controls={},status='Inspect board',previews=0}
    local function available(s)
        local n=o.native.info()
        return not s.stopped and not s.terminal and o.wire.inspectionReady and not o.wire.pending and not o.wire.prepared and n.guardActive
            and n.sessionState==1 and not n.armed and not n.pressed and not n.releaseFailed
    end
    local function capture()
        local state,idle=o.capture()
        assert(idle and #state.unavailable==0,'inspection-board-not-ready')
        return state,o.json.encode(state)
    end
    local function uiState()
        local p=env.Board:GetSelectedPawn()
        return {selected=p and p:GetId() or -1,weapon=p and p:GetArmedWeaponId() or -1}
    end
    local function unchanged(before,ui)
        local after,witness=capture()
        assert(witness==before and o.json.encode(uiState())==o.json.encode(ui),'inspection-changed-observed-state')
        return after
    end
    function self:clear(reason)
        self.preview=nil;self.selecting=false;self.lines={};self.status=reason or 'Click a tile to inspect'
    end
    function self:update(s)
        if self.revision~=s.revision then
            if self.revision~=nil and (self.preview or #self.lines>0) then
                o.emit('inspection_invalidated',{previousRevision=self.revision,revision=s.revision})
            end
            self.revision=s.revision;self:clear('Board changed; inspect again')
        end
        self.allowed=available(s)==true
        if not self.allowed then self.preview=nil;self.selecting=false end
    end
    local function terrain(tile)
        for _,v in ipairs({'ROAD','BUILDING','MOUNTAIN','WATER','FOREST','SAND','ICE','HOLE','RUBBLE','LAVA'}) do
            if env['TERRAIN_'..v]==tile.terrain then return v:sub(1,1)..v:sub(2):lower() end
        end
        return 'Terrain '..tostring(tile.terrain)
    end
    function self:inspect(s,to)
        assert(available(s),'inspection-unavailable')
        local state,before=capture();local ui=uiState()
        local tile=assert(state.tiles[to.y*state.size.x+to.x+1],'inspection-tile-missing')
        self:clear();self.lines=o.json.array({('Tile (%d,%d): %s'):format(to.x,to.y,terrain(tile)),'','','','','',''})
        local flags={}
        for _,name in ipairs({'fire','acid','smoke','frozen','spawning','environmentDanger'}) do
            if tile[name] then flags[#flags+1]=name=='environmentDanger' and 'hazard' or name end
        end
        self.lines[2]=#flags>0 and table.concat(flags,', ') or 'No marked tile hazards'
        if tile.building then self.lines[3]='Building health: '..tile.health end
        for _,p in ipairs(state.pawns) do
            if same(p.position,to) and not p.dead then
                local pawn=assert(env.Board:GetPawn(p.localId),'inspection-pawn-missing')
                self.lines[3]=pawn:GetMechName()
                self.lines[4]=('Health: %d   Move: %d'):format(p.health,p.moveSpeed)
                self.lines[5]=p.team==env.TEAM_PLAYER and (p.active and 'Action active' or 'Action used') or 'Enemy'
                local statuses={}
                for _,k in ipairs({'fire','acid','frozen','shield','grappled'}) do if p[k] then statuses[#statuses+1]=k end end
                self.lines[6]=#statuses>0 and table.concat(statuses,', ') or 'No marked unit conditions'
                if p.team==env.TEAM_ENEMY and p.queuedTarget and env.Board:IsValid(env.Point(p.queuedTarget.x,p.queuedTarget.y)) then
                    self.lines[7]=('Attack aimed at (%d,%d)'):format(p.queuedTarget.x,p.queuedTarget.y)
                end
                break
            end
        end
        unchanged(before,ui)
        o.emit('inspection_tile',{revision=s.revision,tile=to,lines=self.lines,observedStateUnchanged=true,selectionUnchanged=true})
    end
    function self:weapon(s,to,actor)
        assert(available(s),'inspection-unavailable')
        local before,witness=capture();local ui=uiState()
        local spec=assert(weapons[actor],'unsupported-preview-actor')
        local p=assert(env.Board:GetPawn(spec.id),'preview-actor-missing');local from=p:GetSpace()
        local skill=env[spec.skill]
        local supported=p:GetType()==spec.type and p:IsActive() and p:IsPowered() and not p:IsDead() and not p:IsFrozen()
            and not p:IsBoosted() and not env.Board:IsSmoke(from) and p:GetPoweredWeapons()[1]==spec.skill
            and not p:IsAbility('Double_Shot') and not p:IsAbility('Post_Move') and not p:IsAbility('Shifty')
            and skill and off(skill.TwoClick) and off(skill.Limited)
        if actor=='combat' then
            supported=supported and skill.Damage==2 and off(skill.Dash) and off(skill.Projectile) and off(skill.Flip)
                and off(skill.Shield) and off(skill.PushBack)
        elseif actor=='cannon' then
            supported=supported and skill.Damage==1 and skill.Push==1 and off(skill.PushBack) and off(skill.BackShot)
                and off(skill.Freeze) and off(skill.Acid) and off(skill.Flip) and off(skill.Fire) and off(skill.Shield)
                and off(skill.Phase) and off(skill.PhaseShield)
        else
            supported=supported and skill.DamageCenter==1 and skill.DamageOuter==0 and skill.Push==1 and skill.BuildingDamage==true
        end
        if not supported then self.preview=nil;self.lines={};self.status='Stock active '..spec.label..' only';return false end
        local targets=skill:GetTargetArea(from);assert(targets:size()<=64,'preview-target-count')
        local legal=false
        for i=1,targets:size() do if same(targets:index(i),to) then legal=true end end
        if not legal then self.preview=nil;self.lines={};self.status='Choose a legal weapon target';return false end
        local expected=o.json.array()
        local function add(p,damage,push)expected[#expected+1]={x=p.x,y=p.y,damage=damage,push=push}end
        if actor=='artillery' then
            add(to,1,env.DIR_NONE)
            for dir=0,3 do local v=env.DIR_VECTORS[dir];add({x=to.x+v.x,y=to.y+v.y},0,dir) end
        else
            assert(from.x==to.x or from.y==to.y,'preview-target-not-aligned')
            local impact=actor=='cannon' and env.GetProjectileEnd(from,env.Point(to.x,to.y),env.PATH_PROJECTILE) or to
            add(impact,actor=='combat' and 2 or 1,env.GetDirection(env.Point(to.x,to.y)-from))
        end
        -- Observe known Lua RNG entry points; never rewind a consumed draw.
        local random,mathRandom=env.random_int,env.math.random;local draws=0
        env.random_int=function(...)draws=draws+1;return random(...)end
        env.math.random=function(...)draws=draws+1;return mathRandom(...)end
        local ok,fx=pcall(function()return skill:GetSkillEffect(from,env.Point(to.x,to.y))end)
        env.random_int,env.math.random=random,mathRandom
        assert(ok,'preview-builder-failed:'..tostring(not ok and fx or ''))
        assert(draws==0,'preview-consumed-rng-no-retry')
        assert(fx.q_effect:empty() and fx.effect:size()<=16,'preview-effect-unsupported')
        local seen={};local count=0
        for i=1,fx.effect:size() do
            local d=fx.effect:index(i)
            -- Wrapped builders add scripts and a zero-damage achievement marker.
            -- Neither is executed or handed to the rendering API.
            if d.iDamage~=0 or d.iPush~=env.DIR_NONE then
                local matched
                for j,want in ipairs(expected) do
                    if not seen[j] and same(d.loc,want) and d.iDamage==want.damage and d.iPush==want.push then matched=j;break end
                end
                assert(matched,'preview-damage-unsupported');seen[matched]=true;count=count+1
            end
        end
        assert(count==#expected,'preview-damage-missing')
        local after=unchanged(witness,ui)
        self.previews=self.previews+1;assert(self.previews<=64,'preview-experiment-limit')
        self.preview={revision=s.revision,witness=witness,damages=expected}
        self.status='Preview only; no action sent'
        local first=expected[1]
        self.lines=o.json.array({spec.label,('Target (%d,%d)'):format(to.x,to.y),'Base damage: '..first.damage,
            actor=='artillery' and 'Four outward pushes' or ('Impact (%d,%d), push %s'):format(first.x,first.y,({'NE','SE','SW','NW'})[first.push+1]),
            'Damage/push marks only','Other effects not predicted','Command rights unchanged'})
        o.emit('inspection_preview',{revision=s.revision,actor=actor,weapon=spec.skill,from=point(from),to=to,
            damages=expected,rngCalls=draws,selectionBefore=ui,selectionAfter=uiState(),before=before,after=after,
            commandSubmitted=false,coverage='three-stock-weapons-damage-push-only'})
        return true
    end
    function self:click(x,y,s)
        if x>=1600 and x<1912 and y>=340 and y<376 then
            if self.enabled or available(s) then self.enabled=not self.enabled;self:clear();o.emit('inspection_mode',{enabled=self.enabled,revision=s.revision}) end
            return true
        end
        if not self.enabled then return false end
        if not available(s) then return true end
        if x>=1600 and x<1912 then
            for i,actor in ipairs({'combat','cannon','artillery'}) do
                local top=680+i*40
                if y>=top and y<top+36 then self:clear('Choose a '..weapons[actor].label..' target');self.selecting=actor;return true end
            end
            if y>=840 and y<876 then self:clear();return true end
        end
        if x<350 or x>1580 or y<150 or y>975 then return true end
        local to=env.screenPointToTile({x=x,y=y},false)
        if not to or to.x<0 or to.y<0 or to.x>7 or to.y>7 then return true end
        to=point(to)
        if self.selecting then self:weapon(s,to,self.selecting) else self:inspect(s,to) end
        return true
    end
    function self:mark(s)
        local p=self.preview
        if not self.enabled or not p or not available(s) or p.revision~=s.revision then return end
        local before,ui
        if not p.marked then local _;_,before=capture();assert(before==p.witness,'preview-stale-before-mark');ui=uiState() end
        -- Fresh safe SpaceDamage, containing no scripts, animation, status or movement.
        for _,d in ipairs(p.damages) do
            local pos=env.Point(d.x,d.y)
            if env.Board:IsValid(pos) then env.Board:MarkSpaceDamage(env.SpaceDamage(pos,d.damage,d.push)) end
        end
        if not p.marked then
            unchanged(before,ui);p.marked=true
            o.emit('inspection_mark_observed',{revision=s.revision,damages=p.damages,observedStateUnchanged=true,selectionUnchanged=true})
        end
    end
    function self:draw(root,visible)
        if not self.controls.mode then
            local function label(key,y)
                local b=env.Ui():pospx(1600,y):widthpx(312):heightpx(36):caption('')
                    :decorate({env.DecoButton(),env.DecoAlign(0,2),env.DecoCaption()}):addTo(root)
                b.onclicked=function()return true end;self.controls[key]=b
            end
            label('mode',340);label('status',380)
            for i=1,7 do label(i,384+i*40) end
            label('combat',720);label('cannon',760);label('artillery',800);label('clear',840)
        end
        for _,b in pairs(self.controls) do b.visible=visible and self.enabled end
        self.controls.mode.visible=visible
        self.controls.mode:caption(self.enabled and 'Return to action choices' or 'Inspect board / teammate')
        self.controls.status:caption(self.allowed and self.status or 'Action running; please wait')
        for i=1,7 do self.controls[i]:caption(self.allowed and (self.lines[i] or '') or '') end
        for _,actor in ipairs({'combat','cannon','artillery'}) do self.controls[actor]:caption('Preview '..weapons[actor].label) end
        self.controls.clear:caption('Clear inspection / preview')
    end
    return self
end
return M
