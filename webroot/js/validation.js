/* DNSCrypt Manager - validation.js
 *
 * Validadores del LADO CLIENTE. Existen solo para dar feedback inmediato
 * en la interfaz (marcar un campo en rojo antes de tocar la red/CLI).
 *
 * La validacion que realmente importa para la seguridad vive del lado
 * servidor, en scripts/common.sh (valid_nextdns_id, valid_doh_url, etc.)
 * y se aplica de nuevo ahi SIEMPRE, sin excepciones. Si estos dos
 * validadores llegaran a desincronizarse, gana el servidor: en el peor
 * caso la UI deja pasar algo que la CLI va a rechazar igual.
 */
'use strict';

const DCMValidate = (() => {
  const RE = {
    nextdnsId: /^[0-9a-fA-F]{4,12}$/,
    ipv4: /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/,
    ipv6: /^[0-9a-fA-F:]+$/,
    host: /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/,
    stamp: /^sdns:\/\/[A-Za-z0-9_-]+=*$/
  };

  function nextdnsId(v) {
    const s = String(v == null ? '' : v).trim();
    if (!s) return { ok: false, msg: 'Ingresa el Configuration ID de NextDNS.' };
    if (!RE.nextdnsId.test(s)) {
      return { ok: false, msg: 'Debe ser hexadecimal de 4 a 12 caracteres (ej: abcdef).' };
    }
    return { ok: true, msg: '' };
  }

  function ip(v) {
    const s = String(v == null ? '' : v).trim();
    if (RE.ipv4.test(s)) return { ok: true, msg: '' };
    if (RE.ipv6.test(s) && s.includes(':') && s.length <= 45) return { ok: true, msg: '' };
    return { ok: false, msg: 'Direccion IP invalida (IPv4 o IPv6).' };
  }

  function host(v) {
    const s = String(v == null ? '' : v).trim();
    if (s.length && s.length <= 253 && RE.host.test(s)) return { ok: true, msg: '' };
    return { ok: false, msg: 'Nombre de host invalido.' };
  }

  function doh(v) {
    const s = String(v == null ? '' : v).trim();
    if (!s.startsWith('https://')) return { ok: false, msg: 'La URL DoH debe empezar con https://' };
    if (/[\s;&|$`<>()"'\\]/.test(s)) return { ok: false, msg: 'La URL contiene caracteres no permitidos.' };
    if (s.length > 512) return { ok: false, msg: 'URL demasiado larga.' };
    return { ok: true, msg: '' };
  }

  function stamp(v) {
    const s = String(v == null ? '' : v).trim();
    if (!RE.stamp.test(s) || s.length > 1024) return { ok: false, msg: 'DNS stamp invalido (formato sdns://...).' };
    return { ok: true, msg: '' };
  }

  /* Dominio para allowlist / excepciones. MISMA clase que la CLI
   * (sec_valid_domain): minusculas, etiquetas alfanumericas con guiones
   * internos, al menos un punto, y explicitamente NO una IPv4. Rechaza
   * http://, barras, comodines, comillas y metacaracteres de shell. */
  const RE_DOMAIN = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/;
  function isValidDomain(v) {
    const s = String(v == null ? '' : v).trim().toLowerCase();
    if (!s) return { ok: false, msg: 'Ingresa un dominio (ej: example.com).' };
    if (s.length > 253) return { ok: false, msg: 'Dominio demasiado largo.' };
    if (RE.ipv4.test(s)) return { ok: false, msg: 'Es una IP, no un dominio. Usa un nombre como example.com.' };
    if (!RE_DOMAIN.test(s)) {
      return { ok: false, msg: 'Dominio invalido. Formato: example.com o sub.example.com (sin http://, barras ni comodines).' };
    }
    return { ok: true, msg: '', value: s };
  }

  return { nextdnsId, ip, host, doh, stamp, isValidDomain };
})();
