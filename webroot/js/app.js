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

/* --------------------------- utilidades DOM --------------------------- */
const $ = (id) => document.getElementById(id);

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

/* ------------------------------ estado -------------------------------- */
function renderStatus(s) {
  if (!s) return;

  setDot('statusDot', s.disabled ? 'red' : (s.running && s.listening ? 'green' : (s.running ? 'amber' : 'red')));
  setText('statusHeadline', s.disabled ? 'Deshabilitado' : (s.running ? STR.running : STR.stopped));

  setText('pidText', s.running ? String(s.pid) : '—');
  setText('listenText', s.listen || '—');
  setText('listeningText', s.listening ? STR.listeningYes : STR.listeningNo);
  setText('versionText', s.version || '—');
  setText('serverText', s.server || '—');
  setText('backendText', s.backend === 'none' ? 'ninguno detectado' : (s.backend || '—'));

  const redirActive = s.redirect === 'activa';
  setDot('redirectDot', redirActive ? 'green' : 'amber');
  setText('redirectText', redirActive ? STR.redirectOn : STR.redirectOff);

  const bootCb = $('bootRedirectToggle');
  if (bootCb && document.activeElement !== bootCb) bootCb.checked = (s.boot_redirect === 1 || s.boot_redirect === '1');

  const v6sel = $('ipv6ModeSelect');
  if (v6sel && document.activeElement !== v6sel) v6sel.value = s.ipv6_mode || 'redirect';

  const banner = $('disabledBanner');
  if (banner) banner.classList.toggle('hidden', !s.disabled);
  setText('disabledBannerText', STR.disabledBanner);

  const binWarn = $('binMissingBanner');
  if (binWarn) binWarn.classList.toggle('hidden', !!s.binary_present);
}

