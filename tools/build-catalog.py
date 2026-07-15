#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tools/build-catalog.py  —  Creado por Skaymer AR

Fuente UNICA del catalogo de listas de DNSCrypt Manager (v0.2.0-RC2).
Emite dos artefactos, siempre en sincronia:

  config/catalog/blocklists.json        canonico, schema completo (WebUI + docs)
  config/catalog/blocklists.index.tsv   plano, 1 linea por entrada, para la CLI
                                         (awk-friendly; sin dependencia de Python
                                          en Android)

Python se usa SOLO en desarrollo/CI para generar/validar; el modulo en el
dispositivo consume el .tsv ya generado. El build (tools/build-module.sh)
re-ejecuta este script y verifica que el arbol quede sin cambios (catalogo
reproducible).

Uso:
  python3 tools/build-catalog.py            # genera ambos artefactos
  python3 tools/build-catalog.py --check    # falla si algo quedaria distinto
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_OUT = os.path.join(ROOT, "config", "catalog", "blocklists.json")
TSV_OUT = os.path.join(ROOT, "config", "catalog", "blocklists.index.tsv")

SCHEMA_VERSION = 1  # version del schema del catalogo (no confundir con module)
CATALOG_DATE = "2026-07-15"

# Categorias reconocidas (para validacion). Alineadas con el contrato RC2.
VALID_CATEGORIES = {
    "ads", "mobile_ads", "in_app_ads", "popups", "malvertising", "trackers",
    "telemetry", "metrics", "native_trackers", "cname_tracking", "affiliate",
    "malware", "phishing", "scams", "fake_stores", "cryptojacking",
    "crypto_advertising", "spam", "spyware", "ransomware", "badware_hosting",
    "newly_registered_domains", "dga", "dynamic_dns", "url_shorteners",
    "abused_tlds", "dns_rebind", "doh_bypass", "vpn_bypass", "tor_bypass",
    "proxy_bypass", "gambling", "social_networks", "piracy", "adult_content",
    "adult_advertising", "gaming_ads", "app_specific", "regional",
}

# Campos del schema, en orden. Los list-valued se serializan como CSV en el TSV.
FIELDS = [
    "id", "family_id", "name", "maintainer", "homepage", "description_es",
    "categories", "coverage", "aggressiveness", "format", "primary_url",
    "mirrors", "license", "upstream_status", "recommended", "mobile_suitability",
    "known_side_effects", "known_required_allowlist", "supersedes",
    "contained_by", "overlaps_with", "conflicts_with", "archived",
    "last_verified", "notes",
]
LIST_FIELDS = {
    "categories", "mirrors", "known_side_effects", "known_required_allowlist",
    "supersedes", "contained_by", "overlaps_with", "conflicts_with",
}
# Campos que van al TSV (subset suficiente para la CLI; el resto vive en el JSON).
TSV_FIELDS = [
    "id", "family_id", "name", "maintainer", "categories", "aggressiveness",
    "format", "primary_url", "license", "upstream_status", "recommended",
    "mobile_suitability", "archived", "supersedes", "contained_by",
    "overlaps_with", "conflicts_with", "last_verified", "description_es",
]

DEFAULTS = {
    "family_id": "", "maintainer": "", "homepage": "", "description_es": "",
    "categories": [], "coverage": "", "aggressiveness": "medium",
    "format": "domains", "primary_url": "", "mirrors": [], "license": "",
    "upstream_status": "unverified", "recommended": False,
    "mobile_suitability": "good", "known_side_effects": [],
    "known_required_allowlist": [], "supersedes": [], "contained_by": [],
    "overlaps_with": [], "conflicts_with": [], "archived": False,
    "last_verified": CATALOG_DATE, "notes": "",
}


def E(id, name, **kw):
    """Construye una entrada aplicando defaults; valida en build."""
    e = dict(DEFAULTS)
    e["id"] = id
    e["name"] = name
    e.update(kw)
    return e


# ===========================================================================
# CATALOGO
# Nota: primary_url apunta a URLs OFICIALES de cada mantenedor. Se prefiere el
# formato de dominios recomendado para DNSCrypt cuando existe (HaGeZi publica
# variantes wildcard/domains; aca se usan hosts/domains verificables). Las
# cifras de dominios NO se hardcodean: se completan tras descargar y validar.
# ===========================================================================
ENTRIES = []

