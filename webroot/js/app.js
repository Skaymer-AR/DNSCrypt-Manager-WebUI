/* DNSCrypt Manager - app.js
 * Creado por Skaymer AR
 * Controlador principal de la WebUI. Sin frameworks, sin dependencias.
 *
 * ALCANCE DE ESTA WEBUI (pasada "minima funcional"):
 *   Incluye: Panel principal, Servidores (preestablecidos + NextDNS),
 *   Redireccion (aplicar/quitar, inicio automatico, modo IPv6),
 *   Diagnostico basico (Private DNS), Logs, Emergencia.
 *   Deferido a una proxima pasada (no incluido todavia): editor TOML
 *   avanzado en el navegador, gestor visual de copias de seguridad,
 *   seccion Aplicaciones (incluir/excluir por UID) y listas de bloqueo
 *   personalizadas. Todo eso ya es operable por CLI (ver
 *   `dnscrypt-manager help`) mientras se agrega su contraparte visual.
 */
'use strict';

/* Estructura minima para traduccion futura: un solo objeto con los textos
 * que arma el propio JS (los textos estaticos del HTML se traducen aparte,
 * el dia que se agregue selector de idioma). */
const STR = {
  running: 'Corriendo', stopped: 'Detenido',
  listeningYes: 'Escuchando', listeningNo: 'Sin escuchar',
  redirectOn: 'Activa', redirectOff: 'Inactiva',
  disabledBanner: 'Modulo DESHABILITADO (modo seguro). Toca "Habilitar" para reactivarlo.',
  noKsu: 'Esta WebUI necesita KernelSU, KernelSU Next o APatch. ' +
         'En Magisk no hay WebUI nativa: usa el boton de Accion del modulo ' +
         'o la CLI (su -c dnscrypt-manager help).',
  confirmRedirectApply: 'Esto va a redirigir el DNS del sistema hacia dnscrypt-proxy. ¿Continuar?',
  confirmRedirectRemove: '¿Quitar la redireccion DNS? El trafico volvera al DNS normal del sistema.',
  confirmPanic: 'PANIC va a detener todo, quitar la redireccion, restaurar tu DNS normal y ' +
                'DESHABILITAR el modulo hasta que lo reactives. ¿Continuar?',
  confirmLogsClear: '¿Borrar todos los logs? Esta accion no se puede deshacer.',
  timeout: 'Tiempo de espera agotado. Reintenta en unos segundos.'
};

let POLL_MS = 4000;
let pollTimer = null;
let busy = false; // evita acciones superpuestas mientras hay una en curso
const UI_MODE_KEY = 'dcm_ui_mode';
let uiMode = 'simple';

/* --------------------------- utilidades DOM --------------------------- */
const $ = (id) => document.getElementById(id);
const tr = (key) => (typeof I18N !== 'undefined' && I18N.t) ? I18N.t(key) : key;
const trf = (key, values) => tr(key).replace(/\{(\w+)\}/g, (_, name) =>
  Object.prototype.hasOwnProperty.call(values, name) ? String(values[name]) : '{' + name + '}');

function setText(id, text) {
  const el = $(id);
  if (el) el.textContent = text;
}

function setDot(id, level) {
  // level: 'green' | 'amber' | 'red'
  const el = $(id);
  if (!el) return;
  el.classList.remove('dot-green', 'dot-amber', 'dot-red');
  el.classList.add('dot-' + level);
}

function toast(msg, kind) {
  const el = $('toast');
  if (!el) return;
  el.textContent = msg;
  el.className = 'toast show' + (kind ? ' toast-' + kind : '');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { el.className = 'toast'; }, 3800);
}

function setBusy(v) {
  busy = v;
  document.querySelectorAll('button').forEach((b) => { b.disabled = v; });
}

function setUiMode(mode, persist) {
  uiMode = mode === 'advanced' ? 'advanced' : 'simple';
  if (document.body && document.body.setAttribute) document.body.setAttribute('data-ui-mode', uiMode);
  const simple = $('uiModeSimple');
  const advanced = $('uiModeAdvanced');
  if (simple) simple.setAttribute('aria-pressed', uiMode === 'simple' ? 'true' : 'false');
  if (advanced) advanced.setAttribute('aria-pressed', uiMode === 'advanced' ? 'true' : 'false');
  if (persist !== false) {
    try { window.localStorage.setItem(UI_MODE_KEY, uiMode); } catch (_) {}
  }
  if (typeof catRenderFilterOptions === 'function' && $('catFilterSheet') && !$('catFilterSheet').hidden) {
    catRenderFilterOptions();
  }
}

function wireUiMode() {
  let stored = '';
  try { stored = window.localStorage.getItem(UI_MODE_KEY) || ''; } catch (_) {}
  setUiMode(stored === 'advanced' ? 'advanced' : 'simple', false);
  const simple = $('uiModeSimple');
  const advanced = $('uiModeAdvanced');
  if (simple) simple.addEventListener('click', () => setUiMode('simple'));
  if (advanced) advanced.addEventListener('click', () => setUiMode('advanced'));
}

/* ------------------------------ estado -------------------------------- */
function renderStatus(s) {
  if (!s) return;

  setDot('statusDot', s.disabled ? 'red' : (s.running && s.listening ? 'green' : (s.running ? 'amber' : 'red')));
  setText('statusHeadline', s.disabled ? tr('status.disabled') : (s.running ? tr('status.running') : tr('status.stopped')));

  setText('pidText', s.running ? String(s.pid) : '—');
  setText('listenText', s.listen || '—');
  setText('listeningText', s.listening ? tr('status.listening') : tr('status.not_listening'));
  setText('versionText', s.version || '—');
  setText('serverText', s.server || '—');
  setText('backendText', s.backend === 'none' ? tr('status.no_firewall') : (s.backend || '—'));

  const redirActive = s.redirect === 'activa';
  setDot('redirectDot', redirActive ? 'green' : 'amber');
  setText('redirectText', redirActive ? tr('status.redirect_on') : tr('status.redirect_off'));

  const bootCb = $('bootRedirectToggle');
  if (bootCb && document.activeElement !== bootCb) bootCb.checked = (s.boot_redirect === 1 || s.boot_redirect === '1');

  const v6sel = $('ipv6ModeSelect');
  if (v6sel && document.activeElement !== v6sel) v6sel.value = s.ipv6_mode || 'redirect';

  const banner = $('disabledBanner');
  if (banner) banner.classList.toggle('hidden', !s.disabled);
  setText('disabledBannerText', tr('status.disabled_banner'));

  const binWarn = $('binMissingBanner');
  if (binWarn) binWarn.classList.toggle('hidden', !!s.binary_present);
}

async function refreshStatus() {
  if (!DCM.available()) return;
  const r = await DCM.run('status');
  if (r.errno !== 0) {
    toast(r.stderr || tr('status.timeout'), 'error');
    return;
  }
  try {
    renderStatus(JSON.parse(r.stdout));
  } catch (e) {
    // JSON parcial o de un binario "fake"/incompatible: no rompemos la UI.
    console.warn('status --json no parseable:', e, r.stdout);
  }
}

function startPolling() {
  stopPolling();
  refreshStatus();
  pollTimer = setInterval(refreshStatus, POLL_MS);
}
function stopPolling() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
}
document.addEventListener('visibilitychange', () => {
  if (document.hidden) stopPolling(); else startPolling();
});

/* ------------------------- acciones de servicio ------------------------ */
async function doSimple(action, okMsg) {
  if (busy) return;
  setBusy(true);
  try {
    const r = await DCM.run(action);
    if (r.errno === 0) { toast(okMsg, 'ok'); } else { toast((r.stderr || r.stdout || tr('common.fail')).trim(), 'error'); }
    await refreshStatus();
  } finally {
    setBusy(false);
  }
}

function wireServiceButtons() {
  const bStart = $('btnStart'); if (bStart) bStart.addEventListener('click', () => doSimple('start', 'Servicio iniciado.'));
  const bStop = $('btnStop'); if (bStop) bStop.addEventListener('click', () => doSimple('stop', 'Servicio detenido.'));
  const bRestart = $('btnRestart'); if (bRestart) bRestart.addEventListener('click', () => doSimple('restart', 'Servicio reiniciado.'));
  const bEnable = $('btnEnable');
  if (bEnable) bEnable.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    try {
      // Paso 1: sacar el flag 'disable'. Paso 2: arrancar el servicio.
      // (Antes este boton solo llamaba a 'start', que con el flag puesto
      // SIEMPRE fallaba con "DESHABILITADO"; nunca sacaba el flag.)
      const rEnable = await DCM.run('enable');
      if (rEnable.errno !== 0) {
        toast((rEnable.stderr || tr('ui.enable.fail')).trim(), 'error');
        return;
      }
      const rStart = await DCM.run('start');
      toast(rStart.errno === 0 ? tr('ui.enable.done') : (rStart.stderr || tr('ui.start.fail')).trim(),
            rStart.errno === 0 ? 'ok' : 'error');
    } finally {
      await refreshStatus();
      setBusy(false);
    }
  });
}

/* ------------------------------ test DNS -------------------------------- */
function renderTestDnsOutput(text) {
  const box = $('testDnsOutput');
  if (!box) return;
  box.innerHTML = '';
  const lines = String(text || '').split('\n').filter((l) => l.trim().length);
  if (!lines.length) { box.textContent = tr('ui.output.empty'); return; }
  for (const line of lines) {
    const row = document.createElement('div');
    row.className = 'diag-line';
    if (/^\[\d\/4\]/.test(line)) {
      row.classList.add(line.includes('OMITIDA') ? 'diag-warn' : 'diag-ok');
    } else if (/^FALLO|^RESULTADO: DNS OK/.test(line)) {
      row.classList.add(line.startsWith('FALLO') ? 'diag-fail' : 'diag-ok');
    }
    row.textContent = line;
    box.appendChild(row);
  }
}

function wireTestDns() {
  const btn = $('btnTestDns');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    setText('testDnsOutput', tr('ui.dns.testing'));
    try {
      const r = await DCM.run('testDns');
      renderTestDnsOutput((r.stdout || '') + (r.stderr ? '\n' + r.stderr : ''));
      toast(r.errno === 0 ? tr('ui.dns.test.ok') : tr('ui.dns.test.fail'), r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });
}

