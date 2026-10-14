// CrtShader.js — generator shadera ekranowego Hyprland dla CRT Kineskop.
// Format: GLES3 (#version 300 es), jak shadery hyprshade.
// Rola: PRAWDZIWY grade (saturacja/cieplo/jasnosc na pikselach pod spodem)
// + caly RUCH na GPU (flicker, rolling+trial, szum, oddech glow/bloom/persist).
// QML robi tylko statyke (scanlines, maska, soczewka, winieta, krawedzie,
// odblask); grade-approx w QML jest wylaczany gdy shader aktywny.
// `uniform float time` dostarcza Hyprland; gdyby go nie bylo, time=0
// i obraz jest statyczny (bezpieczna degradacja).
// Stale = wartosci z CrtPresets (3 miejsca po przecinku); boost = chwilowy
// dopalacz fosforu przy degauss (odpowiednik persistV += 0.8 w silniku QML).

function buildFragment(s) {
  return build(s, true);
}

// Wariant statyczny: sam grade, BEZ uniform time — damage tracking zostaje
// wlaczony, zero ciaglego kosztu (tryb motion OFF). Ruch wyzerowany,
// zeby nie zostal zamrozony duch pasma/szumu.
function buildStaticFragment(s) {
  var z = {};
  for (var k in s) z[k] = s[k];
  z.flick = 0; z.roll = 0; z.noise = 0;
  z.glow = 0; z.persist = 0; z.bloom = 0; z.boost = 0;
  return build(z, false);
}

function build(s, animated) {
  function f(x) {
    var v = Number(x);
    if (!isFinite(v)) v = 0;
    return v.toFixed(3);
  }
  var L = [];
  L.push("#version 300 es");
  L.push("precision highp float;");
  L.push("in vec2 v_texcoord;");
  L.push("uniform sampler2D tex;");
  if (animated) L.push("uniform float time;");
  L.push("out vec4 fragColor;");
  L.push("const float WARMTH = " + f(s.warmth) + ";");
  L.push("const float SAT = " + f(s.sat) + ";");
  L.push("const float BRIGHT = " + f(1.03 - s.vig * 0.12) + ";");
  L.push("const float FLICK = " + f(s.flick) + ";");
  L.push("const float ROLL = " + f(s.roll) + ";");
  L.push("const float NOISE = " + f(s.noise) + ";");
  L.push("const float GLOW = " + f(s.glow) + ";");
  L.push("const float PERSIST = " + f(s.persist) + ";");
  L.push("const float BLOOM = " + f(s.bloom) + ";");
  L.push("const float BOOST = " + f(s.boost || 0) + ";");
  L.push("float hash12(vec2 p) {");
  L.push("  vec3 p3 = fract(vec3(p.xyx) * 0.1031);");
  L.push("  p3 += dot(p3, p3.yzx + 33.33);");
  L.push("  return fract((p3.x + p3.y) * p3.z);");
  L.push("}");
  L.push("void main() {");
  L.push("  vec4 pix = texture(tex, v_texcoord);");
  L.push("  vec3 c = pix.rgb;");
  // grade jak warstwa .crt-grade w demie
  L.push("  c *= BRIGHT;");
  L.push("  c = mix(c, c * vec3(1.060, 0.990, 0.900), clamp(WARMTH * 1.050, 0.0, 1.0));");
  L.push("  float lum = dot(c, vec3(0.299, 0.587, 0.114));");
  L.push("  c = mix(vec3(lum), c, SAT);");
  // fale jak w crt-engine.js (tylko wariant animowany)
  L.push("  float t = " + (animated ? "time" : "0.0") + ";");
  L.push("  float fast = sin(t * 720.0) * 0.5 + sin(t * 631.0 + 1.7) * 0.5;");
  L.push("  float slow = sin(t * 7.3) * 0.5 + 0.5;");
  // rolling band + smuga (predkosc 0.07/s, zakres -0.35..1.35 jak w silniku)
  L.push("  float phase = fract(t * 0.07 / 1.7);");
  L.push("  float center = mix(-0.35, 1.35, phase);");
  L.push("  float bd = 1.0 - smoothstep(0.0, 0.18, abs(v_texcoord.y - center));");
  L.push("  c += vec3(1.0) * (bd * bd) * ROLL * 0.080;");
  L.push("  float bd2 = 1.0 - smoothstep(0.0, 0.18, abs(v_texcoord.y - (center - 0.12)));");
  L.push("  c += vec3(1.0, 0.84, 0.59) * (bd2 * bd2) * PERSIST * 0.045;");
  // flicker (addytywna biel jak warstwa .crt-flicker)
  L.push("  c += vec3(1.0) * max(0.0, FLICK * (0.012 + 0.010 * fast + 0.014 * slow));");
  // szum 192x108, 20 Hz (jak canvas co 50 ms)
  L.push("  float nt = floor(t * 20.0);");
  L.push("  vec2 cell = floor(v_texcoord * vec2(192.0, 108.0));");
  L.push("  float nz = hash12(cell + nt * vec2(17.0, 29.0));");
  L.push("  c += (nz - 0.5) * NOISE * 0.5;");
  // oddech fosforu: glow + bloom + persist (poziom jak persistV w silniku)
  L.push("  vec2 q = (v_texcoord - vec2(0.5, 0.48)) * vec2(1.6, 1.0);");
  L.push("  float r2 = dot(q, q);");
  L.push("  float vlevel = min(BOOST + 0.06 + 0.05 * slow, 1.2);");
  L.push("  float glowM = exp(-r2 * 8.0) * GLOW * (0.75 + 0.25 * slow);");
  L.push("  c += vec3(1.0, 0.77, 0.47) * glowM * 0.10;");
  L.push("  float edgeM = smoothstep(0.15, 0.40, r2) * GLOW * (0.75 + 0.25 * slow);");
  L.push("  c += vec3(1.0, 0.66, 0.35) * edgeM * 0.07;");
  L.push("  float persM = exp(-r2 * 6.0) * PERSIST * (0.18 + 0.5 * min(vlevel, 1.0));");
  L.push("  c += vec3(1.0, 0.77, 0.47) * persM * 0.14;");
  L.push("  float bloomM = exp(-r2 * 5.0) * BLOOM * (0.55 + 0.30 * slow + 0.4 * min(vlevel, 1.0));");
  L.push("  c += vec3(1.0, 0.86, 0.67) * bloomM * 0.12;");
  L.push("  fragColor = vec4(c, pix.a);");
  L.push("}");
  return L.join("\n");
}
