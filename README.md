# CRT Kineskop — CRT effect across the whole system (Omarchy plugin)

A port of [adrianratajczak/CRT](https://github.com/adrianratajczak/CRT)
(CRT Wrapper: demo + MV3 extension + `crt-overlay`) to an Omarchy shell plugin.
Full original functionality: scanlines, aperture grille, vignette, tube glow,
phosphor trails, flicker, rolling band, noise, chromatic aberration, edge smear,
bloom, glass reflection, power on/off, degauss, light/heavy/custom presets.
All as a transparent, click-through layer over the whole desktop
(Hyprland, all monitors).

---

# CRT Kineskop — efekt kineskopu na froncie calego systemu (wtyczka Omarchy)

Port projektu [adrianratajczak/CRT](https://github.com/adrianratajczak/CRT)
(CRT Wrapper: demo + wtyczka MV3 + `crt-overlay`) na wtyczke powloki Omarchy.
Pelna funkcjonalnosc oryginalu: scanlines, aperture grille, winieta, tube glow,
powidoki fosforu, flicker, rolling band, szum, aberracja chromatyczna, smuga
brzegowa, bloom, odblask szkla, power on/off, degauss, presety light/heavy/custom.
Wszystko jako przezroczysta, klikalna warstwa nad calym pulpitem
(Hyprland, wszystkie monitory).

---

# English

## How it works

The plugin is a `service` (engine + windows) + `bar-widget` (toggle) +
`overlay` (settings panel). The service maps one `PanelWindow` per screen
(`Overlay` layer, empty input mask — clicks pass through underneath, like
`pointer-events: none` in the original) and renders all layers in the original
order:

grade -> chroma -> scanlines -> mask -> rolling -> persist-trail -> noise (192x108)
-> flicker -> persist-glow -> bulge -> vignette -> tubeglow -> edge-ca -> edge-smear
-> bloom -> glass -> flash

Performance, tuned for the desktop: a single loop (30 fps Timer — a fullscreen
repaint every frame is the main cost, and 30 fps is enough for phosphor; the
formulas use real time so they are correct at any rate), per-frame only opacity
and y position (rolling/trail), noise max ~20 Hz, static layers painted once
per settings change (debounced), zero-cost with power off (windows unmapped,
like `destroy()`) and with motion OFF (animated layers hidden, like `.motion-off`).

The whole effect is computed by **a single GPU fragment shader per screen**
(`crt.frag` -> `crt.frag.qsb` via `qsb`, 16 layers, plain-alpha compositing
like the MV3 extension). QML never touches pixels: the service holds state and
time, uniforms update by themselves. Cost: ~+10% of a core over shell idle,
IPC always responsive.

Deliberately avoided (all measured live):

- **Canvas 2D in QML** — the first approach (12 layers, same math as the
  original) choked the main thread at ~100% and killed IPC. The CPU raster
  of canvases was the culprit, not the GPU. Removed entirely.
- **Animated Hyprland screen shader (`uniform time`)** — works and costs ~0 CPU,
  but Hyprland shows an undismissable warning banner on EVERY apply
  (`seterror`, `dismissnotify`, `error_limit`, `error_position`, pre-disabling
  damage tracking, GLSL formats — all tested, the banner stays). Unacceptable
  for a daily toggle. The plugin never touches `screen_shader` at all.
- A static shader (`hypr/crt-grade.frag`, no `time`) is clean: zero banners,
  damage tracking stays on, ~zero cost. It provides TRUE grade
  (saturation/warmth/brightness on the pixels underneath) — impossible for an
  overlay, which sits ABOVE the content. Optional companion, see below.

## Installation

```sh
omarchy plugin add https://github.com/adrianratajczak/omarchy-crt --enable
```

Without `--enable` the plugin lands disabled: you can read the code first
(`~/.config/omarchy/plugins/crt.kineskop/`), then
`omarchy plugin enable crt.kineskop`. The plugin has no install hooks and never
asks for sudo (Omarchy standard). Note: `add`/`update` clone via git — commit
changes before `update`, otherwise they never reach the shell.

Add the `CRT Kineskop` widget to the bar like any widget (default: right
section). Note: with a replacement bar (not `omarchy.bar`) the widget may not
render — a standard platform limitation; service and overlay work the same
(verified in isolation: the widget renders `◉ CRT`).

## Removal

```sh
omarchy plugin remove crt.kineskop
```

Removes the plugin code and the `shell.json` entry. Optionally also delete the
saved settings (defaults return on reinstall):

```sh
rm -rf ~/.local/state/omarchy/crt-kineskop
```

## Dependencies and license

No external dependencies (only Quickshell modules and Omarchy built-in
singletons `qs.Commons` / `qs.Ui`). The plugin installs no hooks, never asks
for sudo, and never overwrites any user configuration — its own settings live
in a separate file under `~/.local/state` (above). License: MIT (`LICENSE`).
Effect and parameters: Adrian Ratajczak, CRT Wrapper project.

## Usage

- Bar: `◉/○ CRT` — Left: settings panel, Right: power, Middle: degauss.
- Settings panel (also: `omarchy-shell -q shell toggle crt.kineskop`): Light /
  Heavy / Custom presets, motion switch, 16 sliders (same ranges as the MV3
  popup), Degauss, Reset. Any slider automatically flips the preset to custom.
- CLI (`bin/crt-kineskop`, symlink into `~/.local/bin` or use in keybinds):
  `toggle|on|off|status|preset light|heavy|set scan 0.6|motion on|off|degauss|reset|settings`.

Example keybinds (`~/.config/hypr/bindings.lua`, Omarchy syntax):

```lua
o.bind("SUPER + SHIFT + C", "Kinescope on/off", "crt-kineskop toggle")
o.bind("SUPER + SHIFT + D", "Kinescope degauss", "crt-kineskop degauss")
```

(Note: the above requires `crt-kineskop` on PATH.)

Settings live in `~/.local/state/omarchy/crt-kineskop/config.json`
(the service is the only writer; the widget and the panel read it live).

## Optional: true grade via a static Hyprland shader

An overlay cannot change the saturation of the pixels underneath. `hypr/crt-grade.frag`
(GLES3 `#version 300 es` format, like hyprshade shaders; static = no banners)
does it at the compositor level:

```sh
hyprctl eval 'hl.config({ decoration = { screen_shader = "/path/to/crt-grade.frag" } })'
hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })'  # disable
```

If enabled, turn saturation/warmth down in the plugin settings (otherwise they
count twice). Tune via the constants at the top of the file.

## Honest differences vs the web version

| Web (CRT Wrapper) | Omarchy (this plugin) |
|---|---|
| backdrop-filter grade (sat/sepia/brightness) | tint approximation in the QML shader; full grade only via the Hyprland companion |
| mix-blend-mode (multiply/screen/overlay) | plain alpha (like the MV3 extension, for the same reason) |
| SVG feDisplacementMap barrel geometry | lens shading only (like the MV3 extension) |
| `curve` case radius, TV skins | none (a desktop has no case) |
| trails from scroll velocity | phosphor gently breathes + boost on degauss |
| smear with blur(8px) | gradient-based (cheaper) |
| 120 FPS animation, 24 Hz noise | 30 FPS `time` uniform, 20 Hz noise (real-time formulas — correct) |

The frame engine (sin waves 720/631/7.3, decay 0.92, trail lag 0.12, roll
speed 0.07, pitch thresholds, presets, slider ranges) is ported 1:1 —
only the execution moved to the GPU instead of the DOM.

## Files

| File | Role |
|---|---|
| `manifest.json` | plugin contract: service + bar-widget + overlay |
| `Service.qml` | state, persistence, power/degauss, time, windows, IPC |
| `CrtScreen.qml` | one ShaderEffect per screen + flash/power/wobble |
| `crt.frag` / `crt.frag.qsb` | GLSL source (Vulkan-style) / compiled shader (qsb `--glsl "100 es,300 es,330"`) |
| `CrtPresets.js` | DEFAULTS + PRESETS + pitch + slider definitions |
| `BarWidget.qml` / `Overlay.qml` / `CrtSettingsForm.qml` | toggle, panel, form |
| `bin/crt-kineskop` | CLI for keybinds |
| `hypr/crt-grade.frag` | optional static compositor grade |

## SYNC RULE (port of the original rule)

Three places must keep identical preset keys and values:

1. `CrtPresets.js` (DEFAULTS, PRESETS, SETTING_DEFS)
2. `Service.qml` (property defaults)
3. `crt.frag` (uniform order == property order in CrtScreen!)

After changing `crt.frag`, recompile:
`qsb --glsl "100 es,300 es,330" -o crt.frag.qsb crt.frag`
(`qsb` lives in `/usr/lib/qt6/bin/`).

## Testing

1. `omarchy plugin validate ./omarchy-crt` — clean report.
2. `node --check CrtPresets.js`.
3. Scan slider — even lines, pitch computed from screen height x DPR.
4. Right-click the widget — black + collapse to a line (~0.4 s), then zero windows (`hyprctl layers`).
5. Degauss — flash + wobble + glow boost.
6. Motion OFF — frozen frame (time stands still).
7. Load: overlay ~+10% of a core over idle, responsive IPC.
8. `crt-kineskop status` — JSON of all settings.

## Troubleshooting

- Sluggish desktop / IPC not responding: `omarchy-restart-shell` (a fresh
  instance heals any degenerate state; the effect returns from file on boot).
- Widget missing from the bar: you run a replacement bar — temporarily switch
  to `omarchy.bar` or use the CLI/overlay.
- No effect despite `power on`: check `hyprctl layers | grep crt-kineskop`
  and `crt-kineskop status`.

## Acknowledgements

Whole effect, parameters and character: Adrian Ratajczak, CRT Wrapper project.
This port translates his engine to QML/Quickshell + RHI.

---

# Polski

## Jak to dziala

Wtyczka to `service` (silnik + okna) + `bar-widget` (przelacznik) + `overlay`
(panel ustawien). Serwis mapuje na kazdym ekranie jedno `PanelWindow`
(warstwa Overlay, pusta maska wejscia: klikniecia przechodza pod spod, jak
`pointer-events: none` w oryginale) i rysuje w nim warstwy w oryginalnej kolejnosci:

grade -> chroma -> scanlines -> mask -> rolling -> persist-trail -> noise (192x108)
-> flicker -> persist-glow -> bulge -> vignette -> tubeglow -> edge-ca -> edge-smear
-> bloom -> glass -> flash

Zasady wydajnosci dostrojone do pulpitu: jedna petla (Timer 30 fps —
pelnoekranowy repaint co klatke to glowny koszt, a 30 fps wystarcza dla fosforu;
formuly uzywaja czasu rzeczywistego), w klatce tylko opacity i pozycja y
(rolling/trail), szum max ~20 Hz, statyczne warstwy malowane raz na zmiane
ustawien (debounce), zero-cost przy zgaszonym zasilaniu (okna odmapowane, jak
`destroy()`) i przy motion OFF (warstwy ruchome ukryte, jak `.motion-off`).

Caly efekt liczy **jeden fragment shader GPU na ekran** (`crt.frag` ->
`crt.frag.qsb` przez `qsb`, 16 warstw, mieszanie zwykla alfa jak wtyczka MV3).
QML nie rusza pikseli: serwis trzyma stan i czas, uniformy aktualizuja sie same.
Koszt: ~+10% rdzenia wzgledem spoczynku powloki, IPC zawsze responsywne.

Czego plugin **celowo nie robi** (wszystko sprawdzone na zywca, zmierzone):

- **Canvas 2D w QML** — pierwsze podejscie (12 warstw, ta sama matematyka co
  w oryginale) dusilo glowny watek pod ~100% i zabijalo IPC. Winny byl raster
  CPU canvasow, nie GPU. Usuniete w calosci.
- **Animowany screen-shader Hyprland (`uniform time`)** — dziala i kosztuje
  ~0 CPU, ale Hyprland pokazuje wtedy nieusuwalny baner ostrzezenia przy KAZDEJ
  aplikacji (`seterror`, `dismissnotify`, `error_limit`, `error_position`,
  wylaczanie damage trackingu, formaty GLSL — wszystko przetestowane, baner
  zostaje). Nie do przyjecia w codziennym przelaczniku. Wtyczka nie dotyka
  `screen_shader` w ogole.
- Statyczny shader (`hypr/crt-grade.frag`, bez `time`) jest czysty: zero
  banerow, damage tracking wlaczony, ~0 kosztu. Daje PRAWDZIWY grade
  (saturacja/cieplo/jasnosc na pikselach pod spodem) — niemozliwy dla overlayu,
  ktory lezy NAD trescia. Opcjonalny kompan — szczegoly nizej.

## Instalacja

```sh
omarchy plugin add https://github.com/adrianratajczak/omarchy-crt --enable
```

Bez `--enable` wtyczka laduje nieaktywna: mozesz najpierw przeczytac kod
(`~/.config/omarchy/plugins/crt.kineskop/`), potem
`omarchy plugin enable crt.kineskop`. Wtyczka nie ma hookow instalacyjnych
i nie prosi o sudo (standard Omarchy). Wazne: `add`/`update` klonuja przez
git — commituj zmiany przed `update`, inaczej nie dojda do powloki.

Widget `CRT Kineskop` dokladasz na bar jak kazdy widget (domyslnie sekcja
prawa). Uwaga: przy zamiennikowym barze (nie `omarchy.bar`) widget moze sie
nie wyswietlic — to standardowe ograniczenie platformy, serwis i overlay
dzialaja tak samo (przetestowane w izolacji: widget renderuje `◉ CRT`).

## Usuwanie

```sh
omarchy plugin remove crt.kineskop
```

Usuwa kod wtyczki i wpis z `shell.json`. Opcjonalnie posprzataj tez zapisane
ustawienia (wroca domyslne przy ponownej instalacji):

```sh
rm -rf ~/.local/state/omarchy/crt-kineskop
```

## Zaleznosci i licencja

Brak zewnetrznych zaleznosci (tylko moduly Quickshella i wbudowane
singletony Omarchy `qs.Commons` / `qs.Ui`). Wtyczka nie instaluje hookow,
nie prosi o sudo i nie nadpisuje zadnej konfiguracji uzytkownika — wlasne
ustawienia trzyma w osobnym pliku w `~/.local/state` (powyzej). Licencja:
MIT (`LICENSE`). Efekt i parametry: Adrian Ratajczak, projekt CRT Wrapper.

## Uzycie

- Bar: `◉/○ CRT` — LPM: panel ustawien, PPM: zasilanie, SPM: degauss.
- Panel ustawien (tez: `omarchy-shell -q shell toggle crt.kineskop`): presety
  Light/Heavy/Custom, przelacznik ruchu, 16 suwakow (te same zakresy co popup
  MV3), Degauss, Reset. Suwak z automatu przelacza preset na custom.
- CLI (`bin/crt-kineskop`, dowiąz do `~/.local/bin` albo keybindy):
  `toggle|on|off|status|preset light|heavy|set scan 0.6|motion on|off|degauss|reset|settings`.

Przykladowe keybindy (`~/.config/hypr/bindings.lua`, skladnia Omarchy):

```lua
o.bind("SUPER + SHIFT + C", "Kineskop on/off", "crt-kineskop toggle")
o.bind("SUPER + SHIFT + D", "Kineskop degauss", "crt-kineskop degauss")
```

(Uwaga: powyzsze wymaga `crt-kineskop` w PATH.)

Ustawienia zyja w `~/.local/state/omarchy/crt-kineskop/config.json`
(serwis jest jedynym pisarzem; widget i panel czytaja na zywo).

## Opcjonalnie: prawdziwy grade statycznym shaderem Hyprland

Overlay nie zmieni saturacji pikseli pod spodem. `hypr/crt-grade.frag`
(format GLES3 `#version 300 es`, jak shadery hyprshade; statyczny =
bez banerow) robi to na poziomie kompozytora:

```sh
hyprctl eval 'hl.config({ decoration = { screen_shader = "/sciezka/do/crt-grade.frag" } })'
hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })'  # wylaczenie
```

Jesli wlaczony, skrec saturacje/cieplo w ustawieniach wtyczki (inaczej licza
sie podwojnie). Parametry stroisz stalymi na gorze pliku.

## Uczciwe roznice vs wersja webowa

| Web (CRT Wrapper) | Omarchy (ta wtyczka) |
|---|---|
| backdrop-filter grade (sat/sepia/brightness) | przyblizenie tintem w shaderze QML; pelny grade tylko kompanem Hyprland |
| mix-blend-mode (multiply/screen/overlay) | zwykla alfa (jak wtyczka MV3, z tego samego powodu) |
| geometria beczki SVG feDisplacementMap | tylko cien soczewki (jak wtyczka MV3) |
| promien obudowy `curve`, skiny TV | brak (pulpit nie ma obudowy) |
| powidoki z predkosci scrolla | fosfor minimalnie oddycha + boost przy degauss |
| smuga z blur(8px) | gradientowa (tansza) |
| animacja 120 FPS, szum 24 Hz | uniform `time` 30 FPS, szum 20 Hz (formuly czasu rzeczywistego — poprawne) |

Silnik klatki (fale sin 720/631/7.3, decay 0.92, lag smugi 0.12, predkosc
roll 0.07, progi pitch, presety, zakresy suwakow) przeniesiony 1:1 —
tylko wykonanie jest na GPU zamiast w DOM.

## Pliki

| Plik | Rola |
|---|---|
| `manifest.json` | kontrakt wtyczki: service + bar-widget + overlay |
| `Service.qml` | stan, persistencja, zasilanie/degauss, czas, okna, IPC |
| `CrtScreen.qml` | jeden ShaderEffect na ekran + flash/power/wobble |
| `crt.frag` / `crt.frag.qsb` | zrodlo GLSL (Vulkan-style) / skompilowany shader (qsb `--glsl "100 es,300 es,330"`) |
| `CrtPresets.js` | DEFAULTS + PRESETS + pitch + definicje suwakow |
| `BarWidget.qml` / `Overlay.qml` / `CrtSettingsForm.qml` | przelacznik, panel, formularz |
| `bin/crt-kineskop` | CLI do keybindow |
| `hypr/crt-grade.frag` | opcjonalny statyczny grade kompozytora |

## REGULA SYNC (port oryginalnej reguly)

Trzy miejsca musza miec identyczne klucze i wartosci presetow:

1. `CrtPresets.js` (DEFAULTS, PRESETS, SETTING_DEFS)
2. `Service.qml` (domyslne wartosci properties)
3. `crt.frag` (kolejnosc uniformow == kolejnosc properties w CrtScreen!)

Po zmianie `crt.frag` przekompiluj:
`qsb --glsl "100 es,300 es,330" -o crt.frag.qsb crt.frag`
(`qsb` jest w `/usr/lib/qt6/bin/`).

## Testowanie

1. `omarchy plugin validate ./omarchy-crt` — czysty raport.
2. `node --check CrtPresets.js`.
3. Suwak scan — rowne linie, pitch liczony z wysokosci ekranu x DPR.
4. PPM na widget — czern + collapse do linii (~0.4 s), potem zero okien (`hyprctl layers`).
5. Degauss — blysk + wobble + podbicie poswiaty.
6. motion OFF — zamrozona klatka (time stoi).
7. Obciazenie: overlay ~+10% rdzenia wzgledem spoczynku, responsywne IPC.
8. `crt-kineskop status` — JSON wszystkich ustawien.

## Rozwiazywanie problemow

- Pulpt zamula / IPC nie odpowiada: `omarchy-restart-shell` (swieza instancja
  leczy kazdy stan zdegenerowany; efekt wraca z pliku przy starcie).
- Widgetu nie ma na barze: masz zamiennikowy bar — przelacz chwilowo na
  `omarchy.bar` albo uzywaj CLI/overlayu.
- Efektu nie widac mimo `power on`: sprawdz `hyprctl layers | grep crt-kineskop`
  i `crt-kineskop status`.

## Podziekowania

Caly efekt, parametry i charakterystyka: Adrian Ratajczak, projekt CRT Wrapper.
Ten port tlumaczy jego silnik na QML/Quickshell + RHI.