/* ------------------------------ servidores ------------------------------ */
function wireProviders() {
  document.querySelectorAll('[data-provider]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      if (busy) return;
      setBusy(true);
      try {
        const r = await DCM.runProvider(btn.getAttribute('data-provider'));
        toast(r.errno === 0 ? tr('ui.dns.provider.done') : (r.stderr || tr('common.fail')).trim(),
              r.errno === 0 ? 'ok' : 'error');
        await refreshStatus();
      } finally {
        setBusy(false);
      }
    });
  });

  const idInput = $('nextdnsId');
  const idError = $('nextdnsError');
  const applyBtn = $('btnNextdnsApply');

  function validateLive() {
    if (!idInput) return;
    const v = DCMValidate.nextdnsId(idInput.value);
    idInput.classList.toggle('field-invalid', !v.ok && idInput.value.trim().length > 0);
    if (idError) idError.textContent = idInput.value.trim().length ? v.msg : '';
  }
  if (idInput) idInput.addEventListener('input', validateLive);

  if (applyBtn) applyBtn.addEventListener('click', async () => {
    if (busy || !idInput) return;
    const v = DCMValidate.nextdnsId(idInput.value);
    if (!v.ok) { validateLive(); toast(v.msg, 'error'); return; }
    setBusy(true);
    try {
      const r = await DCM.runNextdns(idInput.value.trim());
      toast(r.errno === 0 ? tr('ui.dns.nextdns.done') : (r.stderr || tr('common.fail')).trim(),
            r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });
}

/* ------------------------------ redireccion ------------------------------ */
function wireRedirect() {
  const bApply = $('btnRedirectApply');
  if (bApply) bApply.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(tr('status.confirm_redirect'))) return;
    setBusy(true);
    try {
      const r = await DCM.run('redirectApply');
      toast(r.errno === 0 ? tr('ui.redirect.done') : (r.stderr || r.stdout || tr('common.fail')).trim(),
            r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });

  const bRemove = $('btnRedirectRemove');
  if (bRemove) bRemove.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(tr('status.confirm_remove'))) return;
    setBusy(true);
    try {
      const r = await DCM.run('redirectRemove');
      toast(r.errno === 0 ? tr('ui.redirect.removed') : (r.stderr || tr('common.fail')).trim(), r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });

  const bootCb = $('bootRedirectToggle');
  if (bootCb) bootCb.addEventListener('change', async (ev) => {
    if (busy) return;
    setBusy(true);
    try {
      const r = await DCM.run(ev.target.checked ? 'bootRedirOn' : 'bootRedirOff');
      if (r.errno !== 0) { ev.target.checked = !ev.target.checked; toast((r.stderr || tr('common.fail')).trim(), 'error'); }
      else { toast(tr('ui.preference.saved'), 'ok'); }
    } finally {
      setBusy(false);
    }
  });

  const v6sel = $('ipv6ModeSelect');
  if (v6sel) v6sel.addEventListener('change', async (ev) => {
    if (busy) return;
    setBusy(true);
    try {
      const r = await DCM.runIpv6Mode(ev.target.value);
      toast(r.errno === 0 ? tr('ui.ipv6.updated') : (r.stderr || tr('common.fail')).trim(),
            r.errno === 0 ? 'ok' : 'error');
    } finally {
      setBusy(false);
    }
  });
}

/* ------------------------------ private dns ------------------------------ */
function wirePrivateDns() {
  const btn = $('btnPrivateDns');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    setText('privateDnsText', tr('ui.checking'));
    try {
      const r = await DCM.run('privateDns');
      setText('privateDnsText', (r.stdout || r.stderr || tr('ui.no_data.brackets')).trim());
    } finally {
      setBusy(false);
    }
  });
}

/* -------------------------------- logs ---------------------------------- */
function wireLogs() {
  const bLogs = $('btnLogs');
  if (bLogs) bLogs.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    setText('logsOutput', tr('ui.loading'));
    try {
      const r = await DCM.run('logs');
      setText('logsOutput', (r.stdout || r.stderr || tr('ui.logs.empty')).trim());
    } finally {
      setBusy(false);
    }
  });

  const bClear = $('btnLogsClear');
  if (bClear) bClear.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(tr('status.confirm_logs'))) return;
    setBusy(true);
    try {
      const r = await DCM.run('logsClear');
      toast(r.errno === 0 ? tr('ui.logs.cleared') : (r.stderr || tr('common.fail')).trim(), r.errno === 0 ? 'ok' : 'error');
      setText('logsOutput', '');
    } finally {
      setBusy(false);
    }
  });
}

/* ------------------------------ emergencia -------------------------------- */
function wirePanic() {
  const btn = $('btnPanic');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(tr('status.confirm_panic'))) return;
    setBusy(true);
    try {
      const r = await DCM.run('panic');
      toast(r.errno === 0 ? tr('ui.panic.done') : (r.stderr || tr('common.fail')).trim(),
            r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });
}

/* ======================================================================== *
 *  SEGURIDAD v0.2.0 — proteccion, perfiles, listas, allowlist, excepciones,
 *  auditoria de fugas, eventos, privacidad. Todo textContent (sin innerHTML
 *  con datos); botones bloqueados via setBusy durante cada operacion.
 * ======================================================================== */
const SEC_STR = {
  catSub: {
    malware: 'Sitios que distribuyen software malicioso.',
    phishing: 'Paginas que roban credenciales haciendose pasar por otras.',
    scams: 'Dominios de estafas conocidas.',
    trackers: 'Rastreadores de actividad (puede afectar analitica).',
    ads: 'Publicidad (puede romper apps o paginas).',
    cryptomining: 'Mineria de criptomonedas en el navegador.'
  },
  confirmProfileStrict: 'El perfil Estricto activa fail-closed: si DNSCrypt deja de funcionar, ' +
    'podes quedarte sin DNS hasta restaurar la red (PANIC siempre la restaura). ¿Aplicar Estricto?',
  confirmEventsClear: '¿Borrar todo el historial de eventos bloqueados?',
  confirmAllowClear: '¿Vaciar la allowlist por completo?'
};

/* Muestra un error de backend concreto: comando + codigo + mensaje. */
function backendError(res, cmdLabel) {
  const msg = (res.stderr || res.stdout || '').trim() || 'sin detalle';
  return (cmdLabel ? cmdLabel + ': ' : '') + msg + ' (rc=' + res.errno + ')';
}

function safeParse(txt) {
  try { return JSON.parse(txt); } catch (_) { return null; }
}

/* ------------------------------ proteccion ------------------------------ */
async function refreshProtection() {
  const box = $('protectionList');
  if (!box) return;
  const r = await DCM.run('protectionStatus');
  if (r.errno !== 0) { setText('protectionList', backendError(r, 'protection status')); return; }
  const data = safeParse(r.stdout);
  if (!data) { setText('protectionList', tr('ui.backend.invalid')); return; }
  box.textContent = '';
  DCM.CATEGORIES.forEach((cat) => {
    const info = data[cat] || {};
    const row = document.createElement('div');
    row.className = 'toggle-row';
    const left = document.createElement('div');
    const name = document.createElement('div');
    name.className = 'tl-name'; name.textContent = cat;
    const sub = document.createElement('div');
    sub.className = 'tl-sub';
    const dom = (info.domains != null ? info.domains : 0);
    const st = info.status || 'sin_lista';
    sub.textContent = (SEC_STR.catSub[cat] ? tr('protection.desc.' + cat) : '') + ' · ' + dom + ' dominios (' + st + ')';
    left.appendChild(name); left.appendChild(sub);
    const lab = document.createElement('label');
    lab.className = 'switch';
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = !!info.enabled;
    cb.addEventListener('change', async () => {
      if (busy) return;
      setBusy(true);
      try {
        const rr = await DCM.runProtection(cat, cb.checked);
        if (rr.errno !== 0) { cb.checked = !cb.checked; toast(backendError(rr, 'protection'), 'error'); }
        else { toast(trf(cb.checked ? 'ui.protection.enabled' : 'ui.protection.disabled', {category: cat}), 'ok'); }
        await refreshProtection();
      } finally { setBusy(false); }
    });
    lab.appendChild(cb);
    row.appendChild(left); row.appendChild(lab);
    box.appendChild(row);
  });
  setText('protectionTotal', trf('ui.protection.total', {n: data.active_total != null ? data.active_total : 0}));
}

/* ------------------------------- perfiles ------------------------------- */
async function refreshProfile() {
  const r = await DCM.run('profileStatus');
  if (r.errno === 0) {
    const d = safeParse(r.stdout);
    if (d && d.profile) setText('profileCurrent', d.profile);
  }
}
function wireProfiles() {
  document.querySelectorAll('[data-profile]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      if (busy) return;
      const prof = btn.getAttribute('data-profile');
      if (prof === 'strict' && !confirm(tr('ui.strict.confirm'))) return;
      setBusy(true);
      setText('profilePlan', tr('ui.profile.applying'));
      try {
        const action = prof === 'balanced' ? 'profileBalanced' : (prof === 'strict' ? 'profileStrict' : 'profilePrivacy');
        const r = await DCM.run(action);
        setText('profilePlan', (r.stdout || r.stderr || '').trim());
        toast(r.errno === 0 ? trf('ui.profile.applied', {profile: prof}) : backendError(r, 'perfil'), r.errno === 0 ? 'ok' : 'error');
        await Promise.all([refreshProfile(), refreshProtection(), refreshStatus()]);
      } finally { setBusy(false); }
    });
  });
}

/* -------------------------------- listas -------------------------------- */
function renderBlocklists(data) {
  const box = $('blocklistsTable');
  if (!box) return;
  box.textContent = '';
  if (!data) { box.textContent = tr('common.no_data'); return; }
  DCM.CATEGORIES.forEach((cat) => {
    const info = data[cat]; if (!info) return;
    const row = document.createElement('div');
    row.className = 'event-row';
    const t = document.createElement('div');
    t.textContent = cat + ' — ' + (info.enabled ? 'ON' : 'OFF') + ' · ' +
      (info.domains != null ? info.domains : 0) + ' dominios · ' + (info.status || 'sin_lista') +
      (info.updated ? ' · ' + info.updated : '');
    row.appendChild(t);
    if (info.enabled) {
      const acts = document.createElement('div');
      acts.className = 'event-actions';
      const up = document.createElement('button');
      up.textContent = tr('ui.blocklist.refresh');
      up.addEventListener('click', async () => {
        if (busy) return; setBusy(true);
        try {
          const rr = await DCM.runBlocklistUpdateCat(cat);
          toast(rr.errno === 0 ? trf('ui.blocklist.category.updated', {category: cat}) : backendError(rr, 'update ' + cat), rr.errno === 0 ? 'ok' : 'error');
          await refreshBlocklists();
        } finally { setBusy(false); }
      });
      const rb = document.createElement('button');
      rb.textContent = tr('ui.blocklist.rollback');
      rb.addEventListener('click', async () => {
        if (busy) return; setBusy(true);
        try {
          const rr = await DCM.runBlocklistRollbackCat(cat);
          toast(rr.errno === 0 ? trf('ui.blocklist.category.reverted', {category: cat}) : backendError(rr, 'rollback ' + cat), rr.errno === 0 ? 'ok' : 'error');
          await refreshBlocklists();
        } finally { setBusy(false); }
      });
      acts.appendChild(up); acts.appendChild(rb);
      row.appendChild(acts);
    }
    box.appendChild(row);
  });
}
async function refreshBlocklists() {
  const r = await DCM.run('blocklistsStatus');
  if (r.errno !== 0) { setText('blocklistsTable', backendError(r, 'blocklists status')); return; }
  renderBlocklists(safeParse(r.stdout));
}
function wireBlocklists() {
  const up = $('btnBlocklistsUpdate');
  if (up) up.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('blocklistsTable', tr('ui.blocklist.downloading'));
    try {
      const r = await DCM.run('blocklistsUpdate');
      toast(r.errno === 0 ? tr('ui.blocklist.updated') : backendError(r, 'update'), r.errno === 0 ? 'ok' : 'error');
      await refreshBlocklists();
      await refreshProtection();
    } finally { setBusy(false); }
  });
  const val = $('btnBlocklistsValidate');
  if (val) val.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    try {
      const r = await DCM.run('blocklistsValidate');
      setText('blocklistsTable', (r.stdout || r.stderr || '').trim());
      toast(r.errno === 0 ? tr('ui.blocklist.valid') : tr('ui.blocklist.invalid'), r.errno === 0 ? 'ok' : 'error');
    } finally { setBusy(false); }
  });
}

