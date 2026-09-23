#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let PASS = 0, FAIL = 0;
function ok(name) { PASS++; console.log('  OK   ' + name); }
function bad(name, detail) { FAIL++; console.log('  FAIL ' + name + (detail ? ' :: ' + detail : '')); }
function assert(value, name, detail) { if (value) ok(name); else bad(name, detail); }

class FakeElement {
  constructor(tag) { this.tagName = tag; this.children = []; this.attrs = Object.create(null); this.listeners = Object.create(null); this.hidden = false; this.textContent = ''; this.value = ''; }
  appendChild(child) { this.children.push(child); return child; }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  getAttribute(key) { return this.attrs[key] || null; }
  addEventListener(type, fn) { this.listeners[type] = fn; }
  focus() {}
}

const ids = Object.create(null);
['catSearch', 'catFilterOptions', 'catFilterStatus', 'uiModeSimple', 'uiModeAdvanced'].forEach((id) => { ids[id] = new FakeElement(id); });
const storage = Object.create(null);
const context = {
  console,
  window: { localStorage: { getItem: (key) => storage[key] || null, setItem: (key, value) => { storage[key] = String(value); } } },
  document: {
    body: new FakeElement('body'),
    getElementById: (id) => ids[id] || null,
    createElement: (tag) => new FakeElement(tag),
    addEventListener() {},
    querySelectorAll: () => []
  }
};
const app = fs.readFileSync(path.join(__dirname, '../webroot/js/app.js'), 'utf8');
const html = fs.readFileSync(path.join(__dirname, '../webroot/index.html'), 'utf8');
const expose = `\nglobalThis.__catalogUi = {
  setEntries(entries) { catCache = entries; catLoaded = true; catLoadedGroups.clear(); catLoadedGroups.add('Security'); catLoadedGroups.add('Privacy'); },
  setFilters(groups, subgroups, packs) {
    catFilterGroups.clear(); (groups || []).forEach(v => catFilterGroups.add(v.toLowerCase()));
    catFilterSubgroups.clear(); (subgroups || []).forEach(v => catFilterSubgroups.add(v.toLowerCase()));
    catFilterPacks.clear(); (packs || []).forEach(v => catFilterPacks.add(v.toLowerCase()));
  },
  setSearch(value) { document.getElementById('catSearch').value = value; },
  setView(value) { catView = value; },
  addPending(id) { catSelection.add(id); },
  filteredIds() { return catFiltered().map(e => e.id); },
  facets(kind) { return catFacetValues(kind); },
  renderOptions() { catRenderFilterOptions(); return document.getElementById('catFilterOptions'); },
  canAdd(entry) { return catCanAdd(entry); },
  setMode(value) { setUiMode(value); }
};`;
vm.runInNewContext(app + expose, context, { timeout: 3000 });
const ui = context.__catalogUi;

assert(/<button[^>]*id="btnCatDownloadAll"[^>]*>Descargar todas las fuentes<\/button>/.test(html) &&
  /id="catDownloadStatus"[^>]*aria-live="polite"/.test(html), 'el catálogo muestra descarga global y estado accesibles');

const entries = [
  { id: 'privacy_tracker', name: 'Tracker list', source_name: 'Tracker list', source_group: 'Privacy', source_subgroup: 'TrackingDomains', source_packs: 'spyware|liteprivacy', categories: 'trackers', enabled: false },
  { id: 'privacy_ads', name: 'Ad list', source_name: 'Ad list', source_group: 'Privacy', source_subgroup: 'Disconnect', source_packs: 'aggressiveprivacy', categories: 'ads', enabled: true },
  { id: 'security_malware', name: 'Malware list', source_name: 'Malware list', source_group: 'Security', source_subgroup: 'ThreatIntelligence', source_packs: 'malware', categories: 'malware', enabled: false }
];
ui.setEntries(entries);

ui.setFilters([], ['TRACKINGDOMAINS'], ['spyware', 'liteprivacy']);
assert(JSON.stringify(ui.filteredIds()) === JSON.stringify(['privacy_tracker']), 'filtros por subgrupo y etiqueta se combinan correctamente, sin distinguir mayúsculas');
ui.setFilters([], ['TrackingDomains', 'Disconnect'], ['spyware', 'aggressiveprivacy']);
assert(JSON.stringify(ui.filteredIds()) === JSON.stringify(['privacy_tracker', 'privacy_ads']), 'varios chips del mismo grupo usan coincidencia OR');
ui.setFilters(['Security'], [], ['spyware']);
assert(ui.filteredIds().length === 0, 'filtros de grupos distintos se combinan con AND');
ui.setFilters([], [], ['malware']);
ui.setSearch('security_');
assert(JSON.stringify(ui.filteredIds()) === JSON.stringify(['security_malware']), 'la búsqueda se combina con los filtros aplicados');
ui.setSearch('');
ui.setFilters([], [], []);
ui.setView('selected');
ui.addPending('privacy_tracker');
assert(JSON.stringify(ui.filteredIds()) === JSON.stringify(['privacy_tracker', 'privacy_ads']), 'vista Seleccionadas incluye fuentes activas y cambios preparados');

const subgroups = ui.facets('subgroup');
const packs = ui.facets('pack');
assert(subgroups.some((v) => v.label === 'TrackingDomains') && packs.some((v) => v.label === 'spyware'), 'filtros salen de los metadatos reales del catálogo');
const facetRoot = ui.renderOptions();
function treeText(node) { return [node.textContent].concat(node.children.map(treeText)).join(' '); }
const optionText = treeText(facetRoot);
assert(optionText.includes('Categoría') && optionText.includes('Subgrupo') && optionText.includes('Etiquetas del catálogo'), 'el panel muestra grupos de filtros con sus etiquetas');
assert(ui.canAdd({ id: 'unknown', license: 'LICENSE_UNKNOWN', license_blocked: true, enabled: false, activation_blocked: false, upstream_status: 'unverified' }), 'LICENSE_UNKNOWN queda seleccionable por opt-in manual');
assert(!ui.canAdd({ id: 'unsupported', license: 'MIT', enabled: false, activation_blocked: true, upstream_status: 'unverified' }), 'la incompatibilidad técnica sigue bloqueando fuentes no convertibles');

ui.setMode('advanced');
assert(context.document.body.attrs['data-ui-mode'] === 'advanced' && storage.dcm_ui_mode === 'advanced' && ids.uiModeAdvanced.attrs['aria-pressed'] === 'true', 'modo Avanzado se aplica y persiste');
ui.setMode('simple');
assert(context.document.body.attrs['data-ui-mode'] === 'simple' && ids.uiModeSimple.attrs['aria-pressed'] === 'true', 'modo Simple se puede restaurar sin tocar las listas activas');

console.log('\nResumen catalog-ui: ' + PASS + ' OK, ' + FAIL + ' FAIL');
process.exit(FAIL === 0 ? 0 : 1);
