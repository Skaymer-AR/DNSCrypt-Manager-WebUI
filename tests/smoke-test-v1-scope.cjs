#!/usr/bin/env node
/* tests/smoke-test-v1-scope.cjs — Skaymer AR.
   Alcance de v1.0.0: sin advertencia BindHosts, sin Anonymized/ODoH en la UI,
   sin tarjeta heredada de controles de servicio, version estable, eventos lazy. */
'use strict';
const fs=require('fs'), vm=require('vm');
let PASS=0,FAIL=0; const ok=(n)=>{PASS++;console.log('  OK   '+n);}; const bad=(n,e)=>{FAIL++;console.log('  FAIL '+n+(e?' :: '+e:''));};
const R=(p)=>fs.readFileSync(p,'utf8');
const html=R('webroot/index.html'), en=JSON.parse(R('webroot/i18n/en.json')), es=JSON.parse(R('webroot/i18n/es.json'));
const app=R('webroot/js/app.js'), ctrls=R('webroot/js/controls.js'), cust=R('customize.sh'), cli=R('system/bin/dnscrypt-manager'), prop=R('module.prop');

console.log('== 1) BindHosts: sin advertencia de incompatibilidad ==');
/bootloop/i.test(html)?bad('HTML menciona bootloop'):ok('HTML sin advertencia de bootloop');
(html.indexOf('warnBindhosts')<0)?ok('HTML sin banner warnBindhosts'):bad('banner presente');
const i18nTxt=JSON.stringify(en)+JSON.stringify(es);
(/bootloop/i.test(i18nTxt)===false)?ok('i18n EN/ES sin texto de bootloop'):bad('i18n con bootloop');
(Object.keys(en).filter(k=>k.startsWith('bindhosts.warning')||k==='bindhosts.detected').length===0)?ok('i18n sin claves bindhosts.warning/detected'):bad('claves de advertencia presentes');
(/bootloop/i.test(cust)===false && /debe permanecer DESACTIVADO/i.test(cust)===false)?ok('customize.sh sin exigir desactivar BindHosts'):bad('instalador con advertencia');
(/desactivalo, reinicia el dispositivo/i.test(cli)===false)?ok('CLI environment sin exigir desactivar BindHosts'):bad('CLI con advertencia');
(cli.indexOf('Convivencia confirmada por el usuario')>=0)?ok('CLI documenta convivencia probada por el usuario'):bad('sin nota de convivencia');
(en['lists.bindhosts'] && html.indexOf('import-bindhosts')>=0||html.indexOf('bhDir')>=0)?ok('importador de listas BindHosts CONSERVADO'):bad('se perdio el importador');

console.log('== 2) Anonymized DNSCrypt / ODoH fuera de la UI ==');
['anonToggle','odohToggle','anonCard','odohCard','anonResolver','anonRelays'].forEach(id=>{
  html.indexOf(id)<0 ? ok('HTML sin #'+id) : bad('HTML aun tiene '+id); });
(/ODoH|Anonymized/i.test(html)===false)?ok('HTML sin textos Anonymized/ODoH'):bad('HTML menciona Anonymized/ODoH');
(Object.keys(en).filter(k=>k.startsWith('tp.')).length===0 && Object.keys(es).filter(k=>k.startsWith('tp.')).length===0)?ok('i18n sin claves tp.* (transportes)'):bad('claves tp.* presentes');
(ctrls.indexOf('tpOpen')<0 && ctrls.indexOf('runOdohStatus')<0)?ok('controls.js sin codigo de transportes'):bad('controls.js aun tiene transportes');

console.log('== 3) sin tarjeta heredada de controles de servicio ==');
(html.indexOf('svcList')<0)?ok('HTML sin #svcList (tarjeta vacia eliminada)'):bad('svcList presente');
(/async function svcRender/.test(app)===false)?ok('app.js sin svcRender heredado'):bad('svcRender presente');
(en['lists.services']===undefined)?ok('i18n sin clave lists.services'):bad('clave heredada presente');
(html.indexOf('scToggle')>=0)?ok('"Privacidad por servicio" (service-control real) conservada'):bad('falta la seccion real');

console.log('== 4) version estable ==');
(/^version=v1\.0\.0$/m.test(prop))?ok('module.prop version=v1.0.0'):bad('version',prop.match(/version=.*/));
(/^versionCode=10000$/m.test(prop))?ok('module.prop versionCode=10000'):bad('versionCode');
(en['app.testing']===undefined && html.indexOf('testingBar')<0)?ok('sin texto "esta version continua en pruebas"'):bad('texto de pruebas presente');
(/EN PRUEBAS|primera version estable sera/i.test(cust)===false)?ok('instalador sin leyenda de pruebas'):bad('instalador con leyenda');

