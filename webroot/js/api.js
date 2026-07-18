/* DNSCrypt Manager - api.js
 *
 * Puente con la API WebUI de KernelSU / KernelSU Next / APatch.
 *
 * API utilizada (documentada en kernelsu.org, seccion "Module WebUI"; el
 * paquete npm oficial `kernelsu` envuelve exactamente esta interfaz):
 *
 *   window.ksu.exec(command: string, options: string(JSON), callbackName: string)
 *     -> al terminar invoca window[callbackName](errno, stdout, stderr)
 *   window.ksu.toast(mensaje: string)
 *
 * KernelSU Next y APatch (WebUI/WebUI-X) exponen el mismo objeto `ksu`.
 * Magisk NO tiene WebUI nativa: si `ksu` no existe, esta pagina lo informa
 * y la gestion queda en la CLI (`su -c dnscrypt-manager ...`) o `action.sh`.
 * No se inventa ninguna otra API.
 *
 * SEGURIDAD: lista blanca. La UI solo puede ejecutar las cadenas EXACTAS de
 * COMMANDS. Ningun dato del usuario se interpola jamas en un comando.
 */
'use strict';

const DCM = (() => {
  // Resolvedor central de la ruta de la CLI. SOLO estas 3 rutas (allowlist), en
  // orden. No se aceptan rutas del usuario; el probe es una cadena FIJA construida
  // a partir de estas constantes (sin datos externos, sin eval, sin find global).
  const CLI_PATHS = Object.freeze([
    '/system/bin/dnscrypt-manager',
    '/data/adb/modules/dnscrypt_manager/system/bin/dnscrypt-manager',
    '/data/adb/modules_update/dnscrypt_manager/system/bin/dnscrypt-manager'
  ]);
  let CLI = CLI_PATHS[0];      // valor por defecto hasta resolver
  let CLI_RESOLVED = false;
  // Probe FIJO: prueba las 3 rutas y devuelve la primera ejecutable. Las rutas no
  // contienen comillas simples, asi que el comillado simple es seguro.
  const CLI_PROBE = "for p in '" + CLI_PATHS.join("' '") +
    "'; do [ -x \"$p\" ] && { printf '%s' \"$p\"; break; }; done";
  function cli() { return CLI; }
  function cliResolved() { return CLI_RESOLVED; }
  function cliPaths() { return CLI_PATHS.slice(); }
  async function resolveCli() {
    if (!available()) return null;
    const r = await runRawT(CLI_PROBE, 8000);
    const found = String(r && r.stdout ? r.stdout : '').trim();
    if (CLI_PATHS.indexOf(found) >= 0) { CLI = found; CLI_RESOLVED = true; return found; }
    CLI_RESOLVED = false;
    return null;
  }

  const COMMANDS = Object.freeze({
    status:         CLI + ' status --json',
    start:          CLI + ' start',
    stop:           CLI + ' stop',
    restart:        CLI + ' restart',
    testDns:        CLI + ' test-dns',
    redirectApply:  CLI + ' redirect apply',
    redirectRemove: CLI + ' redirect remove',
    bootRedirOn:    CLI + ' set-flag boot_redirect 1',
    bootRedirOff:   CLI + ' set-flag boot_redirect 0',
    logs:           CLI + ' logs --tail 120',
    logsClear:      CLI + ' logs --clear',
    privateDns:     CLI + ' privatedns',
    panic:          CLI + ' panic',
    enable:         CLI + ' enable',

    /* --- Seguridad v0.2.0: TODAS cadenas FIJAS (JSON donde aplica) --- */
    protectionStatus:   CLI + ' protection status --json',
    blocklistsStatus:   CLI + ' blocklists status --json',
    blocklistsUpdate:   CLI + ' blocklists update all',
    blocklistsValidate: CLI + ' blocklists validate',
    allowlistList:      CLI + ' allowlist list --json',
    tempAllowList:      CLI + ' temporary-allow list --json',
    tempAllowSweep:     CLI + ' temporary-allow sweep',
    profileStatus:      CLI + ' security-profile status --json',
    profileBalanced:    CLI + ' security-profile balanced',
    profileStrict:      CLI + ' security-profile strict --confirmed',
    profilePrivacy:     CLI + ' security-profile privacy',
    failclosedStatus:   CLI + ' failclosed status --json',
    failclosedEnable:   CLI + ' failclosed enable --confirmed',
    failclosedDisable:  CLI + ' failclosed disable',
    leakTest:           CLI + ' leak-test --json',
    eventsList:         CLI + ' events list --limit 100 --json',
    eventsStats:        CLI + ' events stats --json',
    eventsClear:        CLI + ' events clear',
    eventsPause:        CLI + ' events pause',
    eventsResume:       CLI + ' events resume'
  });

  function available() {
    return typeof window.ksu !== 'undefined' &&
           typeof window.ksu.exec === 'function';
  }

  let seq = 0;

  function execWhitelisted(action) {
    const cmd = COMMANDS[action];
    if (!cmd) {
      return Promise.resolve({ errno: -1, stdout: '', stderr: 'Accion no permitida: ' + action });
    }
    return new Promise((resolve) => {
      if (!available()) {
        resolve({ errno: -1, stdout: '', stderr: 'API ksu no disponible en este entorno.' });
        return;
      }
      const cb = '__dcm_cb_' + Date.now() + '_' + (seq++);
      let done = false;
      window[cb] = (errno, stdout, stderr) => {
        if (done) return;
        done = true;
        try { delete window[cb]; } catch (_) { window[cb] = undefined; }
        resolve({ errno: Number(errno), stdout: String(stdout || ''), stderr: String(stderr || '') });
      };
      // Timeout defensivo: si el host nunca llama al callback, no colgamos la UI.
      setTimeout(() => {
        if (done) return;
        done = true;
        try { delete window[cb]; } catch (_) { window[cb] = undefined; }
        resolve({ errno: -1, stdout: '', stderr: 'Tiempo de espera agotado (30 s).' });
      }, 30000);
      try {
        window.ksu.exec(cmd, JSON.stringify({}), cb);
      } catch (e) {
        if (!done) {
          done = true;
          try { delete window[cb]; } catch (_) { window[cb] = undefined; }
          resolve({ errno: -1, stdout: '', stderr: String(e) });
        }
      }
    });
  }

  function toast(msg) {
    try {
      if (available() && typeof window.ksu.toast === 'function') window.ksu.toast(msg);
    } catch (_) { /* silencioso */ }
  }

  /* ---------------------------------------------------------------------
   * Proveedor preestablecido: 4 comandos FIJOS (sin interpolar nada).
   * Es el patron mas seguro posible: cada boton dispara una cadena literal
   * que ya existe de antemano, igual que el resto de COMMANDS.
   * ------------------------------------------------------------------- */
  const PROVIDER_COMMANDS = Object.freeze({
    cloudflare: CLI + ' provider cloudflare',
    quad9:      CLI + ' provider quad9',
    adguard:    CLI + ' provider adguard',
    mullvad:    CLI + ' provider mullvad'
  });

  function runProvider(name) {
    const cmd = PROVIDER_COMMANDS[name];
    if (!cmd) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Proveedor no reconocido: ' + name });
    return runRaw(cmd);
  }

  /* ---------------------------------------------------------------------
   * IPv6 al redirigir: 2 comandos fijos (redirect = NAT normal, block =
   * cortar DNS v6 en tabla filter). Ver CLI: set-flag ipv6_mode {valor}.
   * ------------------------------------------------------------------- */
  const IPV6_MODE_COMMANDS = Object.freeze({
    redirect: CLI + ' set-flag ipv6_mode redirect',
    block:    CLI + ' set-flag ipv6_mode block'
  });

  function runIpv6Mode(mode) {
    const cmd = IPV6_MODE_COMMANDS[mode];
    if (!cmd) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Modo IPv6 no reconocido: ' + mode });
    return runRaw(cmd);
  }

  /* ---------------------------------------------------------------------
   * NextDNS: UNICO comando de esta WebUI con un parametro variable.
   *
   * Por que es seguro interpolar `id` en la cadena de comando:
   *   - `id` se valida ACA con la MISMA clase de caracteres que usa el
   *     validador del lado servidor (scripts/common.sh: valid_nextdns_id):
   *     hexadecimal puro, 4 a 12 caracteres. Ese conjunto de caracteres
   *     no incluye espacios, comillas, `;`, `&`, `|`, `$`, backticks ni
   *     `<>()` — es decir, no existe forma de romper el comando con un
   *     valor que pase este regex.
   *   - Aunque este chequeo del lado cliente se saltee o falle, la CLI
   *     vuelve a validar con el MISMO patron antes de tocar el TOML
   *     (cmd_nextdns llama a valid_nextdns_id "$1"); un valor invalido
   *     se rechaza ahi con exit 1 y CERO efectos secundarios (probado:
   *     ver bateria de pruebas, caso T8/T9).
   *   - El argumento ademas viaja como "$1" citado en el shell script,
   *     nunca por 'eval' ni por expansion sin comillas.
   * ------------------------------------------------------------------- */
  const NEXTDNS_ID_RE = /^[0-9a-fA-F]{4,12}$/;

  function runNextdns(id) {
    const clean = String(id == null ? '' : id).trim();
    if (!NEXTDNS_ID_RE.test(clean)) {
      return Promise.resolve({
        errno: -1, stdout: '',
        stderr: 'ID de NextDNS invalido: debe ser hexadecimal de 4 a 12 caracteres (ej: abcdef).'
      });
    }
    return runRaw(CLI + ' nextdns ' + clean);
  }

  /* ---------------------------------------------------------------------
   * Proteccion por categoria: 12 comandos FIJOS (6 categorias x on/off).
   * Igual que PROVIDER_COMMANDS: cada boton dispara una cadena literal.
   * ------------------------------------------------------------------- */
  const CATEGORIES = Object.freeze(['malware', 'phishing', 'scams', 'trackers', 'ads', 'cryptomining']);
  const PROTECTION_COMMANDS = (() => {
    const m = {};
    CATEGORIES.forEach((c) => {
      m['enable_' + c] = CLI + ' protection enable ' + c;
      m['disable_' + c] = CLI + ' protection disable ' + c;
    });
    return Object.freeze(m);
  })();

  function runProtection(cat, enable) {
    const cmd = PROTECTION_COMMANDS[(enable ? 'enable_' : 'disable_') + cat];
    if (!cmd) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Categoria no reconocida: ' + cat });
    return runRaw(cmd);
  }

  /* Actualizar/rollback UNA categoria: cadena fija a partir de la lista blanca. */
  function runBlocklistUpdateCat(cat) {
    if (CATEGORIES.indexOf(cat) < 0) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Categoria no reconocida: ' + cat });
    return runRaw(CLI + ' blocklists update ' + cat);
  }
  function runBlocklistRollbackCat(cat) {
    if (CATEGORIES.indexOf(cat) < 0) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Categoria no reconocida: ' + cat });
    return runRaw(CLI + ' blocklists rollback ' + cat);
  }

  /* ---------------------------------------------------------------------
   * Acciones con DOMINIO variable (allowlist / temporary-allow / eventos).
   *
   * Mismo razonamiento de seguridad que runNextdns: el dominio se valida
   * ACA con la misma clase de caracteres que la CLI (letras/digitos/./-,
   * sin espacios ni ; & | $ ` < > ( ) comillas ni backslash), y la CLI lo
   * REVALIDA con sec_valid_domain antes de tocar nada. Un valor invalido se
   * rechaza en ambos lados con CERO efectos. El dominio viaja citado como
   * "$1" en el shell; nunca por eval.
   * ------------------------------------------------------------------- */
  const DOMAIN_RE = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/;
  const DURATIONS = Object.freeze(['5m', '15m', '1h', 'boot', 'perm']);

  function cleanDomain(d) {
    return String(d == null ? '' : d).trim().toLowerCase();
  }
  function domainInvalidResult(d) {
    return Promise.resolve({
      errno: -1, stdout: '',
      stderr: 'Dominio invalido: "' + d + '". Formato: example.com o sub.example.com ' +
              '(sin http://, sin barras, sin comodines, sin IP).'
    });
  }

  function runAllowlistAdd(domain) {
    const d = cleanDomain(domain);
    if (!DOMAIN_RE.test(d) || d.length > 253) return domainInvalidResult(domain);
    return runRaw(CLI + ' allowlist add ' + d);
  }
  function runAllowlistRemove(domain) {
    const d = cleanDomain(domain);
    if (!DOMAIN_RE.test(d) || d.length > 253) return domainInvalidResult(domain);
    return runRaw(CLI + ' allowlist remove ' + d);
  }
  function runAllowlistSearch(domain) {
    const d = cleanDomain(domain).replace(/[^a-z0-9.-]/g, '');
    if (!d) return Promise.resolve({ errno: -1, stdout: '', stderr: 'Termino de busqueda vacio.' });
    return runRaw(CLI + ' allowlist search ' + d);
  }
  function runTempAllowAdd(domain, duration, reason) {
    const d = cleanDomain(domain);
    if (!DOMAIN_RE.test(d) || d.length > 253) return domainInvalidResult(domain);
    if (DURATIONS.indexOf(duration) < 0) {
      return Promise.resolve({ errno: -1, stdout: '', stderr: 'Duracion no reconocida: ' + duration });
    }
    let cmd = CLI + ' temporary-allow add ' + d + ' ' + duration + ' --origin webui';
    // Motivo OPCIONAL: colapsado a UNA sola palabra segura (sin espacios ni
    // metacaracteres) para preservar la forma fija del comando. La CLI ademas
    // lo sanea con tr -cd. Si queda vacio tras sanear, no se agrega.
    if (reason != null) {
      const safe = String(reason).trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 60);
      if (safe.length) cmd += ' --reason ' + safe;
    }
    return runRaw(cmd);
  }
  function runTempAllowRemove(domain) {
    const d = cleanDomain(domain);
    if (!DOMAIN_RE.test(d) || d.length > 253) return domainInvalidResult(domain);
    return runRaw(CLI + ' temporary-allow remove ' + d);
  }

  // Ejecuta una cadena de comando ya validada/fija (uso interno de este modulo).
  function runRaw(cmd) {
    return runRawT(cmd, 30000);
  }

  // Variante con timeout configurable (compilaciones grandes tardan mas).
  function runRawT(cmd, ms) {
    return new Promise((resolve) => {
      if (!available()) {
        resolve({ errno: -1, stdout: '', stderr: 'API ksu no disponible en este entorno.' });
        return;
      }
      const cb = '__dcm_cb_' + Date.now() + '_' + (seq++);
      let done = false;
      window[cb] = (errno, stdout, stderr) => {
        if (done) return;
        done = true;
        try { delete window[cb]; } catch (_) { window[cb] = undefined; }
        resolve({ errno: Number(errno), stdout: String(stdout || ''), stderr: String(stderr || '') });
      };
      setTimeout(() => {
        if (done) return;
        done = true;
        try { delete window[cb]; } catch (_) { window[cb] = undefined; }
        resolve({ errno: -1, stdout: '', stderr: 'Tiempo de espera agotado.' });
      }, ms);
      try {
        window.ksu.exec(cmd, JSON.stringify({}), cb);
      } catch (e) {
        if (!done) {
          done = true;
          try { delete window[cb]; } catch (_) { window[cb] = undefined; }
          resolve({ errno: -1, stdout: '', stderr: String(e) });
        }
      }
    });
  }

  /* -----------------------------------------------------------------------
   * CATALOGO / SERVICIOS / BINDHOSTS (v0.2.0-RC2)
   * Cada funcion mapea a UN subcomando fijo (allowlist). app.js NUNCA pasa una
   * linea de shell; solo pasa valores concretos (id, url, ruta, modo) que se
   * validan aca contra listas blancas y se interpolan SIEMPRE entre comillas
   * simples (shQuote). Sin eval, sin sh -c armado con datos, sin source. La CLI
   * revalida todo. ksu.exec corre via shell, por eso el comillado es obligatorio.
   * --------------------------------------------------------------------- */
  // SOURCE_ID / SERVICE_CONTROL_ID: empieza alfanumerico, luego [a-z0-9._-], <=64.
  const SOURCE_ID_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
  const SVC_MODES = Object.freeze(['normal', '15m', '1h', 'boot', 'perm']);
  // URL: solo https://, sin comillas ni metacaracteres de shell peligrosos
  // ($ ( ) ; backtick ' " < > | espacio * ! ,). Se permiten los de query (& ? = %).
  const URL_RE = /^https:\/\/[A-Za-z0-9._~:/?#@+=%&-]{3,509}$/;
  // Ruta de importacion: absoluta, sin '..', sin comillas, longitud acotada.
  const PATH_RE = /^\/[A-Za-z0-9._/-]{0,511}$/;

  // Comillado shell seguro: envuelve en comillas simples. Los valores ya se
  // validaron para EXCLUIR la comilla simple, de modo que esto es inyectable-safe.
  function shQuote(s) {
    const v = String(s == null ? '' : s);
    if (v.indexOf("'") >= 0 || /[\u0000-\u001f]/.test(v)) return null; // no debería pasar
    return "'" + v + "'";
  }
  function argErr(msg) { return Promise.resolve({ errno: -1, stdout: '', stderr: msg }); }
  function validId(id) { return SOURCE_ID_RE.test(String(id == null ? '' : id)); }

  function runEnvironmentStatus() { return runRawT(CLI + ' environment status', 8000); }
  function runCatalogListJson() { return runRawT(CLI + ' catalog list --json', 45000); }
  function runServiceListJson() { return runRaw(CLI + ' service list --json'); }
  function runCatalogInfo(id) {
    if (!validId(id)) return argErr('Identificador de fuente invalido.');
    return runRaw(CLI + ' catalog info ' + shQuote(id));
  }
  function runCatalogEnable(id) {
    if (!validId(id)) return argErr('Identificador de fuente invalido.');
    return runRawT(CLI + ' catalog enable ' + shQuote(id), 180000);
  }
  function runCatalogDisable(id) {
    if (!validId(id)) return argErr('Identificador de fuente invalido.');
    return runRawT(CLI + ' catalog disable ' + shQuote(id), 180000);
  }
  function runCatalogUpdate() { return runRawT(CLI + ' catalog update enabled', 300000); }
  function runCatalogCompile() { return runRawT(CLI + ' catalog compile', 300000); }
  function runCatalogConflicts() { return runRaw(CLI + ' catalog conflicts'); }

  function runServiceSet(id, mode) {
    if (!validId(id)) return argErr('Identificador de control invalido.');
    if (SVC_MODES.indexOf(mode) < 0) return argErr('Modo invalido.');
    return runRawT(CLI + ' service set ' + shQuote(id) + ' ' + shQuote(mode), 180000);
  }

  function runCustomAdd(url, name, category) {
    const u = String(url == null ? '' : url).trim();
    if (!URL_RE.test(u)) return argErr('URL invalida. Debe ser https:// y sin caracteres peligrosos.');
    const qu = shQuote(u);
    if (!qu) return argErr('URL invalida.');
    let cmd = CLI + ' catalog custom add ' + qu;
    const n = String(name == null ? '' : name).replace(/[^A-Za-z0-9 ._-]+/g, ' ').trim().slice(0, 60);
    if (n) cmd += ' --name ' + shQuote(n.replace(/\s+/g, '_'));
    const c = String(category == null ? '' : category).replace(/[^a-z_,]+/g, '');
    if (c) cmd += ' --category ' + shQuote(c);
    return runRawT(cmd, 60000);
  }
  function runCustomRemove(id) {
    if (!validId(id)) return argErr('Identificador de fuente invalido.');
    return runRawT(CLI + ' catalog custom remove ' + shQuote(id), 120000);
  }

  function checkPath(dir) {
    const d = String(dir == null ? '' : dir).trim();
    if (!PATH_RE.test(d) || d.indexOf('..') >= 0 || d.charAt(0) === '-') return null;
    return shQuote(d);
  }
  function runBindhostsAnalyze(dir) {
    const qd = checkPath(dir);
    if (!qd) return argErr('Ruta invalida. Debe ser absoluta y sin caracteres peligrosos.');
    return runRawT(CLI + ' import-bindhosts ' + qd + ' --dry-run', 60000);
  }
  function runBindhostsImport(dir) {
    const qd = checkPath(dir);
    if (!qd) return argErr('Ruta invalida. Debe ser absoluta y sin caracteres peligrosos.');
    return runRawT(CLI + ' import-bindhosts ' + qd + ' --confirmed', 300000);
  }

  return {
    run: execWhitelisted,
    runProvider,
    runIpv6Mode,
    runNextdns,
    runProtection,
    runBlocklistUpdateCat,
    runBlocklistRollbackCat,
    runAllowlistAdd,
    runAllowlistRemove,
    runAllowlistSearch,
    runTempAllowAdd,
    runTempAllowRemove,
    runCatalogListJson,
    runCatalogInfo,
    runCatalogEnable,
    runCatalogDisable,
    runCatalogUpdate,
    runCatalogCompile,
    runCatalogConflicts,
    runServiceListJson,
    runServiceSet,
    runCustomAdd,
    runCustomRemove,
    runBindhostsAnalyze,
    runBindhostsImport,
    available,
    resolveCli,
    runEnvironmentStatus,
    cli,
    cliResolved,
    cliPaths,
    toast,
    COMMANDS,
    CATEGORIES,
    DURATIONS,
    SVC_MODES,
    NEXTDNS_ID_RE,
    DOMAIN_RE
  };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = DCM; }