/* ------------------------------ allowlist ------------------------------- */
async function refreshAllowlist() {
  const r = await DCM.run('allowlistList');
  if (r.errno !== 0) { setText('allowList', backendError(r, 'allowlist list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('allowList', tr('common.no_data')); return; }
  const box = $('allowList');
  box.textContent = '';
  if (!d.domains || !d.domains.length) { box.textContent = tr('ui.allow.empty'); return; }
  d.domains.forEach((dom) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const name = document.createElement('span');
    name.textContent = dom + '  ';
    const del = document.createElement('button');
    del.textContent = tr('ui.allow.remove');
    del.className = 'small danger';
    del.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runAllowlistRemove(dom);
        toast(rr.errno === 0 ? trf('ui.allow.removed', {domain: dom}) : backendError(rr, 'remove'), rr.errno === 0 ? 'ok' : 'error');
        await refreshAllowlist();
      } finally { setBusy(false); }
    });
    row.appendChild(name); row.appendChild(del);
    box.appendChild(row);
  });
  setText('allowError', trf('ui.allow.count', {n: d.count}));
}
function wireAllowlist() {
  const inp = $('allowInput');
  const err = $('allowError');
  function live() {
    if (!inp) return;
    if (!inp.value.trim().length) { if (err) err.textContent = ''; inp.classList.remove('field-invalid'); return; }
    const v = DCMValidate.isValidDomain(inp.value);
    inp.classList.toggle('field-invalid', !v.ok);
    if (err) err.textContent = v.ok ? '' : v.msg;
  }
  if (inp) inp.addEventListener('input', live);

  const add = $('btnAllowAdd');
  if (add) add.addEventListener('click', async () => {
    if (busy || !inp) return;
    const v = DCMValidate.isValidDomain(inp.value);
    if (!v.ok) { live(); toast(v.msg, 'error'); return; }
    setBusy(true);
    try {
      const r = await DCM.runAllowlistAdd(inp.value);
      if (r.errno === 0) { toast(tr('ui.allow.added'), 'ok'); inp.value = ''; await refreshAllowlist(); }
      else { toast(backendError(r, 'allowlist add'), 'error'); }
    } finally { setBusy(false); }
  });

  const search = $('btnAllowSearch');
  if (search) search.addEventListener('click', async () => {
    if (busy || !inp) return;
    setBusy(true);
    try {
      const r = await DCM.runAllowlistSearch(inp.value);
      const out = (r.stdout || '').trim();
      setText('allowList', out.length ? out : tr('ui.allow.no_matches'));
    } finally { setBusy(false); }
  });

  const imp = $('btnAllowImport');
  if (imp) imp.addEventListener('click', async () => {
    if (busy) return;
    const ta = $('allowImport');
    if (!ta) return;
    const lines = ta.value.split('\n').map((x) => x.trim().toLowerCase()).filter((x) => x.length && x[0] !== '#');
    if (!lines.length) { toast(tr('ui.allow.no_import'), 'error'); return; }
    if (lines.length > 200) { toast(tr('ui.allow.import_limit'), 'error'); return; }
    setBusy(true);
    let added = 0, dup = 0, bad = 0;
    try {
      for (const dom of lines) {
        const v = DCMValidate.isValidDomain(dom);
        if (!v.ok) { bad++; continue; }
        const r = await DCM.runAllowlistAdd(dom);
        if (r.errno === 0) {
          if ((r.stdout || '').indexOf('Ya estaba') >= 0) dup++; else added++;
        } else { bad++; }
      }
      toast(trf('ui.allow.import.result', {added, dup, bad}), bad ? 'error' : 'ok');
      ta.value = '';
      await refreshAllowlist();
    } finally { setBusy(false); }
  });

  const exp = $('btnAllowExport');
  if (exp) exp.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    try {
      const r = await DCM.run('allowlistList');
      const d = safeParse(r.stdout);
      const text = d && d.domains ? d.domains.join('\n') : '';
      toast(trf('ui.allow.export.count', {n: d ? d.count : 0}), 'ok');
      setText('allowList', text || tr('ui.allow.empty_export'));
    } finally { setBusy(false); }
  });
}

/* --------------------------- excepciones temp --------------------------- */
async function refreshTempAllow() {
  const r = await DCM.run('tempAllowList');
  if (r.errno !== 0) { setText('tempList', backendError(r, 'temporary-allow list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('tempList', tr('common.no_data')); return; }
  const box = $('tempList');
  box.textContent = '';
  if (!d.exceptions || !d.exceptions.length) { box.textContent = tr('ui.temp.empty'); return; }
  d.exceptions.forEach((ex) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const rem = (ex.remaining === 'boot') ? 'hasta reiniciar' : ('quedan ' + ex.remaining + 's');
    const t = document.createElement('div');
    t.textContent = ex.domain + ' — ' + rem + ' · ' + (ex.reason || '-');
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const rev = document.createElement('button');
    rev.textContent = tr('ui.temp.revoke'); rev.className = 'small danger';
    rev.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runTempAllowRemove(ex.domain);
        toast(rr.errno === 0 ? trf('ui.temp.revoked', {domain: ex.domain}) : backendError(rr, 'revocar'), rr.errno === 0 ? 'ok' : 'error');
        await refreshTempAllow();
      } finally { setBusy(false); }
    });
    acts.appendChild(rev);
    row.appendChild(t); row.appendChild(acts);
    box.appendChild(row);
  });
}
function wireTempAllow() {
  const inp = $('tempInput');
  const err = $('tempError');
  function live() {
    if (!inp) return;
    if (!inp.value.trim().length) { if (err) err.textContent = ''; inp.classList.remove('field-invalid'); return; }
    const v = DCMValidate.isValidDomain(inp.value);
    inp.classList.toggle('field-invalid', !v.ok);
    if (err) err.textContent = v.ok ? '' : v.msg;
  }
  if (inp) inp.addEventListener('input', live);

  const add = $('btnTempAdd');
  if (add) add.addEventListener('click', async () => {
    if (busy || !inp) return;
    const v = DCMValidate.isValidDomain(inp.value);
    if (!v.ok) { live(); toast(v.msg, 'error'); return; }
    const dur = ($('tempDuration') || {}).value || '15m';
    const reason = (($('tempReason') || {}).value || '').trim();
    setBusy(true);
    try {
      const r = await DCM.runTempAllowAdd(inp.value, dur, reason);
      toast(r.errno === 0 ? tr('ui.temp.created') : backendError(r, 'excepcion'), r.errno === 0 ? 'ok' : 'error');
      if (r.errno === 0) { inp.value = ''; const rr = $('tempReason'); if (rr) rr.value = ''; }
      await Promise.all([refreshTempAllow(), refreshAllowlist()]);
    } finally { setBusy(false); }
  });
}

/* ---------------------------- auditoria fugas --------------------------- */
let lastLeakText = '';
async function runLeak() {
  const r = await DCM.run('leakTest');
  const box = $('leakResults');
  if (!box) return;
  if (r.errno !== 0) { setText('leakResults', backendError(r, 'leak-test')); return; }
  const d = safeParse(r.stdout);
  if (!d || !d.checks) { setText('leakResults', tr('ui.leak.invalid')); return; }
  box.textContent = '';
  const lines = [];
  d.checks.forEach((c) => {
    const row = document.createElement('div');
    row.className = 'leak-row';
    const st = document.createElement('span');
    st.className = 'st-' + c.state;
    st.textContent = c.state;
    const nm = document.createElement('span');
    nm.textContent = c.name + ': ';
    const dt = document.createElement('div');
    dt.className = 'tl-sub'; dt.textContent = c.detail;
    row.appendChild(nm); row.appendChild(st); row.appendChild(dt);
    box.appendChild(row);
    lines.push(c.name + '\t' + c.state + '\t' + c.detail);
  });
  lastLeakText = lines.join('\n');
}
function wireLeak() {
  const btn = $('btnLeakTest');
  if (btn) btn.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('leakResults', tr('ui.leak.auditing'));
    try { await runLeak(); } finally { setBusy(false); }
  });
  const cp = $('btnLeakCopy');
  if (cp) cp.addEventListener('click', async () => {
    if (!lastLeakText) { toast(tr('ui.leak.run_first'), 'error'); return; }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(lastLeakText); toast(tr('ui.leak.copied'), 'ok'); }
      else { toast(tr('ui.leak.copy_manual'), 'ok'); }
    } catch (_) { toast(tr('ui.leak.copy_fail'), 'error'); }
  });
}

/* -------------------------------- eventos ------------------------------- */
/* v1.0.0: carga DIFERIDA. Nada de esto corre en el arranque de la WebUI ni al
   entrar a Actividad: solo cuando el usuario expande el panel Eventos.
   Al cerrar se desmonta la lista del DOM y las respuestas tardias se ignoran
   (token de generacion). Se renderizan como maximo EV.page filas. */
var EV = { open: false, gen: 0, page: 20, shown: 20 };

async function refreshEvents() {
  if (!EV.open) return;                       // cerrado -> no se consulta nada
  const myGen = EV.gen;
  const r = await DCM.run('eventsList');
  if (myGen !== EV.gen || !EV.open) return;   // cerrado mientras cargaba -> ignorar
  const box = $('eventsList');
  if (!box) return;
  if (r.errno !== 0) { setText('eventsList', backendError(r, 'events list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('eventsList', tr('common.no_data')); return; }
  const filterEl = $('eventsFilter');
  const filter = filterEl ? filterEl.value.trim().toLowerCase() : '';
  box.textContent = '';
  const more = $('eventsMore'); if (more) more.textContent = '';
  let evs = d.events || [];
  if (filter) evs = evs.filter((e) => (e.domain || '').indexOf(filter) >= 0);
  if (!evs.length) { box.textContent = tr('ui.events.none'); evSummary(0); return; }
  const total = evs.length;
  evSummary(total);
  const slice = evs.slice(0, EV.shown);
  if (total > slice.length && more) {         // paginacion: no cientos de filas juntas
    const b = document.createElement('button');
    b.className = 'small';
    b.textContent = I18N.t('ev.more') + ' (' + slice.length + '/' + total + ')';
    b.addEventListener('click', () => { if (busy) return; EV.shown += EV.page; refreshEvents(); });
    more.appendChild(b);
  }
  slice.forEach((e) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const head = document.createElement('div');
    head.textContent = (e.time || '') + '  ' + (e.domain || '');
    const meta = document.createElement('div');
    meta.className = 'tl-sub';
    meta.textContent = 'categoria: ' + (e.category || '-') + ' · regla: ' + (e.rule || '-') +
      (e.list ? ' · lista: ' + e.list : '') + (e.allowed_now ? ' · permitido ahora' : '');
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    [['5m', 'Permitir 5m'], ['1h', 'Permitir 1h']].forEach(([dur, label]) => {
      const b = document.createElement('button');
      b.textContent = label;
      b.addEventListener('click', async () => {
        if (busy) return; setBusy(true);
        try {
          const rr = await DCM.runTempAllowAdd(e.domain, dur);
          toast(rr.errno === 0 ? label + ' → ' + e.domain : backendError(rr, 'permitir'), rr.errno === 0 ? 'ok' : 'error');
          await refreshTempAllow();
        } finally { setBusy(false); }
      });
      acts.appendChild(b);
    });
    const al = document.createElement('button');
    al.textContent = tr('ui.events.allow');
    al.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runAllowlistAdd(e.domain);
        toast(rr.errno === 0 ? trf('ui.events.allowed', {domain: e.domain}) : backendError(rr, 'allowlist'), rr.errno === 0 ? 'ok' : 'error');
        await refreshAllowlist();
      } finally { setBusy(false); }
    });
    const cp = document.createElement('button');
    cp.textContent = tr('ui.events.copy');
    cp.addEventListener('click', async () => {
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(e.domain); toast(tr('ui.events.copied'), 'ok'); }
        else { toast(e.domain, 'ok'); }
      } catch (_) { toast(e.domain, 'ok'); }
    });
    acts.appendChild(al); acts.appendChild(cp);
    row.appendChild(head); row.appendChild(meta); row.appendChild(acts);
    box.appendChild(row);
  });
}
function evSummary(n) {
  const el2 = $('evSummary'); if (!el2) return;
  el2.textContent = (typeof n === 'number') ? I18N.t('ev.count').replace('{n}', String(n)) : I18N.t('ev.tap');
}
async function evOpen() {
  if (EV.open) return;
  EV.open = true; EV.gen++; EV.shown = EV.page;
  const body = $('evBody'); if (body) body.hidden = false;
  const tg = $('evToggle'); if (tg) tg.setAttribute('aria-expanded', 'true');
  const ch = $('evChevron'); if (ch) ch.textContent = '\u25B2';
  setText('eventsList', I18N.t('common.loading'));
  await refreshEvents();                      // UNA sola consulta
}
function evClose() {
  EV.gen++; EV.open = false;                  // invalida respuestas en vuelo
  const body = $('evBody'); if (body) body.hidden = true;
  const list = $('eventsList'); if (list) list.textContent = '';   // desmonta filas del DOM
  const more = $('eventsMore'); if (more) more.textContent = '';
  const st = $('eventsStats'); if (st) st.textContent = '';
  const tg = $('evToggle'); if (tg) tg.setAttribute('aria-expanded', 'false');
  const ch = $('evChevron'); if (ch) ch.textContent = '\u25BC';
  evSummary();
}
function wireEventsToggle() {
  const tg = $('evToggle'); if (!tg || tg._wired) return;
  tg._wired = true;
  tg.addEventListener('click', () => { if (EV.open) evClose(); else evOpen(); });
}

