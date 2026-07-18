#!/system/bin/sh
# scripts/bypass.sh  —  DNSCrypt Manager v0.3.0-RC1  (CHECKPOINT C.2)
#
# Detección best-effort de bypass/fugas DNS. Modos: audit / warning / strict.
# strict OFF por defecto. NUNCA bloquea todo HTTPS; NUNCA clasifica todo 443 como
# DoH. Cada señal reporta un nivel de confianza (info/warning/high).

BP_DIR="${DATA_DIR}/bypass"
BP_CONF="$BP_DIR/config.tsv"

bypass_init() { mkdir -p "$BP_DIR" 2>/dev/null; chmod 0700 "$BP_DIR" 2>/dev/null; [ -f "$BP_CONF" ] || printf 'mode\taudit\n' > "$BP_CONF"; chmod 0600 "$BP_CONF" 2>/dev/null; }
bypass_mode() { bypass_init; grep -m1 '^mode' "$BP_CONF" 2>/dev/null | cut -f2; }
_bp_row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }   # señal | estado | confianza

# Lista mínima y mantenible de hostnames de DoH conocidos (para detección por
# dominio, NO por puerto). No exhaustiva; ampliable.
_bp_known_doh() { printf '%s\n' dns.google cloudflare-dns.com mozilla.cloudflare-dns.com dns.quad9.net doh.opendns.com dns.adguard.com dns.nextdns.io; }

# bypass_audit: recolecta señales. TEST override por variables DCM_BP_TEST_*.
bypass_audit() {
  bypass_init
  _tget() { eval "printf '%s' \"\${DCM_BP_TEST_$1:-}\""; }   # solo lee, sin datos externos
  # redirección activa
  _rd=no; command -v redirect_is_active >/dev/null 2>&1 && redirect_is_active && _rd=yes
  [ "$_rd" = yes ] && _bp_row redirect_active protegido info || _bp_row redirect_active ausente warning
  # proxy vivo
  _px=no; command -v cmd_is_running >/dev/null 2>&1 && cmd_is_running 2>/dev/null && _px=yes
  [ "$_px" = yes ] && _bp_row proxy_running protegido info || _bp_row proxy_running caido high
  # Private DNS (DoT del sistema puede eludir)
  _pdm=$( { [ -n "$(_tget PRIVATE_DNS)" ] && _tget PRIVATE_DNS; } || { command -v settings >/dev/null 2>&1 && settings get global private_dns_mode 2>/dev/null; } )
  case "$_pdm" in
    off) _bp_row private_dns protegido info ;;
    hostname) _bp_row private_dns dot_configurado warning ;;
    opportunistic) _bp_row private_dns dot_oportunista info ;;
    *) _bp_row private_dns no_verificable info ;;
  esac
  # VPN
  _vpn=$( [ -n "$(_tget VPN)" ] && _tget VPN || { command -v ip >/dev/null 2>&1 && ip -o link 2>/dev/null | grep -Eq '(tun|wg|ppp)[0-9]*:' && echo yes || echo no; } )
  [ "$_vpn" = yes ] && _bp_row vpn activa warning || _bp_row vpn ausente info
  # hotspot / tethering
  _hs=$( [ -n "$(_tget HOTSPOT)" ] && _tget HOTSPOT || { command -v ip >/dev/null 2>&1 && ip -o link 2>/dev/null | grep -Eq '(ap0|wlan1|softap|rndis)[0-9]*:' && echo yes || echo no; } )
  [ "$_hs" = yes ] && _bp_row hotspot activo info || _bp_row hotspot ausente info
  # puertos de salida directa (best-effort): 53 UDP/TCP y 853 DoT. Sin ejecutar
  # nada peligroso; se reporta como no_verificable salvo señal explícita de test.
  _p53=$( [ -n "$(_tget PORT53)" ] && _tget PORT53 || echo no_verificable )
  case "$_p53" in directo) _bp_row udp_tcp_53 directo warning ;; bloqueado) _bp_row udp_tcp_53 bloqueado info ;; *) _bp_row udp_tcp_53 no_verificable info ;; esac
  _p853=$( [ -n "$(_tget PORT853)" ] && _tget PORT853 || echo no_verificable )
  case "$_p853" in directo) _bp_row dot_853 directo warning ;; *) _bp_row dot_853 no_verificable info ;; esac
  # IPv6 sin cobertura equivalente
  _v6=$( [ -n "$(_tget IPV6)" ] && _tget IPV6 || echo no_verificable )
  case "$_v6" in sin_cobertura) _bp_row ipv6_coverage sin_cobertura warning ;; *) _bp_row ipv6_coverage no_verificable info ;; esac
}

bypass_status() {
  bypass_init
  echo "mode              : $(bypass_mode)"
  echo "strict_default    : off"
  echo "known_doh_domains : $(_bp_known_doh | wc -l | tr -d ' ') (detección por dominio, NO por puerto 443)"
  echo "note              : NUNCA se bloquea todo HTTPS; el tráfico 443 no se asume DoH."
}

# bypass set-mode audit|warning|strict
bypass_set_mode() {
  bypass_init
  case "$1" in
    audit|warning|strict) printf 'mode\t%s\n' "$1" > "$BP_CONF"; echo "mode=$1" ;;
    *) echo "Uso: bypass mode audit|warning|strict" >&2; return 1 ;;
  esac
}
