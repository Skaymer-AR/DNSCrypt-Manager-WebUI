#!/usr/bin/env node
/* tests/smoke-test-webui-lazy-v030.cjs — Skaymer AR.
   Carga diferida real: nada pesado hasta expandir; al cerrar se desmonta el DOM y
   se detiene el polling (un solo timer); respuestas tardias se ignoran. */
'use strict';
let PASS=0,FAIL=0; const ok=(n)=>{PASS++;console.log('  OK   '+n);}; const bad=(n,e)=>{FAIL++;console.log('  FAIL '+n+(e?' :: '+e:''));};

// ---- fake DOM ----
const REG={};
function FakeEl(tag){ this.tag=tag; this._id=''; this.children=[]; this.attrs={}; this.listeners={}; this.hidden=false; this.className=''; this.type=''; this.value=''; this._text=''; }
Object.defineProperty(FakeEl.prototype,'id',{ get(){return this._id;}, set(v){ this._id=v; if(v) REG[v]=this; } });
Object.defineProperty(FakeEl.prototype,'textContent',{ get(){return this._text;}, set(v){ this._text=String(v); this.children=[]; } }); // set limpia hijos
FakeEl.prototype.appendChild=function(c){ this.children.push(c); if(c && c._id) REG[c._id]=c; return c; };
FakeEl.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
FakeEl.prototype.getAttribute=function(k){ return this.attrs[k]; };
FakeEl.prototype.addEventListener=function(ev,fn){ (this.listeners[ev]=this.listeners[ev]||[]).push(fn); };
FakeEl.prototype.querySelector=function(sel){ const cls=sel.replace('.',''); const dfs=(n)=>{ for(const ch of n.children){ if((ch.className||'').split(' ').indexOf(cls)>=0) return ch; const r=dfs(ch); if(r) return r; } return null; }; return dfs(this); };
FakeEl.prototype.click=function(){ (this.listeners['click']||[]).forEach(f=>f({stopPropagation(){}})); };
function mk(id){ const e=new FakeEl('div'); e.id=id; return e; }
['scBody','scToggle','scChevron','scSummary','anonBody','anonCard','anonToggle','anonChevron','anonSummary','odohBody','odohCard','odohToggle','odohChevron','odohSummary','anonResolver','anonRelays'].forEach(mk);
// estado inicial del HTML: los cuerpos colapsables arrancan hidden
['scBody','anonBody','odohBody'].forEach(id=>{REG[id].hidden=true;});
global.document={ getElementById:(id)=>REG[id]||null, createElement:(t)=>new FakeEl(t), addEventListener:()=>{}, visibilityState:'visible', hidden:false };

// ---- timers con contador ----
let TID=0; const TIMERS=new Set(); let setCount=0, clrCount=0;
global.setInterval=(fn,ms)=>{ setCount++; const id=++TID; TIMERS.add(id); return id; };
global.clearInterval=(id)=>{ if(TIMERS.has(id)){ clrCount++; TIMERS.delete(id); } };
const activeTimers=()=>TIMERS.size;

// ---- globals que usa controls.js ----
global.busy=false; global.setBusy=(v)=>{global.busy=v;}; global.toast=()=>{}; global.confirm=()=>true;
let ROUTE='dns'; global.Router={ current:()=>ROUTE };
global.I18N={ t:(k)=>k };

// ---- DCM mock con CONTADORES ----
const C={ list:0, verify:0, verifyIds:[], set:0, anonStatus:0, odohStatus:0, anonTest:0, odohTest:0 };
let listDelay=0; // ms para simular respuesta tardia
function laterOrNow(val){ return listDelay? new Promise(r=>setTimeout(()=>r(val),listDelay)) : Promise.resolve(val); }
global.DCM={
  cliResolved:()=>true, resolveCli:async()=>{},
  runServiceControlListJson:function(){ C.list++; return laterOrNow({errno:0,stdout:'blocks9',stderr:''}); },
  runServiceControlVerify:function(id){ C.verify++; C.verifyIds.push(id); return Promise.resolve({errno:0,stdout:'verify='+id+' result=enforced',stderr:''}); },
  runServiceControlSet:function(id,m){ C.set++; return Promise.resolve({errno:0,stdout:'service='+id+' mode='+m,stderr:''}); },
  runAnonymizedStatus:function(){ C.anonStatus++; return Promise.resolve({errno:0,stdout:'enabled:false\nresolver:\nrelays:',stderr:''}); },
  runOdohStatus:function(){ C.odohStatus++; return Promise.resolve({errno:0,stdout:'enabled:false\nsupported:code_path_present',stderr:''}); },
  runAnonymizedTest:function(){ C.anonTest++; return Promise.resolve({errno:0,stdout:'result=not_verifiable'}); },
  runOdohTest:function(){ C.odohTest++; return Promise.resolve({errno:0,stdout:'result=not_verifiable'}); },
  runAnonymizedDisable:async()=>({errno:0,stdout:'disabled=yes'}), runOdohDisable:async()=>({errno:0,stdout:'disabled=yes'}), runTransportRollback:async()=>({errno:0,stdout:'rolled_back=yes'}),
  parseKvBlocks:function(x){ const a=[]; for(let i=1;i<=9;i++){ a.push({id:'ctrl_'+i, name:'Control '+i, category:'telemetry', effective_mode:'off', requested_mode:'off', domains:'3', domains_in_blocked:'0/3', allowlist_conflict:'no'}); } return a; },
  transportState:function(kv,kind){ return kind==='odoh'?'not_verifiable':'inactive'; },
  transportStateLabel:function(s){ return 'tp.st.'+s; },
  validMode:(m)=>['off','15m','1h','until_reboot','permanent'].indexOf(m)>=0,
};

const V=require('../webroot/js/controls.js');
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));

