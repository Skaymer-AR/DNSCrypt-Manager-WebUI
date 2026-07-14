// ARCHIVO DE PRUEBA — NO ES PARTE DEL PRODUCTO — NO INCLUIR EN EL MODULO
//
// tests/fixtures/webui-harness.cjs
// Creado por Skaymer AR
//
// Smoke test funcional de la WebUI real (validation.js/api.js/app.js, sin
// copiar ni reescribir nada) contra la CLI real. NO es jsdom (sin red para
// instalarlo); es un stub de DOM hecho a mano.
//
// AISLAMIENTO: nunca escribe en /system ni /data/adb. window.ksu.exec
// traduce el prefijo '/system/bin/dnscrypt-manager' (el UNICO que api.js
// conoce) hacia la CLI real dentro de DNSCRYPT_TEST_MODDIR, invocandola
// con el interprete de DNSCRYPT_TEST_SHELL y timeout individual por
// llamada via execFile (nunca bloquea el proceso indefinidamente).
//
// CIERRE LIMPIO: se lleva la cuenta de cada window.ksu.exec en vuelo
// (pendingCalls). Antes de terminar el proceso, se cancelan los
// intervalos de app.js Y se espera activamente a que pendingCalls llegue
// a 0 (nunca un sleep fijo "a ojo").
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const WEBROOT = process.env.DCM_WEBROOT;
const REAL_CLI_PREFIX = '/system/bin/dnscrypt-manager';
const TEST_MODDIR = process.env.DNSCRYPT_TEST_MODDIR;
const TEST_DATA_DIR = process.env.DNSCRYPT_TEST_DATA_DIR;
const TEST_SHELL = process.env.DNSCRYPT_TEST_SHELL || 'sh';
const CALL_TIMEOUT_MS = 15000;
if (!WEBROOT || !TEST_MODDIR || !TEST_DATA_DIR) {
  console.error('FATAL (arnes roto): faltan variables de entorno (DCM_WEBROOT/DNSCRYPT_TEST_MODDIR/DNSCRYPT_TEST_DATA_DIR)');
  process.exit(99);
}
const REAL_CLI_PATH = path.join(TEST_MODDIR, 'system/bin/dnscrypt-manager');

// ---------------------------------------------------------------------------
// Stub de Elemento
// ---------------------------------------------------------------------------
class FakeClassList {
  constructor() { this.set = new Set(); }
  add(c) { this.set.add(c); }
  remove(c) { this.set.delete(c); }
  toggle(c, force) {
    if (force === undefined) { this.set.has(c) ? this.set.delete(c) : this.set.add(c); }
    else if (force) this.set.add(c); else this.set.delete(c);
  }
  contains(c) { return this.set.has(c); }
}
class FakeElement {
  constructor(tag, attrs) {
    this.tagName = (tag || 'div').toUpperCase();
    this.attrs = attrs || {};
    this._text = '';
    this.children = [];
    this.classList = new FakeClassList();
    this._listeners = {};
    this.value = this.attrs.value || '';
    this.checked = false;
    this.disabled = false;
  }
  get textContent() { return this._text; }
  set textContent(v) { this._text = String(v); this.children = []; }
  set innerHTML(v) { this._text = ''; this.children = []; }
  get className() { return Array.from(this.classList.set).join(' '); }
  set className(v) { this.classList.set = new Set(String(v).split(/\s+/).filter(Boolean)); }
  appendChild(n) { this.children.push(n); }
  getAttribute(n) { return this.attrs[n]; }
  addEventListener(type, fn) { (this._listeners[type] ||= []).push(fn); }
  dispatch(type, evt) { (this._listeners[type] || []).forEach((fn) => fn(evt || { target: this })); }
}

