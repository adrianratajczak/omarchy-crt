// crt-grade.frag — OPCJONALNY shader ekranowy Hyprland dla „CRT Kineskop".
//
// Po co: overlay QML leży NAD treścią, więc nie umie naprawdę zmienić
// saturacji/jasności pikseli pod spodem (w wersji webowej robił to
// backdrop-filter na warstwie grade). Ten shader robi PRAWDZIWY grade
// na poziomie kompozytora: ciepło fosforu + saturacja + przyciemnienie
// + winieta + scanlines.
//
// Użycie (ręczne, jednorazowo):
//   hyprctl keyword decoration:screen_shader "/ścieżka/do/crt-grade.frag"
// Wyłączenie:
//   hyprctl keyword decoration:screen_shader ""
//
// Jeśli shader jest włączony, w ustawieniach wtyczki warto skręcić
// scanlines i winietę do 0 (żeby nie dublować), a warmth zostawić na 0.
// Wartości stroisz #define poniżej — odpowiedniki presetu light.
//
// Format: Hyprland screen shader (GLSL ES): wejście `tex`, UV `v_texcoord`.

precision mediump float;
varying vec2 v_texcoord;
uniform sampler2D tex;

#define WARMTH   0.00   // 0..1  ciepło fosforu (jak warmth; light=0.00 heavy=0.26)
#define SAT      1.06   // 0.5..1.6 nasycenie (light=1.06 heavy=1.18)
#define VIG      0.32   // 0..1  winieta (light=0.32 heavy=0.62)
#define SCAN     0.43   // 0..1  scanlines (light=0.43 heavy=1.0)
#define SCAN_PX  540.0  // linii na wysokość ekranu (1080p -> pitch 2px)

vec3 applySat(vec3 c, float s) {
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  return mix(vec3(l), c, s);
}

void main() {
  vec4 pix = texture2D(tex, v_texcoord);
  vec3 c = pix.rgb;

  // jasność jak grade w demie: 1.03 - vig*0.12
  c *= (1.03 - VIG * 0.12);
  // ciepło fosforu jak sepia(warmth*.35) — przybliżenie: przesunięcie ku bursztynowi
  c = mix(c, c * vec3(1.06, 0.99, 0.90), clamp(WARMTH * 0.35 * 3.0, 0.0, 1.0));
  // nasycenie
  c = applySat(c, SAT);

  // winieta (jak .crt-vignette: transparent 52% -> czerń 100%)
  vec2 d = v_texcoord - vec2(0.5);
  d.x *= 1.6; // korekta proporcji ~16:9
  float r = length(d);
  float vigMask = smoothstep(0.42, 0.95, r);
  float va = 0.35 + VIG * 0.65;
  c *= (1.0 - vigMask * va * 0.72);

  // scanlines (jak .crt-scanlines 50/50)
  float line = step(0.5, fract(v_texcoord.y * SCAN_PX));
  c *= mix(1.0 - 0.55 * SCAN, 1.0 + 0.06 * SCAN, line);

  gl_FragColor = vec4(c, pix.a);
}