async function refreshStatus() {
  if (!DCM.available()) return;
  const r = await DCM.run('status');
  if (r.errno !== 0) {
    toast(r.stderr || STR.timeout, 'error');
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
    if (r.errno === 0) { toast(okMsg, 'ok'); } else { toast((r.stderr || r.stdout || 'Fallo').trim(), 'error'); }
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
        toast((rEnable.stderr || 'No se pudo habilitar el modulo.').trim(), 'error');
        return;
      }
      const rStart = await DCM.run('start');
      toast(rStart.errno === 0 ? 'Modulo habilitado y servicio iniciado.' : (rStart.stderr || 'Fallo al iniciar').trim(),
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
  if (!lines.length) { box.textContent = '(sin salida)'; return; }
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
    setText('testDnsOutput', 'Probando…');
    try {
      const r = await DCM.run('testDns');
      renderTestDnsOutput((r.stdout || '') + (r.stderr ? '\n' + r.stderr : ''));
      toast(r.errno === 0 ? 'Prueba de DNS OK.' : 'La prueba fallo; revisa el detalle.', r.errno === 0 ? 'ok' : 'error');
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
        toast(r.errno === 0 ? 'Proveedor aplicado. Reinicia el servicio para usarlo.' : (r.stderr || 'Fallo').trim(),
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
      toast(r.errno === 0 ? 'NextDNS configurado. Reinicia el servicio para usarlo.' : (r.stderr || 'Fallo').trim(),
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
    if (!confirm(STR.confirmRedirectApply)) return;
    setBusy(true);
    try {
      const r = await DCM.run('redirectApply');
      toast(r.errno === 0 ? 'Redireccion aplicada.' : (r.stderr || r.stdout || 'Fallo').trim(),
            r.errno === 0 ? 'ok' : 'error');
      await refreshStatus();
    } finally {
      setBusy(false);
    }
  });

  const bRemove = $('btnRedirectRemove');
  if (bRemove) bRemove.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(STR.confirmRedirectRemove)) return;
    setBusy(true);
    try {
      const r = await DCM.run('redirectRemove');
      toast(r.errno === 0 ? 'Redireccion retirada.' : (r.stderr || 'Fallo').trim(), r.errno === 0 ? 'ok' : 'error');
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
      if (r.errno !== 0) { ev.target.checked = !ev.target.checked; toast((r.stderr || 'Fallo').trim(), 'error'); }
      else { toast('Preferencia guardada.', 'ok'); }
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
      toast(r.errno === 0 ? 'Modo IPv6 actualizado. Se aplica en el proximo "Aplicar redireccion".' : (r.stderr || 'Fallo').trim(),
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
    setText('privateDnsText', 'Consultando…');
    try {
      const r = await DCM.run('privateDns');
      setText('privateDnsText', (r.stdout || r.stderr || '(sin datos)').trim());
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
    setText('logsOutput', 'Cargando…');
    try {
      const r = await DCM.run('logs');
      setText('logsOutput', (r.stdout || r.stderr || '(sin logs)').trim());
    } finally {
      setBusy(false);
    }
  });

  const bClear = $('btnLogsClear');
  if (bClear) bClear.addEventListener('click', async () => {
    if (busy) return;
    if (!confirm(STR.confirmLogsClear)) return;
    setBusy(true);
    try {
      const r = await DCM.run('logsClear');
      toast(r.errno === 0 ? 'Logs borrados.' : (r.stderr || 'Fallo').trim(), r.errno === 0 ? 'ok' : 'error');
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
    if (!confirm(STR.confirmPanic)) return;
    setBusy(true);
    try {
      const r = await DCM.run('panic');
      toast(r.errno === 0 ? 'Modulo deshabilitado y red restaurada.' : (r.stderr || 'Fallo').trim(),
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
  if (!data) { setText('protectionList', 'Respuesta no valida del backend.'); return; }
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
    sub.textContent = (SEC_STR.catSub[cat] || '') + ' · ' + dom + ' dominios (' + st + ')';
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
        else { toast('Proteccion ' + cat + (cb.checked ? ' activada.' : ' desactivada.'), 'ok'); }
        await refreshProtection();
      } finally { setBusy(false); }
    });
    lab.appendChild(cb);
    row.appendChild(left); row.appendChild(lab);
    box.appendChild(row);
  });
  setText('protectionTotal', 'Total activo: ' + (data.active_total != null ? data.active_total : 0) + ' dominios.');
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
      if (prof === 'strict' && !confirm(SEC_STR.confirmProfileStrict)) return;
      setBusy(true);
      setText('profilePlan', 'Aplicando perfil…');
      try {
        const action = prof === 'balanced' ? 'profileBalanced' : (prof === 'strict' ? 'profileStrict' : 'profilePrivacy');
        const r = await DCM.run(action);
        setText('profilePlan', (r.stdout || r.stderr || '').trim());
        toast(r.errno === 0 ? 'Perfil ' + prof + ' aplicado.' : backendError(r, 'perfil'), r.errno === 0 ? 'ok' : 'error');
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
  if (!data) { box.textContent = 'Sin datos.'; return; }
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
      up.textContent = 'Actualizar';
      up.addEventListener('click', async () => {
        if (busy) return; setBusy(true);
        try {
          const rr = await DCM.runBlocklistUpdateCat(cat);
          toast(rr.errno === 0 ? cat + ' actualizada.' : backendError(rr, 'update ' + cat), rr.errno === 0 ? 'ok' : 'error');
          await refreshBlocklists();
        } finally { setBusy(false); }
      });
      const rb = document.createElement('button');
      rb.textContent = 'Revertir';
      rb.addEventListener('click', async () => {
        if (busy) return; setBusy(true);
        try {
          const rr = await DCM.runBlocklistRollbackCat(cat);
          toast(rr.errno === 0 ? cat + ' revertida.' : backendError(rr, 'rollback ' + cat), rr.errno === 0 ? 'ok' : 'error');
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
    setText('blocklistsTable', 'Descargando y verificando…');
    try {
      const r = await DCM.run('blocklistsUpdate');
      toast(r.errno === 0 ? 'Listas actualizadas.' : backendError(r, 'update'), r.errno === 0 ? 'ok' : 'error');
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
      toast(r.errno === 0 ? 'Validacion OK.' : 'Hay listas con problemas.', r.errno === 0 ? 'ok' : 'error');
    } finally { setBusy(false); }
  });
}

/* ------------------------------ allowlist ------------------------------- */
async function refreshAllowlist() {
  const r = await DCM.run('allowlistList');
  if (r.errno !== 0) { setText('allowList', backendError(r, 'allowlist list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('allowList', 'Sin datos.'); return; }
  const box = $('allowList');
  box.textContent = '';
  if (!d.domains || !d.domains.length) { box.textContent = '(allowlist vacia)'; return; }
  d.domains.forEach((dom) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const name = document.createElement('span');
    name.textContent = dom + '  ';
    const del = document.createElement('button');
    del.textContent = 'Quitar';
    del.className = 'small danger';
    del.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runAllowlistRemove(dom);
        toast(rr.errno === 0 ? 'Quitado: ' + dom : backendError(rr, 'remove'), rr.errno === 0 ? 'ok' : 'error');
        await refreshAllowlist();
      } finally { setBusy(false); }
    });
    row.appendChild(name); row.appendChild(del);
    box.appendChild(row);
  });
  setText('allowError', d.count + ' dominio(s) en la allowlist.');
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
      if (r.errno === 0) { toast('Agregado.', 'ok'); inp.value = ''; await refreshAllowlist(); }
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
      setText('allowList', out.length ? out : '(sin coincidencias)');
    } finally { setBusy(false); }
  });

  const imp = $('btnAllowImport');
  if (imp) imp.addEventListener('click', async () => {
    if (busy) return;
    const ta = $('allowImport');
    if (!ta) return;
    const lines = ta.value.split('\n').map((x) => x.trim().toLowerCase()).filter((x) => x.length && x[0] !== '#');
    if (!lines.length) { toast('No hay dominios para importar.', 'error'); return; }
    if (lines.length > 200) { toast('Maximo 200 dominios por importacion desde la WebUI.', 'error'); return; }
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
      toast('Importado: +' + added + ', dup ' + dup + ', invalidos ' + bad + '.', bad ? 'error' : 'ok');
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
      toast('Allowlist (' + (d ? d.count : 0) + ') mostrada abajo para copiar.', 'ok');
      setText('allowList', text || '(vacia)');
    } finally { setBusy(false); }
  });
}

