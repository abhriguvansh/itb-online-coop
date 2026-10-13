-- Two-move interactive experiment. Reads blocked clicks; never forwards them.
local M={}
local actors={combat={id=0,owner='host',label='Combat'},cannon={id=1,owner='guest',label='Cannon'},
    artillery={id=2,owner='guest',label='Artillery'}}
function M.new(o)
    local self={serial=0,counter=0,status='Waiting for both games',controls={}}
    local function reject(reason)
        self.draft=nil;self.status=tostring(reason)
        o.emit('move_intent_rejected',{reason=self.status,peer=o.wire.peer})
    end
    function self:click(x,y,s)
        if not o.wire.inputReady or s.stopped then return end
        if x>=8 and x<298 then
            local actor=y>=380 and y<416 and 'combat' or y>=420 and y<456 and 'cannon'
                or y>=460 and y<496 and 'artillery'
            if actor then
                self.actor=nil;self.draft=nil
                if actors[actor].owner~=o.wire.peer then reject('That mech belongs to your teammate');return end
                self.actor=actor;self.status='Click a supported destination on the board'
                o.emit('move_intent_selected',{actor=actor,peer=o.wire.peer});return
            end
            if y>=640 and y<676 then self.actor=nil;self.draft=nil;self.status='Move canceled; choose a mech';return end
            if y>=600 and y<636 then
                if not self.draft then reject('Choose a mech and destination first');return end
                local ok,reason=s:previewMove(o.wire.peer,self.draft)
                if not ok then reject(reason);return end
                o.wire:propose(self.draft)
                o.emit('move_intent_submitted',{request=self.draft,peer=o.wire.peer})
                self.actor=nil;self.draft=nil;self.status='Move sent; waiting for both games';return
            end
        end
        if not self.actor then reject('Choose your mech first');return end
        if x<350 or x>1580 or y<150 or y>975 then reject('Click a board tile');return end
        local to=o.env.screenPointToTile({x=x,y=y},false)
        if not to or to.x<0 or to.x>7 or to.y<0 or to.y>7 then reject('Click a board tile');return end
        local pawn=o.env.Board:GetPawn(actors[self.actor].id)
        if not pawn then reject('Mech unavailable');return end
        local from=pawn:GetSpace();self.counter=self.counter+1
        assert(self.counter<=999,'intent-limit')
        local r=o.request('move','move-'..o.wire.peer..'-'..self.counter,self.actor,from.x,from.y,to.x,to.y)
        local ok,reason=s:previewMove(o.wire.peer,r)
        if not ok then reject(reason);return end
        self.draft=r;self.status=actors[self.actor].label..' to ('..to.x..','..to.y..') - Confirm move'
        o.emit('move_intent_draft',{request=r,peer=o.wire.peer})
    end
    function self:update(s,done)
        local n=o.native.info()
        assert(type(n.intentSerial)=='number','intent-capable-native-bridge-required')
        if self.revision~=s.revision then
            self.revision=s.revision;self.actor=nil;self.draft=nil;self.status='Choose your mech, then a board tile'
        end
        if n.intentSerial~=self.serial then
            local contiguous=n.intentSerial==self.serial+1;self.serial=n.intentSerial
            if contiguous and not done and n.guardActive and n.sessionState==1 and not n.armed and not n.pressed then
                self:click(n.intentX,n.intentY,s)
            elseif not contiguous then reject('Multiple clicks; choose again') end
        end
        if done or s.stopped then self.status='Experiment ended - Escape exits'
        elseif not o.wire.inputReady then self.status='Waiting for the other game / move completion' end
        return self.status
    end
    function self:draw(root,visible)
        if not self.controls.title then
            local function label(key,y,text)
                self.controls[key]=o.env.Ui():pospx(8,y):widthpx(290):heightpx(36):caption(text)
                    :decorate({o.env.DecoButton(),o.env.DecoAlign(0,2),o.env.DecoCaption()}):addTo(root)
                self.controls[key].onclicked=function() return true end
            end
            label('title',340,'Co-op movement: '..o.wire.peer)
            for i,actor in ipairs({'combat','cannon','artillery'}) do
                label(actor,340+i*40,actors[actor].label..' ('..actors[actor].owner..')')
            end
            label('status',540,self.status);label('confirm',600,'Confirm move');label('cancel',640,'Cancel selection')
        end
        for _,control in pairs(self.controls) do control.visible=visible end
        self.controls.status:caption(self.status)
    end
    return self
end
return M
