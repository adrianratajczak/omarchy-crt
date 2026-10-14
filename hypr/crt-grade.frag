// crt-grade.frag — OPCJONALNY, statyczny shader grade dla Hyprland.
// Bez uniform `time`: zero banerow, damage tracking zostaje wlaczony,
// zerowy ciagly koszt. Daje PRAWDZIWY grade (saturacja/cieplo/jasnosc
// na pikselach pod spodem) — overlay QML tego nie umie, bo lezy NAD trescia.
//
// Uzycie (reczne):
//   hyprctl eval 'hl.config({ decoration = { screen_shader = "/sciezka/do/crt-grade.frag" } })'
// Wylaczenie:
//   hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })'
//
// Format: GLES3 (#version 300 es), jak shadery hyprshade.
// Wartosci odpowiadaja presetowi light; stroisz stalymi ponizej.

#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float WARMTH = 0.00; // 0..1 (light 0.00, heavy 0.26)
const float SAT = 1.06;    // 0.5..1.6 (light 1.06, heavy 1.18)
const float VIG = 0.32;    // 0..1 (light 0.32, heavy 0.62)

void main() {
  vec4 pix = texture(tex, v_texcoord);
  vec3 c = pix.rgb;
  c *= (1.03 - VIG * 0.12);
  c = mix(c, c * vec3(1.060, 0.990, 0.900), clamp(WARMTH * 1.050, 0.0, 1.0));
  float lum = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(vec3(lum), c, SAT);
  gl_FragColor = vec4(c, pix.a);
}
