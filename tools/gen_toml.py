#!/usr/bin/env python3
"""Genera config/dnscrypt-proxy.toml del modulo con stamps calculados
desde parametros explicitos (no de memoria), y su copia en defaults/."""
import sys, pathlib
sys.path.insert(0, "/home/claude/tools")
from stamps import encode_doh, decode

# Parametros publicos de cada proveedor (DoH, puerto 443 implicito).
# props=0: no afirmamos DNSSEC/NoLog/NoFilter que hoy no podemos verificar.
PROVIDERS = {
    "cloudflare": dict(host="cloudflare-dns.com",   addr="1.1.1.1",       path="/dns-query"),
    "quad9":      dict(host="dns.quad9.net",        addr="9.9.9.9",       path="/dns-query"),
    "adguard":    dict(host="dns.adguard-dns.com",  addr="94.140.14.14",  path="/dns-query"),
    "mullvad":    dict(host="dns.mullvad.net",      addr="194.242.2.2",   path="/dns-query"),
}

stamps = {}
for name, p in PROVIDERS.items():
    s = encode_doh(p["host"], p["path"], p["addr"], props=0)
    d = decode(s)  # verificacion inmediata: lo que codifico se decodifica igual
    assert (d["host"], d["path"], d["addr"]) == (p["host"], p["path"], p["addr"]), name
    stamps[name] = s

TOML = f"""##############################################################################
# DNSCrypt Manager - configuracion por defecto de dnscrypt-proxy
#
# DISEÑO ANTI-BUCLE (leer antes de tocar):
#   * Los servidores [static] llevan la IP EMBEBIDA en el stamp: el trafico
#     upstream del proxy sale por TCP/443 (DoH), nunca por el puerto 53, asi
#     que la redireccion global no lo captura y no puede haber bucle.
#   * ignore_system_dns = true: el proxy jamas le pregunta al resolver del
#     sistema (que, bajo redireccion, seria el mismo).
#   * Si agregas un servidor SOLO por hostname (sin IP), el proxy necesitara
#     bootstrap por puerto 53 al arrancar en frio; bajo redireccion eso puede
#     fallar. El watchdog del modulo retira la redireccion si el DNS no
#     responde, asi que no perdes Internet, pero conviene incluir la IP.
#
# Los stamps de abajo fueron GENERADOS localmente a partir de estos
# parametros (verificables en dnscrypt.info o la web de cada proveedor):
#   cloudflare : https://cloudflare-dns.com/dns-query   (1.1.1.1)
#   quad9      : https://dns.quad9.net/dns-query        (9.9.9.9)
#   adguard    : https://dns.adguard-dns.com/dns-query  (94.140.14.14)
#   mullvad    : https://dns.mullvad.net/dns-query      (194.242.2.2)
#
# Validacion definitiva en el telefono:
#   su -c dnscrypt-manager config validate
##############################################################################

# El servidor activo. Cambialo con la WebUI o:
#   dnscrypt-manager provider <cloudflare|quad9|adguard|mullvad>
#   dnscrypt-manager nextdns <id>
server_names = ['cloudflare']

# Puerto 5354 (no 5353) para no chocar con mDNS de Android.
# Se escucha en ambos loopbacks para que la redireccion IPv6 tenga destino.
listen_addresses = ['127.0.0.1:5354', '[::1]:5354']

max_clients = 250

ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = true
doh_servers = true
odoh_servers = false

# Requisitos sobre servidores de FUENTES (no afectan a los [static] fijados).
require_dnssec = false
require_nolog = false
require_nofilter = false

disabled_server_names = []

force_tcp = false
timeout = 5000
keepalive = 30
cert_refresh_delay = 240

# Bootstrap: solo se usa para resolver hostnames sin IP embebida (raro con
# esta config) y para las fuentes si las activas. Ver nota anti-bucle arriba.
bootstrap_resolvers = ['9.9.9.9:53', '1.1.1.1:53']
ignore_system_dns = true

netprobe_timeout = 60
netprobe_address = '9.9.9.9:53'

block_ipv6 = false
block_unqualified = true
block_undelegated = true

cache = true
cache_size = 4096
cache_min_ttl = 2400
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600

##############################################################################
# Servidores fijos (stamps con IP embebida; ver cabecera).
##############################################################################
[static]

  [static.'cloudflare']
    stamp = '{stamps["cloudflare"]}'

  [static.'quad9']
    stamp = '{stamps["quad9"]}'

  [static.'adguard']
    stamp = '{stamps["adguard"]}'

  [static.'mullvad']
    stamp = '{stamps["mullvad"]}'

##############################################################################
# Fuentes publicas de resolvers: DESACTIVADAS por defecto (offline-first).
# Para activarlas, descomenta el bloque; la primera vez necesita red y
# reescribe el cache en config/public-resolvers.md. La clave minisign es la
# publicada por el proyecto dnscrypt-proxy; verificala antes de confiar.
##############################################################################
# [sources]
#   [sources.public-resolvers]
#     urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
#     cache_file = 'public-resolvers.md'
#     minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
#     refresh_delay = 73
#     prefix = ''
#
#   [sources.relays]
#     urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/relays.md']
#     cache_file = 'relays.md'
#     minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
#     refresh_delay = 73
#     prefix = ''
"""

base = pathlib.Path("/home/claude/DNSCrypt-Manager/config")
(base / "dnscrypt-proxy.toml").write_text(TOML)
(base / "defaults" / "dnscrypt-proxy.toml").write_text(TOML)
print("TOML escrito (config/ y config/defaults/).")
print()
print(f"{'nombre':<12} {'addr':<16} {'host':<22} path")
for n, s in stamps.items():
    d = decode(s)
    print(f"{n:<12} {d['addr']:<16} {d['host']:<22} {d['path']}")
    print(f"{'':<12} {s}")
