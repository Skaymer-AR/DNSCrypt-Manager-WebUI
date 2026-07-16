#!/usr/bin/env node
/* tests/smoke-test-webui-args.cjs  —  Creado por Skaymer AR
 * Auditoria de seguridad de argumentos de webroot/js/api.js (RC2).
 */
'use strict';
const fs = require('fs');
const path = require('path');

let lastCmd = null;
const mockWindow = {
  ksu: {
    exec: (cmd, _opts, cbName) => {
      lastCmd = cmd;
      const cb = mockWindow[cbName];
      if (typeof cb === 'function') cb(0, 'stdout', '');
    },
    toast: () => {}
  }
};

const src = fs.readFileSync(path.join(__dirname, '..', 'webroot', 'js', 'api.js'), 'utf8');
const factory = new Function('window', 'setTimeout', 'clearTimeout', 'JSON', 'Date', src + '\n; return DCM;');
const DCM = factory(mockWindow, setTimeout, clearTimeout, JSON, Date);

let pass = 0, fail = 0;
function ok(name) { pass++; console.log('  OK   ' + name); }
function bad(name, extra) { fail++; console.log('  FAIL ' + name + (extra ? ' :: ' + extra : '')); }

async function rej(name, thunk) {
  lastCmd = null;
  const r = await thunk();
  if (r.errno === -1 && /inval/i.test(r.stderr) && lastCmd === null) ok(name);
  else bad(name, 'errno=' + r.errno + ' stderr=' + JSON.stringify(r.stderr) + ' cmd=' + JSON.stringify(lastCmd));
}
async function acc(name, thunk, mustContain) {
  lastCmd = null;
  await thunk();
  if (lastCmd && lastCmd.indexOf(mustContain) >= 0) ok(name);
  else bad(name, 'cmd=' + JSON.stringify(lastCmd) + ' esperado incluir ' + JSON.stringify(mustContain));
}
function noUnquotedMeta(cmd) {
  const stripped = cmd.replace(/'[^']*'/g, '');
  return !/[;&`$()<>|\n]/.test(stripped);
}

(async () => {
  console.log('== IDs de fuente maliciosos ==');
  await rej('semicolon id', () => DCM.runCatalogEnable('; id'));
  await rej('dollar-paren id', () => DCM.runCatalogEnable('$(id)'));
  await rej('backtick id', () => DCM.runCatalogEnable('`id`'));
  await rej('newline id', () => DCM.runCatalogEnable('a\nb'));
  await rej('quote id', () => DCM.runCatalogEnable("a'b"));
  await rej('help flag id', () => DCM.runCatalogEnable('--help'));
  await rej('id muy largo', () => DCM.runCatalogEnable('a'.repeat(65)));
  await rej('id vacio', () => DCM.runCatalogEnable(''));
  await rej('mayusculas', () => DCM.runCatalogEnable('BadID'));

  console.log('== ID valido (comillado) ==');
  await acc('id valido', () => DCM.runCatalogEnable('hagezi_multi_pro'), "catalog enable 'hagezi_multi_pro'");
  await acc('custom guion', () => DCM.runCatalogEnable('custom_mi-lista'), "'custom_mi-lista'");

  console.log('== URLs maliciosas ==');
  await rej('javascript', () => DCM.runCustomAdd('javascript:alert(1)'));
  await rej('http no https', () => DCM.runCustomAdd('http://x.com/l.txt'));
  await rej('url dollar-paren', () => DCM.runCustomAdd('https://x.com/$(id)'));
  await rej('url semicolon', () => DCM.runCustomAdd('https://x.com/;id'));
  await rej('url quote', () => DCM.runCustomAdd("https://x.com/'a"));
  await rej('url espacio', () => DCM.runCustomAdd('https://x.com/ a'));
  await rej('url backtick', () => DCM.runCustomAdd('https://x.com/`id`'));
  await rej('file no test', () => DCM.runCustomAdd('file:///etc/passwd'));

  console.log('== URL valida (comillada) ==');
  await acc('url valida', () => DCM.runCustomAdd('https://ejemplo.net/lista.txt'), "add 'https://ejemplo.net/lista.txt'");
  await acc('url query', () => DCM.runCustomAdd('https://ejemplo.net/l.txt?v=1&x=2'), "'https://ejemplo.net/l.txt?v=1&x=2'");

  console.log('== Rutas maliciosas ==');
  await rej('ruta semicolon', () => DCM.runBindhostsAnalyze('/etc; rm -rf /'));
  await rej('ruta dollar-paren', () => DCM.runBindhostsAnalyze('/etc/$(id)'));
  await rej('ruta dash', () => DCM.runBindhostsAnalyze('-rf'));
  await rej('ruta espacio', () => DCM.runBindhostsAnalyze('/a b'));
  await rej('ruta dotdot', () => DCM.runBindhostsAnalyze('/a/../b'));
  await rej('ruta relativa', () => DCM.runBindhostsAnalyze('relativa/x'));
  await rej('ruta quote', () => DCM.runBindhostsAnalyze("/a'b"));

  console.log('== Ruta valida (comillada) ==');
  await acc('ruta valida', () => DCM.runBindhostsAnalyze('/data/adb/bindhosts'), "import-bindhosts '/data/adb/bindhosts' --dry-run");

  console.log('== Modos de servicio ==');
  await rej('modo invalido', () => DCM.runServiceSet('youtube_no_history', 'evil'));
  await rej('modo semicolon', () => DCM.runServiceSet('youtube_no_history', '; id'));
  await rej('svc id malicioso', () => DCM.runServiceSet('$(id)', 'perm'));
  await acc('modo perm', () => DCM.runServiceSet('youtube_no_history', 'perm'), "service set 'youtube_no_history' 'perm'");

  console.log('== Sin metacaracteres sin comillar ==');
  const probes = [
    () => DCM.runCatalogEnable('hagezi_multi_pro'),
    () => DCM.runCustomAdd('https://ejemplo.net/l.txt?v=1&x=2'),
    () => DCM.runBindhostsAnalyze('/data/adb/bindhosts'),
    () => DCM.runServiceSet('youtube_no_history', 'boot')
  ];
  for (const t of probes) { lastCmd = null; await t(); if (lastCmd && noUnquotedMeta(lastCmd)) ok('sin meta ok'); else bad('meta sin comillar', lastCmd); }

  console.log('\nResumen: ' + pass + ' OK, ' + fail + ' FAIL');
  process.exit(fail === 0 ? 0 : 1);
})();