# ---- A. HaGeZi (multi + threat + specialized) ----------------------------
HAGEZI = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main"
hagezi_common = dict(
    family_id="hagezi", maintainer="HaGeZi", format="hosts",
    homepage="https://github.com/hagezi/dns-blocklists",
    license="GPL-3.0",
)
ENTRIES += [
    E("hagezi_multi_light", "HaGeZi Multi LIGHT", **hagezi_common,
      categories=["ads", "trackers"], aggressiveness="low", recommended=False,
      coverage="Ads y trackers esenciales, minimos falsos positivos.",
      primary_url=f"{HAGEZI}/hosts/light.txt",
      contained_by=["hagezi_multi_normal", "hagezi_multi_pro", "hagezi_multi_proplus", "hagezi_multi_ultimate"],
      description_es="Version liviana: bloquea publicidad y rastreadores mas comunes con el menor riesgo de romper sitios."),
    E("hagezi_multi_normal", "HaGeZi Multi NORMAL", **hagezi_common,
      categories=["ads", "trackers", "malvertising"], aggressiveness="medium", recommended=True,
      coverage="Ads, trackers y algo de malvertising. Equilibrio general.",
      primary_url=f"{HAGEZI}/hosts/normal.txt",
      supersedes=["hagezi_multi_light"],
      contained_by=["hagezi_multi_pro", "hagezi_multi_proplus", "hagezi_multi_ultimate"],
      description_es="Equilibrio recomendado para uso diario: publicidad, rastreo y parte de malvertising."),
    E("hagezi_multi_pro", "HaGeZi Multi PRO", **hagezi_common,
      categories=["ads", "trackers", "malvertising", "telemetry"], aggressiveness="high", recommended=True,
      coverage="Cobertura amplia de ads/trackers/telemetria.",
      primary_url=f"{HAGEZI}/hosts/pro.txt",
      supersedes=["hagezi_multi_normal", "hagezi_multi_light"],
      contained_by=["hagezi_multi_proplus", "hagezi_multi_ultimate"],
      known_side_effects=["Puede afectar telemetria necesaria para algunas funciones."],
      description_es="Proteccion agresiva de publicidad, rastreo y telemetria. La mas usada de la familia."),
    E("hagezi_multi_pro_mini", "HaGeZi Multi PRO Mini", **hagezi_common,
      categories=["ads", "trackers", "malvertising"], aggressiveness="high", mobile_suitability="excellent",
      coverage="Variante Mini de PRO (menor tamano, pensada para dispositivos con poca RAM).",
      primary_url=f"{HAGEZI}/hosts/pro.mini.txt",
      contained_by=["hagezi_multi_pro", "hagezi_multi_proplus"],
      description_es="PRO reducida para telefonos: mismo enfoque, menos dominios y menor consumo."),
    E("hagezi_multi_proplus", "HaGeZi Multi PRO++", **hagezi_common,
      categories=["ads", "trackers", "malvertising", "telemetry", "spyware"], aggressiveness="very_high",
      coverage="PRO++ agrega telemetria/spyware adicionales.",
      primary_url=f"{HAGEZI}/hosts/pro.plus.txt",
      supersedes=["hagezi_multi_pro", "hagezi_multi_normal", "hagezi_multi_light"],
      contained_by=["hagezi_multi_ultimate"],
      known_side_effects=["Mayor chance de falsos positivos en apps que dependen de telemetria."],
      description_es="Version reforzada de PRO con mas telemetria y spyware. Puede requerir allowlist puntual."),
    E("hagezi_multi_proplus_mini", "HaGeZi Multi PRO++ Mini", **hagezi_common,
      categories=["ads", "trackers", "malvertising", "telemetry"], aggressiveness="very_high", mobile_suitability="excellent",
      coverage="Variante Mini de PRO++.",
      primary_url=f"{HAGEZI}/hosts/pro.plus.mini.txt",
      contained_by=["hagezi_multi_proplus", "hagezi_multi_ultimate"],
      description_es="PRO++ reducida para dispositivos moviles con recursos limitados."),
    E("hagezi_multi_ultimate", "HaGeZi Multi ULTIMATE", **hagezi_common,
      categories=["ads", "trackers", "malvertising", "telemetry", "spyware", "affiliate"], aggressiveness="very_high",
      mobile_suitability="fair",
      coverage="Maxima cobertura de la familia multi. Mayor riesgo de romper cosas.",
      primary_url=f"{HAGEZI}/hosts/ultimate.txt",
      supersedes=["hagezi_multi_proplus", "hagezi_multi_pro"],
      known_side_effects=["Falsos positivos mas probables: login, pagos, notificaciones."],
      description_es="La lista mas agresiva de HaGeZi multi. Solo si estas dispuesto a mantener una allowlist."),
    E("hagezi_multi_ultimate_mini", "HaGeZi Multi ULTIMATE Mini", **hagezi_common,
      categories=["ads", "trackers", "malvertising", "telemetry", "spyware"], aggressiveness="very_high",
      mobile_suitability="good",
      coverage="Variante Mini de ULTIMATE.",
      primary_url=f"{HAGEZI}/hosts/ultimate.mini.txt",
      contained_by=["hagezi_multi_ultimate"],
      description_es="ULTIMATE reducida para moviles."),
    E("hagezi_fake", "HaGeZi Fake", **hagezi_common,
      categories=["scams", "fake_stores", "phishing"], aggressiveness="medium", recommended=True,
      coverage="Tiendas falsas, estafas y sitios fraudulentos.",
      primary_url=f"{HAGEZI}/hosts/fake.txt",
      description_es="Bloquea tiendas falsas y sitios de estafa. Complemento util a las listas de ads."),
    E("hagezi_popupads", "HaGeZi Pop-Up Ads", **hagezi_common,
      categories=["popups", "ads", "malvertising"], aggressiveness="high",
      coverage="Dominios de pop-ups y publicidad intrusiva (incluye parte de adult_advertising indirecto).",
      primary_url=f"{HAGEZI}/hosts/popupads.txt",
      description_es="Especifica de ventanas emergentes y anuncios intrusivos. Cobertura indirecta de publicidad adulta."),
    E("hagezi_tif", "HaGeZi Threat Intelligence Feeds (Full)", **hagezi_common,
      categories=["malware", "phishing", "spyware", "ransomware", "badware_hosting"], aggressiveness="high", recommended=True,
      coverage="Feed completo de amenazas: malware, phishing, C2, badware.",
      primary_url=f"{HAGEZI}/hosts/tif.txt",
      contained_by=[],
      description_es="Inteligencia de amenazas completa. Recomendada junto a una lista de ads/trackers."),
    E("hagezi_tif_medium", "HaGeZi TIF Medium", **hagezi_common,
      categories=["malware", "phishing", "spyware"], aggressiveness="medium",
      coverage="Feed de amenazas de tamano medio.",
      primary_url=f"{HAGEZI}/hosts/tif.medium.txt",
      contained_by=["hagezi_tif"],
      description_es="Version media del feed de amenazas: buena relacion cobertura/tamano."),
    E("hagezi_tif_mini", "HaGeZi TIF Mini", **hagezi_common,
      categories=["malware", "phishing"], aggressiveness="medium", mobile_suitability="excellent",
      coverage="Feed de amenazas minimo.",
      primary_url=f"{HAGEZI}/hosts/tif.mini.txt",
      contained_by=["hagezi_tif", "hagezi_tif_medium"],
      description_es="Amenazas esenciales con el menor tamano. Ideal para moviles."),
    E("hagezi_nrd", "HaGeZi Newly Registered Domains / DGA", **hagezi_common,
      categories=["newly_registered_domains", "dga"], aggressiveness="high", mobile_suitability="fair",
      coverage="Dominios recien registrados y generados por algoritmo (DGA).",
      primary_url=f"{HAGEZI}/hosts/nrds.txt",
      known_side_effects=["Puede bloquear dominios legitimos muy nuevos."],
      description_es="Dominios recien registrados/DGA: utiles contra phishing fresco, pueden dar falsos positivos."),
    E("hagezi_doh_vpn_tor_proxy", "HaGeZi DoH/VPN/TOR/Proxy Bypass", **hagezi_common,
      categories=["doh_bypass", "vpn_bypass", "tor_bypass", "proxy_bypass"], aggressiveness="high", mobile_suitability="fair",
      coverage="Endpoints usados para evadir el filtrado (DoH publico, VPN, TOR, proxies).",
      primary_url=f"{HAGEZI}/hosts/doh-vpn-proxy-bypass.txt",
      conflicts_with=["_service_vpn"],
      known_side_effects=["Puede bloquear apps de VPN/proxy legitimas que uses a proposito."],
      description_es="Corta rutas de evasion del filtro DNS. Ojo si usas VPN/TOR de forma intencional."),
    E("hagezi_doh_only", "HaGeZi DoH-only Bypass", **hagezi_common,
      categories=["doh_bypass"], aggressiveness="high",
      coverage="Solo endpoints DoH publicos (subset del anterior).",
      primary_url=f"{HAGEZI}/hosts/doh.txt",
      contained_by=["hagezi_doh_vpn_tor_proxy"],
      description_es="Bloquea solo servidores DoH publicos, para evitar que apps salteen tu DNS."),
    E("hagezi_dyndns", "HaGeZi Dynamic DNS", **hagezi_common,
      categories=["dynamic_dns"], aggressiveness="medium",
      coverage="Proveedores de DNS dinamico frecuentemente abusados.",
      primary_url=f"{HAGEZI}/hosts/dyndns.txt",
      description_es="DNS dinamico abusado por malware. Puede afectar servicios caseros con dominios dyn."),
    E("hagezi_badware", "HaGeZi Badware Hoster", **hagezi_common,
      categories=["badware_hosting"], aggressiveness="high",
      coverage="Hosters usados recurrentemente para alojar badware.",
      primary_url=f"{HAGEZI}/hosts/hoster.txt",
      description_es="Proveedores de hosting recurrentes de contenido malicioso."),
    E("hagezi_urlshortener", "HaGeZi URL Shortener", **hagezi_common,
      categories=["url_shorteners"], aggressiveness="medium", mobile_suitability="fair",
      coverage="Acortadores de URL (pueden ocultar destinos).",
      primary_url=f"{HAGEZI}/hosts/shortener.txt",
      known_side_effects=["Rompe enlaces acortados legitimos (bit.ly, t.co, etc.)."],
      description_es="Bloquea acortadores de URL. Rompe enlaces cortos legitimos: usar con criterio."),
    E("hagezi_abused_tlds", "HaGeZi Most Abused TLDs", **hagezi_common,
      categories=["abused_tlds"], aggressiveness="very_high", mobile_suitability="fair",
      coverage="TLDs con altisima tasa de abuso.",
      primary_url=f"{HAGEZI}/hosts/spam-tlds.txt",
      known_side_effects=["Bloquea TLDs enteros: alto riesgo de falsos positivos."],
      description_es="Bloquea TLDs muy abusados por completo. Agresiva: puede tirar sitios legitimos de esos TLDs."),
    E("hagezi_dns_rebind", "HaGeZi DNS Rebind Protection", **hagezi_common,
      categories=["dns_rebind"], aggressiveness="low",
      coverage="Protege contra ataques de DNS rebinding (IPs privadas en respuestas).",
      primary_url=f"{HAGEZI}/hosts/rebind.txt",
      known_side_effects=["Puede interferir con dispositivos IoT/servicios en la LAN."],
      description_es="Anti DNS-rebinding. Puede chocar con acceso a dispositivos de tu red local."),
    E("hagezi_antipiracy", "HaGeZi Anti-Piracy", **hagezi_common,
      categories=["piracy"], aggressiveness="high", recommended=False, mobile_suitability="good",
      coverage="Sitios de pirateria.",
      primary_url=f"{HAGEZI}/hosts/anti.piracy.txt",
      description_es="Bloquea sitios de pirateria. Desactivada por defecto (decision del usuario)."),
    E("hagezi_gambling_full", "HaGeZi Gambling (Full)", **hagezi_common,
      categories=["gambling"], aggressiveness="high", recommended=False,
      coverage="Apuestas y juego online, cobertura completa.",
      primary_url=f"{HAGEZI}/hosts/gambling.txt",
      supersedes=["hagezi_gambling_medium", "hagezi_gambling_mini"],
      description_es="Bloqueo de apuestas online (completo)."),
    E("hagezi_gambling_medium", "HaGeZi Gambling Medium", **hagezi_common,
      categories=["gambling"], aggressiveness="medium", recommended=False,
      coverage="Apuestas, cobertura media.",
      primary_url=f"{HAGEZI}/hosts/gambling.medium.txt",
      contained_by=["hagezi_gambling_full"],
      description_es="Bloqueo de apuestas (medio)."),
    E("hagezi_gambling_mini", "HaGeZi Gambling Mini", **hagezi_common,
      categories=["gambling"], aggressiveness="medium", recommended=False, mobile_suitability="excellent",
      coverage="Apuestas, cobertura minima.",
      primary_url=f"{HAGEZI}/hosts/gambling.mini.txt",
      contained_by=["hagezi_gambling_full", "hagezi_gambling_medium"],
      description_es="Bloqueo de apuestas (minimo)."),
    E("hagezi_social", "HaGeZi Social Networks", **hagezi_common,
      categories=["social_networks"], aggressiveness="high", recommended=False, mobile_suitability="good",
      coverage="Redes sociales (bloqueo de acceso, no solo ads).",
      primary_url=f"{HAGEZI}/hosts/social.txt",
      known_side_effects=["Bloquea el acceso a las redes sociales, no solo su publicidad."],
      description_es="Bloquea redes sociales por completo. No es una lista de ads: corta el acceso."),
    E("hagezi_nsfw", "HaGeZi NSFW", **hagezi_common,
      categories=["adult_content"], aggressiveness="high", recommended=False, mobile_suitability="good",
      coverage="Contenido adulto (paginas, no solo publicidad).",
      primary_url=f"{HAGEZI}/hosts/nsfw.txt",
      known_side_effects=["Bloquea sitios adultos completos, no solamente su publicidad."],
      description_es="Bloquea contenido adulto (paginas enteras). NO es adult_advertising."),
    E("hagezi_native_tracker", "HaGeZi Native Tracker", **hagezi_common,
      categories=["native_trackers", "telemetry"], aggressiveness="high", mobile_suitability="good",
      coverage="Rastreadores nativos de fabricantes (Samsung, Xiaomi, Huawei, Apple, etc.).",
      primary_url=f"{HAGEZI}/hosts/native.txt",
      known_side_effects=["Puede afectar servicios del fabricante y notificaciones push."],
      description_es="Telemetria/rastreo nativo de fabricantes de dispositivos. Puede afectar servicios OEM."),
]

