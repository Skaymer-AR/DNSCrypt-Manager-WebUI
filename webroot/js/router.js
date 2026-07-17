/* webroot/js/router.js  —  DNSCrypt Manager v0.3.0-RC1
 *
 * Router hash minimalista para la SPA. Muestra/oculta contenedores .route sin
 * recargar la pagina, marca el item activo de la navegacion inferior, recuerda
 * la ultima pestaña y responde al boton Atras (evento hashchange). Defensivo:
 * si faltan elementos (p.ej. en tests con DOM mockeado) no lanza. DOM seguro.
 */
const Router = (() => {
  const ROUTES = ['status', 'dns', 'lists', 'activity', 'settings'];
  const DEFAULT = 'status';
  const STORE_KEY = 'dcm_tab';
  let onChange = null;

  function storeGet() { try { return window.localStorage.getItem(STORE_KEY); } catch (_) { return null; } }
  function storeSet(v) { try { window.localStorage.setItem(STORE_KEY, v); } catch (_) {} }

  function routeFromHash() {
    const h = (window.location && window.location.hash) ? window.location.hash : '';
    const m = /^#\/([a-z]+)/.exec(h);
    const r = m ? m[1] : '';
    return ROUTES.indexOf(r) >= 0 ? r : '';
  }

  function show(route) {
    if (ROUTES.indexOf(route) < 0) route = DEFAULT;
    // contenedores
    ROUTES.forEach((r) => {
      const el = document.getElementById('route-' + r);
      if (el) { if (r === route) el.removeAttribute('hidden'); else el.setAttribute('hidden', ''); }
    });
    // estado activo de la nav
    const items = document.querySelectorAll('[data-nav]');
    if (items && items.forEach) {
      items.forEach((a) => {
        const on = a.getAttribute('data-nav') === route;
        if (on) a.classList.add('active'); else a.classList.remove('active');
        if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
      });
    }
    // scroll al tope del contenido al cambiar de seccion
    try { const v = document.getElementById('views'); if (v && v.scrollTo) v.scrollTo(0, 0); else window.scrollTo(0, 0); } catch (_) {}
    storeSet(route);
    if (typeof onChange === 'function') { try { onChange(route); } catch (_) {} }
  }

  function sync() {
    const fromHash = routeFromHash();
    if (fromHash) { show(fromHash); return; }
    // sin hash valido: usar la ultima pestaña recordada (o el default) y fijar el hash
    const remembered = storeGet();
    const start = (ROUTES.indexOf(remembered) >= 0) ? remembered : DEFAULT;
    // fijar el hash dispara hashchange -> show; si no cambia, mostrar directo
    if (('#/' + start) !== (window.location ? window.location.hash : '')) {
      try { window.location.hash = '#/' + start; } catch (_) { show(start); }
    } else {
      show(start);
    }
  }

  function go(route) {
    if (ROUTES.indexOf(route) < 0) return;
    try { window.location.hash = '#/' + route; } catch (_) { show(route); }
  }

  function init(opts) {
    onChange = (opts && typeof opts.onChange === 'function') ? opts.onChange : null;
    try { window.addEventListener('hashchange', sync); } catch (_) {}
    sync();
  }

  return { init, go, sync, routes: () => ROUTES.slice(), current: () => routeFromHash() || DEFAULT };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = Router; }
