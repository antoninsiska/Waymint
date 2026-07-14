(() => {
  "use strict";

  const STORAGE_KEY = "waymint.web.library.v1";
  const BRAND = { appName: "Waymint", logoText: "W", fileExtension: ".way", primaryColorHex: "#247A53", darkRouteColorHex: "#0A281C", description: "Waymint route export. The file is JSON with a custom .way extension." };
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const uid = () => crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const now = () => new Date().toISOString();
  const esc = (value = "") => String(value).replace(/[&<>'"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const slug = value => String(value || "export").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9]+/g, "-").replace(/^-|-$/g, "") || "export";
  const fmtDate = value => new Intl.DateTimeFormat("cs-CZ", {day:"numeric", month:"long", year:"numeric"}).format(new Date(value));
  const fmtTime = value => new Intl.DateTimeFormat("cs-CZ", {hour:"2-digit", minute:"2-digit"}).format(new Date(value));
  const inputTime = value => { const date = new Date(value); return `${String(date.getHours()).padStart(2,"0")}:${String(date.getMinutes()).padStart(2,"0")}`; };
  const shortMonth = value => new Intl.DateTimeFormat("cs-CZ", {month:"short"}).format(new Date(value)).replace(".", "");
  const minutes = n => n < 60 ? `${n} min` : `${Math.floor(n/60)} h${n%60 ? ` ${n%60} min` : ""}`;

  let library = load();
  let search = "";
  let addressResults = [];
  let lastGeocodeRequestAt = 0;
  let addressSearchTimer;
  let addressSearchController;
  const GEOCODER_URL = "https://photon.komoot.io/api/";
  const ROUTER_URL = "https://routing.openstreetmap.de";

  function load() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || []; }
    catch { return []; }
  }
  function save() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(library));
    render();
  }
  function toast(message) {
    const el = $("#toast"); el.textContent = message; el.classList.add("show");
    clearTimeout(toast.timer); toast.timer = setTimeout(() => el.classList.remove("show"), 2600);
  }
  function download(filename, data) {
    const blob = new Blob([JSON.stringify(data, null, 2)], {type:"application/json"});
    const url = URL.createObjectURL(blob); const a = document.createElement("a");
    a.href = url; a.download = filename; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function cityById(id) { return library.find(city => city.id === id); }
  function tripById(city, id) { return city?.trips?.find(trip => trip.id === id); }
  function stopById(trip, id) { return trip?.stops?.find(stop => stop.id === id); }
  function tripDuration(trip) {
    const stops = [...(trip.stops || [])].sort((a,b) => a.sortIndex-b.sortIndex);
    return stops.length > 1 ? Math.max(0, Math.round((new Date(stops.at(-1).plannedDeparture)-new Date(stops[0].plannedArrival))/60000)) : 0;
  }
  function normalizedTrip(trip, city) {
    const result = structuredClone(trip);
    result.cityName = city?.name ?? result.cityName ?? null;
    result.country = city?.country ?? result.country ?? null;
    result.timeRangeLabel = timeRange(result);
    result.approximateDurationMinutes = tripDuration(result);
    return result;
  }
  function timeRange(trip) {
    if (trip.hasFixedStartTime === false) return "Bez pevného začátku";
    const stops = [...(trip.stops || [])].sort((a,b) => a.sortIndex-b.sortIndex);
    return stops.length ? `${fmtTime(stops[0].plannedArrival)}–${fmtTime(stops.at(-1).plannedDeparture)}` : fmtTime(trip.startTime || trip.date);
  }
  function tripCount() { return library.reduce((n,c) => n + (c.trips?.length || 0), 0); }
  function stopCount() { return library.reduce((n,c) => n + (c.trips || []).reduce((m,t) => m + (t.stops?.length || 0), 0), 0); }

  function render() {
    const hash = location.hash || "#/";
    const parts = hash.slice(2).split("/").filter(Boolean);
    if (parts[0] === "city" && parts[1]) return renderCity(parts[1]);
    if (parts[0] === "trip" && parts[1] && parts[2]) return renderTrip(parts[1], parts[2]);
    renderHome();
  }

  function setPrimaryAction(action, label, data = {}) {
    const button = $("#primary-action");
    button.dataset.action = action;
    delete button.dataset.city;
    delete button.dataset.trip;
    Object.entries(data).forEach(([key, value]) => button.dataset[key] = value);
    button.textContent = label;
  }

  function renderHome() {
    setPrimaryAction("new-city", "＋ Přidat město");
    const q = search.trim().toLocaleLowerCase("cs");
    const cities = library.filter(c => !q || [c.name,c.country,...(c.trips||[]).map(t=>t.title)].join(" ").toLocaleLowerCase("cs").includes(q));
    $("#view").innerHTML = `
      <section class="hero"><div class="hero-copy"><span class="eyebrow">Tvůj klidný cestovní plán</span><h1>Cesty, které dávají smysl.</h1><p>Naplánuj města, denní trasy a zastávky. Importuj data z iOS aplikace a vezmi si je zase s sebou.</p><div class="hero-actions"><button class="button secondary" data-action="new-city">Naplánovat město</button><button class="button ghost" data-action="import">Importovat soubor</button></div></div></section>
      <section class="stats"><div class="stat"><strong>${library.length}</strong><span>${library.length === 1 ? "město" : "měst"}</span></div><div class="stat"><strong>${tripCount()}</strong><span>naplánovaných cest</span></div><div class="stat"><strong>${stopCount()}</strong><span>zastávek v itineráři</span></div></section>
      <div class="section-head"><div><h2>Tvoje města</h2><p>Všechny plány uložené v tomto zařízení.</p></div><button class="button" data-action="export-library">⇧ Exportovat vše</button></div>
      ${cities.length ? `<section class="city-grid">${cities.map(cityCard).join("")}</section>` : emptyState(q ? "Nic jsme nenašli" : "Začni prvním městem", q ? "Zkus jiný název města nebo cesty." : "Vytvoř si město, nebo importuj existující .way či .waymint soubor.")}`;
  }

  function cityCard(city) {
    const next = [...(city.trips || [])].sort((a,b)=>new Date(a.date)-new Date(b.date))[0];
    return `<article class="city-card" data-href="#/city/${city.id}" tabindex="0"><div class="city-icon">⌖</div><span class="eyebrow">${esc(city.country || "Cesta")}</span><h3>${esc(city.name)}</h3><p>${esc(city.landingSubtitle || "Připraveno k plánování")}</p><div class="card-foot"><span class="pill">${city.trips?.length || 0} plánů</span><span>${next ? fmtDate(next.date) : "Bez termínu"} →</span></div></article>`;
  }

  function renderCity(id) {
    const city = cityById(id); if (!city) return location.hash = "#/";
    setPrimaryAction("new-trip", "＋ Přidat cestu", {city:id});
    const trips = [...(city.trips || [])].sort((a,b)=>(a.sortIndex??0)-(b.sortIndex??0));
    $("#view").innerHTML = `<div class="breadcrumb"><button data-action="home">Waymint</button><span>/</span><span>${esc(city.name)}</span></div>
      <section class="hero city-hero"><div class="hero-copy"><span class="eyebrow">${esc(city.country || "Město")}</span><h1>${esc(city.landingTitle || city.name)}</h1><p>${esc(city.landingSubtitle || `Naplánuj dny, místa, přesuny a vstupenky pro ${city.name}.`)}</p></div><div class="hero-actions"><button class="button secondary" data-action="new-trip" data-city="${city.id}">＋ Nová cesta</button><button class="button ghost" data-action="export-city" data-city="${city.id}">⇧ Export města</button></div></section>
      <div class="section-head"><div><h2>Denní plány</h2><p>${trips.length} ${trips.length === 1 ? "cesta" : "cest"} v itineráři</p></div><div class="actions"><button class="button" data-action="edit-city" data-city="${city.id}">Upravit město</button><button class="button danger" data-action="delete-city" data-city="${city.id}">Smazat</button></div></div>
      ${trips.length ? `<section class="trip-list">${trips.map(t=>tripRow(city,t)).join("")}</section>` : emptyState("Zatím žádná cesta", "Přidej denní trasu a začni skládat zastávky podle času.", `<button class="button primary" data-action="new-trip" data-city="${city.id}">Přidat cestu</button>`)}`;
  }

  function tripRow(city, trip) {
    const d = new Date(trip.date);
    return `<article class="trip-row" data-href="#/trip/${city.id}/${trip.id}" tabindex="0"><div class="date-tile"><span>${shortMonth(d)}</span><strong>${d.getDate()}</strong></div><div><h3>${esc(trip.title)}</h3><p>${timeRange(trip)} · ${trip.stops?.length || 0} zastávek · ${minutes(tripDuration(trip))}</p></div><div class="trip-meta"><span class="pill">${statusTitle(trip.status)}</span><p>${trip.tickets?.length || 0} vstupenek →</p></div></article>`;
  }

  function renderTrip(cityId, tripId) {
    const city = cityById(cityId), trip = tripById(city, tripId); if (!trip) return location.hash = "#/";
    setPrimaryAction("new-stop", "＋ Přidat zastávku", {city:cityId, trip:tripId});
    const stops = [...(trip.stops || [])].sort((a,b)=>a.sortIndex-b.sortIndex);
    $("#view").innerHTML = `<div class="breadcrumb"><button data-action="home">Waymint</button><span>/</span><button data-href="#/city/${city.id}">${esc(city.name)}</button><span>/</span><span>${esc(trip.title)}</span></div>
      <section class="detail-head"><div><span class="eyebrow">${fmtDate(trip.date)} · ${esc(city.name)}</span><h1>${esc(trip.title)}</h1><p>${timeRange(trip)} · ${stops.length} zastávek · ${minutes(tripDuration(trip))}</p></div><div class="actions"><button class="button primary" data-action="new-stop" data-city="${city.id}" data-trip="${trip.id}">＋ Zastávka</button><button class="button" data-action="export-trip" data-city="${city.id}" data-trip="${trip.id}">⇧ Export .way</button><button class="button danger" data-action="delete-trip" data-city="${city.id}" data-trip="${trip.id}">Smazat</button></div></section>
      ${trip.landingTitle || trip.landingSubtitle ? `<div class="stat" style="margin-top:24px"><strong style="font-size:18px">${esc(trip.landingTitle)}</strong><span>${esc(trip.landingSubtitle)}</span></div>` : ""}
      <div class="section-head"><div><h2>Časová osa</h2><p>${trip.hasFixedStartTime === false ? "Trasa bez pevného začátku" : "Přehled dne krok za krokem"}</p></div></div>
      ${stops.length ? `<section class="timeline">${stops.map((s,i)=>stopCard(s,i,city,trip)).join("")}</section>` : emptyState("Časová osa je prázdná", "Přidej první zastávku a nastav čas příchodu a odchodu.", `<button class="button primary" data-action="new-stop" data-city="${city.id}" data-trip="${trip.id}">Přidat zastávku</button>`)}`;
  }

  function stopCard(stop, index, city, trip) {
    const segment = (trip.travelSegments || []).find(s => s.toStopID === stop.id);
    const distance = segment?.plannedDistanceMeters ? ` · ${segment.plannedDistanceMeters >= 1000 ? `${(segment.plannedDistanceMeters/1000).toFixed(1)} km` : `${segment.plannedDistanceMeters} m`}` : "";
    const travel = index && segment ? `<div class="segment">${transportTitle(segment.transportMode)} · ${minutes((segment.plannedDurationMinutes||0)+(segment.bufferMinutes||0))}${distance}${segment.bufferMinutes ? " včetně rezervy" : ""}${segment.note === "Orientační odhad" ? " · orientačně" : ""}</div>` : "";
    const checklist = stop.checklist || [];
    const doneCount = checklist.filter(item => item.isDone).length;
    const details = stop.note || checklist.length ? `<div class="stop-details">${stop.note ? `<span>📝 ${esc(stop.note)}</span>` : ""}${checklist.length ? `<span>☑ ${doneCount}/${checklist.length} hotovo</span>` : ""}</div>` : "";
    return `${travel}<article class="stop"><div class="rail"><div class="dot">${index ? index+1 : "⚑"}</div><div class="line"></div></div><div class="stop-card"><div class="stop-top"><div><span class="stop-time">${trip.hasFixedStartTime === false ? (index ? `Bod ${index+1}` : "Start") : `${fmtTime(stop.plannedArrival)}–${fmtTime(stop.plannedDeparture)}`}</span><h3>${esc(stop.title)}</h3><p>${esc(stop.address || stop.mainReason || typeTitle(stop.type))}</p></div><div class="stop-actions"><span class="pill">${stop.isRequired === false ? "Volitelná" : index ? stopStatusTitle(stop.status) : "Start"}</span><button class="button" type="button" data-action="edit-stop" data-city="${city.id}" data-trip="${trip.id}" data-stop="${stop.id}">Upravit</button></div></div>${details}</div></article>`;
  }

  function emptyState(title, text, action = `<button class="button primary" data-action="new-city">Přidat město</button>`) {
    return `<section class="empty"><div class="empty-icon">⌖</div><h2>${title}</h2><p>${text}</p>${action}</section>`;
  }

  function openModal(title, body, submit) {
    $("#modal-root").innerHTML = `<div class="modal-backdrop"><form class="modal"><div class="modal-head"><h2>${title}</h2><button class="modal-close" type="button" data-action="close-modal">×</button></div>${body}<div class="modal-actions"><button type="button" class="button" data-action="close-modal">Zrušit</button><button class="button primary" type="submit">Uložit</button></div></form></div>`;
    $("form.modal")?.addEventListener("submit", async e => { e.preventDefault(); await submit(new FormData(e.currentTarget)); closeModal(); });
    $(".modal input")?.focus();
  }
  function closeModal() { $("#modal-root").innerHTML = ""; }
  const field = (name,label,value="",type="text",full=false,attrs="") => `<div class="field ${full?"full":""}"><label for="${name}">${label}</label><input id="${name}" name="${name}" type="${type}" value="${esc(value)}" ${attrs}></div>`;
  const checklistRow = (item = {}) => `<div class="checklist-row" data-id="${esc(item.id || uid())}"><input class="checklist-done" type="checkbox" aria-label="Hotovo" ${item.isDone ? "checked" : ""}><input class="checklist-title" type="text" value="${esc(item.title || "")}" placeholder="Např. koupit vstupenku"><button class="icon-button danger" type="button" data-action="remove-checklist" aria-label="Odebrat položku">×</button></div>`;

  function cityModal(city) {
    openModal(city ? "Upravit město" : "Nové město", `<div class="form-grid">${field("name","Název města",city?.name||"","text",false,"required")}${field("country","Země",city?.country||"")}${field("landingTitle","Nadpis úvodní karty",city?.landingTitle||"","text",true)}${field("landingSubtitle","Krátký popis",city?.landingSubtitle||"","text",true)}</div>`, data => {
      if (city) Object.assign(city, Object.fromEntries(data), {updatedAt:now()});
      else library.push({id:uid(), name:data.get("name"), country:data.get("country"), landingTitle:data.get("landingTitle"), landingSubtitle:data.get("landingSubtitle"), sortIndex:library.length, createdAt:now(), updatedAt:now(), trips:[]});
      save(); toast(city ? "Město bylo upraveno." : "Město bylo vytvořeno.");
    });
  }
  function tripModal(city) {
    const today = new Date().toISOString().slice(0,10);
    openModal("Nová cesta", `<div class="form-grid">${field("title","Název cesty","","text",true,"required")}${field("date","Datum",today,"date",false,"required")}${field("start","Začátek","09:00","time",false,"required")}${field("landingTitle","Nadpis","","text",true)}${field("landingSubtitle","Krátký popis","","text",true)}</div>`, data => {
      const startTime = new Date(`${data.get("date")}T${data.get("start")}:00`).toISOString();
      city.trips ||= []; city.trips.push({id:uid(),cityName:city.name,country:city.country,title:data.get("title"),date:new Date(`${data.get("date")}T12:00:00`).toISOString(),startTime,hasFixedStartTime:true,actualStartedAt:null,actualEndedAt:null,status:"draft",sortIndex:city.trips.length,timeRangeLabel:data.get("start"),approximateDurationMinutes:0,landingTitle:data.get("landingTitle"),landingSubtitle:data.get("landingSubtitle"),photoAlbumTitle:null,note:"",stops:[],travelSegments:[],tickets:[]});
      city.updatedAt=now(); save(); toast("Cesta byla přidána.");
    });
  }
  function stopModal(city, trip, existingStop = null) {
    const date = new Date(trip.date).toISOString().slice(0,10);
    const isEditing = Boolean(existingStop);
    const sortedStops = [...(trip.stops || [])].sort((a,b)=>a.sortIndex-b.sortIndex);
    const stopIndex = isEditing ? sortedStops.findIndex(stop => stop.id === existingStop.id) : sortedStops.length;
    const previous = stopIndex > 0 ? sortedStops[stopIndex-1] : null;
    const incomingSegment = previous ? (trip.travelSegments || []).find(segment => segment.toStopID === existingStop?.id) : null;
    const address = existingStop?.address || "";
    const typeOptions = [["sight","Památka"],["museum","Muzeum"],["restaurant","Restaurace"],["cafe","Kavárna"],["park","Park"],["hotel","Hotel"],["custom","Vlastní bod"]];
    const transportOptions = [["walking","Pěšky"],["publicTransport","MHD"],["car","Auto"],["bike","Kolo"]];
    const options = (items, selected) => items.map(([value,label]) => `<option value="${value}" ${value === selected ? "selected" : ""}>${label}</option>`).join("");
    addressResults = [];
    const checklistMarkup = (existingStop?.checklist || []).sort((a,b)=>(a.sortIndex||0)-(b.sortIndex||0)).map(checklistRow).join("");
    openModal(isEditing ? "Upravit zastávku" : "Nová zastávka", `<div class="form-grid">${field("title","Název místa",existingStop?.title||"","text",true,"required")}${field("arrival","Příchod",existingStop ? inputTime(existingStop.plannedArrival) : "10:00","time",false,"required")}${field("departure","Odchod",existingStop ? inputTime(existingStop.plannedDeparture) : "11:00","time",false,"required")}<div class="field full"><label for="address-query">Vyhledat adresu nebo místo</label><div class="address-search"><input id="address-query" type="search" autocomplete="off" value="${esc(address)}" data-selected-address="${esc(address)}" placeholder="Začni psát, např. Pražský hrad"><span class="search-spinner" aria-hidden="true"></span></div><input id="address" name="address" type="hidden" value="${esc(address)}"><input id="latitude" name="latitude" type="hidden" value="${existingStop?.latitude ?? ""}"><input id="longitude" name="longitude" type="hidden" value="${existingStop?.longitude ?? ""}"><div id="address-results" class="address-results"></div><div id="address-status" class="search-status">${address ? `Aktuální adresa: ${esc(address)}` : "Návrhy se zobrazí po zadání alespoň tří znaků."}</div><div id="map-preview" class="map-preview" hidden></div><div class="address-credit">Vyhledávání Photon · data © OpenStreetMap contributors</div></div>${field("mainReason","Hlavní důvod návštěvy",existingStop?.mainReason||"","text",true)}<div class="field"><label for="type">Typ</label><select name="type" id="type">${options(typeOptions, existingStop?.type || "sight")}</select></div><div class="field"><label for="transportMode">Přesun z předchozího bodu</label><select name="transportMode" id="transportMode" ${previous ? "" : "disabled"}>${options(transportOptions, incomingSegment?.transportMode || "walking")}</select><span class="search-status">${previous ? "Délka přesunu se spočítá automaticky." : "První zastávka nemá předchozí přesun."}</span></div><div class="field full"><label for="note">Poznámky</label><textarea id="note" name="note" rows="4" placeholder="Důležité informace, tipy nebo rezervace…">${esc(existingStop?.note||"")}</textarea></div><div class="field full"><div class="checklist-head"><label>Checklist</label><button class="button" type="button" data-action="add-checklist">＋ Přidat položku</button></div><div id="checklist-items" class="checklist-items">${checklistMarkup}</div><span class="search-status">Položky se uloží ve stejném pořadí.</span></div></div>`, async data => {
      const arrival = new Date(`${date}T${data.get("arrival")}:00`).toISOString(), departure = new Date(`${date}T${data.get("departure")}:00`).toISOString();
      const checklist = $$(".checklist-row").map((row,sortIndex) => ({id:row.dataset.id||uid(),title:$(".checklist-title",row).value.trim(),isDone:$(".checklist-done",row).checked,sortIndex})).filter(item=>item.title);
      const values = {title:data.get("title"),type:data.get("type"),plannedArrival:arrival,plannedDeparture:departure,plannedVisitDurationMinutes:Math.max(0,Math.round((new Date(departure)-new Date(arrival))/60000)),address:data.get("address"),latitude:data.get("latitude") ? Number(data.get("latitude")) : null,longitude:data.get("longitude") ? Number(data.get("longitude")) : null,mainReason:data.get("mainReason"),note:data.get("note"),checklist};
      const stop = existingStop || {id:uid(),status:"planned",note:"",isRequired:true,sortIndex:trip.stops?.length||0,checklist:[],tickets:[]};
      Object.assign(stop, values);
      if (!isEditing) { trip.stops ||= []; trip.stops.push(stop); }
      if(previous){
        const transportMode = data.get("transportMode") || "walking";
        const route = await calculateTransfer(previous, stop, transportMode);
        trip.travelSegments ||= [];
        const segment = incomingSegment || {id:uid(),bufferMinutes:0,fromStopID:previous.id,toStopID:stop.id,sortIndex:trip.travelSegments.length};
        Object.assign(segment,{transportMode,plannedDurationMinutes:route.minutes,plannedDistanceMeters:route.distance,plannedDeparture:previous.plannedDeparture,note:route.estimated ? "Orientační odhad" : "Automaticky spočítáno podle mapy"});
        if (!incomingSegment) trip.travelSegments.push(segment);
      }
      const next = sortedStops[stopIndex+1];
      const outgoingSegment = next ? (trip.travelSegments || []).find(segment => segment.fromStopID === stop.id && segment.toStopID === next.id) : null;
      if (next && outgoingSegment) {
        const route = await calculateTransfer(stop, next, outgoingSegment.transportMode);
        Object.assign(outgoingSegment,{plannedDurationMinutes:route.minutes,plannedDistanceMeters:route.distance,plannedDeparture:stop.plannedDeparture,note:route.estimated ? "Orientační odhad" : "Automaticky spočítáno podle mapy"});
      }
      city.updatedAt = now(); save(); toast(isEditing ? "Zastávka byla upravena." : "Zastávka byla přidána.");
    });
  }

  function scheduleAddressSearch(cityName) {
    clearTimeout(addressSearchTimer);
    const query = $("#address-query")?.value.trim() || "";
    if (query.length < 3) { addressSearchController?.abort(); $("#address-results").innerHTML=""; $("#address-status").textContent="Napiš alespoň tři znaky."; return; }
    $("#address-status").textContent = "Čekám, až dopíšeš…";
    addressSearchTimer = setTimeout(() => searchAddress(cityName), 450);
  }

  async function searchAddress(cityName) {
    const input = $("#address-query"), status = $("#address-status"), results = $("#address-results");
    const query = input?.value.trim();
    if (!query || query.length < 3) { status.textContent = "Zadej alespoň tři znaky."; return; }
    const cacheKey = `waymint.photon.${query.toLocaleLowerCase("cs")}.${cityName.toLocaleLowerCase("cs")}`;
    const cached = localStorage.getItem(cacheKey);
    if (cached) { showAddressResults(JSON.parse(cached)); return; }
    const wait = 1000 - (Date.now() - lastGeocodeRequestAt);
    if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
    status.textContent = "Hledám návrhy…"; results.innerHTML = ""; lastGeocodeRequestAt = Date.now();
    addressSearchController?.abort(); addressSearchController = new AbortController();
    try {
      const url = new URL(GEOCODER_URL);
      url.search = new URLSearchParams({q:`${query}, ${cityName}`,limit:"5"});
      const response = await fetch(url, {headers:{Accept:"application/json"},signal:addressSearchController.signal});
      if (!response.ok) throw new Error("Geocoding failed");
      const payload = await response.json();
      const found = (payload.features || []).map(feature => { const p=feature.properties||{}, coords=feature.geometry?.coordinates||[]; return {display_name:[p.name,p.street,p.housenumber,p.city,p.state,p.country].filter((v,i,a)=>v&&a.indexOf(v)===i).join(", "),lat:String(coords[1]),lon:String(coords[0])}; }).filter(item=>item.display_name&&item.lat&&item.lon);
      localStorage.setItem(cacheKey, JSON.stringify(found)); showAddressResults(found);
    } catch (error) {
      if (error.name === "AbortError") return;
      status.textContent = "Adresu se nepodařilo vyhledat. Zkontroluj připojení a zkus to znovu.";
    }
  }

  async function calculateTransfer(from, to, mode) {
    if (from.latitude == null || from.longitude == null || to.latitude == null || to.longitude == null) return {minutes:0,distance:0,estimated:true};
    const profile = mode === "walking" ? "foot" : mode === "bike" ? "bike" : "car";
    const coordinates = `${from.longitude},${from.latitude};${to.longitude},${to.latitude}`;
    try {
      const response = await fetch(`${ROUTER_URL}/routed-${profile}/route/v1/driving/${coordinates}?overview=false&steps=false`);
      const payload = await response.json(); const route = payload.routes?.[0]; if (!route) throw new Error("No route");
      const factor = mode === "publicTransport" ? 1.15 : 1;
      return {minutes:Math.max(1,Math.round(route.duration*factor/60)),distance:Math.round(route.distance),estimated:mode==="publicTransport"};
    } catch {
      const distance = haversine(from.latitude,from.longitude,to.latitude,to.longitude)*1.22;
      const speed = ({walking:4.8,bike:15,car:35,publicTransport:22})[mode] || 5;
      return {minutes:Math.max(1,Math.round(distance/1000/speed*60)),distance:Math.round(distance),estimated:true};
    }
  }

  function haversine(lat1,lon1,lat2,lon2) { const r=6371000,toRad=v=>v*Math.PI/180,dLat=toRad(lat2-lat1),dLon=toRad(lon2-lon1); const a=Math.sin(dLat/2)**2+Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*Math.sin(dLon/2)**2; return 2*r*Math.atan2(Math.sqrt(a),Math.sqrt(1-a)); }

  function showAddressResults(found) {
    addressResults = found;
    const status = $("#address-status"), results = $("#address-results");
    status.textContent = found.length ? "Vyber správný výsledek:" : "Žádná odpovídající adresa nebyla nalezena.";
    results.innerHTML = found.map((item,index) => `<button class="address-result" type="button" data-action="choose-address" data-index="${index}">${esc(item.display_name)}</button>`).join("");
  }

  function chooseAddress(index) {
    const item = addressResults[index]; if (!item) return;
    $("#address").value = item.display_name;
    $("#latitude").value = item.lat;
    $("#longitude").value = item.lon;
    $("#address-status").textContent = `Vybráno: ${item.display_name}`;
    $("#address-results").innerHTML = "";
    const lat = Number(item.lat), lon = Number(item.lon), delta = .008;
    const bbox = [lon-delta,lat-delta,lon+delta,lat+delta].join(",");
    const preview = $("#map-preview");
    preview.hidden = false;
    preview.innerHTML = `<iframe title="Náhled vybrané adresy" loading="lazy" src="https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(bbox)}&marker=${encodeURIComponent(`${lat},${lon}`)}"></iframe>`;
  }

  function exportTrip(city, trip) { download(`Waymint-${slug(trip.title)}.way`, {format:"waymint.trip",version:1,exportedAt:now(),brand:BRAND,trip:normalizedTrip(trip,city)}); toast("Cesta byla exportována."); }
  function exportCity(city) { download(`Waymint-${slug(city.name)}.waymint`, libraryEnvelope([city])); toast("Město bylo exportováno."); }
  function exportLibrary() { download(`Waymint-zaloha-${new Date().toISOString().slice(0,10)}.waymint`, libraryEnvelope(library)); toast("Knihovna byla exportována."); }
  function libraryEnvelope(cities) { return {format:"waymint.library",version:1,exportedAt:now(),brand:BRAND,cities:cities.map(c=>({...structuredClone(c),trips:(c.trips||[]).map(t=>normalizedTrip(t,c))}))}; }

  async function importFiles(files) {
    let imported = 0;
    for (const file of files) try {
      const data = JSON.parse((await file.text()).replace(/^\uFEFF/, ""));
      if (data.format === "waymint.library" && Array.isArray(data.cities)) { data.cities.forEach(city => mergeCity(city)); imported += data.cities.length; }
      else if (data.format === "waymint.trip" && data.trip) { importStandaloneTrip(data.trip); imported++; }
      else throw new Error("Neznámý formát");
    } catch (error) { toast(`Soubor ${file.name} se nepodařilo načíst.`); }
    if (imported) { save(); toast(`Importováno: ${imported} ${imported===1?"položka":"položek"}.`); }
    $("#file-input").value = "";
  }
  function mergeCity(raw) {
    const city = {...raw,id:uid(),sortIndex:library.length,createdAt:raw.createdAt||now(),updatedAt:now(),trips:(raw.trips||[]).map((t,i)=>({...t,id:uid(),sortIndex:i}))};
    library.push(city);
  }
  function importStandaloneTrip(raw) {
    let city = library.find(c => c.name === (raw.cityName || "Importované cesty"));
    if (!city) { city={id:uid(),name:raw.cityName||"Importované cesty",country:raw.country||"",landingTitle:raw.cityName||"Importované cesty",landingSubtitle:"Importováno z Waymint",sortIndex:library.length,createdAt:now(),updatedAt:now(),trips:[]}; library.push(city); }
    city.trips.push({...raw,id:uid(),sortIndex:city.trips.length});
  }

  function statusTitle(v){return({draft:"Rozpracováno",planned:"Naplánováno",active:"Aktivní",completed:"Dokončeno",archived:"Archiv"})[v]||"Plán";}
  function stopStatusTitle(v){return({planned:"Plánovaná",next:"Následující",active:"Probíhá",completed:"Dokončena",skipped:"Přeskočena",delayed:"Zpožděna"})[v]||"Plánovaná";}
  function typeTitle(v){return({hotel:"Hotel",museum:"Muzeum",gallery:"Galerie",restaurant:"Restaurace",food:"Jídlo",cafe:"Kavárna",park:"Park",sight:"Památka",viewpoint:"Vyhlídka",trainStation:"Nádraží",airport:"Letiště",transport:"Doprava",activity:"Aktivita",shop:"Obchod",custom:"Vlastní bod",transfer:"Přesun"})[v]||"Místo";}
  function transportTitle(v){return({walking:"Pěšky",publicTransport:"MHD",car:"Auto",taxi:"Taxi",train:"Vlak",bike:"Kolo",boat:"Loď",other:"Přesun"})[v]||"Přesun";}

  document.addEventListener("click", e => {
    const target = e.target.closest("[data-action],[data-href]"); if (!target) return;
    if (target.dataset.href) { location.hash=target.dataset.href; return; }
    const action=target.dataset.action, city=cityById(target.dataset.city), trip=tripById(city,target.dataset.trip), stop=stopById(trip,target.dataset.stop);
    if(action==="enter-app") { document.body.classList.add("app-entered"); sessionStorage.setItem("waymint.app.entered","true"); location.hash="#/"; window.scrollTo({top:0,behavior:"smooth"}); }
    if(action==="home") location.hash="#/";
    if(action==="toggle-menu") $(".sidebar").classList.toggle("open");
    if(action==="toggle-theme"){const dark=document.documentElement.dataset.theme!=="dark";document.documentElement.dataset.theme=dark?"dark":"";localStorage.setItem("waymint.theme",dark?"dark":"light");}
    if(action==="import") $("#file-input").click();
    if(action==="new-city") cityModal();
    if(action==="edit-city") cityModal(city);
    if(action==="new-trip") tripModal(city);
    if(action==="new-stop") stopModal(city,trip);
    if(action==="edit-stop") stopModal(city,trip,stop);
    if(action==="add-checklist") { $("#checklist-items").insertAdjacentHTML("beforeend", checklistRow()); $("#checklist-items .checklist-row:last-child .checklist-title")?.focus(); }
    if(action==="remove-checklist") target.closest(".checklist-row")?.remove();
    if(action==="choose-address") chooseAddress(Number(target.dataset.index));
    if(action==="close-modal") closeModal();
    if(action==="export-trip") exportTrip(city,trip);
    if(action==="export-city") exportCity(city);
    if(action==="export-library") exportLibrary();
    if(action==="delete-city" && confirm(`Opravdu smazat město ${city.name}?`)){library=library.filter(c=>c.id!==city.id);save();location.hash="#/";}
    if(action==="delete-trip" && confirm(`Opravdu smazat cestu ${trip.title}?`)){city.trips=city.trips.filter(t=>t.id!==trip.id);save();location.hash=`#/city/${city.id}`;}
  });
  document.addEventListener("input", e => { if(e.target.id === "address-query") { if (e.target.value !== e.target.dataset.selectedAddress) { $("#address").value=""; $("#latitude").value=""; $("#longitude").value=""; } scheduleAddressSearch(e.target.closest(".modal")?.querySelector("[data-city-name]")?.dataset.cityName || currentCityName()); } });
  document.addEventListener("keydown", e => { const el=e.target.closest("[data-href]"); if(el && (e.key==="Enter"||e.key===" ")) location.hash=el.dataset.href; if(e.key==="Escape") closeModal(); });
  $("#search").addEventListener("input", e => { search=e.target.value; if(location.hash!=="#/") location.hash="#/"; else renderHome(); });
  $("#file-input").addEventListener("change", e => importFiles([...e.target.files]));
  function currentCityName(){const parts=(location.hash||"").slice(2).split("/");return cityById(parts[1])?.name||"";}
  window.addEventListener("hashchange", render);
  document.documentElement.dataset.theme = localStorage.getItem("waymint.theme") === "dark" ? "dark" : "";
  if (sessionStorage.getItem("waymint.app.entered") === "true" || /^#\/(city|trip)\//.test(location.hash)) document.body.classList.add("app-entered");
  const revealObserver = new IntersectionObserver(entries => entries.forEach(entry => {
    if (entry.isIntersecting) { entry.target.classList.add("is-visible"); revealObserver.unobserve(entry.target); }
  }), {threshold:.16});
  $$(".scroll-reveal").forEach(element => revealObserver.observe(element));
  render();
})();