# ---- B. OISD -------------------------------------------------------------
oisd_common = dict(family_id="oisd", maintainer="OISD", format="domains",
                   homepage="https://oisd.nl/", license="custom-oisd")
ENTRIES += [
    E("oisd_big", "OISD Big", **oisd_common,
      categories=["ads", "trackers", "malware", "phishing", "telemetry"], aggressiveness="high", recommended=True,
      coverage="Agregador grande y balanceado de ads/trackers/malware.",
      primary_url="https://big.oisd.nl/domainswild",
      supersedes=["oisd_small"],
      overlaps_with=["hagezi_multi_pro", "hagezi_multi_proplus"],
      description_es="Agregador amplio y curado. Buena opcion 'todo en uno'. Se solapa bastante con HaGeZi PRO."),
    E("oisd_small", "OISD Small", **oisd_common,
      categories=["ads", "trackers"], aggressiveness="medium", mobile_suitability="excellent",
      coverage="Version reducida de OISD, ads/trackers principales.",
      primary_url="https://small.oisd.nl/domainswild",
      contained_by=["oisd_big"],
      description_es="Version chica de OISD para dispositivos con poca RAM."),
    E("oisd_nsfw", "OISD NSFW", **oisd_common,
      categories=["adult_content"], aggressiveness="high", recommended=False,
      coverage="Contenido adulto (paginas).",
      primary_url="https://nsfw.oisd.nl/domainswild",
      supersedes=["oisd_nsfw_small"],
      known_side_effects=["Bloquea sitios adultos completos, no solo publicidad."],
      description_es="Contenido adulto (paginas). Bloquea sitios adultos completos, no publicidad."),
    E("oisd_nsfw_small", "OISD NSFW Small", **oisd_common,
      categories=["adult_content"], aggressiveness="medium", recommended=False,
      coverage="Contenido adulto, version reducida.",
      primary_url="https://nsfw-small.oisd.nl/domainswild",
      contained_by=["oisd_nsfw"],
      known_side_effects=["Bloquea sitios adultos, no solo publicidad."],
      description_es="Version chica de la lista de contenido adulto de OISD."),
]