function wireEvents() {
  wireEventsToggle();
  const rf = $('btnEventsRefresh');
  if (rf) rf.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('eventsList', tr('ui.loading'));
    try { await refreshEvents(); } finally { setBusy(false); }
  });
  const filt = $('eventsFilter');
  if (filt) filt.addEventListener('input', () => { if (!busy) refreshEvents(); });
  const stats = $('btnEventsStats');
  if (stats) stats.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    try {
      const r = await DCM.run('eventsStats');
      const d = safeParse(r.stdout);
      if (d) {
        setText('eventsStats', 'Total ' + d.total + ' · malware ' + d.malware + ' · phishing ' + d.phishing +
          ' · estafas ' + d.scams + ' · rastreadores ' + d.trackers + ' · ads ' + d.ads +
          ' · cripto ' + d.cryptomining + ' · top: ' + (d.top_domain || '-') +
          ' · listas: ' + (d.lists_last_update || '-'));
      } else { setText('eventsStats', (r.stdout || r.stderr || '').trim()); }
    } finally { setBusy(false); }
  });
  const clr = $('btnEventsClear');
  if (clr) clr.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(tr('ui.events.confirm_clear'))) return;
    setBusy(true);
    try {
      const r = await DCM.run('eventsClear');
      toast(r.errno === 0 ? tr('ui.events.cleared') : backendError(r, 'events clear'), r.errno === 0 ? 'ok' : 'error');
      setText('eventsList', tr('ui.events.none'));
      setText('eventsStats', '');
    } finally { setBusy(false); }
  });
  const exp = $('btnEventsExport');
  if (exp) exp.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    try {
      const r = await DCM.run('eventsList');
      const d = safeParse(r.stdout);
      const text = d && d.events ? d.events.map((e) => [e.time, e.domain, e.category, e.rule].join('\t')).join('\n') : '';
      setText('eventsList', text || tr('ui.events.none'));
      toast(tr('ui.events.exported'), 'ok');
    } finally { setBusy(false); }
  });
}

/* ---------------------------- privacidad -------------------------------- */
function applyHistFromStatus(s) {
  if (!s) return;
  const hm = $('histModeSelect');
  if (hm && document.activeElement !== hm && s.hist_mode) hm.value = s.hist_mode;
  const hd = $('histDaysSelect');
  if (hd && document.activeElement !== hd && s.hist_days) hd.value = String(s.hist_days);
  const hx = $('histMaxInput');
  if (hx && document.activeElement !== hx && s.hist_max) hx.value = String(s.hist_max);
}
function wirePrivacy() {
  const btn = $('btnHistApply');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    try {
      const mode = ($('histModeSelect') || {}).value || 'blocked';
      const days = ($('histDaysSelect') || {}).value || '3';
      let max = parseInt(($('histMaxInput') || {}).value, 10);
      if (!(max >= 50 && max <= 10000)) { toast(tr('ui.history.max_error'), 'error'); setBusy(false); return; }
      // Cada set-flag es una cadena FIJA (clave conocida + valor de lista blanca).
      const CLIcmd = DCM.cli();
      const seq = [
        CLIcmd + ' set-flag hist_mode ' + mode,
        CLIcmd + ' set-flag hist_days ' + days,
        CLIcmd + ' set-flag hist_max ' + max
      ];
      let okAll = true, lastErr = '';
      for (const cmd of seq) {
        const r = await execRawExternal(cmd);
        if (r.errno !== 0) { okAll = false; lastErr = backendError(r); break; }
      }
      toast(okAll ? tr('ui.history.saved') : lastErr, okAll ? 'ok' : 'error');
      await refreshStatus();
    } finally { setBusy(false); }
  });
}
/* Ejecuta una de las cadenas set-flag FIJAS de privacidad (clave y valor ya
 * restringidos a listas blancas de la UI; la CLI revalida ambos). */
function execRawExternal(cmd) {
  return new Promise((resolve) => {
    if (!DCM.available()) { resolve({ errno: -1, stdout: '', stderr: 'API ksu no disponible.' }); return; }
    const cb = '__dcm_hist_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    let done = false;
    window[cb] = (errno, stdout, stderr) => {
      if (done) return; done = true;
      try { delete window[cb]; } catch (_) { window[cb] = undefined; }
      resolve({ errno: Number(errno), stdout: String(stdout || ''), stderr: String(stderr || '') });
    };
    setTimeout(() => { if (!done) { done = true; try { delete window[cb]; } catch (_) {} resolve({ errno: -1, stdout: '', stderr: 'Timeout.' }); } }, 30000);
    try { window.ksu.exec(cmd, JSON.stringify({}), cb); }
    catch (e) { if (!done) { done = true; resolve({ errno: -1, stdout: '', stderr: String(e) }); } }
  });
}

/* Extiende renderStatus para reflejar privacidad sin duplicar logica. */
const _origRenderStatus = renderStatus;
renderStatus = function (s) {
  _origRenderStatus(s);
  applyHistFromStatus(s);
};

/* Carga inicial de todas las secciones de seguridad. */
async function initSecurity() {
  wireProfiles();
  wireBlocklists();
  wireAllowlist();
  wireTempAllow();
  wireLeak();
  wireEvents();
  wirePrivacy();
  await refreshProtection();
  await refreshProfile();
  await refreshBlocklists();
  await refreshAllowlist();
  await refreshTempAllow();
  /* v1.0.0: los eventos NO se cargan en el arranque (panel lazy). */
}

/* ------------------------------------------------------------------------ */
/* ======================================================================== *
 *  RC2 — Catalogo, fuentes personalizadas, BindHosts, controles de servicio.
 *  Paginacion del lado cliente (no se renderizan miles de tarjetas de una).
 * ======================================================================== */
let catCache = [];        // metadata del catalogo; los DOM de listas se crean por acordeon
// Todos los encabezados visibles, filas desmontadas hasta abrir una categoría.
let catOpenGroup = '';
let catPageByGroup = Object.create(null);
let catDownloadPollTimer = null;
let catDownloadPollInFlight = false;
let catDownloadRefreshJobId = '';
let catLastDownloadInfo = null;
let catLoaded = false;
let catLoading = null;
let catAllLoading = null;
let catCliReady = false;
let catView = 'all';
let catGroupCounts = Object.create(null);
let catGroupActive = Object.create(null);
const catLoadedGroups = new Set();
const catGroupLoading = Object.create(null);
const catSelection = new Set();
const catDisableSelection = new Set();
const catFilterGroups = new Set();
const catFilterSubgroups = new Set();
const catFilterPacks = new Set();
let catFilterDraftGroups = new Set();
let catFilterDraftSubgroups = new Set();
let catFilterDraftPacks = new Set();
const CAT_PAGE_SIZE = 15;
const CAT_GROUP_DEFS = [
  { key: 'Security', labelKey: 'cat.group.security', descriptionKey: 'cat.group.security.desc' },
  { key: 'Privacy', labelKey: 'cat.group.privacy', descriptionKey: 'cat.group.privacy.desc' },
  { key: 'ParentalControl', labelKey: 'cat.group.parental', descriptionKey: 'cat.group.parental.desc' },
  { key: 'dcm', labelKey: 'cat.group.dcm', descriptionKey: 'cat.group.dcm.desc' },
  { key: 'rethink_unassigned', labelKey: 'cat.group.unassigned', descriptionKey: 'cat.group.unassigned.desc' }
];

function catCategories(e) {
  return String(e.categories || '').split(',').map((c) => c.trim().toLowerCase()).filter(Boolean);
}
function catGroupKey(e) {
  if (e.source_name) return e.source_group || 'rethink_unassigned';
  return 'dcm';
}
function catFacetTokens(value) {
  const values = Array.isArray(value) ? value : String(value || '').split(/[|,]/);
  return values.map((value) => String(value || '').trim()).filter(Boolean);
}
function catPacks(e) { return catFacetTokens(e && e.source_packs); }
function catSubgroups(e) { return catFacetTokens(e && e.source_subgroup); }
function catNormalizedSet(set) { return new Set(Array.from(set).map((value) => String(value).toLowerCase())); }
function catFiltersActive() {
  return catFilterGroups.size > 0 || catFilterSubgroups.size > 0 || catFilterPacks.size > 0;
}
function catIsNarrowed() {
  return catFiltersActive() || catView === 'selected' || Boolean((($('catSearch') || {}).value || '').trim());
}
function catEntryMatchesFilters(e) {
  const groups = catNormalizedSet(catFilterGroups);
  const subgroups = catNormalizedSet(catFilterSubgroups);
  const packs = catNormalizedSet(catFilterPacks);
  if (groups.size && !groups.has(catGroupKey(e).toLowerCase())) return false;
  if (subgroups.size && !catSubgroups(e).some((value) => subgroups.has(value.toLowerCase()))) return false;
  if (packs.size && !catPacks(e).some((value) => packs.has(value.toLowerCase()))) return false;
  return true;
}
function catDisplayName(e) { return e.source_name || e.name; }
function catCanAdd(e) {
  return !e.enabled && !e.activation_blocked && !e.archived &&
    e.upstream_status !== 'broken' && e.upstream_status !== 'archived';
}
function catStateLabel(e) {
  const failed = e.runtime_status === 'download_failed' || e.runtime_status === 'validation_failed';
  const hasCache = Number(e.cache_domains || 0) > 0;
  if (failed) return hasCache ? (e.enabled ? tr('cat.state.cache_active') : tr('cat.state.cache_error')) : tr('cat.state.no_cache');
  if (e.enabled) return tr('cat.state.active');
  if (e.upstream_status === 'broken') return tr('cat.state.broken');
  if (e.archived || e.upstream_status === 'archived') return tr('cat.state.archived');
  if (e.activation_blocked) return tr('cat.state.review');
  if (/^(|unknown|license_unknown)$/i.test(String(e.license || ''))) return 'LICENSE_UNKNOWN';
  if (e.runtime_status === 'verified') return tr('cat.state.verified');
  if (e.runtime_status === 'never_checked') return e.upstream_status === 'legacy' ? 'LEGACY' : tr('cat.state.never');
  return e.runtime_status || e.upstream_status || tr('cat.state.unknown');
}