/* --------------------------- excepciones temp --------------------------- */
async function refreshTempAllow() {
  const r = await DCM.run('tempAllowList');
  if (r.errno !== 0) { setText('tempList', backendError(r, 'temporary-allow list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('tempList', 'Sin datos.'); return; }
  const box = $('tempList');
  box.textContent = '';
  if (!d.exceptions || !d.exceptions.length) { box.textContent = '(sin excepciones vigentes)'; return; }
  d.exceptions.forEach((ex) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const rem = (ex.remaining === 'boot') ? 'hasta reiniciar' : ('quedan ' + ex.remaining + 's');
    const t = document.createElement('div');
    t.textContent = ex.domain + ' — ' + rem + ' · ' + (ex.reason || '-');
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const rev = document.createElement('button');
    rev.textContent = 'Revocar'; rev.className = 'small danger';
    rev.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runTempAllowRemove(ex.domain);
        toast(rr.errno === 0 ? 'Revocada: ' + ex.domain : backendError(rr, 'revocar'), rr.errno === 0 ? 'ok' : 'error');
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
      toast(r.errno === 0 ? 'Excepcion creada.' : backendError(r, 'excepcion'), r.errno === 0 ? 'ok' : 'error');
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
  if (!d || !d.checks) { setText('leakResults', 'Respuesta no valida.'); return; }
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
    setText('leakResults', 'Auditando…');
    try { await runLeak(); } finally { setBusy(false); }
  });
  const cp = $('btnLeakCopy');
  if (cp) cp.addEventListener('click', async () => {
    if (!lastLeakText) { toast('Primero ejecuta la prueba.', 'error'); return; }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(lastLeakText); toast('Diagnostico copiado.', 'ok'); }
      else { toast('Copia manual: el detalle esta arriba.', 'ok'); }
    } catch (_) { toast('No se pudo copiar automaticamente.', 'error'); }
  });
}

