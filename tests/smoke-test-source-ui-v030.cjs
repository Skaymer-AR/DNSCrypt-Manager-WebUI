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
// 3) Catalog status keeps last success/cache visible and distinguishes no-cache failures.
const fs=require('fs'), app=fs.readFileSync(require('path').join(__dirname,'../webroot/js/app.js'),'utf8');
app.includes('e.cache_domains') && app.includes('e.last_success') ? ok('catalog UI muestra caché y último éxito') : bad('catalog cache metadata');
app.includes('ERROR · usa caché') && app.includes('ERROR · sin caché') ? ok('catalog UI distingue el error con caché válida del error sin caché') : bad('catalog stale status');
// 4) Catálogo Rethink: 197 feeds con grupos originales y acordeones lazy.
const html=fs.readFileSync(require('path').join(__dirname,'../webroot/index.html'),'utf8');
html.indexOf('id="catSearch"') < html.indexOf('id="catResults"') &&
  html.indexOf('id="catResults"') < html.indexOf('id="scToggle"') &&
  html.includes('Las categorías están a la vista') && html.includes('id="btnCatFilter"')
  ? ok('categorías visibles primero; búsqueda y embudo quedan a mano') : bad('catalog first screen');
html.includes('id="uiModeSimple"') && html.includes('id="uiModeAdvanced"') &&
  html.includes('id="btnCatAll"') && html.includes('id="btnCatSelected"') &&
  html.includes('id="catFilterSheet"') && html.includes('btnCatFilterApply')
  ? ok('selector Simple/Avanzado y hoja de filtros integrados en la WebUI') : bad('catalog filter controls');
app.includes('catFilterGroups') && app.includes('catFilterSubgroups') && app.includes('catFilterPacks') &&
  app.includes('catEntryMatchesFilters') && app.includes('catFacetValues') && app.includes('catLoadAllGroups')
  ? ok('filtros dinámicos por grupo, subgrupo y etiquetas originales, con carga diferida') : bad('catalog filter engine');
html.includes('body[data-ui-mode="simple"] .ui-advanced-only') === false &&
  fs.readFileSync(require('path').join(__dirname,'../webroot/css/style.css'),'utf8').includes('body[data-ui-mode="simple"] .ui-advanced-only')
  ? ok('modo Simple reduce datos técnicos en todas las pestañas') : bad('global simple/advanced mode');
const catalog=JSON.parse(fs.readFileSync(require('path').join(__dirname,'../config/catalog/blocklists.json'),'utf8'));
catalog.source_catalog && catalog.source_catalog.entry_count===197 &&
  catalog.source_catalog.group_counts.Security===44 && catalog.source_catalog.group_counts.Privacy===85 &&
  catalog.source_catalog.group_counts.ParentalControl===67
  ? ok('catálogo fijo conserva las 197 fuentes y grupos reales de Rethink') : bad('rethinks catalog inventory');
const rFeeds=catalog.entries.filter((e)=>e.source_name);
rFeeds.length===197 && rFeeds.filter((e)=>e.license==='LICENSE_UNKNOWN').length===182
  ? ok('feeds sin licencia clara quedan LICENSE_UNKNOWN, sin importar sus datos') : bad('feed license guards');
!html.includes('data-cat-view=') && app.includes('const CAT_GROUP_DEFS') && app.includes('panel.hidden = !expanded') &&
  app.includes('catOpenGroup === group.key') && app.includes("let catOpenGroup = ''")
  ? ok('categorías colapsables; solo el acordeón abierto crea sus filas') : bad('lazy accordion catalog');
app.includes('const catSelection = new Set()') && app.includes('const catDisableSelection = new Set()') &&
  app.includes('catSelection.add(e.id)') && app.includes('DCM.runCatalogEnable(action.id)') &&
  app.includes('DCM.runCatalogDisable(action.id)')
  ? ok('catalog UI permite activar/desactivar fuentes y aplicar cambios solo al confirmar') : bad('catalog staged selection');
app.includes('catalog-group-pick') && app.includes('catToggleGroupSelection') && app.includes('Activar o desactivar todas las listas')
  ? ok('catalog UI tiene checkbox maestro por categoría') : bad('catalog category master checkbox');
app.includes('!e.activation_blocked') && !app.includes('!e.license_blocked') &&
  app.includes("e.upstream_status !== 'broken'") && app.includes("e.upstream_status !== 'archived'")
  ? ok('catalog UI permite el opt-in de licencia desconocida y conserva los bloqueos técnicos') : bad('catalog availability policy');
app.includes('source_group') && app.includes('source_packs') && app.includes('source_formats')
  ? ok('catalog UI conserva grupo, etiquetas y formato originales de cada feed') : bad('catalog source provenance');
// 5) runSourceDoctor rechaza id invalido sin ejecutar
DCM.runSourceDoctor('evil;rm').then((r)=>{
  (r && r.errno===-1) ? ok('runSourceDoctor rechaza id con metacaracteres') : bad('id meta');
  console.log('\nResumen source-ui: '+PASS+' OK, '+FAIL+' FAIL'); process.exit(FAIL===0?0:1);
});