async function catLoad() {
  const r = await DCM.runCatalogGroupsJson();
  if (r.errno !== 0) { setText('catResults', backendError(r, 'catalog groups')); return false; }
  const d = safeParse(r.stdout);
  if (!d || !Array.isArray(d.groups)) { setText('catResults', tr('cat.response.invalid')); return false; }
  catGroupCounts = Object.create(null);
  catGroupActive = Object.create(null);
  d.groups.forEach((g) => {
    if (!g || !g.key) return;
    const key = g.key === 'RethinkUnassigned' ? 'rethink_unassigned' : String(g.key);
    catGroupCounts[key] = Number(g.count || 0);
    catGroupActive[key] = Number(g.active || 0);
  });
  catLoaded = true;
  return true;
}

async function catLoadGroup(groupKey, force) {
  if (!force && catLoadedGroups.has(groupKey)) return true;
  if (!force && catGroupLoading[groupKey]) return catGroupLoading[groupKey];
  const backendKey = groupKey === 'rethink_unassigned' ? 'RethinkUnassigned' : groupKey;
  if (!DCM.runCatalogGroupJson) return false;
  const task = (async () => {
    const r = await DCM.runCatalogGroupJson(backendKey);
    if (r.errno !== 0) {
      setText('catResults', backendError(r, 'catalog list'));
      return false;
    }
    const d = safeParse(r.stdout);
    if (!d || !Array.isArray(d.entries)) {
      setText('catResults', tr('cat.response.invalid'));
      return false;
    }
    catCache = catCache.filter((e) => catGroupKey(e) !== groupKey).concat(d.entries);
    catLoadedGroups.add(groupKey);
    return true;
  })();
  catGroupLoading[groupKey] = task;
  try { return await task; }
  finally { delete catGroupLoading[groupKey]; }
}

async function catReload() {
  catCache = [];
  catLoadedGroups.clear();
  const ok = await catLoad();
  if (!ok) return false;
  if (catOpenGroup) await catLoadGroup(catOpenGroup);
  return true;
}

function catEnsureGroup(groupKey) {
  if (catLoadedGroups.has(groupKey) || catGroupLoading[groupKey]) return;
  catLoadGroup(groupKey).then((ok) => {
    if (ok) catRender();
  });
}

async function catLoadAllGroups() {
  if (catAllLoading) return catAllLoading;
  catAllLoading = (async () => {
    for (const group of CAT_GROUP_DEFS) {
      if ((catGroupCounts[group.key] || 0) > 0 && !(await catLoadGroup(group.key))) return false;
    }
    return true;
  })();
  try {
    const ok = await catAllLoading;
    catRender();
    return ok;
  } finally { catAllLoading = null; }
}

function catFiltered() {
  const q = (($('catSearch') || {}).value || '').trim().toLowerCase();
  return catCache.filter((e) => {
    if (!catEntryMatchesFilters(e)) return false;
    if (catView === 'selected' && !e.enabled && !catSelection.has(e.id)) return false;
    if (q) {
      const hay = [e.id, e.name, e.source_name, e.maintainer, e.source_subgroup,
        e.source_group, e.source_packs, e.source_formats, e.categories].join(' ').toLowerCase();
      if (hay.indexOf(q) < 0) return false;
    }
    return true;
  });
}

function catFacetValues(kind) {
  const map = Object.create(null);
  if (kind === 'group') {
    CAT_GROUP_DEFS.forEach((group) => {
      const count = catCache.filter((e) => catGroupKey(e) === group.key).length;
      if (count) map[group.key.toLowerCase()] = { key: group.key.toLowerCase(), label: tr(group.labelKey), count };
    });
  } else {
    catCache.forEach((e) => {
      const values = kind === 'subgroup' ? catSubgroups(e) : catPacks(e);
      values.forEach((label) => {
        const key = label.toLowerCase();
        if (!map[key]) map[key] = { key, label, count: 0 };
        map[key].count++;
      });
    });
  }
  return Object.keys(map).map((key) => map[key]).sort((a, b) => a.label.localeCompare(b.label));
}

function catRenderFacet(parent, title, values, selection, facetName) {
  if (!values.length) return;
  const section = document.createElement('section'); section.className = 'filter-facet';
  const heading = document.createElement('div'); heading.className = 'filter-facet-title'; heading.textContent = title;
  const chips = document.createElement('div'); chips.className = 'filter-chips';
  values.forEach((value) => {
    const chip = document.createElement('button'); chip.type = 'button'; chip.className = 'filter-chip';
    const selected = selection.has(value.key);
    chip.setAttribute('aria-pressed', selected ? 'true' : 'false');
    chip.setAttribute('data-filter-facet', facetName);
    chip.setAttribute('data-filter-value', value.key);
    const label = document.createElement('span'); label.textContent = value.label;
    const count = document.createElement('span'); count.className = 'filter-chip-count'; count.textContent = String(value.count);
    chip.appendChild(label); chip.appendChild(count);
    chip.addEventListener('click', () => {
      const current = facetName === 'group' ? catFilterDraftGroups :
        (facetName === 'subgroup' ? catFilterDraftSubgroups : catFilterDraftPacks);
      if (current.has(value.key)) current.delete(value.key); else current.add(value.key);
      catRenderFilterOptions();
    });
    chips.appendChild(chip);
  });
  section.appendChild(heading); section.appendChild(chips); parent.appendChild(section);
}

function catRenderFilterOptions() {
  const box = $('catFilterOptions');
  const status = $('catFilterStatus');
  if (!box) return;
  box.textContent = '';
  if (!catLoaded || !catLoadedGroups.size || catAllLoading) {
    if (status && !catAllLoading && !catLoaded) status.textContent = tr('cat.filter.loading');
    return;
  }
  catRenderFacet(box, tr('cat.filter.group'), catFacetValues('group'), catFilterDraftGroups, 'group');
  catRenderFacet(box, tr('cat.filter.subgroup'), catFacetValues('subgroup'), catFilterDraftSubgroups, 'subgroup');
  catRenderFacet(box, tr('cat.filter.tags'), catFacetValues('pack'), catFilterDraftPacks, 'pack');
  if (status) status.textContent = tr('cat.filter.hint');
}

function catOpenFilterSheet() {
  const sheet = $('catFilterSheet');
  const backdrop = $('catFilterBackdrop');
  if (!sheet || !backdrop) return;
  catFilterDraftGroups = new Set(catFilterGroups);
  catFilterDraftSubgroups = new Set(catFilterSubgroups);
  catFilterDraftPacks = new Set(catFilterPacks);
  sheet.hidden = false; sheet.setAttribute('aria-hidden', 'false');
  backdrop.hidden = false;
  if (document.body && document.body.classList) document.body.classList.add('filter-open');
  const opener = $('btnCatFilter');
  if (opener) opener.setAttribute('aria-expanded', 'true');
  const status = $('catFilterStatus');
  if (!catCliReady) {
    if (status) status.textContent = tr('cat.filter.wait');
    return;
  }
  if (status) status.textContent = tr('cat.filter.loading');
  catRenderFilterOptions();
  const loading = catLoaded ? catLoadAllGroups() : catRefreshAndRender().then((ready) => ready ? catLoadAllGroups() : false);
  loading.then((ok) => {
    if (sheet.hidden) return;
    if (ok) catRenderFilterOptions();
    else if (status) status.textContent = tr('cat.filter.fail');
  });
  const close = $('btnCatFilterClose');
  if (close && close.focus) close.focus();
}

function catCloseFilterSheet(restoreFocus) {
  const sheet = $('catFilterSheet');
  const backdrop = $('catFilterBackdrop');
  if (sheet) { sheet.hidden = true; sheet.setAttribute('aria-hidden', 'true'); }
  if (backdrop) backdrop.hidden = true;
  if (document.body && document.body.classList) document.body.classList.remove('filter-open');
  const opener = $('btnCatFilter');
  if (opener) opener.setAttribute('aria-expanded', 'false');
  if (restoreFocus !== false && opener && opener.focus) opener.focus();
}

function catApplyFilterDraft() {
  catFilterGroups.clear(); catFilterDraftGroups.forEach((value) => catFilterGroups.add(value));
  catFilterSubgroups.clear(); catFilterDraftSubgroups.forEach((value) => catFilterSubgroups.add(value));
  catFilterPacks.clear(); catFilterDraftPacks.forEach((value) => catFilterPacks.add(value));
  catPageByGroup = Object.create(null);
  catCloseFilterSheet(true);
  catRender();
}

function catClearFilterDraft() {
  catFilterDraftGroups.clear(); catFilterDraftSubgroups.clear(); catFilterDraftPacks.clear();
  catRenderFilterOptions();
}

function catRenderActiveFilters() {
  const box = $('catActiveFilters');
  const badge = $('catFilterBadge');
  const count = catFilterGroups.size + catFilterSubgroups.size + catFilterPacks.size;
  if (badge) { badge.textContent = String(count); badge.hidden = count === 0; }
  if (!box) return;
  box.textContent = '';
  box.hidden = count === 0 && catView === 'all';
  if (count) {
    const summary = document.createElement('span'); summary.textContent = trf('cat.filter.applied', {n: count}); box.appendChild(summary);
    const clear = document.createElement('button'); clear.type = 'button'; clear.className = 'small'; clear.textContent = tr('cat.filter.clear');
    clear.addEventListener('click', () => {
      catFilterGroups.clear(); catFilterSubgroups.clear(); catFilterPacks.clear();
      catPageByGroup = Object.create(null); catRender();
    });
    box.appendChild(clear);
  } else if (catView === 'selected') {
    const summary = document.createElement('span'); summary.textContent = tr('cat.filter.selected'); box.appendChild(summary);
  }
}

function catSetView(view) {
  catView = view === 'selected' ? 'selected' : 'all';
  const all = $('btnCatAll'); const selected = $('btnCatSelected');
  if (all) all.setAttribute('aria-pressed', catView === 'all' ? 'true' : 'false');
  if (selected) selected.setAttribute('aria-pressed', catView === 'selected' ? 'true' : 'false');
  catPageByGroup = Object.create(null);
  catRender();
  if (catView === 'selected' && catLoaded && !catLoadedGroups.size) catLoadAllGroups();
  else if (catView === 'selected' && catLoadedGroups.size < CAT_GROUP_DEFS.filter((group) => catGroupCounts[group.key] > 0).length) catLoadAllGroups();
}

function catPendingCount() { return catSelection.size + catDisableSelection.size; }
function catEffectiveEnabled(e) {
  if (e.enabled) return !catDisableSelection.has(e.id);
  return catSelection.has(e.id);
}
function catStageGroup(groupKey, wantEnabled) {
  const pool = catIsNarrowed() ? catFiltered() : catCache;
  const entries = pool.filter((e) => catGroupKey(e) === groupKey);
  entries.forEach((e) => {
    if (!e.enabled && !catCanAdd(e)) return;
    if (wantEnabled) {
      if (e.enabled) catDisableSelection.delete(e.id);
      else catSelection.add(e.id);
    } else {
      if (e.enabled) catDisableSelection.add(e.id);
      else catSelection.delete(e.id);
    }
  });
  catRender();
}
async function catToggleGroupSelection(groupKey, wantEnabled) {
  if (busy) return;
  if (!catLoadedGroups.has(groupKey)) {
    setText('catApplyStatus', tr('cat.group.loading'));
    const ok = await catLoadGroup(groupKey);
    if (!ok) return;
  }
  catStageGroup(groupKey, wantEnabled);
}