/* -------------------------------- eventos ------------------------------- */
async function refreshEvents() {
  const r = await DCM.run('eventsList');
  const box = $('eventsList');
  if (!box) return;
  if (r.errno !== 0) { setText('eventsList', backendError(r, 'events list')); return; }
  const d = safeParse(r.stdout);
  if (!d) { setText('eventsList', 'Sin datos.'); return; }
  const filterEl = $('eventsFilter');
  const filter = filterEl ? filterEl.value.trim().toLowerCase() : '';
  box.textContent = '';
  let evs = d.events || [];
  if (filter) evs = evs.filter((e) => (e.domain || '').indexOf(filter) >= 0);
  if (!evs.length) { box.textContent = '(sin eventos)'; return; }
  evs.forEach((e) => {
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
    al.textContent = 'A la allowlist';
    al.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runAllowlistAdd(e.domain);
        toast(rr.errno === 0 ? 'Agregado a allowlist: ' + e.domain : backendError(rr, 'allowlist'), rr.errno === 0 ? 'ok' : 'error');
        await refreshAllowlist();
      } finally { setBusy(false); }
    });
    const cp = document.createElement('button');
    cp.textContent = 'Copiar';
    cp.addEventListener('click', async () => {
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(e.domain); toast('Dominio copiado.', 'ok'); }
        else { toast(e.domain, 'ok'); }
      } catch (_) { toast(e.domain, 'ok'); }
    });
    acts.appendChild(al); acts.appendChild(cp);
    row.appendChild(head); row.appendChild(meta); row.appendChild(acts);
    box.appendChild(row);
  });
}
function wireEvents() {
  const rf = $('btnEventsRefresh');
  if (rf) rf.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('eventsList', 'Cargando…');
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
    if (!confirm(SEC_STR.confirmEventsClear)) return;
    setBusy(true);
    try {
      const r = await DCM.run('eventsClear');
      toast(r.errno === 0 ? 'Historial borrado.' : backendError(r, 'events clear'), r.errno === 0 ? 'ok' : 'error');
      setText('eventsList', '(sin eventos)');
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
      setText('eventsList', text || '(sin eventos)');
      toast('Eventos volcados abajo para copiar.', 'ok');
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
      if (!(max >= 50 && max <= 10000)) { toast('El maximo debe estar entre 50 y 10000.', 'error'); setBusy(false); return; }
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
      toast(okAll ? 'Preferencias guardadas.' : lastErr, okAll ? 'ok' : 'error');
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
  await refreshEvents();
}

/* ------------------------------------------------------------------------ */
/* ======================================================================== *
 *  RC2 — Catalogo, fuentes personalizadas, BindHosts, controles de servicio.
 *  Paginacion del lado cliente (no se renderizan miles de tarjetas de una).
 * ======================================================================== */
let catCache = [];        // entradas del catalogo (cacheadas del JSON)
let catView = 'recommended';
let catPage = 0;
const CAT_PAGE_SIZE = 15;

async function catLoad() {
  const r = await DCM.runCatalogListJson();
  if (r.errno !== 0) { setText('catResults', backendError(r, 'catalog list')); return false; }
  const d = safeParse(r.stdout);
  if (!d || !d.entries) { setText('catResults', 'Respuesta no valida del catalogo.'); return false; }
  catCache = d.entries;
  return true;
}

function catFiltered() {
  const q = (($('catSearch') || {}).value || '').trim().toLowerCase();
  return catCache.filter((e) => {
    if (catView === 'recommended' && !e.recommended) return false;
    if (catView === 'enabled' && !e.enabled) return false;
    if (q) {
      const hay = (e.id + ' ' + e.name + ' ' + e.maintainer + ' ' + e.categories).toLowerCase();
      if (hay.indexOf(q) < 0) return false;
    }
    return true;
  });
}

function catRender() {
  const box = $('catResults');
  if (!box) return;
  const list = catFiltered();
  const pages = Math.max(1, Math.ceil(list.length / CAT_PAGE_SIZE));
  if (catPage >= pages) catPage = pages - 1;
  const slice = list.slice(catPage * CAT_PAGE_SIZE, catPage * CAT_PAGE_SIZE + CAT_PAGE_SIZE);
  box.textContent = '';
  if (!slice.length) { box.textContent = '(sin coincidencias)'; }
  slice.forEach((e) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const head = document.createElement('div');
    head.textContent = (e.enabled ? '● ' : '○ ') + e.name + '  [' + e.upstream_status + '/' + (e.runtime_status || 'never_checked') + ']';
    const meta = document.createElement('div');
    meta.className = 'tl-sub';
    meta.textContent = e.maintainer + ' · ' + e.categories + ' · ' + e.aggressiveness +
      ' · movil:' + e.mobile_suitability + (e.valid_domains && e.valid_domains !== '-' ? ' · ' + e.valid_domains + ' dom' : '') +
      (e.recommended ? ' · recomendada' : '') + (e.archived ? ' · ARCHIVADA' : '');
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const tog = document.createElement('button');
    tog.textContent = e.enabled ? 'Desactivar' : 'Activar';
    if (!e.enabled) tog.className = 'primary';
    tog.addEventListener('click', async () => {
      if (busy) return;
      setBusy(true);
      setText('catResults', e.enabled ? 'Desactivando y recompilando…' : 'Activando, descargando y compilando…');
      try {
        const rr = e.enabled ? await DCM.runCatalogDisable(e.id) : await DCM.runCatalogEnable(e.id);
        toast(rr.errno === 0 ? (e.name + (e.enabled ? ' desactivada' : ' activada')) : backendError(rr, 'catalog'), rr.errno === 0 ? 'ok' : 'error');
        if (await catLoad()) catRender();
      } finally { setBusy(false); }
    });
    acts.appendChild(tog);
    row.appendChild(head); row.appendChild(meta); row.appendChild(acts);
    box.appendChild(row);
  });
  const pager = $('catPager');
  if (pager) {
    pager.textContent = '';
    if (pages > 1) {
      const prev = document.createElement('button'); prev.textContent = '‹'; prev.className = 'small';
      prev.disabled = catPage === 0;
      prev.addEventListener('click', () => { if (catPage > 0) { catPage--; catRender(); } });
      const lbl = document.createElement('span'); lbl.className = 'hint';
      lbl.textContent = ' ' + (catPage + 1) + '/' + pages + ' (' + list.length + ') ';
      const next = document.createElement('button'); next.textContent = '›'; next.className = 'small';
      next.disabled = catPage >= pages - 1;
      next.addEventListener('click', () => { if (catPage < pages - 1) { catPage++; catRender(); } });
      pager.appendChild(prev); pager.appendChild(lbl); pager.appendChild(next);
    }
  }
}

