/* webroot/js/i18n.js  —  DNSCrypt Manager v0.3.0-RC1
 *
 * i18n minimalista y seguro para la WebUI. English es el idioma por defecto y
 * el fallback; el usuario puede elegir Español y la elección se persiste. No
 * depende del idioma del sistema. Solo texto visible; nunca traduce ids,
 * comandos, claves JSON, dominios ni URLs. DOM seguro: textContent, sin eval.
 */
const I18N = (() => {
  const SUPPORTED = ['en', 'es'];
  const DEFAULT = 'en';
  const STORE_KEY = 'dcm_lang';
  let base = {};      // diccionario EN (fallback siempre cargado)
  let dict = {};      // diccionario del idioma activo
  let lang = DEFAULT;

  function safeStoreGet() {
    try { return window.localStorage.getItem(STORE_KEY); } catch (_) { return null; }
  }
  function safeStoreSet(v) {
    try { window.localStorage.setItem(STORE_KEY, v); } catch (_) { /* no-op */ }
  }

  async function fetchDict(code) {
    try {
      const r = await fetch('i18n/' + code + '.json', { cache: 'no-store' });
      if (!r.ok) return null;
      const d = await r.json();
      return (d && typeof d === 'object') ? d : null;
    } catch (_) { return null; }
  }

  // Traduce una clave: idioma activo -> EN -> la propia clave (nunca undefined).
  function t(key) {
    if (Object.prototype.hasOwnProperty.call(dict, key)) return dict[key];
    if (Object.prototype.hasOwnProperty.call(base, key)) return base[key];
    return key;
  }

  // Aplica traducciones a un subarbol. Usa SOLO textContent y setAttribute con
  // atributos de una allowlist. data-i18n = clave para textContent;
  // data-i18n-ph = clave para placeholder; data-i18n-aria = clave para aria-label.
  function apply(root) {
    const r = root || document;
    r.querySelectorAll('[data-i18n]').forEach((el) => {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    r.querySelectorAll('[data-i18n-ph]').forEach((el) => {
      el.setAttribute('placeholder', t(el.getAttribute('data-i18n-ph')));
    });
    r.querySelectorAll('[data-i18n-aria]').forEach((el) => {
      el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria')));
    });
    try { document.documentElement.setAttribute('lang', lang); } catch (_) { /* no-op */ }
  }

  function current() { return lang; }
  function supported() { return SUPPORTED.slice(); }

  // Cambia de idioma en caliente, persiste y reaplica.
  async function setLang(code) {
    if (SUPPORTED.indexOf(code) < 0) code = DEFAULT;
    lang = code;
    safeStoreSet(code);
    if (code === DEFAULT) {
      dict = base;
    } else {
      const d = await fetchDict(code);
      dict = d || base;   // fallback a EN si falla la carga
    }
    apply(document);
  }

  // Inicializa: carga EN como base/fallback, luego el idioma elegido (o EN).
  async function init() {
    base = (await fetchDict(DEFAULT)) || {};
    const stored = safeStoreGet();
    const chosen = (stored && SUPPORTED.indexOf(stored) >= 0) ? stored : DEFAULT;
    await setLang(chosen);
    return lang;
  }

  return { init, setLang, t, apply, current, supported };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = I18N; }