function catRenderSelectionControls() {
  const n = catPendingCount();
  const add = $('btnCatAddSelected');
  const clear = $('btnCatClearSelection');
  if (add) {
    add.textContent = trf('cat.apply.button', {n});
    add.disabled = busy || n === 0;
  }
  if (clear) clear.disabled = busy || n === 0;
  setText('catSelectionStatus', n ? trf('cat.apply.staged', {n}) :
    tr('cat.apply.none'));
}

function catRenderPager(parent, group, list) {
  const pages = Math.max(1, Math.ceil(list.length / CAT_PAGE_SIZE));
  let page = Number(catPageByGroup[group] || 0);
  if (page >= pages) page = pages - 1;
  catPageByGroup[group] = page;
  if (pages < 2) return;
  const pager = document.createElement('div');
  pager.className = 'btn-row catalog-pager';
  const prev = document.createElement('button');
  prev.type = 'button'; prev.className = 'small'; prev.textContent = '‹'; prev.disabled = page === 0;
  prev.setAttribute('aria-label', tr('cat.pager.prev'));
  prev.addEventListener('click', () => { catPageByGroup[group] = Math.max(0, page - 1); catRender(); });
  const status = document.createElement('span');
  status.className = 'hint'; status.textContent = trf('cat.pager.status', {page: page + 1, pages, n: list.length});
  const next = document.createElement('button');
  next.type = 'button'; next.className = 'small'; next.textContent = '›'; next.disabled = page >= pages - 1;
  next.setAttribute('aria-label', tr('cat.pager.next'));
  next.addEventListener('click', () => { catPageByGroup[group] = Math.min(pages - 1, page + 1); catRender(); });
  pager.appendChild(prev); pager.appendChild(status); pager.appendChild(next); parent.appendChild(pager);
}

function catRenderSource(e) {
  const row = document.createElement('div');
  row.className = 'event-row catalog-source';
  const head = document.createElement('div');
  head.className = 'catalog-source-head';
  const title = document.createElement('span');
  title.className = 'catalog-source-title'; title.textContent = catDisplayName(e);
  const state = document.createElement('span');
  state.className = 'catalog-source-status'; state.textContent = catStateLabel(e);
  head.appendChild(title); head.appendChild(state);

  const pick = document.createElement('label');
  pick.className = 'catalog-source-pick';
  const check = document.createElement('input');
  check.type = 'checkbox'; check.checked = catEffectiveEnabled(e);
  check.disabled = busy || (!e.enabled && !catCanAdd(e));
  check.setAttribute('aria-label', (e.enabled ? tr('cat.source.on') : tr('cat.source.select')) + catDisplayName(e));
  if (!check.disabled) {
    check.addEventListener('change', () => {
      if (busy) return;
      if (e.enabled) {
        if (check.checked) catDisableSelection.delete(e.id);
        else catDisableSelection.add(e.id);
      } else if (check.checked) catSelection.add(e.id);
      else catSelection.delete(e.id);
      catRender();
    });
  }
  pick.appendChild(check);
  const pickText = document.createElement('span');
  const pendingDisable = e.enabled && catDisableSelection.has(e.id);
  const pendingEnable = !e.enabled && catSelection.has(e.id);
  pickText.textContent = pendingDisable ? tr('cat.source.disable_pending') : pendingEnable ? tr('cat.source.enable_pending') :
    e.enabled ? tr('cat.source.active') : catCanAdd(e) ? tr('cat.source.select_label') : tr('cat.source.unavailable');
  pick.appendChild(pickText); head.appendChild(pick); row.appendChild(head);

  const domains = Number(e.cache_domains || e.valid_domains || 0);
  const count = document.createElement('div');
  count.className = 'catalog-source-count';
  count.textContent = Number.isFinite(domains) && domains > 0 ? trf('cat.source.domains', {n: domains.toLocaleString()}) : tr('cat.source.no_count');
  row.appendChild(count);

  const tags = document.createElement('div');
  tags.className = 'catalog-source-tags';
  const tagValues = catSubgroups(e).concat(catPacks(e)).filter(Boolean).filter((value, index, all) =>
    all.findIndex((candidate) => candidate.toLowerCase() === value.toLowerCase()) === index).slice(0, 4);
  tagValues.forEach((value) => {
    const tag = document.createElement('span'); tag.className = 'catalog-source-tag'; tag.textContent = value;
    tags.appendChild(tag);
  });
  if (tagValues.length) row.appendChild(tags);

  const meta = document.createElement('div');
  meta.className = 'tl-sub catalog-source-meta ui-advanced-only';
  const packLabels = catPacks(e);
  const formats = String(e.source_formats || e.format || tr('cat.source.no_format')).replace(/\|/g, ', ');
  const project = e.source_subgroup || e.maintainer || tr('cat.source.no_project');
  const countLabel = Number.isFinite(domains) && domains > 0 ? trf('cat.source.domains', {n: domains.toLocaleString()}) : tr('cat.source.not_downloaded');
  const successTime = Number(e.last_success || 0);
  const successLabel = successTime > 0 ? new Date(successTime * 1000).toLocaleString() : tr('cat.source.no_update');
  const labels = packLabels.length ? packLabels : catCategories(e);
  meta.textContent = project + (labels.length ? ' · ' + labels.join(' · ') : '') +
    trf('cat.source.meta', {formats, count: countLabel, date: successLabel}) +
    (e.recommended ? tr('cat.source.recommended') : '');
  row.appendChild(meta);

  const reasons = [];
  if (/^(|unknown|license_unknown)$/i.test(String(e.license || '')))
    reasons.push(tr('cat.source.license'));
  if (e.activation_blocked) reasons.push(tr('cat.source.review'));
  if (e.upstream_status === 'broken') reasons.push(tr('cat.source.broken'));
  else if (e.archived || e.upstream_status === 'archived') reasons.push(tr('cat.source.archived'));
  else if (e.upstream_status === 'legacy') reasons.push(tr('cat.source.legacy'));
  if (reasons.length) {
    const note = document.createElement('div');
    note.className = 'hint catalog-source-unavailable'; note.textContent = reasons.join(' '); row.appendChild(note);
  }

  const urls = String(e.source_urls || '').split('|').filter(Boolean);
  if (urls.length) {
    const details = document.createElement('details');
    details.className = 'catalog-source-details ui-advanced-only';
    const summary = document.createElement('summary'); summary.textContent = tr('cat.source.provenance');
    details.appendChild(summary);
    urls.forEach((url, index) => {
      const line = document.createElement('div'); line.className = 'catalog-source-url';
      if (/^https:\/\//i.test(url)) {
        const link = document.createElement('a'); link.href = url; link.target = '_blank';
        link.rel = 'noopener noreferrer'; link.textContent = trf('cat.source.url', {n: index + 1, url});
        line.appendChild(link);
      } else {
        line.textContent = trf('cat.source.http', {n: index + 1, url});
      }
      details.appendChild(line);
    });
    row.appendChild(details);
  }

  return row;
}

function catRender() {
  const box = $('catResults');
  if (!box) return;
  catRenderSelectionControls();
  catRenderActiveFilters();
  const allTab = $('btnCatAll'); const selectedTab = $('btnCatSelected');
  if (allTab) allTab.setAttribute('aria-pressed', catView === 'all' ? 'true' : 'false');
  if (selectedTab) selectedTab.setAttribute('aria-pressed', catView === 'selected' ? 'true' : 'false');
  box.textContent = '';
  if (!catLoaded) { box.textContent = catCliReady ? tr('cat.empty.prompt') : tr('cat.empty.route'); return; }
  const query = (($('catSearch') || {}).value || '').trim();
  const filteredEntries = catFiltered();
  let renderedGroups = 0;
  CAT_GROUP_DEFS.forEach((group) => {
    const full = catCache.filter((e) => catGroupKey(e) === group.key);
    const knownCount = Number(catGroupCounts[group.key] || full.length || 0);
    if (!knownCount) return;
    const loaded = catLoadedGroups.has(group.key);
    const matches = loaded ? filteredEntries.filter((e) => catGroupKey(e) === group.key) : [];
    if (catIsNarrowed() && loaded && !matches.length) return;
    const activePool = loaded ? (catIsNarrowed() ? matches : full) : full;
    const activeCount = loaded ? activePool.filter((e) => e.enabled).length :
      (catGroupActive[group.key] != null ? catGroupActive[group.key] : 0);
    const shownCount = catIsNarrowed() && loaded ? matches.length : knownCount;
    const section = document.createElement('section'); section.className = 'catalog-group';
    const header = document.createElement('div'); header.className = 'catalog-group-header';
    const toggle = document.createElement('button'); toggle.type = 'button';
    toggle.className = 'catalog-group-toggle';
    const expanded = catOpenGroup === group.key;
    toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    toggle.setAttribute('aria-controls', 'cat-panel-' + group.key);
    const label = document.createElement('span'); label.className = 'catalog-group-label'; label.textContent = tr(group.labelKey);
    const count = document.createElement('span'); count.className = 'catalog-group-count';
    count.textContent = trf('cat.group.count', {shown: catIsNarrowed() && loaded ? trf('cat.group.of', {n: matches.length}) : '', total: shownCount, active: activeCount});
    const description = document.createElement('span'); description.className = 'catalog-group-description'; description.textContent = tr(group.descriptionKey);
    const master = document.createElement('label'); master.className = 'catalog-group-pick';
    const masterCheck = document.createElement('input'); masterCheck.type = 'checkbox';
    masterCheck.setAttribute('aria-label', trf('cat.group.toggle', {group: tr(group.labelKey)}));
    const actionablePool = loaded ? (catIsNarrowed() ? matches : full) : [];
    const actionable = actionablePool.filter((e) => e.enabled || catCanAdd(e));
    const enabledNow = actionable.filter(catEffectiveEnabled).length;
    masterCheck.checked = actionable.length > 0 && enabledNow === actionable.length;
    masterCheck.indeterminate = loaded ? (enabledNow > 0 && enabledNow < actionable.length) : activeCount > 0;
    masterCheck.disabled = busy || (loaded && actionable.length === 0);
    masterCheck.addEventListener('click', (ev) => { if (ev && ev.stopPropagation) ev.stopPropagation(); });
    masterCheck.addEventListener('change', () => {
      if (busy) return;
      catToggleGroupSelection(group.key, masterCheck.checked);
    });
    const masterText = document.createElement('span'); masterText.textContent = tr('cat.group.pick_all');
    master.appendChild(masterCheck); master.appendChild(masterText);
    const chevron = document.createElement('span'); chevron.className = 'catalog-group-chevron'; chevron.textContent = '›';
    // La casilla es HERMANA del botón: nunca un input interactivo dentro de
    // otro botón. Tocar "Todas" no debe cerrar/abrir el acordeón en Android.
    toggle.appendChild(label); toggle.appendChild(count); toggle.appendChild(description); toggle.appendChild(chevron);
    toggle.addEventListener('click', () => {
      if (busy) return;
      catOpenGroup = catOpenGroup === group.key ? '' : group.key;
      catPageByGroup[group.key] = 0;
      catRender();
      if (catOpenGroup === group.key) catEnsureGroup(group.key);
    });
    header.appendChild(toggle); header.appendChild(master); section.appendChild(header);
    const panel = document.createElement('div'); panel.className = 'catalog-group-panel';
    panel.id = 'cat-panel-' + group.key; panel.hidden = !expanded;
    if (expanded) {
      if (!loaded) {
        const loading = document.createElement('div'); loading.className = 'hint';
        loading.textContent = tr('cat.group.loading_sources'); panel.appendChild(loading);
      } else if (!matches.length) {
        const empty = document.createElement('div'); empty.className = 'hint'; empty.textContent = tr('cat.group.empty'); panel.appendChild(empty);
      } else {
        let page = Number(catPageByGroup[group.key] || 0);
        const pages = Math.max(1, Math.ceil(matches.length / CAT_PAGE_SIZE));
        if (page >= pages) page = pages - 1;
        catPageByGroup[group.key] = page;
        const slice = matches.slice(page * CAT_PAGE_SIZE, page * CAT_PAGE_SIZE + CAT_PAGE_SIZE);
        slice.forEach((e) => panel.appendChild(catRenderSource(e)));
        catRenderPager(panel, group.key, matches);
      }
    }
    section.appendChild(panel); box.appendChild(section); renderedGroups++;
  });
  if (!renderedGroups) {
    box.textContent = catView === 'selected' && !catLoadedGroups.size ? tr('cat.empty.selected_loading') :
      (catView === 'selected' && !catSelection.size && !catCache.some((e) => e.enabled) ? tr('cat.empty.selected') : tr('cat.empty.filtered'));
  }
}