# ---- C. 1Hosts -----------------------------------------------------------
onehosts_common = dict(family_id="1hosts", maintainer="badmojr", format="domains",
                       homepage="https://github.com/badmojr/1Hosts", license="CC-BY-SA-4.0")
ENTRIES += [
    E("1hosts_lite", "1Hosts (Lite)", **onehosts_common,
      categories=["ads", "trackers"], aggressiveness="medium", mobile_suitability="excellent",
      coverage="Ads/trackers, enfoque liviano.",
      primary_url="https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/domains.txt",
      contained_by=["1hosts_xtra"],
      description_es="Version liviana de 1Hosts: ads/trackers con bajo riesgo."),
    E("1hosts_pro", "1Hosts (Pro)", **onehosts_common,
      categories=["ads", "trackers", "malvertising", "telemetry"], aggressiveness="high", recommended=True,
      coverage="Ads/trackers/telemetria, enfoque equilibrado-fuerte.",
      primary_url="https://raw.githubusercontent.com/badmojr/1Hosts/master/Pro/domains.txt",
      supersedes=["1hosts_lite"],
      description_es="Version Pro de 1Hosts (equivale a la fuente heredada del usuario)."),
    E("1hosts_xtra", "1Hosts (Xtra)", **onehosts_common,
      categories=["ads", "trackers", "malvertising", "telemetry", "spyware"], aggressiveness="very_high",
      mobile_suitability="fair",
      coverage="Cobertura maxima de 1Hosts.",
      primary_url="https://raw.githubusercontent.com/badmojr/1Hosts/master/Xtra/domains.txt",
      supersedes=["1hosts_pro", "1hosts_lite"],
      known_side_effects=["Muy agresiva: falsos positivos probables."],
      description_es="Version Xtra (maxima) de 1Hosts. Agresiva, puede romper sitios."),
]

