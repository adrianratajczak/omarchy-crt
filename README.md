# CRT Kineskop — efekt kineskopu na froncie całego systemu (wtyczka Omarchy)

Port projektu [adrianratajczak/CRT](https://github.com/adrianratajczak/CRT)
(CRT Wrapper: demo + wtyczka MV3 + `crt-overlay`) na wtyczkę powłoki Omarchy.
Pelna funkcjonalnosc oryginalu: scanlines, aperture grille, winieta, tube glow,
powidoki fosforu, flicker, rolling band, szum, aberracja chromatyczna, smuga
brzegowa, bloom, odblask szkla, power on/off, degauss, presety light/heavy/custom.
Wszystko jako przezroczysta, klikalna warstwa nad calym pulpitem
(Hyprland, wszystkie monitory).

## Architektura (dlaczego tak)

Caly efekt liczy **jeden fragment shader GPU na ekran** (`crt.frag` ->
`crt.frag.qsb` przez `qsb`, 16 warstw w kolejnosci z `css/crt-core.css`,
mieszanie zwykla alfa jak wtyczka MV3). QML nie rusza pikseli: serwis trzyma
stan i czas, uniformy aktualizuja sie same. Koszt: ~+10% rdzenia wzgledem
spoczynku powloki, IPC zawsze responsywne.

Czego plugin **celowo nie robi** (sprawdzone na zywca, wszystko mierzone):

- **Canvas 2D w QML** — pierwsze podejscie (12 warstw, ta sama matematyka
  co w oryginale) dusilo glowny watek pod ~100% i zabijalo IPC. Winny byl
  raster CPU canvasow, nie GPU. Usuniete w calosci.
- **Animowany screen-shader Hyprland (`uniform time`)** — dziala i kosztuje
  ~0 CPU, ale Hyprland pokazuje wtedy nieusuwalny baner ostrzezenia przy
  KAZDEJ aplikacji (`seterror disable`, `dismissnotify`, `error_limit`,
  `error_position` — wszystko przetestowane, baner zostaje). Nie do przyjecia
  w codziennym przelaczniku. Wtyczka nie dotyka `screen_shader` w ogole.
- Statyczny shader (`hypr/crt-grade.frag`, bez `time`) jest czysty: zero
  banerow, damage tracking wlaczony, ~0 kosztu. Daje PRAWDZIWY grade
  (saturacja/cieplo/jasnosc na pikselach), ktorego overlay z natury nie umie
  (lezy NAD trescia). Opcjonalny kompan — szczegoly nizej.

## Instalacja

```sh
omarchy plugin add https://github.com/TWOJ-USER/omarchy-crt --enable
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
(serwis jest jedynym pisarzem; widget i panel czytaja na zywo; zapis ma
retry, zeby nie skasowac decyzji uzytkownika przy przejsciowym bledzie IO).

## Opcjonalnie: prawdziwy grade statycznym shaderem

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

Po zmianie `crt.frag` przekompiluj: `qsb --glsl "100 es,300 es,330" -o crt.frag.qsb crt.frag`
(`qsb` jest w `/usr/lib/qt6/bin/`).

## Testowanie

1. `omarchy plugin validate ./omarchy-crt` — czysty raport.
2. `node --check CrtPresets.js`.
3. Suwak scan — rowne linie, pitch liczony z wysokosci ekranu x DPR.
4. PPM na widget — czern + collapse do linii (~0.4 s), potem zero okien (`hyprctl layers`).
5. Degauss — blysk + wobble + podbicie poswiaty.
6. motion OFF — zamrozona klatka (time stoi).
7. Obciazenie: overlay ~+10% rdzenia wzgledem spoczynku, IPC responsywne.
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
