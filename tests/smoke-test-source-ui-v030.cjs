#!/usr/bin/env node
/* tests/smoke-test-source-ui-v030.cjs — Skaymer AR. failureClassToState + parseDoctor. */
'use strict';
let PASS=0,FAIL=0; const ok=(n)=>{PASS++;console.log('  OK   '+n);}; const bad=(n,e)=>{FAIL++;console.log('  FAIL '+n+(e?' :: '+e:''));};
global.window={ksu:{exec(){},toast(){}}}; global.document={getElementById:()=>null,querySelectorAll:()=>[]};
const DCM=require('../webroot/js/api.js');
// 1) mapeo failure_class -> estado humano
const map={ok:'actualizada',self_blocked:'autobloqueada',dns_system_failed:'error_dns',dns_proxy_failed:'error_dns',
  http_404:'fuente_rota',http_error:'error_http',connection_failed:'error_http',tls_failed:'error_http',
  redirect_invalid:'validacion_fallida',empty:'validacion_fallida',html_instead_of_list:'validacion_fallida',
  validation_failed:'validacion_fallida',unsupported_format:'validacion_fallida',cancelled:'cancelada',timeout:'timeout'};
let allok=true;
Object.keys(map).forEach((fc)=>{ if(DCM.failureClassToState(fc)!==map[fc]){allok=false; bad('map '+fc,DCM.failureClassToState(fc));}});
if(allok) ok('failureClassToState mapea las 15 clases correctamente');
if(DCM.failureClassToState('cosa_rara')==='sin_lista') ok('clase desconocida -> sin_lista'); else bad('default');
// 2) parseDoctor
const txt='source_id=rc1_phishing_army\nfailure_class=dns_system_failed\nhostname=phishing.army\nhttp_status=\nlast_valid_available=yes\nlast_valid_domains=1234';
const d=DCM.parseDoctor(txt);
d.source_id==='rc1_phishing_army' && d.failure_class==='dns_system_failed' && d.hostname==='phishing.army' ? ok('parseDoctor extrae campos') : bad('parse',JSON.stringify(d));
d.last_valid_domains==='1234' ? ok('parseDoctor conserva last_valid_domains') : bad('lastvalid');
// 3) runSourceDoctor rechaza id invalido sin ejecutar
DCM.runSourceDoctor('evil;rm').then((r)=>{
  (r && r.errno===-1) ? ok('runSourceDoctor rechaza id con metacaracteres') : bad('id meta');
  console.log('\nResumen source-ui: '+PASS+' OK, '+FAIL+' FAIL'); process.exit(FAIL===0?0:1);
});