const html = fs.readFileSync(path.join(WEBROOT, 'index.html'), 'utf8');
const htmlIds = new Set([...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));
const TYPES = { nextdnsId: ['input', {}], bootRedirectToggle: ['input', {}], ipv6ModeSelect: ['select', {}] };
function realTag(id) {
  const m = html.match(new RegExp('<(\\w+)[^>]*\\bid="' + id + '"'));
  return m ? m[1].toLowerCase() : 'div';
}
const classById = {};
for (const m of html.matchAll(/id="([^"]+)"[^>]*class="([^"]+)"|class="([^"]+)"[^>]*id="([^"]+)"/g)) {
  const id = m[1] || m[4], cls = m[2] || m[3];
  if (id) classById[id] = cls.split(/\s+/);
}
function initialText(id) {
  const m = html.match(new RegExp('id="' + id + '"[^>]*>([^<]*)<'));
  return m ? m[1] : '';
}
const registry = new Map();
for (const id of htmlIds) {
  const tag = TYPES[id] ? TYPES[id][0] : realTag(id);
  const attrs = TYPES[id] ? TYPES[id][1] : {};
  const el = new FakeElement(tag, attrs);
  (classById[id] || []).forEach((c) => el.classList.add(c));
  if (!TYPES[id] && tag !== 'button') el._text = initialText(id);
  registry.set(id, el);
}
const providerNames = [...html.matchAll(/data-provider="([^"]+)"/g)].map((m) => m[1]);
const providerButtons = providerNames.map((name) => new FakeElement('button', { 'data-provider': name }));
const allButtons = [...registry.values()].filter((e) => e.tagName === 'BUTTON').concat(providerButtons);

const document = {
  hidden: false, activeElement: null, _dcl: [], _vis: [],
  getElementById: (id) => registry.get(id) || null,
  querySelectorAll: (sel) => (sel === '[data-provider]' ? providerButtons : allButtons),
  createElement: (tag) => new FakeElement(tag, {}),
  addEventListener(type, fn) {
    if (type === 'DOMContentLoaded') this._dcl.push(fn);
    if (type === 'visibilitychange') this._vis.push(fn);
  },
};

// ---------------------------------------------------------------------------
// window.ksu.exec REAL, con:
//   - contador de llamadas en vuelo (pendingCalls) para cierre limpio;
//   - timeout individual por llamada (execFile 'timeout' option);
//   - clasificacion: 126/127 (no ejecutable/no encontrado) = arnes roto,
//     aborta TODO el proceso; timeout = errno -124 (distinguible).
// ---------------------------------------------------------------------------
const window = {};
let ABORT = false;
let pendingCalls = 0;
function execReal(cmd, cbName) {
  pendingCalls++;
  if (!cmd.startsWith(REAL_CLI_PREFIX)) {
    pendingCalls--;
    const fn = window[cbName];
    if (typeof fn === 'function') fn(-1, '', 'comando fuera de la whitelist esperada por el harness: ' + cmd);
    return;
  }
  const rest = cmd.slice(REAL_CLI_PREFIX.length);
  const args = rest.trim().length ? rest.trim().split(/\s+/) : [];
  execFile(TEST_SHELL, [REAL_CLI_PATH, ...args], {
    encoding: 'utf8', timeout: CALL_TIMEOUT_MS,
    env: Object.assign({}, process.env, {
      DNSCRYPT_TEST_MODE: '1',
      DNSCRYPT_TEST_DATA_DIR: TEST_DATA_DIR,
      DNSCRYPT_TEST_MODDIR: TEST_MODDIR,
    }),
  }, (err, stdout, stderr) => {
    pendingCalls--;
    let errno = 0;
    if (err) {
      if (err.killed && err.signal) {
        // Timeout: execFile mata el proceso con una señal al vencer.
        errno = -124;
      } else {
        errno = typeof err.code === 'number' ? err.code : 1;
        if (errno === 126 || errno === 127) {
          console.error('\nFATAL (arnes roto): window.ksu.exec -> ' + cmd + ' => rc=' + errno +
                         ' (comando no encontrado/no ejecutable), no es un resultado valido del producto.');
          ABORT = true;
          process.exitCode = 99;
          process.exit(99);
          return;
        }
      }
    }
    const fn = window[cbName];
    if (typeof fn === 'function') fn(errno, stdout || '', stderr || (err ? String(err.message) : ''));
  });
}
window.ksu = {
  exec(cmd, _optionsJson, cbName) { setTimeout(() => execReal(cmd, cbName), 0); },
  toast(msg) { window._lastToastNative = msg; },
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const context = vm.createContext({
  window, document, console, confirm: () => true,
  setTimeout, clearTimeout, setInterval, clearInterval, Promise,
});
for (const f of ['js/validation.js', 'js/api.js', 'js/app.js']) {
  vm.runInContext(fs.readFileSync(path.join(WEBROOT, f), 'utf8'), context, { filename: f });
}

let pass = 0, fail = 0;
function check(label, condFn) {
  let cond;
  try { cond = !!condFn(); } catch (e) { cond = false; }
  if (cond) { pass++; console.log('  OK   ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
}
async function waitFor(condFn, timeoutMs = 20000, stepMs = 60) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    if (ABORT) return false;
    try { if (condFn()) return true; } catch (_) { /* aun no listo */ }
    await sleep(stepMs);
  }
  return false;
}
async function waitNotBusy() { return waitFor(() => !registry.get('btnStart').disabled); }

// Consulta status --json DIRECTAMENTE (fuera del DOM) para verificar la
// condicion COMBINADA explicita running+listening+pid>0, sin depender de
// parseo de texto del DOM ni de sleeps fijos ni del poll de 4s de app.js.
function queryStatusDirect() {
  return new Promise((resolve) => {
    const cbName = '__probe_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    window[cbName] = (errno, stdout) => {
      delete window[cbName];
      if (errno !== 0) { resolve(null); return; }
      try { resolve(JSON.parse(stdout)); } catch (_) { resolve(null); }
    };
    execReal(REAL_CLI_PREFIX + ' status --json', cbName);
  });
}
async function waitForRunningListeningPid() {
  return waitFor(async () => {
    const s = await queryStatusDirect();
    return !!(s && s.running === true && s.listening === true && Number.isInteger(s.pid) && s.pid > 0);
  }, 20000, 200);
}