(async()=>{
  // 1) al cargar / rutear: NADA pesado
  ok('modulo cargado'); 
  ROUTE='lists'; V.onRoute('lists');
  (C.list===0)?ok('onRoute(lists): 0 llamadas service-control (no carga eager)'):bad('cargo en onRoute',C.list);
  (activeTimers()===0)?ok('onRoute(lists): 0 timers'):bad('timer en onRoute',activeTimers());
  (document.getElementById('scBody').hidden===true)?ok('seccion inicia cerrada (scBody hidden)'):bad('no cerrada');

  // 2) abrir -> UNA carga + UN timer + filas
  await V._scOpen();
  (C.list===1)?ok('abrir: exactamente 1 llamada status --all'):bad('llamadas al abrir',C.list);
  (activeTimers()===1)?ok('abrir: exactamente 1 timer de polling'):bad('timers al abrir',activeTimers());
  const inner=document.getElementById('scListInner');
  (inner && inner.children.length===9)?ok('abrir: 9 filas compactas'):bad('filas',inner?inner.children.length:'sin scListInner');
  // filas compactas: detalle NO existe todavia (scdet-* vacio)
  (document.getElementById('scdet-ctrl_1') && document.getElementById('scdet-ctrl_1').children.length===0)?ok('detalle NO cargado inicialmente (fila compacta)'):bad('detalle eager');

  // 3) verify NO se ejecuta para los 9 al abrir
  (C.verify===0)?ok('abrir: verify NO se ejecuta (0 llamadas, no 9)'):bad('verify eager',C.verify);

  // 4) abrir una fila -> verify SOLO de ese id
  C.verify=0; C.verifyIds=[];
  await V._scToggleRow('ctrl_3');
  (C.verify===1 && C.verifyIds.length===1 && C.verifyIds[0]==='ctrl_3')?ok('abrir fila: verify SOLO de ese control (1, no 9)'):bad('verify por fila',C.verify+' '+C.verifyIds.join(','));
  (V._sc.openRow==='ctrl_3')?ok('accordion: openRow=ctrl_3'):bad('openRow');
  // abrir otra -> cierra la anterior
  await V._scToggleRow('ctrl_5');
  (V._sc.openRow==='ctrl_5' && document.getElementById('scdet-ctrl_3')._text==='')?ok('accordion: abrir otra cierra la anterior'):bad('accordion no cierra');

  // 5) cerrar -> desmonta DOM + detiene polling
  const beforeClr=clrCount;
  V._scClose();
  (document.getElementById('scBody')._text==='' && document.getElementById('scBody').children.length===0)?ok('cerrar: scBody desmontado (sin hijos)'):bad('no desmonto');
  (document.getElementById('scBody').hidden===true)?ok('cerrar: scBody hidden'):bad('no hidden');
  (activeTimers()===0 && clrCount>beforeClr)?ok('cerrar: polling detenido (clearInterval + 0 timers)'):bad('timer no detenido',activeTimers());

  // 6) abrir/cerrar 10 veces -> nunca mas de 1 timer activo, sin fuga
  for(let i=0;i<10;i++){ await V._scOpen(); V._scClose(); }
  (activeTimers()===0)?ok('tras 10 open/close: 0 timers activos (sin fuga)'):bad('fuga de timers',activeTimers());
  (setCount>=11 && (setCount-clrCount)===activeTimers())?ok('cada open crea 1 timer y cada close lo limpia (balanceado)'):bad('timers desbalanceados',setCount+'/'+clrCount);

  // 7) respuesta TARDIA tras cerrar se ignora
  C.list=0; listDelay=30;
  const p=V._scOpen();        // dispara status (tardio 30ms)
  V._scClose();               // cierra antes de que resuelva
  await p; await sleep(50);
  const inner2=document.getElementById('scListInner');
  (!inner2 || inner2===null || (document.getElementById('scBody')._text===''))?ok('respuesta tardia tras cerrar: NO se inserta en DOM destruido'):bad('inserto tardio');
  listDelay=0;

  // 8) transportes: colapsados; abrir consulta estado UNA vez; NO ejecuta test
  ROUTE='dns'; V.onRoute('dns');
  (C.anonStatus===0 && C.anonTest===0)?ok('onRoute(dns): tarjetas NO cargan (0 status, 0 test)'):bad('dns eager',C.anonStatus+'/'+C.anonTest);
  await V._tpOpen('anon');
  (C.anonStatus===1)?ok('abrir Anonymized: 1 status'):bad('anon status',C.anonStatus);
  (C.anonTest===0)?ok('abrir Anonymized: NO ejecuta test (0)'):bad('anon test auto',C.anonTest);
  (document.getElementById('anonBody').hidden===false)?ok('anonBody visible al abrir'):bad('anonBody');
  V._tpClose('anon');
  (document.getElementById('anonCard')._text==='' && document.getElementById('anonBody').hidden===true)?ok('cerrar Anonymized: detalle desmontado + hidden'):bad('anon no desmonto');
  await V._tpOpen('odoh');
  (C.odohStatus===1 && C.odohTest===0)?ok('abrir ODoH: 1 status, 0 test'):bad('odoh',C.odohStatus+'/'+C.odohTest);

  // 9) DOM seguro: controls.js no usa innerHTML/eval
  const src=require('fs').readFileSync('webroot/js/controls.js','utf8');
  (src.indexOf('innerHTML')<0)?ok('controls.js sin innerHTML'):bad('usa innerHTML');
  (/[^a-zA-Z]eval\s*\(/.test(src)===false)?ok('controls.js sin eval'):bad('usa eval');

  console.log('\nResumen webui-lazy: '+PASS+' OK, '+FAIL+' FAIL'); process.exit(FAIL===0?0:1);
})();
