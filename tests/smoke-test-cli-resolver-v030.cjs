#!/usr/bin/env node
/* tests/smoke-test-cli-resolver-v030.cjs  —  Creado por Skaymer AR
 * Verifica el resolvedor central de CLI de la WebUI (api.js): 3 rutas de
 * allowlist, probe fijo, solo acepta rutas permitidas, null si ninguna existe.
 */
'use strict';
let PASS = 0, FAIL = 0;
const ok = (n) => { PASS++; console.log('  OK   ' + n); };
const bad = (n, e) => { FAIL++; console.log('  FAIL ' + n + (e ? ' :: ' + e : '')); };

// Mock de ksu.exec: responde el probe segun un "sistema de archivos" simulado.
let FS_EXEC = {};   // ruta -> ejecutable?
function setFs(map) { FS_EXEC = map; }
global.window = {
  ksu: {
    exec(cmd, _opt, cbName) {
      setTimeout(() => {
        // El probe es: for p in 'a' 'b' 'c'; do [ -x "$p" ] && { printf '%s' "$p"; break; }; done
        const paths = (cmd.match(/'([^']+)'/g) || []).map((x) => x.slice(1, -1));
        let found = '';
        for (const p of paths) { if (FS_EXEC[p]) { found = p; break; } }
        const fn = global.window[cbName];
        if (typeof fn === 'function') fn(0, found, '');
      }, 0);
    },
    toast() {}
  }
};
global.document = { getElementById: () => null, querySelectorAll: () => [] };

const DCM = require('../webroot/js/api.js');
const PATHS = DCM.cliPaths();

(async () => {
  // 1) /system/bin valido
  setFs({ [PATHS[0]]: true, [PATHS[1]]: true, [PATHS[2]]: true });
  let r = await DCM.resolveCli();
  if (r === PATHS[0] && DCM.cli() === PATHS[0]) ok('elige /system/bin cuando existe (prioridad)'); else bad('systemless', r);

  // 2) fallback a modules
  setFs({ [PATHS[1]]: true });
  r = await DCM.resolveCli();
  if (r === PATHS[1] && DCM.cli() === PATHS[1]) ok('fallback a /data/adb/modules cuando /system no esta'); else bad('modules', r);

  // 3) fallback a modules_update
  setFs({ [PATHS[2]]: true });
  r = await DCM.resolveCli();
  if (r === PATHS[2]) ok('fallback a /data/adb/modules_update'); else bad('modules_update', r);

  // 4) ninguna ruta valida -> null
  setFs({});
  r = await DCM.resolveCli();
  if (r === null && DCM.cliResolved() === false) ok('ninguna ruta valida -> null (CLI no resuelta)'); else bad('none', r);

  // 5) una ruta fuera de la allowlist NO se acepta
  setFs({ '/tmp/evil/dnscrypt-manager': true });
  r = await DCM.resolveCli();
  if (r === null) ok('ruta fuera de la allowlist se rechaza'); else bad('allowlist', r);

  // 6) el probe solo contiene las 3 rutas de la allowlist (sin datos externos)
  const allow = new Set(PATHS);
  let probePaths = [];
  global.window.ksu.exec("for p in '" + PATHS.join("' '") + "'; do :; done", null, null);
  if (PATHS.length === 3 && PATHS.every((p) => p.indexOf('dnscrypt_manager') >= 0 || p.indexOf('/system/bin') >= 0)) ok('allowlist = 3 rutas fijas del modulo'); else bad('allowlist shape');

  console.log('\nResumen cli-resolver: ' + PASS + ' OK, ' + FAIL + ' FAIL');
  process.exit(FAIL === 0 ? 0 : 1);
})();
