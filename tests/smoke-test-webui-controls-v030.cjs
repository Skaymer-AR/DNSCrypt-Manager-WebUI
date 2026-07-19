#!/usr/bin/env node
/* tests/smoke-test-webui-controls-v030.cjs — Skaymer AR.
   service-control / Anonymized / ODoH en la WebUI: comandos, estados honestos,
   validación, uso de la CLI resuelta, seguridad DOM. */
'use strict';
let PASS=0,FAIL=0; const ok=(n)=>{PASS++;console.log('  OK   '+n);}; const bad=(n,e)=>{FAIL++;console.log('  FAIL '+n+(e?' :: '+e:''));};

// Mock ksu: callback por NOMBRE (global.window[cbName]), como el runtime real.
let LAST=[];
let FS={ '/system/bin/dnscrypt-manager':false,
  '/data/adb/modules/dnscrypt_manager/system/bin/dnscrypt-manager':true,
  '/data/adb/modules_update/dnscrypt_manager/system/bin/dnscrypt-manager':false };
global.window={ ksu:{ exec:(cmd,_opt,cbName)=>{ LAST.push(cmd);
  setTimeout(()=>{ let out='';
    if(/for p in '/.test(cmd)){ const paths=(cmd.match(/'([^']+)'/g)||[]).map(x=>x.slice(1,-1)); for(const p of paths){ if(FS[p]){out=p;break;} } }
    else if(cmd.indexOf('service-control status --all')>=0) out="=== spotify_telemetry ===\nid=spotify_telemetry\nname=Spotify\nrequested_mode=1h\neffective_mode=1h\nstate=active\ndomains=3\ndomains_in_blocked=3/3\nallowlist_conflict=no\n";
    const fn=global.window[cbName]; if(typeof fn==='function') fn(0,out,'');
  },0);
}, toast:()=>{} } };
global.document={getElementById:()=>null,querySelectorAll:()=>[],addEventListener:()=>{}};
const D=require('../webroot/js/api.js');

(async()=>{
  // 1) nunca usa el comando heredado 'service ' (con espacio); usa 'service-control'
  LAST=[]; await D.runServiceControlListJson();
  const cmd=LAST[LAST.length-1]||'';
  cmd.indexOf('service-control status --all')>=0 ? ok("list usa 'service-control status --all'") : bad("list cmd",cmd);
  /(^|[^-])\bservice\s(?!-)/.test(cmd) ? bad("usa el comando heredado 'service'") : ok("NO usa el comando heredado 'service'");

  // 2) usa la CLI RESUELTA (no la ruta por defecto congelada)
  await D.resolveCli();
  LAST=[]; await D.runServiceControlStatus('spotify_telemetry');
  const c2=LAST[LAST.length-1]||'';
  c2.indexOf('/data/adb/modules/dnscrypt_manager/system/bin/dnscrypt-manager')>=0 ? ok("usa la CLI resuelta (ruta del módulo KSU)") : bad("no usa CLI resuelta",c2);

  // 3) validación estricta: id/modo/stamp inválidos NO ejecutan
  LAST=[]; const r=await D.runServiceControlSet('evil;rm','1h'); (r&&r.errno===-1)?ok("id inválido rechazado sin ejecutar"):bad("id");
  LAST.length===0 ? ok("id inválido no llamó a ksu.exec") : bad("ejecutó pese a id malo");
  const r2=await D.runServiceControlSet('spotify_telemetry','2d'); (r2&&r2.errno===-1)?ok("modo inválido rechazado"):bad("modo");
  const r3=await D.runOdohApply('notastamp',''); (r3&&r3.errno===-1)?ok("stamp ODoH inválido rechazado"):bad("stamp");
  const r4=await D.runAnonymizedTest('bad;res','anon-cs-fr'); (r4&&r4.errno===-1)?ok("resolver inválido rechazado"):bad("resolver");

  // 4) modos válidos
  ['off','15m','1h','until_reboot','permanent'].every(m=>D.validMode(m)) ? ok("acepta los 5 modos válidos") : bad("modos");

  // 5) estados honestos de transporte
  D.transportState({enabled:'true',resolver:'cloudflare'},'anon')==='configured' ? ok("flag+resolver sin evidencia -> configured (NUNCA active)") : bad("estado flag");
  D.transportState({last_test:'ok',verified:'yes'},'anon')==='active' ? ok("evidencia real (test ok + verified) -> active") : bad("estado active");
  D.transportState({last_test:'not_verifiable'},'anon')==='not_verifiable' ? ok("not_verifiable no es active") : bad("nv");
  D.transportState({supported:'no'},'odoh')==='unsupported' ? ok("ODoH sin soporte -> unsupported") : bad("unsup");
  D.transportState({},'anon')==='inactive' ? ok("sin datos -> inactive") : bad("inactive");

  // 6) parseKvBlocks (status --all)
  const blk=D.parseKvBlocks("=== a ===\nstate=active\n\n=== b ===\nstate=off\n");
  (blk.length===2 && blk[0].id==='a' && blk[0].state==='active') ? ok("parseKvBlocks separa por control") : bad("blocks");

  // 7) DOM safety: el api.js no usa innerHTML/eval/Function
  const fs=require('fs'); const src=fs.readFileSync(require('path').join(__dirname,'../webroot/js/api.js'),'utf8');
  /\binnerHTML\b/.test(src) ? bad("api.js usa innerHTML") : ok("api.js sin innerHTML");
  /\beval\s*\(|new Function\s*\(/.test(src) ? bad("api.js usa eval/Function") : ok("api.js sin eval/Function");
  const app=fs.readFileSync(require('path').join(__dirname,'../webroot/js/app.js'),'utf8');
  // los renderers v0.3 no deben usar innerHTML
  /V030[\s\S]*innerHTML/.test(app) ? bad("renderers v0.3 usan innerHTML") : ok("renderers v0.3 sin innerHTML (createElement/textContent)");

  console.log('\nResumen webui-controls: '+PASS+' OK, '+FAIL+' FAIL'); process.exit(FAIL===0?0:1);
})();