# ---- D. StevenBlack (base + extensiones componibles) ---------------------
SB = "https://raw.githubusercontent.com/StevenBlack/hosts/master"
sb_common = dict(family_id="stevenblack", maintainer="StevenBlack", format="hosts",
                 homepage="https://github.com/StevenBlack/hosts", license="MIT")
ENTRIES += [
    E("stevenblack_base", "StevenBlack (Base: Ads + Malware)", **sb_common,
      categories=["ads", "malware", "trackers"], aggressiveness="medium", recommended=True,
      coverage="Base unificada de ads+malware. Se puede COMPONER con extensiones.",
      primary_url=f"{SB}/hosts",
      description_es="Base unificada y muy mantenida. Componer con extensiones (fakenews/gambling/porn/social) segun necesites."),
    E("stevenblack_fakenews", "StevenBlack + Fakenews (extension)", **sb_common,
      categories=["scams"], aggressiveness="medium", recommended=False,
      coverage="Extension: sitios de noticias falsas. Componer sobre Base.",
      primary_url=f"{SB}/alternates/fakenews/hosts",
      notes="Extension componible: incluye Base + fakenews.",
      description_es="Extension de noticias falsas para componer con la base de StevenBlack."),
    E("stevenblack_gambling", "StevenBlack + Gambling (extension)", **sb_common,
      categories=["gambling"], aggressiveness="medium", recommended=False,
      coverage="Extension: apuestas. Componer sobre Base.",
      primary_url=f"{SB}/alternates/gambling/hosts",
      overlaps_with=["hagezi_gambling_full"],
      description_es="Extension de apuestas para componer con la base de StevenBlack."),
    E("stevenblack_porn", "StevenBlack + Porn (extension)", **sb_common,
      categories=["adult_content"], aggressiveness="high", recommended=False,
      coverage="Extension: contenido adulto (paginas). Componer sobre Base.",
      primary_url=f"{SB}/alternates/porn/hosts",
      overlaps_with=["hagezi_nsfw", "oisd_nsfw"],
      known_side_effects=["Bloquea sitios adultos completos, no solo publicidad."],
      description_es="Extension de contenido adulto (paginas). NO es adult_advertising."),
    E("stevenblack_social", "StevenBlack + Social (extension)", **sb_common,
      categories=["social_networks"], aggressiveness="high", recommended=False,
      coverage="Extension: redes sociales. Componer sobre Base.",
      primary_url=f"{SB}/alternates/social/hosts",
      overlaps_with=["hagezi_social"],
      known_side_effects=["Bloquea el acceso a redes sociales."],
      description_es="Extension de redes sociales para componer con la base de StevenBlack."),
]

# ---- E. GoodbyeAds -------------------------------------------------------
GBA = "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master"
gba_common = dict(family_id="goodbyeads", maintainer="jerryn70", format="hosts",
                  homepage="https://github.com/jerryn70/GoodbyeAds", license="GPL-3.0")
ENTRIES += [
    E("goodbyeads_core", "GoodbyeAds (Core)", **gba_common,
      categories=["ads", "mobile_ads", "trackers"], aggressiveness="high", mobile_suitability="excellent", recommended=True,
      coverage="Ads moviles + trackers, foco en Android.",
      primary_url=f"{GBA}/Hosts/GoodbyeAds.txt",
      description_es="Enfocada en publicidad movil (in-app) y rastreadores en Android."),
    E("goodbyeads_xiaomi", "GoodbyeAds Xiaomi Ads", **gba_common,
      categories=["mobile_ads", "in_app_ads"], aggressiveness="high", mobile_suitability="excellent",
      coverage="Publicidad especifica de dispositivos Xiaomi/MIUI.",
      primary_url=f"{GBA}/Extension/GoodbyeAds-Xiaomi-Extension.txt",
      description_es="Anuncios especificos de Xiaomi/MIUI."),
    E("goodbyeads_samsung", "GoodbyeAds Samsung Ads", **gba_common,
      categories=["mobile_ads", "in_app_ads"], aggressiveness="high", mobile_suitability="excellent",
      coverage="Publicidad especifica de dispositivos Samsung.",
      primary_url=f"{GBA}/Extension/GoodbyeAds-Samsung-AdBlock.txt",
      description_es="Anuncios especificos de Samsung."),
    E("goodbyeads_spotify", "GoodbyeAds Spotify Ads", **gba_common,
      categories=["in_app_ads"], aggressiveness="medium", mobile_suitability="good",
      coverage="Anuncios de Spotify (cobertura DNS parcial).",
      primary_url=f"{GBA}/Extension/GoodbyeAds-Spotify-AdBlock.txt",
      known_side_effects=["Cobertura DNS parcial; Spotify puede seguir sirviendo ads por otros medios."],
      description_es="Anuncios de Spotify. Cobertura parcial por DNS."),
    E("goodbyeads_youtube", "GoodbyeAds YouTube Ads", **gba_common,
      categories=["in_app_ads"], aggressiveness="medium", mobile_suitability="fair", recommended=False,
      coverage="Anuncios de YouTube (cobertura DNS muy parcial).",
      primary_url=f"{GBA}/Extension/GoodbyeAds-YouTube-AdBlock.txt",
      known_side_effects=["El bloqueo DNS de ads de YouTube es incompleto y puede romper la reproduccion: los anuncios comparten infraestructura con el contenido."],
      description_es="Anuncios de YouTube por DNS: incompleto y puede romper la reproduccion. Los ads comparten dominios con el video."),
]

# ---- F. AdAway -----------------------------------------------------------
ENTRIES += [
    E("adaway_official", "AdAway (oficial)", family_id="adaway", maintainer="AdAway",
      format="hosts", homepage="https://adaway.org/", license="CC-BY-3.0",
      categories=["ads", "mobile_ads"], aggressiveness="medium", mobile_suitability="excellent", recommended=True,
      coverage="Lista clasica de ads moviles.",
      primary_url="https://adaway.org/hosts.txt",
      description_es="La lista historica de AdAway: publicidad movil, conservadora y confiable."),
]

