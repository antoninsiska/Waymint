# Waymint Web

Statická webová verze Waymint určená pro GitHub Pages. Nemá backend ani externí závislosti; data ukládá do `localStorage` aktuálního prohlížeče.

## GitHub Pages

1. Nahrajte složku `docs` do hlavní větve repozitáře.
2. V GitHubu otevřete **Settings → Pages**.
3. Jako zdroj zvolte **Deploy from a branch**, větev a složku **/docs**.

Web podporuje import a export formátů iOS aplikace:

- `.way` – jedna cesta,
- `.waymint` – vybrané město nebo kompletní knihovna.

Našeptávání adres používá Photon nad daty OpenStreetMap. Požadavky mají prodlevu, jsou omezené na nejvýše jeden za sekundu a výsledky se lokálně cachují. Přesuny mezi body se automaticky počítají pomocí OSRM; při nedostupnosti serveru se použije lokální odhad podle vzdálenosti a typu dopravy. Pro větší veřejný provoz je vhodné nastavit vlastní geokódovací a routing endpoint v konstantách `GEOCODER_URL` a `ROUTER_URL`.

Lokálně lze stránku otevřít přes jednoduchý server, například `python3 -m http.server 8080 -d docs`.
