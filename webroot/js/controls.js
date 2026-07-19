/* ===================== v0.3 WebUI: service-controls + transportes (LAZY) ===================== */
/* DOM seguro (createElement/textContent). Usa SIEMPRE la CLI resuelta vía DCM.
   No duplica enforcement: solo consulta/ejecuta el backend.
   CARGA DIFERIDA: nada pesado hasta que el usuario expande. Al cerrar, se
   desmonta el DOM pesado y se detiene el polling (un solo timer). Respuestas
   tardias de una apertura anterior se ignoran via token de generacion. */
var V030 = (function () {
  var POLL_MS = 15000;
  var MODES = ['off', '15m', '1h', 'until_reboot', 'permanent'];
  function t(k) { return (typeof I18N !== 'undefined' && I18N.t) ? I18N.t(k) : k; }
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function gid(id) { return document.getElementById(id); }
  function isVisible() { return (typeof document === 'undefined') || document.visibilityState === undefined || document.visibilityState === 'visible'; }
  function routeVisible(r) { return (typeof Router === 'undefined') || !Router.current || Router.current() === r; }
  function busyNow() { return (typeof busy !== 'undefined') && busy; }

  function badge(stateKey, stateVal) {
    var b = el('span', 'v-badge v-' + stateVal);
    var ic = { active: '\u25CF', off: '\u25CB', inactive: '\u25CB', configured: '\u25D0', testing: '\u2026', not_verifiable: '?', failed: '\u2717', unsupported: '\u2298', expired: '\u231B', pending: '\u2026', conflict: '!', error: '\u2717', unknown: '?' };
    b.textContent = (ic[stateVal] || '') + ' ' + t(stateKey);
    return b;
  }

  /* =================== SERVICE-CONTROLS (seccion colapsable) =================== */
  var sc = { open: false, gen: 0, timer: null, openRow: null, blocks: null, active: null, wired: false };

  function scStopPoll() { if (sc.timer) { clearInterval(sc.timer); sc.timer = null; } }
  function scStartPoll() {
    scStopPoll();
    sc.timer = setInterval(function () {
      if (sc.open && routeVisible('lists') && isVisible() && !busyNow()) scRefreshSummary();
    }, POLL_MS);
  }
  function scUpdateSummaryLabel() {
    var s = gid('scSummary'); if (!s) return;
    if (sc.active == null) { s.textContent = t('sc.section.tap'); return; }
    s.textContent = t('sc.section.count').replace('{n}', String((sc.blocks || []).length)).replace('{a}', String(sc.active));
  }
  function scTeardown() {
    scStopPoll(); sc.gen++; sc.open = false; sc.openRow = null; sc.blocks = null; sc.active = null;
    var body = gid('scBody'); if (body) { body.textContent = ''; body.hidden = true; }
    var tg = gid('scToggle'); if (tg) tg.setAttribute('aria-expanded', 'false');
    var ch = gid('scChevron'); if (ch) ch.textContent = '\u25BC';
    scUpdateSummaryLabel();
  }
  function scHeaderActions() {
    var bar = el('div', 'v-collapse-actions');
    var refr = el('button', 'small', t('sc.btn.refreshsummary'));
    refr.type = 'button';
    refr.addEventListener('click', function () { if (!busyNow()) scRefreshSummary(); });
    var close = el('button', 'small', t('sc.btn.close'));
    close.type = 'button';
    close.addEventListener('click', function () { scTeardown(); });
    bar.appendChild(refr); bar.appendChild(close);
    return bar;
  }
  async function scOpenSection() {
    if (sc.open) return;
    sc.open = true; var myGen = ++sc.gen;
    var body = gid('scBody'); if (!body) { sc.open = false; return; }
    body.hidden = false; body.textContent = '';
    var tg = gid('scToggle'); if (tg) tg.setAttribute('aria-expanded', 'true');
    var ch = gid('scChevron'); if (ch) ch.textContent = '\u25B2';
    body.appendChild(scHeaderActions());
    var lb = el('div', 'v-sc-list'); lb.id = 'scListInner'; body.appendChild(lb);
    lb.appendChild(el('div', 'v-muted', t('common.loading')));
    if (!DCM.cliResolved()) { try { await DCM.resolveCli(); } catch (e) {} }
    var r; try { r = await DCM.runServiceControlListJson(); } catch (e) { if (myGen === sc.gen && sc.open) scLoadError(); return; }
    if (myGen !== sc.gen || !sc.open) return;                 // cerrada mientras cargaba -> ignorar
    if (r && r.errno && r.errno !== 0 && !((r.stdout || '').length)) { scLoadError(r.stderr); return; }
    sc.blocks = DCM.parseKvBlocks((r && r.stdout) ? r.stdout : []);
    scRenderRows();
    scStartPoll();
  }
  function scLoadError(msg) {
    var lb = gid('scListInner'); if (!lb) return; lb.textContent = '';
    lb.appendChild(el('div', 'v-err', msg || t('sc.loadfail')));
    var retry = el('button', 'small', t('common.retry')); retry.type = 'button';
    retry.addEventListener('click', function () { if (!busyNow()) scRefreshSummary(); });
    lb.appendChild(retry);
  }
  async function scRefreshSummary() {
    if (!sc.open) return;
    var myGen = sc.gen;                                        // no bump: es refresco, no reapertura
    var r; try { r = await DCM.runServiceControlListJson(); } catch (e) { return; }
    if (myGen !== sc.gen || !sc.open) return;
    sc.blocks = DCM.parseKvBlocks((r && r.stdout) ? r.stdout : []);
    scRenderRows();
  }
  function scRenderRows() {
    var lb = gid('scListInner'); if (!lb) return; lb.textContent = '';
    var blocks = sc.blocks || []; var active = 0;
    for (var i = 0; i < blocks.length; i++) { var eff = blocks[i].effective_mode || 'off'; if (eff !== 'off') active++; lb.appendChild(scRow(blocks[i])); }
    sc.active = active; scUpdateSummaryLabel();
    // reabrir el detalle que estaba abierto (si sigue existiendo)
    if (sc.openRow) { var d = gid('scdet-' + sc.openRow); if (d) { /* se recarga on demand al tocar */ } }
  }
  function scRow(c) {
    var eff = c.effective_mode || 'off';
    var wrap = el('div', 'v-sc-row');
    var head = document.createElement('button'); head.type = 'button'; head.className = 'v-sc-rowh';
    head.setAttribute('aria-expanded', 'false'); head.setAttribute('aria-controls', 'scdet-' + c.id);
    head.appendChild(el('span', 'v-sc-name', c.name || c.id));
    head.appendChild(el('span', 'v-sc-cat', t('sc.cat.' + (c.category || 'other'))));
    var st = eff === 'off' ? 'off' : 'active';
    head.appendChild(badge('sc.st.' + st, st));
    if (eff !== 'off') head.appendChild(el('span', 'v-sc-mode', t('sc.mode.' + eff)));
    head.appendChild(el('span', 'v-sc-chev', '\u203A'));
    head.addEventListener('click', function () { scToggleRow(c.id); });
    // toggle ON/OFF (no expande; opera)
    var toggle = document.createElement('button'); toggle.type = 'button';
    toggle.className = 'v-sc-toggle' + (eff !== 'off' ? ' on' : '');
    toggle.setAttribute('aria-pressed', eff !== 'off' ? 'true' : 'false');
    toggle.textContent = eff !== 'off' ? t('sc.on') : t('sc.off');
    toggle.addEventListener('click', function (ev) { if (ev && ev.stopPropagation) ev.stopPropagation(); if (!busyNow()) scToggleControl(c.id, eff); });
    var top = el('div', 'v-sc-top'); top.appendChild(head); top.appendChild(toggle);
    wrap.appendChild(top);
    var det = el('div', 'v-sc-det'); det.id = 'scdet-' + c.id; det.hidden = true; wrap.appendChild(det);
    wrap._c = c;
    return wrap;
  }
  async function scToggleRow(id) {
    var det = gid('scdet-' + id); if (!det) return;
    var wrap = det.parentNode; var head = wrap && wrap.querySelector ? wrap.querySelector('.v-sc-rowh') : null;
    if (sc.openRow === id) {                                    // cerrar este
      det.hidden = true; det.textContent = ''; sc.openRow = null; if (head) head.setAttribute('aria-expanded', 'false'); return;
    }
    if (sc.openRow) {                                           // accordion: cerrar el anterior
      var pd = gid('scdet-' + sc.openRow); if (pd) { pd.hidden = true; pd.textContent = ''; var ph = pd.parentNode && pd.parentNode.querySelector ? pd.parentNode.querySelector('.v-sc-rowh') : null; if (ph) ph.setAttribute('aria-expanded', 'false'); }
    }
    sc.openRow = id; if (head) head.setAttribute('aria-expanded', 'true');
    det.hidden = false; det.textContent = t('common.loading');
    var myGen = sc.gen;
    var vr; try { vr = await DCM.runServiceControlVerify(id); } catch (e) {}   // SOLO este control
    if (myGen !== sc.gen || !sc.open || sc.openRow !== id) return;             // ignorar tardias
    scRenderDetail(det, (wrap && wrap._c) || { id: id }, (vr && (vr.stdout || vr.stderr)) || '');
  }
  function scRenderDetail(det, c, verifyText) {
    det.textContent = '';
    det.appendChild(el('div', 'v-id', c.id));
    if (c.description) det.appendChild(el('div', 'v-desc', c.description));
    var grid = el('div', 'v-grid');
    function row(lblKey, val) { if (val == null || val === '') return; var r2 = el('div', 'v-row'); r2.appendChild(el('span', 'v-k', t(lblKey))); r2.appendChild(el('span', 'v-v', String(val))); grid.appendChild(r2); }
    row('sc.col.requested', c.requested_mode);
    row('sc.col.applied', c.domains_in_blocked || '0/0');
    row('sc.col.domains', c.domains);
    row('sc.col.expiry', c.expiry_epoch && c.expiry_epoch !== '0' ? c.expiry_epoch : null);
    det.appendChild(grid);
    if (c.allowlist_conflict === 'yes') { var w = el('div', 'v-conflict'); w.textContent = '\u26A0 ' + t('sc.conflict'); det.appendChild(w); }
    if (verifyText) { var vr = el('div', 'v-verify'); vr.textContent = verifyText.replace(/\n/g, ' '); det.appendChild(vr); }
    // selector de duracion + acciones
    var ctr = el('div', 'v-actions');
    var sel = document.createElement('select'); sel.className = 'v-sel';
    for (var i = 0; i < MODES.length; i++) { var o = document.createElement('option'); o.value = MODES[i]; o.textContent = t('sc.mode.' + MODES[i]); if (MODES[i] === (c.requested_mode || 'off')) o.selected = true; sel.appendChild(o); }
    ctr.appendChild(sel);
    var apply = el('button', 'small', t('sc.btn.apply')); apply.type = 'button';
    apply.addEventListener('click', function () { if (busyNow()) return; var m = sel.value; if (m === 'off') m = 'until_reboot'; scSet(c.id, m); });
    var offb = el('button', 'small', t('sc.btn.off')); offb.type = 'button';
    offb.addEventListener('click', function () { if (!busyNow()) scSet(c.id, 'off'); });
    var ver = el('button', 'small', t('sc.btn.verify')); ver.type = 'button';
    ver.addEventListener('click', function () { if (!busyNow()) scReverify(c.id, det, c); });
    ctr.appendChild(apply); ctr.appendChild(offb); ctr.appendChild(ver);
    det.appendChild(ctr);
    var res = el('div', 'v-result'); res.id = 'scres-' + c.id; det.appendChild(res);
  }
  async function scReverify(id, det, c) {
    setBusy(true);
    try { var r = await DCM.runServiceControlVerify(id); var res = gid('scres-' + id); if (res) res.textContent = ((r && (r.stdout || r.stderr)) || '').replace(/\n/g, ' '); }
    catch (e) {} finally { setBusy(false); }
  }
  function scToggleControl(id, eff) { scSet(id, eff === 'off' ? 'until_reboot' : 'off'); }
  async function scSet(id, mode) {
    if (!DCM.validMode(mode) || !/^[a-zA-Z0-9_]+$/.test(id)) { toast(t('common.error'), 'error'); return; }
    setBusy(true);
    try {
      var r = await DCM.runServiceControlSet(id, mode);
      var res = gid('scres-' + id); if (res) res.textContent = ((r && (r.stdout || r.stderr)) || '').split('\n')[0];
    } catch (e) {} finally {
      setBusy(false);
      await scRefreshSummary();                                // refresca solo el resumen
      if (sc.openRow === id) { var det = gid('scdet-' + id); if (det) { var b = (sc.blocks || []).filter(function (x) { return x.id === id; })[0]; if (b) { var vr; try { vr = await DCM.runServiceControlVerify(id); } catch (e2) {} scRenderDetail(det, b, (vr && (vr.stdout || vr.stderr)) || ''); } } }
    }
  }
  function scWire() {
    if (sc.wired) return; var tg = gid('scToggle'); if (!tg) return;
    tg.addEventListener('click', function () { if (sc.open) scTeardown(); else scOpenSection(); });
    sc.wired = true;
  }

  /* =================== TRANSPORTES (tarjetas colapsables) =================== */
  var tp = { anon: { open: false, gen: 0, wired: false }, odoh: { open: false, gen: 0, wired: false } };
  function kvToObj(text) { var o = {}; String(text || '').split('\n').forEach(function (ln) { var i = ln.indexOf(':'); if (i < 0) i = ln.indexOf('='); if (i > 0) { o[ln.slice(0, i).trim()] = ln.slice(i + 1).trim(); } }); return o; }
  function tpIds(kind) { return kind === 'odoh' ? { body: 'odohBody', card: 'odohCard', tg: 'odohToggle', chev: 'odohChevron', sum: 'odohSummary' } : { body: 'anonBody', card: 'anonCard', tg: 'anonToggle', chev: 'anonChevron', sum: 'anonSummary' }; }
  function tpTeardown(kind) {
    var s = tp[kind]; s.gen++; s.open = false; var ids = tpIds(kind);
    var body = gid(ids.body); if (body) body.hidden = true;
    var card = gid(ids.card); if (card) card.textContent = '';
    var tg = gid(ids.tg); if (tg) tg.setAttribute('aria-expanded', 'false');
    var ch = gid(ids.chev); if (ch) ch.textContent = '\u25BC';
    var sum = gid(ids.sum); if (sum) sum.textContent = t('tp.tap');
  }
  async function tpOpen(kind) {
    var s = tp[kind]; if (s.open) return; s.open = true; var myGen = ++s.gen; var ids = tpIds(kind);
    var body = gid(ids.body); if (!body) { s.open = false; return; }
    body.hidden = false;
    var tg = gid(ids.tg); if (tg) tg.setAttribute('aria-expanded', 'true');
    var ch = gid(ids.chev); if (ch) ch.textContent = '\u25B2';
    var card = gid(ids.card); if (card) { card.textContent = ''; card.appendChild(el('div', 'v-muted', t('common.loading'))); }
    await tpRenderStatus(kind, myGen);                          // SOLO consulta estado (sin test/logs)
  }
  async function tpRenderStatus(kind, myGen) {
    var ids = tpIds(kind); var box = gid(ids.card); if (!box) return;
    if (typeof myGen !== 'number') myGen = tp[kind].gen;
    if (!DCM.cliResolved()) { try { await DCM.resolveCli(); } catch (e) {} }
    var r; try { r = (kind === 'odoh') ? await DCM.runOdohStatus() : await DCM.runAnonymizedStatus(); } catch (e) { if (myGen === tp[kind].gen && tp[kind].open) box.textContent = t('common.error'); return; }
    if (myGen !== tp[kind].gen || !tp[kind].open) return;       // cerrada mientras cargaba
    var kv = kvToObj((r && r.stdout) ? r.stdout : '');
    var state = DCM.transportState(kv, kind);
    var sum = gid(ids.sum); if (sum) sum.textContent = t(DCM.transportStateLabel(state));
    box.textContent = '';
    var head = el('div', 'v-card-h');
    head.appendChild(el('span', 'v-name', t(kind === 'odoh' ? 'tp.odoh.title' : 'tp.anon.title')));
    head.appendChild(badge(DCM.transportStateLabel(state), state));
    box.appendChild(head);
    var grid = el('div', 'v-grid');
    function row(lblKey, val) { if (val == null || val === '') return; var r2 = el('div', 'v-row'); r2.appendChild(el('span', 'v-k', t(lblKey))); r2.appendChild(el('span', 'v-v', String(val))); grid.appendChild(r2); }
    if (kind === 'odoh') { row('tp.col.target', kv.target); row('tp.col.evidence', kv.supported); }
    else { row('tp.col.resolver', kv.resolver); row('tp.col.relays', kv.relays); }
    box.appendChild(grid);
    if (kind !== 'odoh') { var note = el('div', 'v-note'); note.textContent = t('tp.anon.novpn'); box.appendChild(note); }
    var ctr = el('div', 'v-actions');
    var test = el('button', 'small', t('tp.btn.test')); test.type = 'button';
    test.addEventListener('click', function () { if (!busyNow()) tpTest(kind); });
    var dis = el('button', 'small', t('tp.btn.disable')); dis.type = 'button';
    dis.addEventListener('click', function () { if (!busyNow()) tpDisable(kind); });
    var roll = el('button', 'small', t('tp.btn.rollback')); roll.type = 'button';
    roll.addEventListener('click', function () { if (!busyNow()) tpRollback(kind); });
    var refr = el('button', 'small', t('tp.btn.refresh')); refr.type = 'button';
    refr.addEventListener('click', function () { if (!busyNow()) tpRenderStatus(kind); });
    ctr.appendChild(test); ctr.appendChild(dis); ctr.appendChild(roll); ctr.appendChild(refr);
    box.appendChild(ctr);
    var res = el('div', 'v-result'); res.id = 'tpres-' + kind; box.appendChild(res);
  }
  async function tpTest(kind) {
    setBusy(true);
    var out = gid('tpres-' + kind); if (out) out.textContent = t('tp.st.testing');
    try {
      var r = (kind === 'odoh') ? await DCM.runOdohTest('', '') : await DCM.runAnonymizedTest(
        (gid('anonResolver') || {}).value || 'cloudflare', (gid('anonRelays') || {}).value || 'anon-cs-fr');
      if (out) out.textContent = ((r && (r.stdout || r.stderr)) || '').replace(/\n/g, ' ');
    } catch (e) {} finally { setBusy(false); tpRenderStatus(kind); }
  }
  async function tpDisable(kind) {
    setBusy(true);
    try { (kind === 'odoh') ? await DCM.runOdohDisable() : await DCM.runAnonymizedDisable(); }
    catch (e) {} finally { setBusy(false); tpRenderStatus(kind); }
  }
  async function tpRollback(kind) {
    if (typeof confirm === 'function' && !confirm(t('tp.confirm.apply'))) return;
    setBusy(true);
    try { await DCM.runTransportRollback(); } catch (e) {} finally { setBusy(false); tpRenderStatus(kind); }
  }
  function tpWire(kind) {
    var s = tp[kind]; if (s.wired) return; var ids = tpIds(kind); var tg = gid(ids.tg); if (!tg) return;
    tg.addEventListener('click', function () { if (s.open) tpTeardown(kind); else tpOpen(kind); });
    s.wired = true;
  }

  /* =================== ruteo: solo cablea y limpia; NO carga =================== */
  function onRoute(route) {
    if (route === 'lists') { scWire(); }
    else { if (sc.open) scTeardown(); }                          // salir de lists -> desmontar
    if (route === 'dns') { tpWire('anon'); tpWire('odoh'); }
    else { if (tp.anon.open) tpTeardown('anon'); if (tp.odoh.open) tpTeardown('odoh'); }
  }
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) { scStopPoll(); }                       // pausa polling; no desmonta
    else if (sc.open) { scStartPoll(); }
  });

  var api = {
    onRoute: onRoute,
    // test hooks (estado interno, sin DOM):
    _sc: sc, _tp: tp,
    _scOpen: scOpenSection, _scClose: scTeardown, _scToggleRow: scToggleRow, _scRefresh: scRefreshSummary,
    _tpOpen: tpOpen, _tpClose: tpTeardown, _scWire: scWire, _tpWire: tpWire
  };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; }
  return api;
})();