# ---- G. DandelionSprout --------------------------------------------------
# URL oficial COMPLETA (corrige la ruta partida 'Sprout/...'+'Dandelion').
ENTRIES += [
    E("dandelionsprout_antimalware", "DandelionSprout Anti-Malware List", family_id="dandelionsprout",
      maintainer="DandelionSprout", format="hosts",
      homepage="https://github.com/DandelionSprout/adfilt", license="BSD-3-Clause",
      categories=["malware", "phishing"], aggressiveness="medium", recommended=True,
      coverage="Anti-malware curada, buena para complementar TIF.",
      primary_url="https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt",
      description_es="Anti-malware de DandelionSprout (URL oficial completa, corregida)."),
]

# ---- H. r-a-y/mobile-hosts (AdGuard + EasyPrivacy variants) ---------------
RAY = "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master"
ray_common = dict(family_id="r-a-y_mobile-hosts", maintainer="r-a-y", format="hosts",
                  homepage="https://github.com/r-a-y/mobile-hosts", license="unknown")
ENTRIES += [
    E("ray_adguard_apps", "AdGuard Apps (r-a-y)", **ray_common,
      categories=["in_app_ads", "mobile_ads"], aggressiveness="high", mobile_suitability="excellent",
      coverage="Publicidad dentro de apps (AdGuard, empaquetada por r-a-y).",
      primary_url=f"{RAY}/AdguardApps.txt",
      description_es="Anuncios in-app segun AdGuard."),
    E("ray_adguard_dns", "AdGuard DNS (r-a-y)", **ray_common,
      categories=["ads", "trackers"], aggressiveness="high", recommended=True,
      coverage="Filtro DNS de AdGuard.",
      primary_url=f"{RAY}/AdguardDNS.txt",
      description_es="Filtro DNS de AdGuard (fuente heredada del usuario)."),
    E("ray_adguard_mobile_ads", "AdGuard Mobile Ads (r-a-y)", **ray_common,
      categories=["mobile_ads", "in_app_ads"], aggressiveness="high", mobile_suitability="excellent", recommended=True,
      coverage="Publicidad movil segun AdGuard.",
      primary_url=f"{RAY}/AdguardMobileAds.txt",
      description_es="Publicidad movil de AdGuard (fuente heredada del usuario)."),
    E("ray_adguard_mobile_spyware", "AdGuard Mobile Spyware (r-a-y)", **ray_common,
      categories=["spyware", "native_trackers"], aggressiveness="high", mobile_suitability="good", recommended=True,
      coverage="Spyware movil segun AdGuard.",
      primary_url=f"{RAY}/AdguardMobileSpyware.txt",
      known_side_effects=["Puede afectar telemetria del fabricante."],
      description_es="Spyware movil de AdGuard (fuente heredada del usuario)."),
    E("ray_adguard_tracking", "AdGuard Tracking (r-a-y)", **ray_common,
      categories=["trackers"], aggressiveness="high",
      coverage="Rastreadores segun AdGuard.",
      primary_url=f"{RAY}/AdguardTracking.txt",
      description_es="Rastreadores de AdGuard."),
    E("ray_adguard_cname_ads", "AdGuard CNAME Ads (r-a-y)", **ray_common,
      categories=["cname_tracking", "ads"], aggressiveness="high",
      coverage="Ads camuflados por CNAME.",
      primary_url=f"{RAY}/AdguardCNAMEAds.txt",
      description_es="Publicidad que se oculta detras de CNAME."),
    E("ray_adguard_cname_clickthroughs", "AdGuard CNAME Clickthroughs (r-a-y)", **ray_common,
      categories=["cname_tracking", "affiliate"], aggressiveness="high",
      coverage="Clickthroughs/afiliados por CNAME.",
      primary_url=f"{RAY}/AdguardCNAMEClickthroughs.txt",
      description_es="Enlaces de afiliado/clickthrough camuflados por CNAME."),
    E("ray_adguard_cname_microsites", "AdGuard CNAME Microsites (r-a-y)", **ray_common,
      categories=["cname_tracking"], aggressiveness="medium",
      coverage="Microsites por CNAME.",
      primary_url=f"{RAY}/AdguardCNAMEMicrosites.txt",
      description_es="Microsites de campanas camuflados por CNAME."),
    E("ray_adguard_cname_trackers", "AdGuard CNAME Trackers (r-a-y)", **ray_common,
      categories=["cname_tracking", "trackers"], aggressiveness="high",
      coverage="Rastreadores por CNAME.",
      primary_url=f"{RAY}/AdguardCNAMETrackers.txt",
      description_es="Rastreadores camuflados por CNAME."),
    E("ray_easyprivacy_3rdparty", "EasyPrivacy 3rd Party (r-a-y)", **ray_common,
      categories=["trackers"], aggressiveness="high",
      coverage="EasyPrivacy: rastreadores de terceros (subset DNS).",
      primary_url=f"{RAY}/EasyPrivacy3rdParty.txt",
      description_es="EasyPrivacy de terceros. Cobertura DNS parcial (lista de origen ABP)."),
    E("ray_easyprivacy_specific", "EasyPrivacy Specific (r-a-y)", **ray_common,
      categories=["trackers"], aggressiveness="high",
      coverage="EasyPrivacy: reglas especificas (subset DNS).",
      primary_url=f"{RAY}/EasyPrivacySpecific.txt",
      description_es="EasyPrivacy especifica. Cobertura DNS parcial."),
]