(async () => {
  console.log('=== init() vía DOMContentLoaded ===');
  document._dcl.forEach((fn) => fn());
  await waitFor(() => registry.get('listenText').textContent !== '—');

  check('ksuBanner sigue oculto (ksu SI disponible, class inicial respetada)',
        () => registry.get('ksuBanner').classList.contains('hidden'));
  check('statusDot tiene alguna clase dot-*',
        () => ['dot-green', 'dot-amber', 'dot-red'].some((c) => registry.get('statusDot').classList.contains(c)));
  check('listenText se lleno con la direccion real (puerto de prueba dinamico)',
        () => /^127\.0\.0\.1:\d+$/.test(registry.get('listenText').textContent));
  check('backendText refleja "ninguno detectado" (sandbox sin iptables/nft en PATH)',
        () => registry.get('backendText').textContent === 'ninguno detectado');
  await waitNotBusy();

  console.log('\n=== click Iniciar (btnStart): espera EXPLICITA combinada running+listening+pid>0 ===');
  registry.get('btnStart').dispatch('click');
  // No confiamos SOLO en el DOM: consultamos status --json directo, en
  // paralelo, para la condicion combinada exacta que pide el requisito.
  const gotReady = await waitForRunningListeningPid();
  check('status --json combinado: running=true, listening=true, pid entero>0', () => gotReady);
  await waitFor(() => registry.get('listeningText').textContent === 'Escuchando');
  check('DOM: tras iniciar, listeningText = "Escuchando"', () => registry.get('listeningText').textContent === 'Escuchando');
  check('DOM: tras iniciar, pidText es numerico', () => /^\d+$/.test(registry.get('pidText').textContent));
  await waitNotBusy();

  console.log('\n=== click Probar DNS (btnTestDns) ===');
  registry.get('btnTestDns').dispatch('click');
  await waitFor(() => /RESULTADO|FALLO/.test(registry.get('testDnsOutput').children.map((c) => c.textContent).join('\n')));
  const stagesShown = registry.get('testDnsOutput').children.filter((c) => /^\[\d\/4\]/.test(c.textContent));
  check('se renderizaron las 4 etapas de test-dns', () => stagesShown.length === 4);
  check('etapa 4 marcada OMITIDA (sin redireccion en sandbox)',
        () => stagesShown[3] && stagesShown[3].classList.contains('diag-warn'));
  await waitNotBusy();

  console.log('\n=== NextDNS: ID invalido -> NO debe tocar la CLI ===');
  const idInput = registry.get('nextdnsId');
  idInput.value = 'xyz'; idInput.dispatch('input');
  check('input invalido marca field-invalid', () => idInput.classList.contains('field-invalid'));
  const serverBefore = registry.get('serverText').textContent;
  registry.get('btnNextdnsApply').dispatch('click');
  await sleep(250);
  check('con ID invalido, serverText NO cambio (se corto antes de llamar a ksu.exec)',
        () => registry.get('serverText').textContent === serverBefore);

  console.log('\n=== NextDNS: ID valido -> SI debe llegar a la CLI real ===');
  idInput.value = 'abcdef'; idInput.dispatch('input');
  check('input valido limpia field-invalid', () => !idInput.classList.contains('field-invalid'));
  registry.get('btnNextdnsApply').dispatch('click');
  await waitFor(() => registry.get('serverText').textContent === 'nextdns-abcdef');
  check('tras aplicar, serverText = nextdns-abcdef', () => registry.get('serverText').textContent === 'nextdns-abcdef');
  await waitNotBusy();

  console.log('\n=== Redireccion: aplicar SIN backend -> debe fallar prolijo ===');
  const redirBefore = registry.get('redirectText').textContent;
  registry.get('toast').className = 'toast';
  registry.get('btnRedirectApply').dispatch('click');
  await waitFor(() => /toast-(ok|error)/.test(registry.get('toast').className));
  check('se disparo un toast de resultado (ok o error)', () => /toast-(ok|error)/.test(registry.get('toast').className));
  check('el toast es de error (no hay backend de firewall en el sandbox)',
        () => registry.get('toast').className.includes('toast-error'));
  check('redirectText sigue "Inactiva" tras el fallo esperado',
        () => registry.get('redirectText').textContent === redirBefore && redirBefore === 'Inactiva');
  await waitNotBusy();

  console.log('\n=== Logs: ver y limpiar ===');
  registry.get('btnLogs').dispatch('click');
  await waitFor(() => { const t = registry.get('logsOutput').textContent; return t.length > 0 && t !== 'Cargando…'; });
  check('logsOutput trajo contenido real (no vacio, no placeholder)',
        () => { const t = registry.get('logsOutput').textContent; return t.length > 0 && t !== 'Cargando…'; });
  await waitNotBusy();
  registry.get('btnLogsClear').dispatch('click');
  await waitFor(() => registry.get('logsOutput').textContent === '');
  check('logsOutput se vacio tras limpiar', () => registry.get('logsOutput').textContent === '');
  await waitNotBusy();

  console.log('\n=== PANIC -> deshabilita ===');
  registry.get('btnPanic').dispatch('click');
  await waitFor(() => !registry.get('disabledBanner').classList.contains('hidden'));
  check('tras panic, banner de deshabilitado visible', () => !registry.get('disabledBanner').classList.contains('hidden'));
  check('tras panic, statusDot pasa a rojo', () => registry.get('statusDot').classList.contains('dot-red'));
  await waitNotBusy();

  console.log('\n=== Recuperacion: btnEnable reactiva el modulo Y arranca el servicio ===');
  registry.get('btnEnable').dispatch('click');
  await waitFor(() => registry.get('disabledBanner').classList.contains('hidden'));
  check('tras habilitar, banner deshabilitado vuelve a ocultarse',
        () => registry.get('disabledBanner').classList.contains('hidden'));
  const gotReady2 = await waitForRunningListeningPid();
  check('tras habilitar: status --json combinado running+listening+pid>0 de nuevo', () => gotReady2);
  await waitNotBusy();

  console.log('\n=== Cierre limpio: cancelar intervalos y esperar llamadas ksu.exec pendientes ===');
  document.hidden = true;
  document._vis.forEach((fn) => fn());
  const drained = await waitFor(() => pendingCalls === 0, 20000, 50);
  check('todas las llamadas ksu.exec pendientes terminaron antes de cerrar (pendingCalls=0)', () => drained && pendingCalls === 0);

  console.log(`\n=== RESULTADO: ${pass} OK, ${fail} FAIL ===`);
  process.exit(fail > 0 ? 1 : 0);
})();
