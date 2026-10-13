// CrtPresets.js — port parametrów z projektu CRT Wrapper
// (js/presets.js + extension/popup.js + crt-overlay/presets.js).
// REGUŁA SYNC: klucze i wartości presetów light/heavy muszą być identyczne
// z tamtymi plikami. Jedyna różnica: brak `curve` (promień obudowy TV
// w demie — na pulpicie nie ma obudowy) i brak `sites` (per-domena nie
// dotyczy pulpitu).
// Zakresy suwaków jak w extension/popup.html.

var DEFAULTS = {
  enabled: true,
  motion: true,
  preset: "light",
  scan: 0.43,
  mask: 0.35,
  vig: 0.32,
  bulge: 0.55,
  warmth: 0.0,
  sat: 1.06,
  flick: 0.35,
  roll: 0.5,
  noise: 0.25,
  chroma: 0.4,
  glass: 0.1,
  glow: 0.35,
  persist: 0.3,
  ca: 0.4,
  smear: 0.3,
  bloom: 0.3
};

var PRESETS = {
  light: {
    scan: 0.43, mask: 0.35, vig: 0.32, bulge: 0.55,
    warmth: 0.0, sat: 1.06, flick: 0.35, roll: 0.5,
    noise: 0.25, chroma: 0.4, glass: 0.1,
    glow: 0.35, persist: 0.3, ca: 0.4, smear: 0.3, bloom: 0.3
  },
  heavy: {
    scan: 1.0, mask: 0.55, vig: 0.62, bulge: 0.7,
    warmth: 0.26, sat: 1.18, flick: 0.55, roll: 0.7,
    noise: 0.4, chroma: 0.55, glass: 0.14,
    glow: 0.6, persist: 0.55, ca: 0.65, smear: 0.5, bloom: 0.55
  }
};

// Pitch scanline'ów — ta sama reguła co w demie i wtyczce MV3:
// physH<=1000 lub physH>=1800 (fizyczne px) -> 4px, inaczej 2px, min 2px.
function scanlinePitchCss(screenH, dpr) {
  dpr = Math.min(dpr || 1, 3);
  var physH = Math.round(screenH * dpr);
  var pitch = (physH <= 1000 || physH >= 1800) ? 4 : 2;
  return Math.max(2, Math.round(pitch / dpr));
}

// Definicje suwaków panelu ustawień (label PL, zakresy z popup.html).
var SETTING_DEFS = [
  { group: "Szkło", key: "scan", label: "Scanlines", min: 0, max: 1, step: 0.01 },
  { group: "Szkło", key: "mask", label: "Grille", min: 0, max: 1, step: 0.01 },
  { group: "Szkło", key: "vig", label: "Winieta", min: 0, max: 1, step: 0.01 },
  { group: "Szkło", key: "bulge", label: "Soczewka", min: 0, max: 1, step: 0.01 },
  { group: "Szkło", key: "warmth", label: "Ciepło", min: 0, max: 1, step: 0.01 },
  { group: "Szkło", key: "sat", label: "Nasycenie", min: 0.5, max: 1.6, step: 0.01 },
  { group: "Ruch", key: "flick", label: "Flicker", min: 0, max: 1, step: 0.01 },
  { group: "Ruch", key: "roll", label: "Rolling", min: 0, max: 1, step: 0.01 },
  { group: "Ruch", key: "noise", label: "Szum", min: 0, max: 1, step: 0.01 },
  { group: "Ruch", key: "chroma", label: "Chroma", min: 0, max: 1, step: 0.01 },
  { group: "Ruch", key: "glass", label: "Odblask szkła", min: 0, max: 0.3, step: 0.01 },
  { group: "Ruch", key: "glow", label: "Poświata lampy", min: 0, max: 1, step: 0.01 },
  { group: "Ruch", key: "persist", label: "Powidoki", min: 0, max: 1, step: 0.01 },
  { group: "Soczewka", key: "ca", label: "Aberracja", min: 0, max: 1, step: 0.01 },
  { group: "Soczewka", key: "smear", label: "Smuga", min: 0, max: 1, step: 0.01 },
  { group: "Soczewka", key: "bloom", label: "Bloom", min: 0, max: 1, step: 0.01 }
];

function sanitized(patch) {
  // Przepuszcza tylko znane klucze liczbowe w ich zakresach (jak popup.js
  // ufał suwakom, tak tu ufamy IPC — ale granice te same).
  var out = {};
  for (var i = 0; i < SETTING_DEFS.length; i++) {
    var d = SETTING_DEFS[i];
    if (patch[d.key] === undefined) continue;
    var v = Number(patch[d.key]);
    if (!isFinite(v)) continue;
    out[d.key] = Math.min(d.max, Math.max(d.min, v));
  }
  return out;
}
