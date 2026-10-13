# CRT Kineskop — efekt kineskopu na froncie całego systemu (wtyczka Omarchy)

Port projektu [adrianratajczak/CRT](https://github.com/adrianratajczak/CRT)
(CRT Wrapper: demo + wtyczka MV3 + `crt-overlay`) na wtyczkę powłoki Omarchy.
Pelna funkcjonalnosc oryginalu: scanlines, aperture grille, winieta, tube glow,
powidoki fosforu, flicker, rolling band, szum, aberracja chromatyczna, smuga
brzegowa, bloom, odblask szkla, power on/off, degauss, presety light/heavy/custom.
Wszystko jako przezroczysta, klikalna warstwa nad calym pulpitem
(Hyprland, wszystkie monitory).

## Jak to dziala

Wtyczka to `service` (silnik + okna) + `bar-widget` (przelacznik) + `overlay`
(panel ustawien). Serwis mapuje na kazdym ekranie jedno `PanelWindow`
(warstwa Overlay, pusta maska wejscia: klikniecia przechodza pod spod, jak
`pointer-events: none` w oryginale) i rysuje w nim warstwy w oryginalnej kolejnosci:

grade -> chroma -> scanlines -> mask -> rolling -> persist-trail -> noise (192x108)
-> flicker -> persist-glow -> bulge -> vignette -> tubeglow -> edge-ca -> edge-smear
-> bloom -> glass -> flash

Zasady wydajnosci z oryginalu, dostrojone do pulpitu: jedna petla
(Timer 30 fps — pelnoekranowy repaint co klatke to glowny koszt, a 30 fps
wystarcza dla fosforu; formuly uzywaja czasu rzeczywistego), w klatce tylko
opacity i pozycja y (rolling/trail), szum max ~20 Hz,
statyczne warstwy malowane raz na zmiane ustawien (debounce), zero-cost przy
zgaszonym zasilaniu (okna odmapowane, jak destroy()) i przy motion OFF
(warstwy ruchome ukryte, jak .motion-off).

## Instalacja

```sh
omarchy plugin add https://github.com/TWOJ-USER/omarchy-crt --enable
```

Bez `--enable` wtyczka laduje nieaktywna: mozesz najpierw przeczytac kod
(`~/.config/omarchy/plugins/crt.kineskop/`), potem `omarchy plugin enable crt.kineskop`.
Wtyczka nie ma hookow instalacyjnych i nie prosi o sudo (standard Omarchy).

Widget `CRT Kineskop` dokladasz na bar jak kazdy widget (domyslnie sekcja prawa).

## Uzycie

- Bar: `CRT` z kropka — LPM: panel ustawien, PPM: zasilanie, SPM: degauss.
- Panel ustawien (tez: `omarchy-shell -q shell toggle crt.kineskop`): presety
  Light/Heavy/Custom, przelacznik ruchu, 16 suwakow (te same zakresy co popup MV3),
  Degauss, Reset. Suwak z automatu przelacza preset na custom (jak w oryginale).
- CLI (`bin/crt-kineskop`, dowiąz do ~/.local/bin albo keybindy):
  `toggle|on|off|status|preset light|heavy|set scan 0.6|motion on|off|degauss|reset|settings`.

Przykladowe keybindy (`~/.config/hypr/hyprland.conf`):

```ini
bindd = SUPER SHIFT, C, kineskop on/off, exec, ~/.local/bin/crt-kineskop toggle
bindd = SUPER SHIFT, D, kineskop degauss, exec, ~/.local/bin/crt-kineskop degauss
bindd = SUPER SHIFT, S, kineskop settings, exec, ~/.local/bin/crt-kineskop settings
```

Ustawienia zyja w `~/.local/state/omarchy/crt-kineskop/config.json`
(serwis jest jedynym pisarzem; widget i panel czytaja na zywo).

## Opcjonalnie: prawdziwy grade shaderem Hyprland

Overlay lezy NAD trescia, wiec nie umie naprawde zmienic saturacji/jasnosci
pikseli pod spodem (w wersji webowej robil to backdrop-filter na warstwie grade).
`hypr/crt-grade.frag` robi PRAWDZIWY grade na poziomie kompozytora
(cieplo + saturacja + jasnosc + winieta + scanlines):

```sh
hyprctl keyword decoration:screen_shader "/sciezka/do/crt-grade.frag"
hyprctl keyword decoration:screen_shader ""  # wylaczenie
```

Jesli shader jest wlaczony, w ustawieniach wtyczki skrec scanlines i winiete
do 0 (zeby nie dublowac). Parametry stroisz #define na gorze pliku.

## Uczciwe roznice vs wersja webowa

| Web (CRT Wrapper) | Omarchy (ta wtyczka) |
|---|---|
| backdrop-filter grade (sat/sepia/brightness) | przyblizenie tintem; pelny grade tylko shaderem Hyprland |
| mix-blend-mode (multiply/screen/overlay) | zwykle alfy (jak w wersji Shadow/MV3, z tego samego powodu) |
| geometria beczki SVG feDisplacementMap | tylko cien soczewki (jak wtyczka MV3) |
| promien obudowy `curve`, skiny TV | brak (pulpit nie ma obudowy) |
| powidoki z predkosci scrolla | fosfor minimalnie oddycha + boost przy degauss (brak sygnalu scrolla) |
| smuga z blur(8px) | gradientowa (tansza, bez blur na fullscreen) |
| szum Canvas gladko skalowany | j.w. (lekko miekszy niz pixelated na LCD) |
| per-domena on/off | brak (nie dotyczy pulpitu) |

Silnik klatki (fale sin, decay 0.92, lag smugi 0.12, predkosc roll 0.07,
progi pitch, presety, zakresy suwakow) przeniesiony 1:1.

## REGULA SYNC (port oryginalnej reguly)

Trzy miejsca musza miec identyczne klucze i wartosci presetow:

1. `CrtPresets.js` (DEFAULTS, PRESETS, SETTING_DEFS)
2. `Service.qml` (domyslne wartosci properties)
3. `CrtSettingsForm.qml` (fallbacki) + `hypr/crt-grade.frag` (#define)

## Testowanie

1. `omarchy plugin validate ./omarchy-crt` — czysty raport.
2. `node --check CrtPresets.js`.
3. Po enable: suwak scan — linie rowne, pitch jak w demie; winieta w rogach.
4. PPM na widget — czern + collapse do linii (~0.4 s), potem zero okien.
5. Degauss — blysk + wobble + podbicie poswiaty.
6. motion OFF — brak rolling/flicker/noise; statyczny glow zostaje.
7. Podmiana monitora / resize — overlay wraca sam na wszystkich ekranach.
8. `crt-kineskop status` — JSON wszystkich ustawien.

## Podziekowania

Caly efekt, parametry i charakterystyka: Adrian Ratajczak, projekt CRT Wrapper.
Ten port tylko tlumaczy jego silnik na QML/Quickshell.
