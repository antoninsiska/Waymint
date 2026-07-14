# Waymint Web

Statická webová verze Waymint určená pro GitHub Pages. Obsahuje animovanou produktovou landing page a plnohodnotný plánovač cest v prohlížeči. Nemá vlastní backend ani účet uživatele; data ukládá do `localStorage` aktuálního prohlížeče.

## Použití

Web se otevře na landing page. Tlačítko **Vstup do aplikace** přejde do plánovače. Z plánovače se lze vrátit kliknutím na logo Waymint nebo položkou **Úvodní stránka** v levém menu.

Plánovač podporuje:

- města, cesty, časové zastávky, poznámky a checklisty,
- vyhledávání adres a náhled vybraného místa na mapě,
- automatický odhad přesunů pěšky, na kole, MHD nebo autem,
- světlý a tmavý motiv,
- lokální ukládání bez registrace,
- import a export cest i celé knihovny.

## GitHub Pages

1. Nahrajte složku `docs` do hlavní větve repozitáře.
2. V GitHubu otevřete **Settings → Pages**.
3. Jako zdroj zvolte **Deploy from a branch**, větev a složku **/docs**.

Po dalším pushi do vybrané větve GitHub Pages automaticky zveřejní aktualizovanou verzi obsahu složky `docs`.

Web podporuje import a export formátů iOS aplikace:

- `.way` – jedna cesta,
- `.waymint` – vybrané město nebo kompletní knihovna.

Protože jsou data uložena pouze v daném prohlížeči, před vymazáním jeho úložiště nebo přechodem na jiné zařízení doporučujeme použít **Export knihovny**.

Našeptávání adres používá Photon nad daty OpenStreetMap. Požadavky mají prodlevu, jsou omezené na nejvýše jeden za sekundu a výsledky se lokálně cachují. Přesuny mezi body se automaticky počítají pomocí OSRM; při nedostupnosti serveru se použije lokální odhad podle vzdálenosti a typu dopravy. Pro větší veřejný provoz je vhodné nastavit vlastní geokódovací a routing endpoint v konstantách `GEOCODER_URL` a `ROUTER_URL`.

## Lokální spuštění

Z kořenové složky repozitáře spusťte:

```sh
python3 -m http.server 8080 -d docs
```

Potom otevřete `http://localhost:8080`. Přímé otevření `index.html` jako lokálního souboru se nedoporučuje, protože chování prohlížeče se může lišit od GitHub Pages.
