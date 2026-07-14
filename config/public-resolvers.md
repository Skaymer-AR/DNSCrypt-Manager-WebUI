# public-resolvers.md - CACHE LOCAL (vacio de fabrica)
#
# Este archivo es el cache de la fuente [sources.public-resolvers] de
# dnscrypt-proxy. Se distribuye VACIO a proposito: no incluimos una copia
# posiblemente desactualizada ni inventada de la lista publica.
#
# La configuracion por defecto NO lo necesita: usa servidores [static] con
# stamps de IP embebida definidos en dnscrypt-proxy.toml.
#
# Para poblarlo:
#   1) Descomenta el bloque [sources] en dnscrypt-proxy.toml.
#   2) Con red, reinicia el servicio: dnscrypt-proxy descarga la lista,
#      verifica su firma minisign y reescribe este archivo solo.
# O manualmente:
#   curl -o public-resolvers.md \
#     https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md
