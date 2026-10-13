// RagnaMusic-Theme: Badge „RagnaPatched“ oben rechts, Theme-Umschalter und Einfärben
// nach dem Cover. Spicetify lädt diese Datei als extensions/theme.js in den Spotify-Client.
//
// Der Umschalter setzt die Farben als --spice-*-Variablen direkt am <html>-Element. Die
// überschreiben colors.css aus color.ini, und weil Spicetify Spotifys Farben auf diese
// Variablen umgebogen hat, wechselt der ganze Client sofort.

(function ragnaTheme() {
  // Ersetzt patch.ps1 beim Kopieren ins Spicetify-Themes-Verzeichnis durch die Patch-Daten
  const PATCH_INFO = /*RAGNA_PATCH_INFO*/ null;

  const BADGE_ID = "ragna-badge";
  const STORE_KEY = "ragna:theme";
  const UPDATE_KEY = "ragna:update";
  /** GitHub wird höchstens so oft gefragt (ohne Anmeldung gilt ein Limit von 60 Anfragen/h) */
  const UPDATE_EVERY_MS = 6 * 60 * 60 * 1000;
  /** „Später“ blendet die Meldung für diese Version so lange aus */
  const SNOOZE_MS = 24 * 60 * 60 * 1000;
  /** Startet patch.ps1 -Update; der Patcher verknüpft das Protokoll bei der Installation */
  const UPDATE_URL = "ragnapatch://update";
  /** So lange wird auf die obere Leiste gewartet, danach schwebt das Badge frei */
  const NAV_WAIT_MS = 8000;
  const started = Date.now();

  // ---------- Farbschemata ----------

  // Gleiche Schlüssel wie color.ini (Werte ohne #)
  const BASES = {
    dark: {
      text: "eceff6", subtext: "a4acbf", main: "121621", "main-elevated": "1a1f2d",
      highlight: "1a1f2d", "highlight-elevated": "242a3b", sidebar: "07090e", player: "07090e",
      card: "1a1f2d", shadow: "000000", "selected-row": "eceff6", button: "f3aa3c",
      "button-active": "f7bd62", "button-disabled": "343b4f", "tab-active": "242a3b",
      notification: "4e80bc", "notification-error": "ff6b5f", misc: "6e778d",
      "accent-ink": "1b1305", like: "ff5f78", line: "262c3d", tint: "4e80bc",
      "algo-familiar": "ff7f93", "algo-similar": "41cdbb", "algo-discover": "a891ff",
    },
    light: {
      text: "121722", subtext: "4a5368", main: "f8f9fc", "main-elevated": "eef0f6",
      highlight: "eef0f6", "highlight-elevated": "e1e5ee", sidebar: "cfd5e0", player: "cfd5e0",
      card: "eef0f6", shadow: "1e2846", "selected-row": "121722", button: "b5680a",
      "button-active": "c97a17", "button-disabled": "b9c0ce", "tab-active": "e1e5ee",
      notification: "2f5f99", "notification-error": "c8372c", misc: "7b8498",
      "accent-ink": "fff9ef", like: "d92f4d", line: "d6dbe6", tint: "4e80bc",
      "algo-familiar": "c93a55", "algo-similar": "0e8577", "algo-discover": "6a4fd8",
    },
    // reines Schwarz für OLED-Bildschirme, sonst wie Dunkel
    oled: {
      text: "eceff6", subtext: "a4acbf", main: "0a0b0f", "main-elevated": "14161d",
      highlight: "14161d", "highlight-elevated": "1d2029", sidebar: "000000", player: "000000",
      card: "14161d", shadow: "000000", "selected-row": "eceff6", button: "f3aa3c",
      "button-active": "f7bd62", "button-disabled": "2a2e3a", "tab-active": "1d2029",
      notification: "4e80bc", "notification-error": "ff6b5f", misc: "6e778d",
      "accent-ink": "1b1305", like: "ff5f78", line: "1d2029", tint: "4e80bc",
      "algo-familiar": "ff7f93", "algo-similar": "41cdbb", "algo-discover": "a891ff",
    },
  };

  const BASE_NAMES = { dark: "Dunkel", light: "Hell", oled: "OLED" };

  // Vertraut, Ähnlich und Entdecken tragen die Farben der drei Algorithmen aus RagnaMusic
  const PRESETS = [
    { id: "dark", name: "Dunkel", base: "dark" },
    { id: "light", name: "Hell", base: "light" },
    { id: "oled", name: "OLED", base: "oled" },
    { id: "familiar", name: "Vertraut", base: "dark", accent: "ff7f93" },
    { id: "similar", name: "Ähnlich", base: "dark", accent: "41cdbb" },
    { id: "discover", name: "Entdecken", base: "dark", accent: "a891ff" },
  ];

  /** Schnellauswahl für das eigene Theme (falls der Farbwähler im Client nicht aufgeht) */
  const ACCENT_CHIPS = ["f3aa3c", "ff7f93", "41cdbb", "a891ff", "4e80bc", "4fd18b", "ff6b5f", "eceff6"];

  // ---------- Farben rechnen ----------

  function normalizeHex(value) {
    let hex = String(value || "").trim().replace(/^#/, "").toLowerCase();
    if (/^[0-9a-f]{3}$/.test(hex)) hex = hex.replace(/./g, (c) => c + c);
    return /^[0-9a-f]{6}$/.test(hex) ? hex : null;
  }

  const toRgb = (hex) => [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const toHex = (rgb) => rgb.map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("");
  const mix = (a, b, t) => {
    const [x, y] = [toRgb(a), toRgb(b)];
    return toHex(x.map((v, i) => v + (y[i] - v) * t));
  };

  function luminance(hex) {
    const [r, g, b] = toRgb(hex).map((v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  function contrast(a, b) {
    const [hi, lo] = [luminance(a), luminance(b)].sort((p, q) => q - p);
    return (hi + 0.05) / (lo + 0.05);
  }

  /** Akzent einsetzen: bleibt auf der Fläche lesbar, Symbol darauf dunkel oder weiß */
  function withAccent(colors, accent, light) {
    const toward = light ? "000000" : "ffffff";
    let button = accent;
    for (let i = 0; i < 12 && contrast(button, colors.main) < 3; i++) button = mix(button, light ? "000000" : "ffffff", 0.12);
    colors.button = button;
    colors["button-active"] = mix(button, toward, 0.18);
    colors["accent-ink"] = contrast(button, "14110c") >= contrast(button, "ffffff") ? "14110c" : "ffffff";
    colors.tint = button;
    return colors;
  }

  /** Einstellungen → vollständiges Farbschema */
  function resolveColors(settings) {
    const preset = PRESETS.find((p) => p.id === settings.preset);
    const base = preset ? preset.base : settings.custom.base;
    const accent = preset ? preset.accent : settings.custom.accent;
    const colors = { ...BASES[base] };
    return { base, colors: accent ? withAccent(colors, accent, base === "light") : colors };
  }

  // ---------- Einstellungen ----------

  function installedBase() {
    return typeof Spicetify !== "undefined" && Spicetify.Config?.color_scheme === "light" ? "light" : "dark";
  }

  function defaultSettings() {
    return { preset: installedBase(), custom: { base: "dark", accent: "f3aa3c" }, coverTint: true };
  }

  function loadSettings() {
    const settings = defaultSettings();
    try {
      const stored = JSON.parse(localStorage.getItem(STORE_KEY) || "null");
      if (!stored) return { settings, stored: false };
      if (PRESETS.some((p) => p.id === stored.preset) || stored.preset === "custom") settings.preset = stored.preset;
      if (BASES[stored.custom?.base]) settings.custom.base = stored.custom.base;
      settings.custom.accent = normalizeHex(stored.custom?.accent) || settings.custom.accent;
      if (typeof stored.coverTint === "boolean") settings.coverTint = stored.coverTint;
      return { settings, stored: true };
    } catch {
      return { settings, stored: false };
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(state));
    } catch {
      // ohne Speicher gilt die Wahl nur bis zum Neustart
    }
  }

  const loaded = loadSettings();
  let state = loaded.settings;
  let lastCoverTint = null;

  // ---------- Anwenden ----------

  function applyTheme() {
    const root = document.documentElement;
    const { base, colors } = resolveColors(state);
    for (const [key, hex] of Object.entries(colors)) {
      root.style.setProperty(`--spice-${key}`, `#${hex}`);
      root.style.setProperty(`--spice-rgb-${key}`, toRgb(hex).join(","));
    }
    root.style.colorScheme = base === "light" ? "light" : "dark";
    // auf hellem Grund wirkt dieselbe Einfärbung viel kräftiger
    root.style.setProperty("--ragna-tint-mix", base === "light" ? "24%" : "42%");
    applyTint();
  }

  function applyTint() {
    const root = document.documentElement.style;
    if (state.coverTint && lastCoverTint) root.setProperty("--ragna-tint", lastCoverTint);
    else root.removeProperty("--ragna-tint");
  }

  function update(change) {
    state = { ...state, ...change, custom: { ...state.custom, ...(change.custom || {}) } };
    saveSettings();
    applyTheme();
    renderSwitcher();
  }

  // Gespeicherte Wahl sofort setzen, damit Spotify nicht erst im Standardschema aufblitzt
  if (loaded.stored) applyTheme();

  // ---------- Umschalter ----------

  let switcherRoot = null;

  function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
      if (key === "class") node.className = value;
      else if (key === "style") Object.assign(node.style, value);
      else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
      else if (key in node) node[key] = value;
      else node.setAttribute(key, value);
    }
    node.append(...children.filter((c) => c != null));
    return node;
  }

  /** Mini-Vorschau: Fenster, Panel, Textzeilen und Akzent */
  function preview(colors) {
    const c = (key) => `#${colors[key]}`;
    return el(
      "span",
      { class: "ragna-preview", style: { background: c("sidebar") } },
      el(
        "span",
        { class: "ragna-preview__panel", style: { background: c("main") } },
        el("span", { class: "ragna-preview__line", style: { background: c("text") } }),
        el("span", { class: "ragna-preview__line ragna-preview__line--short", style: { background: c("subtext") } }),
        el("span", { class: "ragna-preview__dot", style: { background: c("button") } }),
      ),
    );
  }

  function presetButton(preset) {
    const { colors } = resolveColors({ ...state, preset: preset.id });
    return el(
      "button",
      {
        type: "button",
        class: "ragna-preset" + (state.preset === preset.id ? " is-active" : ""),
        "aria-pressed": String(state.preset === preset.id),
        onclick: () => update({ preset: preset.id }),
      },
      preview(colors),
      el("span", { class: "ragna-preset__name" }, preset.name),
    );
  }

  function customSection() {
    const custom = state.custom;
    const active = state.preset === "custom";
    const setCustom = (change) => update({ preset: "custom", custom: change });

    const bases = el(
      "div",
      { class: "ragna-segmented", role: "group" },
      ...Object.keys(BASES).map((key) =>
        el(
          "button",
          {
            type: "button",
            class: active && custom.base === key ? "is-active" : "",
            onclick: () => setCustom({ base: key }),
          },
          BASE_NAMES[key],
        ),
      ),
    );

    const hexInput = el("input", {
      class: "ragna-hex",
      type: "text",
      value: `#${custom.accent}`,
      maxLength: 7,
      spellcheck: false,
      "aria-label": "Akzentfarbe als Hex-Wert",
      onchange: (e) => {
        const hex = normalizeHex(e.target.value);
        if (hex) setCustom({ accent: hex });
        else e.target.value = `#${custom.accent}`;
      },
    });

    const picker = el("input", {
      class: "ragna-picker",
      type: "color",
      value: `#${custom.accent}`,
      "aria-label": "Akzentfarbe wählen",
      onchange: (e) => setCustom({ accent: normalizeHex(e.target.value) }),
    });

    const chips = el(
      "div",
      { class: "ragna-chips" },
      ...ACCENT_CHIPS.map((hex) =>
        el("button", {
          type: "button",
          class: "ragna-chip" + (active && custom.accent === hex ? " is-active" : ""),
          title: `#${hex}`,
          style: { background: `#${hex}` },
          onclick: () => setCustom({ accent: hex }),
        }),
      ),
    );

    const { colors } = resolveColors({ ...state, preset: "custom" });
    return el(
      "section",
      { class: "ragna-custom" + (active ? " is-active" : "") },
      el(
        "div",
        { class: "ragna-custom__head" },
        preview(colors),
        el(
          "div",
          {},
          el("h3", {}, "Eigenes Theme"),
          el("p", {}, active ? "Aktiv. Änderungen wirken sofort." : "Basis und Akzentfarbe wählen."),
        ),
      ),
      el("div", { class: "ragna-field" }, el("span", {}, "Basis"), bases),
      el("div", { class: "ragna-field" }, el("span", {}, "Akzent"), el("div", { class: "ragna-accent" }, picker, hexInput, chips)),
    );
  }

  function updateControl() {
    if (updater.latest) {
      return el("button", { type: "button", class: "ragna-pill ragna-pill--accent", onclick: startUpdate }, `Auf ${updater.latest.version} updaten`);
    }
    const label = { checking: "Suche …", current: "Aktuell", failed: "Nicht erreichbar" }[updater.status] || "Nach Updates suchen";
    return el(
      "button",
      { type: "button", class: "ragna-pill", disabled: updater.status === "checking", onclick: () => checkForUpdate(true) },
      label,
    );
  }

  function infoList() {
    const rows = [
      ["Patch", PATCH_INFO?.patchVersion],
      ["Gepatcht am", PATCH_INFO?.patchedAt],
      ["Spicetify", Spicetify.Config?.version || PATCH_INFO?.spicetifyVersion],
      ["SpotX", PATCH_INFO?.spotxRef],
      ["Spotify", Spicetify.Platform?.version || PATCH_INFO?.spotifyVersion],
    ].filter(([, value]) => value);
    return el("dl", {}, ...rows.flatMap(([key, value]) => [el("dt", {}, key), el("dd", {}, String(value))]));
  }

  function renderSwitcher() {
    if (!switcherRoot || !switcherRoot.isConnected) return;
    switcherRoot.replaceChildren(
      el("section", {}, el("h3", {}, "Farbschema"), el("div", { class: "ragna-presets" }, ...PRESETS.map(presetButton))),
      customSection(),
      el(
        "label",
        { class: "ragna-toggle" },
        el("input", { type: "checkbox", checked: state.coverTint, onchange: (e) => update({ coverTint: e.target.checked }) }),
        el("span", { class: "ragna-toggle__track" }),
        el("span", {}, el("b", {}, "Nach Cover einfärben"), el("small", {}, "Die Oberfläche nimmt die Farbe des laufenden Songs an.")),
      ),
      el(
        "footer",
        { class: "ragna-footer" },
        infoList(),
        el(
          "div",
          { class: "ragna-footer__actions" },
          updateControl(),
          el(
            "button",
            {
              type: "button",
              class: "ragna-pill ragna-reset",
              onclick: () => {
                try {
                  localStorage.removeItem(STORE_KEY);
                } catch {}
                update(defaultSettings());
              },
            },
            "Zurücksetzen",
          ),
        ),
      ),
    );
  }

  function openSwitcher() {
    switcherRoot = el("div", { class: "ragna-switcher" });
    Spicetify.PopupModal.display({ title: "RagnaMusic Theme", content: switcherRoot, isLarge: true });
    renderSwitcher();
  }

  // ---------- Badge ----------

  function createBadge() {
    const logo = el("img", { src: "ragna/logo.png", alt: "", draggable: false });
    return el(
      "button",
      {
        id: BADGE_ID,
        type: "button",
        class: "ragna-badge" + (updater.latest ? " has-update" : ""),
        title: "RagnaMusic Theme wechseln",
        onclick: openSwitcher,
      },
      logo,
      el("span", {}, el("b", {}, "Ragna"), "Patched"),
    );
  }

  /** Avatar-Knopf oben rechts; das Badge kommt direkt links davor */
  function findAnchor() {
    const avatar =
      document.querySelector('[data-testid="user-widget-link"]') ||
      document.querySelector(".main-userWidget-box");
    if (!avatar) return null;
    // Hülle mit nur einem Kind überspringen, damit das Badge in der Zeile der Knöpfe landet
    let node = avatar;
    while (node.parentElement && node.parentElement.childElementCount === 1 && node.parentElement !== document.body) {
      node = node.parentElement;
    }
    return node.parentElement ? node : null;
  }

  function mountBadge() {
    let badge = document.getElementById(BADGE_ID);
    const anchor = findAnchor();

    if (anchor) {
      if (!badge) badge = createBadge();
      if (badge.nextElementSibling !== anchor) {
        badge.classList.remove("ragna-badge--floating");
        anchor.parentElement.insertBefore(badge, anchor);
      }
      return;
    }

    if (!badge && Date.now() - started > NAV_WAIT_MS) {
      badge = createBadge();
      badge.classList.add("ragna-badge--floating");
      document.body.appendChild(badge);
    }
  }

  // Spotify rendert die obere Leiste öfter neu; dann wird das Badge wieder eingesetzt.
  // Timer statt requestAnimationFrame: das pausiert, solange Spotify minimiert im Tray startet.
  let queued = false;
  function scheduleMount() {
    if (queued) return;
    queued = true;
    setTimeout(() => {
      queued = false;
      mountBadge();
    }, 50);
  }

  // ---------- Updates ----------

  /** status: idle | checking | current | failed; latest: { version, url } einer neueren Version */
  const updater = { status: "idle", latest: null, started: false };

  function readUpdateMemo() {
    try {
      return JSON.parse(localStorage.getItem(UPDATE_KEY) || "null") || {};
    } catch {
      return {};
    }
  }

  function writeUpdateMemo(memo) {
    try {
      localStorage.setItem(UPDATE_KEY, JSON.stringify(memo));
    } catch {}
  }

  function isNewer(candidate, current) {
    const a = String(candidate).split(".").map(Number);
    const b = String(current).split(".").map(Number);
    for (let i = 0; i < 3; i++) {
      if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) > (b[i] || 0);
    }
    return false;
  }

  async function checkForUpdate(manual) {
    const repo = PATCH_INFO?.updateRepo;
    const current = PATCH_INFO?.patchVersion;
    if (!repo || !current) return;

    const memo = readUpdateMemo();
    let latest = memo.latest || null;
    if (manual || !memo.checkedAt || Date.now() - memo.checkedAt > UPDATE_EVERY_MS) {
      updater.status = "checking";
      renderSwitcher();
      try {
        const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
          headers: { Accept: "application/vnd.github+json" },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const release = await res.json();
        latest = { version: String(release.tag_name || "").replace(/^v/, ""), url: release.html_url };
        writeUpdateMemo({ ...memo, checkedAt: Date.now(), latest });
      } catch {
        updater.status = "failed";
        renderSwitcher();
        return;
      }
    }

    updater.latest = latest && isNewer(latest.version, current) ? latest : null;
    updater.status = updater.latest ? "available" : "current";
    document.getElementById(BADGE_ID)?.classList.toggle("has-update", !!updater.latest);
    renderSwitcher();

    const snoozed = memo.snoozed?.version === updater.latest?.version && Date.now() - memo.snoozed.at < SNOOZE_MS;
    if (updater.latest && (manual || !snoozed)) showUpdateNotice();
  }

  function startUpdate() {
    updater.started = true;
    window.open(UPDATE_URL);
    showUpdateNotice();
  }

  function hideUpdateNotice() {
    document.querySelector(".ragna-update")?.remove();
  }

  /** Karte unten rechts: „Update verfügbar“ mit Updaten und Später */
  function showUpdateNotice() {
    hideUpdateNotice();
    const { version, url } = updater.latest;
    const body = updater.started
      ? el(
          "div",
          {},
          el("b", {}, "Update läuft …"),
          el("p", {}, "Ein Fenster von RagnaMusic Patch öffnet sich, danach startet Spotify neu."),
          el("p", { class: "ragna-update__hint" }, "Kein Fenster? Startmenü → RagnaMusic Patch → RagnaMusic Patch aktualisieren."),
        )
      : el(
          "div",
          {},
          el("b", {}, "Update verfügbar"),
          el("p", {}, `RagnaMusic Patch ${version} ist da (installiert: ${PATCH_INFO.patchVersion}).`),
          el(
            "div",
            { class: "ragna-update__actions" },
            el("button", { type: "button", class: "ragna-update__primary", onclick: startUpdate }, "Updaten"),
            el(
              "button",
              {
                type: "button",
                onclick: () => {
                  writeUpdateMemo({ ...readUpdateMemo(), snoozed: { version, at: Date.now() } });
                  hideUpdateNotice();
                },
              },
              "Später",
            ),
            url ? el("button", { type: "button", class: "ragna-update__link", onclick: () => window.open(url) }, "Was ist neu?") : null,
          ),
        );
    const close = el("button", { type: "button", class: "ragna-update__close", "aria-label": "Schließen", onclick: hideUpdateNotice }, "×");
    document.body.append(
      el("div", { class: "ragna-update", role: "status" }, el("img", { src: "ragna/logo.png", alt: "", draggable: false }), body, close),
    );
  }

  // ---------- Einfärben nach dem Cover ----------

  async function updateTint() {
    const data = Spicetify.Player.data;
    const uri = data?.item?.uri || data?.track?.uri;
    lastCoverTint = null;
    if (uri) {
      try {
        const colors = await Spicetify.colorExtractor(uri);
        lastCoverTint = colors?.VIBRANT_NON_ALARMING || colors?.DESATURATED || colors?.PROMINENT || null;
      } catch {
        // lokale Dateien und Podcasts liefern oft keine Farben: Ton des Schemas behalten
      }
    }
    applyTint();
  }

  // ---------- Start ----------

  function ready() {
    return typeof Spicetify !== "undefined" && Spicetify.Player?.addEventListener && Spicetify.colorExtractor && Spicetify.PopupModal && document.body;
  }

  function init() {
    if (!ready()) {
      setTimeout(init, 300);
      return;
    }
    // Spicetify.Config steht erst jetzt sicher bereit: Standard folgt dem installierten Schema
    if (!loaded.stored) state.preset = installedBase();

    new MutationObserver(scheduleMount).observe(document.body, { childList: true, subtree: true });
    // falls sich nichts mehr am DOM ändert, trotzdem nach der Wartezeit frei schwebend zeigen
    setTimeout(scheduleMount, NAV_WAIT_MS + 100);
    scheduleMount();

    // zweiter Weg zum Umschalter: Profilmenü oben rechts
    try {
      new Spicetify.Menu.Item("RagnaMusic Theme", false, openSwitcher).register();
    } catch {
      // ältere Spicetify-Versionen ohne Menü-API: nur über das Badge
    }

    Spicetify.Player.addEventListener("songchange", updateTint);
    updateTint();

    // nach dem Start kurz warten, damit die Prüfung den Start von Spotify nicht bremst
    setTimeout(() => checkForUpdate(false), 5000);
    setInterval(() => checkForUpdate(false), UPDATE_EVERY_MS);
  }

  init();
})();