async function catRefreshAndRender() {
  if (!catCliReady) { catRender(); return false; }
  if (catLoading) return catLoading;
  setText('catResults', tr('cat.loading.metadata'));
  catLoading = (async () => {
    const ok = await catLoad();
    if (ok) {
      // Mostrar primero TODOS los encabezados, sin buscador ni filas montadas.
      catRender();
      if (catOpenGroup && (catGroupCounts[catOpenGroup] || 0) > 0) {
        await catLoadGroup(catOpenGroup);
        catRender();
      }
      const query = (($('catSearch') || {}).value || '').trim();
      const needsAll = catView === 'selected' || catFiltersActive() || Boolean(query);
      if (needsAll) await catLoadAllGroups();
    }
    return ok;
  })();
  try { return await catLoading; } finally { catLoading = null; }
}

async function catApplySelected() {
  if (busy) return;
  const enableIds = Array.from(catSelection).filter((id) => {
    const e = catCache.find((item) => item.id === id);
    if (!e || !catCanAdd(e)) { catSelection.delete(id); return false; }
    return true;
  });
  const disableIds = Array.from(catDisableSelection).filter((id) => {
    const e = catCache.find((item) => item.id === id);
    if (!e || !e.enabled) { catDisableSelection.delete(id); return false; }
    return true;
  });
  const actions = enableIds.map((id) => ({ id, mode: 'enable' }))
    .concat(disableIds.map((id) => ({ id, mode: 'disable' })));
  if (!actions.length) { catRenderSelectionControls(); return; }
  const failures = [];
  let applied = 0;
  setBusy(true);
  document.querySelectorAll('#catResults input[type="checkbox"]').forEach((check) => { check.disabled = true; });
  try {
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      const e = catCache.find((item) => item.id === action.id);
      const verb = action.mode === 'enable' ? tr('cat.apply.enabling') : tr('cat.apply.disabling');
      setText('catApplyStatus', trf('cat.apply.progress', {verb, index: i + 1, total: actions.length, name: e ? catDisplayName(e) : action.id}));
      try {
        const r = action.mode === 'enable' ? await DCM.runCatalogEnable(action.id) : await DCM.runCatalogDisable(action.id);
        if (r && r.errno === 0) {
          if (action.mode === 'enable') catSelection.delete(action.id);
          else catDisableSelection.delete(action.id);
          applied++;
        } else failures.push((e ? e.name : action.id) + ': ' + backendError(r, 'catalog'));
      } catch (err) {
        failures.push((e ? e.name : action.id) + ': ' + String(err && err.message || err));
      }
    }
    await catReload();
  } finally {
    setBusy(false);
    catRender();
  }
  const summary = trf(failures.length ? 'cat.apply.partial' : 'cat.apply.success', {applied, errors: failures.length});
  setText('catApplyStatus', summary + (failures.length ? ' ' + failures.join(' · ') : ''));
  toast(summary, failures.length ? 'error' : 'ok');
}

function catDownloadProgressText(info) {
  const done = Number(info.done || 0), total = Number(info.total || 0);
  const ok = Number(info.success || 0), failed = Number(info.failed || 0), skipped = Number(info.skipped || 0);
  if (info.state === 'queued' || info.state === 'running') {
    const current = info.current && info.current !== 'preparando' ? trf('cat.download.current', {name: info.current}) : '';
    return trf('cat.download.running', {done, total, ok, failed, skipped, current});
  }
  if (info.state === 'done') {
    return trf('cat.download.done', {ok, skipped});
  }
  if (info.state === 'partial') {
    return trf('cat.download.partial', {ok, failed, skipped});
  }
  if (info.state === 'idle') return tr('cat.download.none');
  return trf('cat.download.state', {state: info.state || tr('cat.state.unknown'), done, total});
}

async function catPollDownloadAll() {
  if (catDownloadPollInFlight || !DCM.runCatalogDownloadAllStatus) return;
  catDownloadPollInFlight = true;
  try {
    const r = await DCM.runCatalogDownloadAllStatus();
    if (r.errno !== 0) {
      setText('catDownloadStatus', backendError(r, 'estado de descarga global'));
      return;
    }
    const info = safeParse(r.stdout);
    if (!info || typeof info.state !== 'string') {
      setText('catDownloadStatus', tr('cat.download.invalid'));
      return;
    }
    catLastDownloadInfo = info;
    setText('catDownloadStatus', catDownloadProgressText(info));
    const button = $('btnCatDownloadAll');
    const running = info.state === 'queued' || info.state === 'running';
    if (button) button.disabled = running;
    if (running) {
      if (catDownloadPollTimer) clearTimeout(catDownloadPollTimer);
      catDownloadPollTimer = setTimeout(() => { catDownloadPollTimer = null; catPollDownloadAll(); }, 5000);
    } else if (catDownloadPollTimer) {
      clearTimeout(catDownloadPollTimer); catDownloadPollTimer = null;
    }
    if (!running && info.job_id && catDownloadRefreshJobId !== info.job_id) {
      catDownloadRefreshJobId = info.job_id;
      if (await catReload()) catRender();
    }
  } finally { catDownloadPollInFlight = false; }
}

async function catStartDownloadAll() {
  const button = $('btnCatDownloadAll');
  if (!DCM.runCatalogDownloadAllStart || (button && button.disabled)) return;
  if (!confirm(tr('cat.download.confirm'))) return;
  if (button) button.disabled = true;
  setText('catDownloadStatus', tr('cat.download.starting'));
  const r = await DCM.runCatalogDownloadAllStart();
  if (r.errno !== 0) {
    if (button) button.disabled = false;
    setText('catDownloadStatus', backendError(r, 'descarga global'));
    return;
  }
  setText('catDownloadStatus', (r.stdout || tr('cat.download.started')).trim());
  await catPollDownloadAll();
}

function wireCatalog() {
  const s = $('catSearch');
  if (s) s.addEventListener('input', () => {
    catPageByGroup = Object.create(null);
    if (!catLoaded && catCliReady) { catRefreshAndRender(); return; }
    catRender();
    if (String(s.value || '').trim()) catLoadAllGroups();
  });
  const filter = $('btnCatFilter');
  if (filter) filter.addEventListener('click', catOpenFilterSheet);
  const closeFilter = $('btnCatFilterClose');
  if (closeFilter) closeFilter.addEventListener('click', () => catCloseFilterSheet(true));
  const backdrop = $('catFilterBackdrop');
  if (backdrop) backdrop.addEventListener('click', () => catCloseFilterSheet(false));
  const clearFilter = $('btnCatFilterClear');
  if (clearFilter) clearFilter.addEventListener('click', catClearFilterDraft);
  const applyFilter = $('btnCatFilterApply');
  if (applyFilter) applyFilter.addEventListener('click', catApplyFilterDraft);
  if (document.addEventListener) document.addEventListener('keydown', (ev) => {
    if (ev && ev.key === 'Escape' && $('catFilterSheet') && !$('catFilterSheet').hidden) catCloseFilterSheet(true);
  });
  const all = $('btnCatAll');
  if (all) all.addEventListener('click', () => catSetView('all'));
  const selected = $('btnCatSelected');
  if (selected) selected.addEventListener('click', () => catSetView('selected'));
  const add = $('btnCatAddSelected');
  if (add) add.addEventListener('click', catApplySelected);
  const clear = $('btnCatClearSelection');
  if (clear) clear.addEventListener('click', () => { catSelection.clear(); catDisableSelection.clear(); catRender(); });
  const downloadAll = $('btnCatDownloadAll');
  if (downloadAll) downloadAll.addEventListener('click', catStartDownloadAll);
  catPollDownloadAll();
  const up = $('btnCatUpdate');
  if (up) up.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('catResults', tr('cat.updating'));
    try {
      const r = await DCM.runCatalogUpdate();
      toast(r.errno === 0 ? tr('cat.update.done') : backendError(r, 'update'), r.errno === 0 ? 'ok' : 'error');
      if (await catReload()) catRender();
    } finally { setBusy(false); }
  });
  const cp = $('btnCatCompile');
  if (cp) cp.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('catResults', tr('cat.compiling'));
    try {
      const r = await DCM.runCatalogCompile();
      toast(r.errno === 0 ? tr('cat.compile.done') : backendError(r, 'compile'), r.errno === 0 ? 'ok' : 'error');
      if (await catReload()) catRender();
    } finally { setBusy(false); }
  });
  const cf = $('btnCatConflicts');
  if (cf) cf.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    try {
      const r = await DCM.runCatalogConflicts();
      setText('catConflicts', (r.stdout || r.stderr || '').trim());
    } finally { setBusy(false); }
  });
}