# ---- I. Fuentes ya presentes en RC1 (mapeadas al catalogo) ----------------
ENTRIES += [
    E("rc1_urlhaus", "URLhaus (abuse.ch)", family_id="rc1", maintainer="abuse.ch",
      format="hosts", homepage="https://urlhaus.abuse.ch/", license="CC0-1.0",
      categories=["malware", "badware_hosting"], aggressiveness="medium", recommended=True,
      coverage="Dominios de distribucion de malware (threat intel).",
      primary_url="https://urlhaus.abuse.ch/downloads/hostfile/",
      notes="Fuente por defecto de la categoria 'malware' en RC1.",
      description_es="URLhaus de abuse.ch. Ya venia como fuente de malware en RC1."),
    E("rc1_phishing_army", "Phishing Army (Extended)", family_id="rc1", maintainer="Phishing Army",
      format="domains", homepage="https://phishing.army/", license="CC-BY-NC-4.0",
      categories=["phishing"], aggressiveness="medium", recommended=True,
      coverage="Anti-phishing.",
      primary_url="https://phishing.army/download/phishing_army_blocklist_extended.txt",
      description_es="Phishing Army. Fuente de phishing de RC1."),
    E("rc1_coinblocker", "CoinBlockerLists (ZeroDot1)", family_id="rc1", maintainer="ZeroDot1",
      format="domains", homepage="https://gitlab.com/ZeroDot1/CoinBlockerLists", license="GPL-3.0",
      categories=["cryptojacking"], aggressiveness="medium",
      coverage="Mineria de criptomonedas en el navegador (cryptojacking).",
      primary_url="https://raw.githubusercontent.com/ZeroDot1/CoinBlockerLists/master/list.txt",
      notes="cryptojacking (NO es publicidad de cripto).",
      description_es="CoinBlockerLists: cryptojacking. Fuente de criptomineria de RC1."),
    E("rc1_easyprivacy_firebog", "EasyPrivacy (Firebog)", family_id="rc1", maintainer="The Firebog",
      format="domains", homepage="https://firebog.net/", license="GPL-3.0",
      categories=["trackers"], aggressiveness="high",
      coverage="Rastreadores (EasyPrivacy, empaquetada por Firebog).",
      primary_url="https://v.firebog.net/hosts/Easyprivacy.txt",
      description_es="EasyPrivacy via Firebog. Fuente de rastreadores de RC1."),
]

# ---- J. Fuentes heredadas del usuario (validadas; NO auto-activadas) ------
# Se incluyen tal cual las paso el usuario, con estado y sin recomendar por
# defecto. Duplicado de StevenBlack ELIMINADO (ya esta como stevenblack_base).
# La ruta partida de DandelionSprout se corrigio arriba. antipopads-re va como
# archivada. 1Hosts Pro heredada = 1hosts_pro (ya definida).
ENTRIES += [
    E("legacy_github_hosts", "github-hosts (maxiaof)", family_id="legacy", maintainer="maxiaof",
      format="hosts", homepage="https://github.com/maxiaof/github-hosts", license="unknown",
      categories=["regional"], aggressiveness="low", recommended=False, mobile_suitability="fair",
      coverage="Hosts para acceso a GitHub (NO es blocklist: mapea IPs).",
      primary_url="https://raw.githubusercontent.com/maxiaof/github-hosts/refs/heads/master/hosts",
      upstream_status="legacy",
      known_side_effects=["No es una lista de bloqueo: son pares IP+dominio de acceso a GitHub."],
      notes="Formato hosts con IPs reales de acceso; util como custom, no como blocklist.",
      description_es="Hosts de acceso a GitHub. No bloquea: mapea IPs. Se incluye como fuente heredada, apagada."),
    E("legacy_turtlecute_d3host", "Turtlecute d3host", family_id="legacy", maintainer="Turtlecute33",
      format="hosts", homepage="https://github.com/Turtlecute33/toolz", license="unknown",
      categories=["ads", "trackers"], aggressiveness="medium", recommended=False,
      coverage="Lista de ads/trackers de terceros (procedencia a verificar).",
      primary_url="https://raw.githubusercontent.com/Turtlecute33/toolz/refs/heads/master/src/d3host.txt",
      upstream_status="legacy",
      notes="Procedencia/licencia no verificadas; se incluye apagada.",
      description_es="Fuente heredada del usuario. Procedencia sin verificar: apagada y no recomendada."),
    E("legacy_frogeye_firstparty", "Frogeye First-Party Trackers", family_id="legacy", maintainer="Frogeye",
      format="hosts", homepage="https://hostfiles.frogeye.fr/", license="custom",
      categories=["trackers", "cname_tracking"], aggressiveness="high", recommended=False,
      coverage="Rastreadores first-party (CNAME).",
      primary_url="https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt",
      upstream_status="legacy",
      description_es="Rastreadores first-party de Frogeye. Fuente heredada, apagada por defecto."),
    E("legacy_divested", "Divested Hosts", family_id="legacy", maintainer="Divested", format="hosts",
      homepage="https://divested.dev/", license="unknown",
      categories=["ads", "trackers", "malware"], aggressiveness="very_high", recommended=False, mobile_suitability="fair",
      coverage="Agregador grande (procedencia a verificar).",
      primary_url="https://divested.dev/hosts",
      upstream_status="legacy",
      description_es="Agregador heredado del usuario. Grande y sin verificar: apagado."),
    E("legacy_antipopads_re", "antipopads-re (Legacy/Archived)", family_id="legacy", maintainer="AdroitAdorKhan",
      format="hosts", homepage="https://github.com/AdroitAdorKhan/antipopads-re", license="unknown",
      categories=["popups", "ads"], aggressiveness="high", recommended=False, archived=True,
      upstream_status="archived", mobile_suitability="fair",
      coverage="Anti pop-up ads. Repositorio ARCHIVADO.",
      primary_url="https://raw.githubusercontent.com/AdroitAdorKhan/antipopads-re/master/formats/hosts.txt",
      notes="Archivado upstream. Se conserva como legado, apagado y no recomendado.",
      description_es="antipopads-re: ARCHIVADO. Solo como legado. Cobertura indirecta de publicidad adulta."),
    E("legacy_rem01_bypassroot", "rem01 bypassroot", family_id="legacy", maintainer="rem01gaming",
      format="hosts", homepage="https://hosts.rem01gaming.dev/", license="unknown",
      categories=["doh_bypass", "vpn_bypass"], aggressiveness="high", recommended=False,
      coverage="Endpoints de bypass (procedencia a verificar).",
      primary_url="https://hosts.rem01gaming.dev/bypassroot",
      upstream_status="legacy",
      overlaps_with=["hagezi_doh_vpn_tor_proxy"],
      description_es="Fuente heredada de bypass. Sin verificar: apagada."),
    E("legacy_hagezi_proplus_compressed", "HaGeZi Pro++ (compressed, legacy URL)", family_id="legacy",
      maintainer="HaGeZi", format="domains", homepage="https://github.com/hagezi/dns-blocklists",
      license="GPL-3.0", categories=["ads", "trackers", "telemetry"], aggressiveness="very_high", recommended=False,
      coverage="Variante comprimida de Pro++ (URL heredada del usuario).",
      primary_url="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.plus-compressed.txt",
      contained_by=["hagezi_multi_proplus"],
      upstream_status="legacy",
      notes="Duplicado funcional de hagezi_multi_proplus; se conserva por compatibilidad con la config del usuario.",
      description_es="Pro++ comprimida (URL heredada). Equivale a HaGeZi Multi PRO++."),
    E("legacy_o0_pro", "o0.pages.dev Pro", family_id="legacy", maintainer="o0", format="hosts",
      homepage="https://o0.pages.dev/", license="unknown",
      categories=["ads", "trackers"], aggressiveness="high", recommended=False,
      coverage="Espejo/derivado (procedencia a verificar).",
      primary_url="https://o0.pages.dev/Pro/hosts.txt",
      upstream_status="legacy",
      description_es="Fuente heredada del usuario. Procedencia sin verificar: apagada."),
]


