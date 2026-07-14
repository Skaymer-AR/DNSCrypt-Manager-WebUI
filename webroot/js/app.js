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

/* ------------------------------------------------------------------------ */
function init() {
  if (!DCM.available()) {
    const b = $('ksuBanner');
    if (b) { b.textContent = STR.noKsu; b.classList.remove('hidden'); }
    // Sin puente ksu no hay nada mas para hacer: no arrancamos el polling.
    return;
  }
  wireServiceButtons();
  wireTestDns();
  wireProviders();
  wireRedirect();
  wirePrivateDns();
  wireLogs();
  wirePanic();
  startPolling();
}

document.addEventListener('DOMContentLoaded', init);