async function catRefreshAndRender() {
  setText('catResults', 'Cargando catalogo…');
  if (await catLoad()) { catPage = 0; catRender(); }
}

function wireCatalog() {
  const s = $('catSearch');
  if (s) s.addEventListener('input', () => { catPage = 0; if (catCache.length) catRender(); else catRefreshAndRender(); });
  const rec = $('btnCatRecommended');
  if (rec) rec.addEventListener('click', () => { catView = 'recommended'; catPage = 0; if (catCache.length) catRender(); else catRefreshAndRender(); });
  const en = $('btnCatEnabled');
  if (en) en.addEventListener('click', () => { catView = 'enabled'; catPage = 0; if (catCache.length) catRender(); else catRefreshAndRender(); });
  const all = $('btnCatAll');
  if (all) all.addEventListener('click', () => { catView = 'all'; catPage = 0; if (catCache.length) catRender(); else catRefreshAndRender(); });
  const up = $('btnCatUpdate');
  if (up) up.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('catResults', 'Actualizando fuentes activas (puede tardar)…');
    try {
      const r = await DCM.runCatalogUpdate();
      toast(r.errno === 0 ? 'Fuentes actualizadas.' : backendError(r, 'update'), r.errno === 0 ? 'ok' : 'error');
      if (await catLoad()) catRender();
    } finally { setBusy(false); }
  });
  const cp = $('btnCatCompile');
  if (cp) cp.addEventListener('click', async () => {
    if (busy) return; setBusy(true);
    setText('catResults', 'Compilando…');
    try {
      const r = await DCM.runCatalogCompile();
      toast(r.errno === 0 ? 'Compilado.' : backendError(r, 'compile'), r.errno === 0 ? 'ok' : 'error');
      if (await catLoad()) catRender();
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
  if (!catCache.length) { await catLoad(); }
  const customs = catCache.filter((e) => e.id.indexOf('custom_') === 0);
  box.textContent = '';
  if (!customs.length) { box.textContent = '(sin fuentes personalizadas)'; return; }
  customs.forEach((e) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const t = document.createElement('div');
    t.textContent = (e.enabled ? '● ' : '○ ') + e.name + ' [' + e.id + ']';
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const tog = document.createElement('button');
    tog.textContent = e.enabled ? 'Desactivar' : 'Activar';
    tog.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = e.enabled ? await DCM.runCatalogDisable(e.id) : await DCM.runCatalogEnable(e.id);
        toast(rr.errno === 0 ? 'Listo.' : backendError(rr, 'catalog'), rr.errno === 0 ? 'ok' : 'error');
        if (await catLoad()) { customRender(); catRender(); }
      } finally { setBusy(false); }
    });
    const del = document.createElement('button');
    del.textContent = 'Eliminar'; del.className = 'small danger';
    del.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runCustomRemove(e.id);
        toast(rr.errno === 0 ? 'Eliminada.' : backendError(rr, 'remove'), rr.errno === 0 ? 'ok' : 'error');
        if (await catLoad()) { customRender(); catRender(); }
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
    if (!/^https:\/\//i.test(url)) { setText('customError', 'La URL debe empezar con https://'); return; }
    setText('customError', '');
    setBusy(true);
    try {
      const r = await DCM.runCustomAdd(url, name, '');
      toast(r.errno === 0 ? 'Fuente agregada (no activada).' : backendError(r, 'custom add'), r.errno === 0 ? 'ok' : 'error');
      if (r.errno === 0) { const u = $('customUrl'); if (u) u.value = ''; const n = $('customName'); if (n) n.value = ''; }
      if (await catLoad()) { customRender(); catRender(); }
    } finally { setBusy(false); }
  });
}