def validate(entries):
    ids = set()
    errs = []
    for e in entries:
        if e["id"] in ids:
            errs.append(f"id duplicado: {e['id']}")
        ids.add(e["id"])
        for c in e["categories"]:
            if c not in VALID_CATEGORIES:
                errs.append(f"{e['id']}: categoria invalida '{c}'")
        if e["format"] not in ("hosts", "domains", "abp", "wildcard"):
            errs.append(f"{e['id']}: formato invalido '{e['format']}'")
        if not e["primary_url"].startswith("https://"):
            errs.append(f"{e['id']}: primary_url no https")
        if e["upstream_status"] not in ("verified", "unverified", "archived", "broken", "legacy"):
            errs.append(f"{e['id']}: estado invalido '{e['upstream_status']}'")
        if e["archived"] and e["upstream_status"] != "archived":
            errs.append(f"{e['id']}: archived=True requiere upstream_status='archived'")
        if e["upstream_status"] in ("archived", "broken") and e["recommended"]:
            errs.append(f"{e['id']}: no se puede recomendar una fuente archived/broken")
    # URLs duplicadas: dos entradas no deben compartir primary_url.
    seen_urls = {}
    for e in entries:
        u = e["primary_url"]
        if u in seen_urls:
            errs.append(f"{e['id']}: primary_url duplicada con '{seen_urls[u]}'")
        seen_urls[u] = e["id"]
    # Referencias cruzadas (supersedes/contained_by/...) deben existir o ser
    # marcadores de servicio (prefijo '_service').
    for e in entries:
        for rel in ("supersedes", "contained_by", "overlaps_with", "conflicts_with"):
            for ref in e[rel]:
                if ref not in ids and not ref.startswith("_service"):
                    errs.append(f"{e['id']}.{rel}: referencia inexistente '{ref}'")
    return errs


def to_tsv_value(e, field):
    v = e[field]
    if field in LIST_FIELDS:
        return ",".join(v)
    if isinstance(v, bool):
        return "1" if v else "0"
    return str(v).replace("\t", " ").replace("\n", " ")


def render_tsv(entries):
    lines = ["#" + "\t".join(TSV_FIELDS)]
    for e in sorted(entries, key=lambda x: x["id"]):
        lines.append("\t".join(to_tsv_value(e, f) for f in TSV_FIELDS))
    return "\n".join(lines) + "\n"


def render_json(entries):
    doc = {
        "schema_version": SCHEMA_VERSION,
        "generated": CATALOG_DATE,
        "generator": "tools/build-catalog.py",
        "count": len(entries),
        "entries": sorted(entries, key=lambda x: x["id"]),
    }
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def main():
    check = "--check" in sys.argv
    errs = validate(ENTRIES)
    if errs:
        print("CATALOGO INVALIDO:", file=sys.stderr)
        for e in errs:
            print("  - " + e, file=sys.stderr)
        sys.exit(2)
    js = render_json(ENTRIES)
    tsv = render_tsv(ENTRIES)
    os.makedirs(os.path.dirname(JSON_OUT), exist_ok=True)
    if check:
        bad = False
        for path, content in ((JSON_OUT, js), (TSV_OUT, tsv)):
            cur = open(path, encoding="utf-8").read() if os.path.exists(path) else None
            if cur != content:
                print(f"DESINCRONIZADO: {path} difiere de lo generado.", file=sys.stderr)
                bad = True
        sys.exit(1 if bad else 0)
    open(JSON_OUT, "w", encoding="utf-8").write(js)
    open(TSV_OUT, "w", encoding="utf-8").write(tsv)
    print(f"OK: {len(ENTRIES)} entradas -> {os.path.relpath(JSON_OUT, ROOT)} + {os.path.relpath(TSV_OUT, ROOT)}")


if __name__ == "__main__":
    main()
