#!/usr/bin/env node
/* tests/smoke-test-webui-v030.cjs  —  Creado por Skaymer AR
 * Verifica el router hash de la SPA y el sistema i18n con un DOM mockeado.
 */
'use strict';
const fs = require('fs');
const path = require('path');

let PASS = 0, FAIL = 0;
const ok = (n) => { PASS++; console.log('  OK   ' + n); };
const bad = (n, e) => { FAIL++; console.log('  FAIL ' + n + (e ? ' :: ' + e : '')); };

// ---- DOM / window mock ----
function el(attrs) {
  const a = Object.assign({ _hidden: false, _cls: {}, _attr: {} }, attrs || {});
  return {
    removeAttribute(k) { if (k === 'hidden') a._hidden = false; delete a._attr[k]; },
    setAttribute(k, v) { if (k === 'hidden') a._hidden = true; else a._attr[k] = v; },
    getAttribute(k) { return k in a._attr ? a._attr[k] : (a[k] !== undefined ? a[k] : null); },
    get hidden() { return a._hidden; },
    classList: {
      add(c) { a._cls[c] = true; }, remove(c) { delete a._cls[c]; },
      contains(c) { return !!a._cls[c]; }
    },
    textContent: '', value: a.value || '',
    addEventListener() {}, scrollTo() {}, _a: a
  };
}

const routes = ['status', 'dns', 'lists', 'activity', 'settings'];
const elements = {};
routes.forEach((r) => { elements['route-' + r] = el(); });
elements['views'] = el();
elements['langSelect'] = el({ value: 'en' });
const navItems = routes.map((r) => { const e = el(); e.setAttribute('data-nav', r); return e; });
// data-i18n de prueba
const i18nEls = [ (function(){ const e = el(); e.setAttribute('data-i18n','nav.status'); return e; })() ];

let hashListeners = [];
const store = {};
global.window = {
  location: { hash: '' },
  localStorage: {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); }
  },
  addEventListener: (ev, fn) => { if (ev === 'hashchange') hashListeners.push(fn); },
  scrollTo() {}
};
// setter de hash que dispara hashchange (como el navegador)
let _hash = '';
Object.defineProperty(global.window.location, 'hash', {
  get() { return _hash; },
  set(v) { _hash = v; hashListeners.forEach((f) => { try { f(); } catch (_) {} }); }
});
global.document = {
  getElementById: (id) => elements[id] || null,
  querySelectorAll: (sel) => {
    if (sel === '[data-nav]') return navItems;
    if (sel === '[data-i18n]') return i18nEls;
    return [];
  },
  documentElement: el()
};
// fetch mock -> lee los JSON locales
global.fetch = async (url) => {
  const p = path.join(__dirname, '..', 'webroot', url);
  try {
    const txt = fs.readFileSync(p, 'utf8');
    return { ok: true, json: async () => JSON.parse(txt) };
  } catch (_) { return { ok: false, json: async () => ({}) }; }
};

const Router = require('../webroot/js/router.js');
const I18N = require('../webroot/js/i18n.js');

(async () => {
  console.log('== Router ==');
  Router.init();
  // sin hash previo -> default status
  if (elements['route-status'].hidden === false && elements['route-dns'].hidden === true) ok('init muestra #/status por defecto');
  else bad('init default', 'status.hidden=' + elements['route-status'].hidden);
  if (navItems[0].classList.contains('active')) ok('nav marca Status activo'); else bad('nav activo status');

  Router.go('lists');
  if (elements['route-lists'].hidden === false && elements['route-status'].hidden === true) ok('go(lists) muestra Lists y oculta Status');
  else bad('go lists', 'lists.hidden=' + elements['route-lists'].hidden);
  if (navItems[2].classList.contains('active') && !navItems[0].classList.contains('active')) ok('nav mueve el activo a Lists');
  else bad('nav activo lists');
  if (store['dcm_tab'] === 'lists') ok('recuerda la ultima pestaña (localStorage)'); else bad('recuerda pestaña', store['dcm_tab']);

  // hashchange directo (boton atras / navegacion)
  global.window.location.hash = '#/activity';
  if (elements['route-activity'].hidden === false) ok('hashchange (boton Atras) cambia de seccion'); else bad('hashchange');

  // ruta invalida sin pestaña recordada -> fallback al default (status)
  delete store['dcm_tab'];
  global.window.location.hash = '#/noexiste';
  if (elements['route-status'].hidden === false) ok('ruta invalida sin memoria cae al default (status)'); else bad('fallback ruta invalida', 'status.hidden=' + elements['route-status'].hidden);

  console.log('== i18n ==');
  // antes de cargar: t devuelve la clave
  if (I18N.t('nav.status') === 'nav.status') ok('t() sin cargar devuelve la clave'); else bad('t sin cargar');
  await I18N.init();
  if (I18N.current() === 'en') ok('idioma por defecto = en'); else bad('default en', I18N.current());
  if (I18N.t('nav.status') === 'Status') ok('EN: nav.status = Status'); else bad('EN nav.status', I18N.t('nav.status'));
  await I18N.setLang('es');
  if (I18N.t('nav.status') === 'Estado') ok('ES: nav.status = Estado (cambio en caliente)'); else bad('ES nav.status', I18N.t('nav.status'));
  if (I18N.t('clave.inexistente') === 'clave.inexistente') ok('clave inexistente -> devuelve la clave'); else bad('clave inexistente');
  // aplica al DOM
  I18N.apply(global.document);
  if (i18nEls[0].textContent === 'Estado') ok('apply() traduce [data-i18n] con textContent'); else bad('apply textContent', i18nEls[0].textContent);
  await I18N.setLang('en');
  if (I18N.t('nav.status') === 'Status') ok('volver a EN funciona'); else bad('volver EN');
  // idioma no soportado -> fallback en
  await I18N.setLang('fr');
  if (I18N.current() === 'en') ok('idioma no soportado -> fallback en'); else bad('fallback idioma', I18N.current());

  console.log('\nResumen webui-v030: ' + PASS + ' OK, ' + FAIL + ' FAIL');
  process.exit(FAIL === 0 ? 0 : 1);
})();