function wireBindhosts() {
  const an = $('btnBhAnalyze');
  if (an) an.addEventListener('click', async () => {
    if (busy) return;
    const dir = (($('bhDir') || {}).value || '').trim();
    if (!/^\//.test(dir)) { setText('bhError', 'Ingresa una ruta absoluta (empieza con /).'); return; }
    setText('bhError', '');
    setBusy(true);
    setText('bhResults', 'Analizando…');
    try {
      const r = await DCM.runBindhostsAnalyze(dir);
      setText('bhResults', (r.stdout || r.stderr || '').trim());
    } finally { setBusy(false); }
  });
  const im = $('btnBhImport');
  if (im) im.addEventListener('click', async () => {
    if (busy) return;
    const dir = (($('bhDir') || {}).value || '').trim();
    if (!/^\//.test(dir)) { setText('bhError', 'Ingresa una ruta absoluta.'); return; }
    if (!confirm('Importar desde ' + dir + '? Se agregaran dominios a blacklist/allowlist y se activaran fuentes reconocidas.')) return;
    setText('bhError', '');
    setBusy(true);
    setText('bhResults', 'Importando…');
    try {
      const r = await DCM.runBindhostsImport(dir);
      setText('bhResults', (r.stdout || r.stderr || '').trim());
      toast(r.errno === 0 ? 'Importado.' : backendError(r, 'import'), r.errno === 0 ? 'ok' : 'error');
      if (await catLoad()) catRender();
    } finally { setBusy(false); }
  });
}

async function svcRender() {
  const box = $('svcList');
  if (!box) return;
  const r = await DCM.runServiceListJson();
  if (r.errno !== 0) { setText('svcList', backendError(r, 'service list')); return; }
  const d = safeParse(r.stdout);
  if (!d || !d.controls) { setText('svcList', 'Sin controles.'); return; }
  box.textContent = '';
  if (!d.controls.length) { box.textContent = '(sin controles disponibles)'; return; }
  d.controls.forEach((c) => {
    const row = document.createElement('div');
    row.className = 'event-row';
    const head = document.createElement('div');
    head.textContent = c.name + ' — modo: ' + c.mode + ' [' + c.confidence + ']';
    const sel = document.createElement('select');
    DCM.SVC_MODES.forEach((m) => {
      const o = document.createElement('option'); o.value = m;
      o.textContent = m === 'normal' ? 'Normal' : (m === 'boot' ? 'Hasta reiniciar' : (m === 'perm' ? 'Siempre' : m));
      if (m === c.mode) o.selected = true;
      sel.appendChild(o);
    });
    const acts = document.createElement('div');
    acts.className = 'event-actions';
    const apply = document.createElement('button');
    apply.textContent = 'Aplicar'; apply.className = 'primary';
    apply.addEventListener('click', async () => {
      if (busy) return; setBusy(true);
      try {
        const rr = await DCM.runServiceSet(c.id, sel.value);
        setText('svcList', (rr.stdout || rr.stderr || '').trim());
        toast(rr.errno === 0 ? 'Aplicado.' : backendError(rr, 'service set'), rr.errno === 0 ? 'ok' : 'error');
        await svcRender();
      } finally { setBusy(false); }
    });
    acts.appendChild(sel); acts.appendChild(apply);
    row.appendChild(head); row.appendChild(acts);
    box.appendChild(row);
  });
}

async function initCatalogRC2() {
  wireCatalog();
  wireCustom();
  wireBindhosts();
  await svcRender();
  await customRender();
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

function init() {
  // Navegacion (SPA) e idioma se inicializan SIEMPRE, haya o no puente ksu.
  if (typeof Router !== 'undefined' && Router.init) {
    try { Router.init(); } catch (_) {}
  }
  if (typeof I18N !== 'undefined' && I18N.init) {
    try {
      I18N.init().then(function () {
        const sel = $('langSelect');
        if (sel) {
          sel.value = I18N.current();
          sel.addEventListener('change', function () {
            if (I18N.setLang) I18N.setLang(sel.value);
          });
        }
      });
    } catch (_) {}
  }
  if (!DCM.available()) {
    const b = $('ksuBanner');
    if (b) { b.textContent = STR.noKsu; b.classList.remove('hidden'); }
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
    startPolling();
  });
}

document.addEventListener('DOMContentLoaded', init);