async function customRender() {
  const box = $('customList');
  if (!box) return;
  if (!catLoaded) { await catLoad(); }
  if (!catLoadedGroups.has('dcm')) { await catLoadGroup('dcm'); }
  const customs = catCache.filter((e) => e.id.indexOf('custom_') === 0);
  box.textContent = '';
  if (!customs.length) { box.textContent = tr('cat.custom.none'); return; }
  customs.forEach((e) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const t = document.createElement('div');
    t.textContent = (e.enabled ? '● ' : '○ ') + e.name + ' [' + e.id + ']';
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const tog = document.createElement('button');
    tog.textContent = e.enabled ? tr('cat.custom.disable') : tr('cat.custom.enable');
    tog.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = e.enabled ? await DCM.runCatalogDisable(e.id) : await DCM.runCatalogEnable(e.id);
        toast(rr.errno === 0 ? tr('cat.custom.done') : backendError(rr, 'catalog'), rr.errno === 0 ? 'ok' : 'error');
        if (await catReload()) { await customRender(); catRender(); }
      } finally { setBusy(false); }
    });
    const del = document.createElement('button');
    del.textContent = tr('cat.custom.delete'); del.className = 'small danger';
    del.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runCustomRemove(e.id);
        toast(rr.errno === 0 ? tr('cat.custom.deleted') : backendError(rr, 'remove'), rr.errno === 0 ? 'ok' : 'error');
        if (await catReload()) { await customRender(); catRender(); }
      } finally { setBusy(false); }
    });
    acts.appendChild(tog); acts.appendChild(del);
    row.appendChild(t); row.appendChild(acts);
    box.appendChild(row);
  });
}
function wireCustom() {
  const add = $('btnCustomAdd');
  if (add) add.addEventListener('click', async () => {
    if (busy) return;
    const url = (($('customUrl') || {}).value || '').trim();
    const name = (($('customName') || {}).value || '').trim();
    if (!/^https:\/\//i.test(url)) { setText('customError', tr('cat.custom.url')); return; }
    setText('customError', '');
    setBusy(true);
    try {
      const r = await DCM.runCustomAdd(url, name, '');
      toast(r.errno === 0 ? tr('cat.custom.added') : backendError(r, 'custom add'), r.errno === 0 ? 'ok' : 'error');
      if (r.errno === 0) { const u = $('customUrl'); if (u) u.value = ''; const n = $('customName'); if (n) n.value = ''; }
      if (await catReload()) { await customRender(); catRender(); }
    } finally { setBusy(false); }
  });
}

function wireBindhosts() {
  const an = $('btnBhAnalyze');
  if (an) an.addEventListener('click', async () => {
    if (busy) return;
    const dir = (($('bhDir') || {}).value || '').trim();
    if (!/^\//.test(dir)) { setText('bhError', tr('cat.bind.path')); return; }
    setText('bhError', '');
    setBusy(true);
    setText('bhResults', tr('cat.bind.analyzing'));
    try {
      const r = await DCM.runBindhostsAnalyze(dir);
      setText('bhResults', (r.stdout || r.stderr || '').trim());
    } finally { setBusy(false); }
  });
  const im = $('btnBhImport');
  if (im) im.addEventListener('click', async () => {
    if (busy) return;
    const dir = (($('bhDir') || {}).value || '').trim();
    if (!/^\//.test(dir)) { setText('bhError', tr('cat.bind.path.short')); return; }
    if (!confirm(trf('cat.bind.confirm', {dir}))) return;
    setText('bhError', '');
    setBusy(true);
    setText('bhResults', tr('cat.bind.importing'));
    try {
      const r = await DCM.runBindhostsImport(dir);
      setText('bhResults', (r.stdout || r.stderr || '').trim());
      toast(r.errno === 0 ? tr('cat.bind.imported') : backendError(r, 'import'), r.errno === 0 ? 'ok' : 'error');
      if (await catReload()) catRender();
    } finally { setBusy(false); }
  });
}

/* svcRender (motor heredado RC2 `service`) eliminado en v1.0.0: la tarjeta quedaba
   vacia y duplicaba "Privacidad por servicio" (backend real `service-control`). */

function initCatalogRC2() {
  wireCatalog();
  wireCustom();
  wireBindhosts();
}

function catOnRoute(route) {
  if (route !== 'lists' || !catCliReady || catLoaded) return;
  catRefreshAndRender().then(function (loaded) {
    if (loaded) customRender();
  });
}

/* Tarjeta de entorno (v0.3 A1): corre `environment status` y lo muestra. */
async function refreshEnvironmentCard() {
  const box = $('envCard');
  if (!box) return;
  if (!DCM.runEnvironmentStatus) { box.textContent = '-'; return; }
  box.textContent = (typeof I18N !== 'undefined' && I18N.t) ? I18N.t('common.loading') : 'Loading...';
  try {
    const r = await DCM.runEnvironmentStatus();
    const txt = (r && (r.stdout || r.stderr) ? (r.stdout || r.stderr) : '').trim();
    box.textContent = txt || (I18N && I18N.t ? I18N.t('env.cli.unresolved') : '-');
  } catch (_) {
    box.textContent = (I18N && I18N.t) ? I18N.t('common.error') : 'error';
  }
}
function wireEnvironment() {
  const b = $('btnEnvRefresh');
  if (b) b.addEventListener('click', function () { if (!busy) refreshEnvironmentCard(); });
}

/* A2.5: source doctor en la WebUI. DOM seguro (createElement/textContent),
   sin innerHTML con datos externos. Muestra estado humano, failure_class,
   ultima copia valida, HTTP, hostname + detalles y botones de accion. */
function renderSourceDoctor(container, d) {
  container.textContent = '';
  const t = (k) => (typeof I18N !== 'undefined' && I18N.t) ? I18N.t(k) : k;
  const fc = d.failure_class || 'sin_lista';
  const stateKey = DCM.failureClassToState(fc);
  // Badge de estado humano
  const badge = document.createElement('div');
  badge.className = 'src-badge src-' + stateKey;
  badge.textContent = t('src.state.' + stateKey) + '  ·  ' + fc;
  container.appendChild(badge);
  // Campos legibles
  const rows = [
    ['hostname', d.hostname], ['http_status', d.http_status],
    ['source_hostname_blocked', d.source_hostname_blocked],
    ['last_valid_available', d.last_valid_available],
    ['last_valid_domains', d.last_valid_domains],
    ['last_valid_timestamp', d.last_valid_timestamp],
    ['runtime_status', d.runtime_status], ['recommendation', d.recommendation]
  ];
  const dl = document.createElement('div'); dl.className = 'src-fields';
  rows.forEach(([k, v]) => {
    if (v === undefined || v === '') return;
    const r = document.createElement('div'); r.className = 'src-row';
    const kk = document.createElement('span'); kk.className = 'src-k'; kk.textContent = k;
    const vv = document.createElement('span'); vv.className = 'src-v'; vv.textContent = String(v);
    r.appendChild(kk); r.appendChild(vv); dl.appendChild(r);
  });
  container.appendChild(dl);
  // Si hubo última copia válida, mostrar cantidad + fecha de forma destacada.
  if (d.last_valid_available === 'yes') {
    const lv = document.createElement('div'); lv.className = 'src-lastvalid';
    lv.textContent = t('src.lastvalid')
      .replace('{count}', String(d.last_valid_domains || '?'))
      .replace('{date}', String(d.last_valid_timestamp || '?'));
    container.appendChild(lv);
  }
  // Detalles tecnicos expandibles (createElement, no innerHTML)
  const det = document.createElement('details'); det.className = 'src-details';
  const sum = document.createElement('summary'); sum.textContent = t('src.action.copydetails').replace('Copy', 'Details').replace(tr('ui.events.copy'), 'Detalles');
  const pre = document.createElement('pre'); pre.style.whiteSpace = 'pre-wrap';
  pre.textContent = Object.keys(d).map((k) => k + '=' + d[k]).join('\n');
  det.appendChild(sum); det.appendChild(pre); container.appendChild(det);
  // Botones de accion
  const bar = document.createElement('div'); bar.className = 'src-actions';
  const mkBtn = (labelKey, fn) => {
    const b = document.createElement('button'); b.className = 'small'; b.textContent = t(labelKey);
    b.addEventListener('click', fn); return b;
  };
  const id = d.source_id || '';
  bar.appendChild(mkBtn('src.action.diagnose', function () { if (!busy) runSourceDoctorUI(id); }));
  bar.appendChild(mkBtn('src.action.retry', function () { if (!busy) runSourceDoctorUI(id); }));
  bar.appendChild(mkBtn('src.action.copydetails', function () {
    const txt = pre.textContent;
    try { if (navigator.clipboard) navigator.clipboard.writeText(txt); } catch (_) {}
    toast(t('src.action.copydetails'), 'ok');
  }));
  container.appendChild(bar);
}

async function runSourceDoctorUI(id) {
  const box = $('srcDoctorResult'); if (!box) return;
  const theId = id || (($('srcDoctorId') || {}).value || '').trim();
  if (!/^[a-zA-Z0-9_-]+$/.test(theId)) { toast((I18N && I18N.t) ? I18N.t('common.error') : 'error', 'error'); return; }
  box.textContent = (typeof I18N !== 'undefined' && I18N.t) ? I18N.t('common.loading') : 'Loading...';
  try {
    const r = await DCM.runSourceDoctor(theId);
    const d = DCM.parseDoctor((r && (r.stdout || r.stderr)) ? (r.stdout || r.stderr) : '');
    if (!d.source_id) d.source_id = theId;
    renderSourceDoctor(box, d);
  } catch (_) {
    box.textContent = (I18N && I18N.t) ? I18N.t('common.error') : 'error';
  }
}
function wireSourceDoctor() {
  const b = $('btnSrcDoctor');
  if (b) b.addEventListener('click', function () { if (!busy) runSourceDoctorUI(); });
}

function initBackend() {
  if (!DCM.available()) {
    const b = $('ksuBanner');
    if (b) { b.textContent = tr('status.no_ksu'); b.classList.remove('hidden'); }
    // Sin puente ksu no hay backend: navegacion/idioma siguen, pero no hay polling.
    return;
  }
  // Cablear listeners (seguro aunque la CLI aun no este resuelta).
  wireServiceButtons();
  wireTestDns();
  wireProviders();
  wireRedirect();
  wirePrivateDns();
  wireLogs();
  wirePanic();
  initSecurity();
  initCatalogRC2();
  wireEnvironment();
  wireSourceDoctor();
  // Resolver la ruta de la CLI (3 rutas de allowlist) ANTES de emitir comandos.
  DCM.resolveCli().then(function (path) {
    if (!path) {
      // La CLI existe pero no es ejecutable desde el contexto WebUI: en KernelSU
      // Next suele ser Hybrid Mount apagado. Mensaje claro, no rc=127.
      const b = $('ksuBanner');
      const msg = (typeof I18N !== 'undefined' && I18N.t) ? I18N.t('env.cli.unresolved') : '';
      if (b) { b.textContent = msg || 'No se pudo acceder a la CLI del modulo. Si usas KernelSU Next, activa Hybrid Mount, reinicia y vuelve a abrir la interfaz.'; b.classList.remove('hidden'); }
      // Igual mostramos el estado del entorno si se puede (usa comando fijo, no la CLI resuelta).
      if (typeof refreshEnvironmentCard === 'function') { try { refreshEnvironmentCard(); } catch (_) {} }
      return;
    }
    if (typeof refreshEnvironmentCard === 'function') { try { refreshEnvironmentCard(); } catch (_) {} }
    catCliReady = true;
    if (typeof Router !== 'undefined' && Router.current && Router.current() === 'lists') catOnRoute('lists');
    startPolling();
  });
}

function init() {
  wireUiMode();
  if (typeof Router !== 'undefined' && Router.init) {
    try {
      Router.init({ onChange: function (route) {
        if (typeof V030 !== 'undefined' && V030.onRoute) { try { V030.onRoute(route); } catch (e) {} }
        catOnRoute(route);
      } });
    } catch (_) {}
  }
  if (typeof I18N === 'undefined' || !I18N.init) { initBackend(); return; }
  // Cargar el idioma antes del primer render dinámico evita mostrar claves sin traducir.
  Promise.resolve().then(() => I18N.init()).catch(() => {}).then(() => {
    const sel = $('langSelect');
    if (sel) {
      sel.value = I18N.current();
      sel.addEventListener('change', async function () {
        if (I18N.setLang) await I18N.setLang(sel.value);
        catRender();
        if ($('catFilterSheet') && !$('catFilterSheet').hidden) catRenderFilterOptions();
        if (catLastDownloadInfo) setText('catDownloadStatus', catDownloadProgressText(catLastDownloadInfo));
        if (DCM.available()) refreshStatus();
      });
    }
    initBackend();
  });
}

document.addEventListener('DOMContentLoaded', init);

/* V030 (service-controls + transportes, lazy) se movio a webroot/js/controls.js (global var V030). */