console.log('== 5) eventos: lazy y colapsables ==');
(html.indexOf('evToggle')>=0 && /id="evBody"[^>]*hidden/.test(html))?ok('panel Eventos existe y arranca cerrado (hidden)'):bad('panel no colapsado');
(/await refreshEvents\(\);\s*\n\}/.test(app)===false)?ok('init NO llama refreshEvents (0 consultas al arrancar)'):bad('init carga eventos');
(app.indexOf('if (!EV.open) return;')>=0)?ok('refreshEvents no consulta con el panel cerrado'):bad('sin guarda de cerrado');
(app.indexOf('myGen !== EV.gen')>=0)?ok('token de generacion: respuesta tardia ignorada'):bad('sin token');
(/EV\s*=\s*\{[^}]*page:\s*20/.test(app))?ok('pagina inicial de 20 eventos'):bad('sin limite 20');
(app.indexOf("I18N.t('ev.more')")>=0)?ok('boton "Cargar mas" para paginar'):bad('sin paginacion');

console.log('== 6) eventos: comportamiento real (contadores) ==');
(function(){
  const REG={}; let calls=0; let resolveLate=null;
  function E(tag){ this.tag=tag; this._id=''; this.children=[]; this.attrs={}; this.hidden=false; this._t=''; this.value=''; this.className=''; }
  Object.defineProperty(E.prototype,'id',{get(){return this._id;},set(v){this._id=v; if(v) REG[v]=this;}});
  Object.defineProperty(E.prototype,'textContent',{get(){return this._t;},set(v){this._t=String(v); this.children=[];}});
  E.prototype.appendChild=function(c){this.children.push(c); if(c._id)REG[c._id]=c; return c;};
  E.prototype.setAttribute=function(k,v){this.attrs[k]=String(v);};
  E.prototype.getAttribute=function(k){return this.attrs[k];};
  E.prototype.addEventListener=function(){};
  ['evBody','evToggle','evChevron','evSummary','eventsList','eventsMore','eventsStats','eventsFilter'].forEach(id=>{const e=new E('div'); e.id=id; REG[id]=e;});
  REG.evBody.hidden=true;
  const evs=[]; for(let i=0;i<57;i++) evs.push({time:'t'+i,domain:'d'+i+'.com',category:'ads',rule:'r'});
  const sandbox={
    document:{getElementById:(i)=>REG[i]||null,createElement:(t)=>new E(t),addEventListener:()=>{},querySelectorAll:()=>[],visibilityState:'visible',hidden:false},
    window:{}, navigator:{}, console,
    setTimeout, clearTimeout, setInterval:()=>1, clearInterval:()=>{},
    I18N:{t:(k)=>k}, Router:{current:()=>'activity'},
    DCM:{ run:(what)=>{ if(what==='eventsList'){ calls++; return Promise.resolve({errno:0,stdout:JSON.stringify({events:evs})}); } return Promise.resolve({errno:0,stdout:'{}'}); },
          cliResolved:()=>true, resolveCli:async()=>{} },
  };
  sandbox.globalThis=sandbox;
  vm.createContext(sandbox);
  try { vm.runInContext(app,sandbox,{filename:'app.js'}); } catch(e){ bad('no se pudo cargar app.js en sandbox',e.message); return; }
  const S=sandbox;
  (calls===0)?ok('cargar app.js: 0 consultas de eventos'):bad('consulto al cargar',calls);
  (S.EV && S.EV.open===false)?ok('EV.open=false al inicio'):bad('EV abierto');
  (typeof S.evOpen==='function' && typeof S.evClose==='function')?ok('evOpen/evClose disponibles'):bad('faltan funciones');
  return S.evOpen().then(()=>{
    (calls===1)?ok('abrir: exactamente 1 consulta'):bad('consultas al abrir',calls);
    const list=REG.eventsList;
    (list.children.length===20)?ok('renderiza 20 filas (no 57)'):bad('filas',list.children.length);
    (REG.eventsMore.children.length===1)?ok('muestra boton Cargar mas'):bad('sin boton mas');
    (REG.evBody.hidden===false)?ok('evBody visible al abrir'):bad('body oculto');
    S.evClose();
    (REG.eventsList._t==='' && REG.eventsList.children.length===0)?ok('cerrar: lista desmontada del DOM'):bad('no desmonto');
    (REG.evBody.hidden===true)?ok('cerrar: evBody hidden'):bad('body visible');
    (REG.evToggle.getAttribute('aria-expanded')==='false')?ok('aria-expanded=false al cerrar'):bad('aria');
    const before=calls;
    return S.refreshEvents().then(()=>{
      (calls===before)?ok('cerrado: refreshEvents no consulta'):bad('consulto cerrado');
      // respuesta tardia: abrir y cerrar antes de que resuelva
      const p=S.evOpen(); S.evClose();
      return p.then(()=>{
        (REG.eventsList.children.length===0)?ok('respuesta tardia tras cerrar: no se inserta en el DOM'):bad('inserto tardio');
        console.log('\nResumen v1-scope: '+PASS+' OK, '+FAIL+' FAIL'); process.exit(FAIL===0?0:1);
      });
    });
  });
})();
