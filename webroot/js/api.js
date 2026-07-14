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
  const CLI = '/system/bin/dnscrypt-manager';

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
    enable:         CLI + ' enable'
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

  // Ejecuta una cadena de comando ya validada/fija (uso interno de este modulo).
  function runRaw(cmd) {
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

  return {
    run: execWhitelisted,
    runProvider,
    runIpv6Mode,
    runNextdns,
    available,
    toast,
    COMMANDS,
    NEXTDNS_ID_RE
  };
})();
