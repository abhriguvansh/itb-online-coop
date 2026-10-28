// One fresh experimental battle, not campaign persistence or rotation.
const {canonical}=require('./probe-report.cjs');
const actors=['combat','cannon','artillery'];
class PrimarySetup{
 constructor(core){this.c=core;this.generation=0;this.choices={};this.ready={};this.applied={};}
 snapshot(){
  const h=this.choices.host,g=this.choices.guest;
  const valid=h&&g&&h.primary!==g.primary&&h.sharedController===g.sharedController;
  const sharedActor=valid?actors.find(a=>a!==h.primary&&a!==g.primary):null;
  const owners=valid?{[h.primary]:'host',[g.primary]:'guest',[sharedActor]:h.sharedController}:null;
  return {generation:this.generation,choices:this.choices,ready:this.ready,sharedActor,owners};
 }
 frame(kind){const h=this.choices.host,g=this.choices.guest;return {...this.c.frame(kind,'-','primary-'+this.generation),
  witness:[this.generation,h?.primary||'-',h?.sharedController||'-',g?.primary||'-',g?.sharedController||'-',this.ready.host?1:0,this.ready.guest?1:0].join('|')};}
 start(){
  const c=this.c;c.require(c.stage===0&&c.deployment&&c.fullMission&&c.interactive,'primary-setup-mode');
  c.require(c.states.host.witness===c.states.guest.witness,'primary-setup-board-divergence');
  c.mode='primary';c.both(this.frame('SQUAD'));c.record({type:'primary_setup_started'});
 }
 receive(peer,m){
  const c=this.c;c.require(c.mode==='primary'||c.mode==='primary-applying','primary-setup-closed');
  c.context(m,0);c.require(m.witness===c.states[peer].witness,'primary-setup-stale-board');
  c.require(m.native?.guardActive===true&&m.native.sessionState===1&&m.native.releaseFailed===false&&!m.native.armed&&!m.native.pressed,'primary-setup-protection');
  if(m.type==='primary_choice'){
   c.require(c.mode==='primary'&&actors.includes(m.primary)&&['host','guest'].includes(m.sharedController),'primary-choice-invalid');
   const choice={primary:m.primary,sharedController:m.sharedController};
   if(canonical(this.choices[peer]||{})===canonical(choice)){c.send(peer,this.frame('SQUAD'));return;}
   c.require(this.generation<32,'primary-choice-limit');this.choices[peer]=choice;this.generation++;this.ready={};
   c.record({type:'primary_choice',peer,generation:this.generation,...choice});c.both(this.frame('SQUAD'));return;
  }
  if(m.type==='primary_ready'){
   c.require(c.mode==='primary','primary-ready-closed');
   if(m.generation!==this.generation){c.record({type:'primary_ready_stale',peer,generation:m.generation,current:this.generation});c.send(peer,this.frame('SQUAD'));return;}
   c.require(m.confirm===true&&this.snapshot().owners,'primary-ready-conflict');
   if(this.ready[peer])return;
   this.ready[peer]=true;c.record({type:'primary_ready',peer,generation:this.generation});
   if(this.ready.host&&this.ready.guest){c.mode='primary-applying';c.both(this.frame('SQUADLOCK'));}
   else c.both(this.frame('SQUAD'));
   return;
  }
  c.require(m.type==='primary_applied'&&c.mode==='primary-applying'&&m.generation===this.generation&&!this.applied[peer],'primary-applied-context');
  const owners=this.snapshot().owners;c.require(canonical(m.owners)===canonical(owners),'primary-applied-mismatch');
  this.applied[peer]=true;c.record({type:'primary_applied',peer,generation:this.generation,owners});
  if(this.applied.host&&this.applied.guest){
   c.entities=Object.fromEntries(actors.map((a,id)=>[a,{id,peer:owners[a]}]));
   c.record({type:'primary_assignments_locked',generation:this.generation,owners,sharedActor:this.snapshot().sharedActor,scope:'one-fresh-battle-no-rotation'});
   c.advance();
  }
 }
}
module.exports={PrimarySetup};
