// crt.frag — caly kineskop w JEDNYM shaderze GPU (Qt RHI, zrodlo pod qsb).
// Port 16 warstw CRT Wrapper (kolejnosc jak w css/crt-core.css):
// grade -> chroma -> scanlines -> mask -> rolling -> persist-trail -> noise
// -> flicker -> persist-glow -> bulge -> vignette -> tubeglow -> edge-ca
// -> edge-smear -> bloom -> glass.
// Mieszanie "over" zwykla alfa (jak wtyczka MV3: bez mix-blend-mode).
// Uniformy MUSZA byc w tej kolejnosci co properties w CrtScreen.qml
// (resolution tuz po qt_Matrix ze wzgledu na std140).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  vec2 resolution;
  float time;
  float scan;
  float mask;
  float vig;
  float bulge;
  float warmth;
  float flick;
  float roll;
  float noise;
  float chroma;
  float glass;
  float glow;
  float persist;
  float ca;
  float smear;
  float bloom;
  float pitch;
  float boost;
};

vec3 acc = vec3(0.0);
float accA = 0.0;
void over(vec3 c, float a) {
  a = clamp(a, 0.0, 1.0);
  acc = c * a + acc * (1.0 - a);
  accA = a + accA * (1.0 - a);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 uv = qt_TexCoord0;
  float t = time;
  float aspect = resolution.x / max(1.0, resolution.y);

  // fale jak w crt-engine.js
  float fast = sin(t * 720.0) * 0.5 + sin(t * 631.0 + 1.7) * 0.5;
  float slow = sin(t * 7.3) * 0.5 + 0.5;

  // 1-2. grade (przyblizenie; prawdziwy saturate tylko shaderem Hyprland)
  over(vec3(1.0, 0.70, 0.42), warmth * 0.10);
  over(vec3(0.0), vig * 0.10);

  // 3. chroma: boczne tinty (op = chroma*.45 jak .crt-chroma)
  float edgeL = clamp(1.0 - uv.x / 0.12, 0.0, 1.0);
  float edgeR = clamp((uv.x - 0.88) / 0.12, 0.0, 1.0);
  over(vec3(1.0, 0.24, 0.43), edgeL * edgeL * chroma * 0.45 * 0.16);
  over(vec3(0.24, 0.86, 1.0), edgeR * edgeR * chroma * 0.45 * 0.16);

  // 4. scanlines (pitch z JS, ciemne 50% jak w demie)
  float row = floor(uv.y * resolution.y / max(1.0, pitch));
  float dark = 1.0 - step(0.5, mod(row, 2.0));
  over(vec3(0.0), dark * scan * 0.55);

  // 5. aperture grille (1px na 3px, monochromatyczna)
  float col = fract(uv.x * resolution.x / 3.0);
  over(vec3(0.0), (1.0 - step(1.0 / 3.0, col)) * mask * 0.35);

  // 6-7. rolling + smuga (0.07/s, zakres -0.35..1.35, lag 0.12)
  float phase = fract(t * 0.07 / 1.7);
  float center = mix(-0.35, 1.35, phase);
  float bd = 1.0 - smoothstep(0.0, 0.18, abs(uv.y - center));
  over(vec3(1.0), bd * bd * roll * 0.080);
  float bd2 = 1.0 - smoothstep(0.0, 0.18, abs(uv.y - (center - 0.12)));
  over(vec3(1.0, 0.84, 0.59), bd2 * bd2 * persist * 0.045);

  // 8. szum 192x108, 20 Hz
  float nt = floor(t * 20.0);
  vec2 cell = floor(uv * vec2(192.0, 108.0));
  float nz = hash12(cell + nt * vec2(17.0, 29.0));
  over(vec3(nz), noise * 0.35);

  // 9. flicker (addytywna biel)
  over(vec3(1.0), max(0.0, flick * (0.012 + 0.010 * fast + 0.014 * slow)));

  // 10. powidok (poziom jak persistV: boost + oddech)
  vec2 q = (uv - vec2(0.5, 0.48)) * vec2(aspect, 1.0);
  float r2 = dot(q, q);
  float vlevel = min(boost + 0.06 + 0.05 * slow, 1.2);
  over(vec3(1.0, 0.77, 0.47), exp(-r2 * 6.0) * persist * (0.18 + 0.5 * min(vlevel, 1.0)) * 0.14);

  // 11. soczewka: jasny srodek, ciemne brzegi (jak .crt-bulge)
  vec2 bq = (uv - vec2(0.5, 0.46)) * vec2(aspect, 1.0);
  float br = sqrt(dot(bq, bq));
  over(vec3(1.0), (1.0 - smoothstep(0.0, 0.45, br)) * 0.06 * bulge);
  over(vec3(0.0), smoothstep(0.45, 0.78, br) * 0.48 * bulge);

  // 12. winieta (sila .35 + vig*.65)
  float va = 0.35 + vig * 0.65;
  vec2 vq = (uv - vec2(0.5)) * vec2(aspect, 1.0);
  float vr = sqrt(dot(vq, vq));
  over(vec3(0.0), smoothstep(0.30, 0.68, vr) * va * 0.72);

  // 13. tube glow (reuse wolnej fali)
  float gmo = glow * (0.75 + 0.25 * slow);
  over(vec3(1.0, 0.77, 0.47), exp(-r2 * 8.0) * gmo * 0.10);
  over(vec3(1.0, 0.66, 0.35), smoothstep(0.15, 0.40, r2) * gmo * 0.07);

  // 14. edge-ca: R gora, C dol (12%), слабее boki (8%)
  over(vec3(1.0, 0.27, 0.27), (1.0 - smoothstep(0.0, 0.12, uv.y)) * ca * 0.14);
  over(vec3(0.31, 0.90, 1.0), smoothstep(0.88, 1.0, uv.y) * ca * 0.14);
  over(vec3(1.0, 0.27, 0.27), (1.0 - smoothstep(0.0, 0.08, uv.x)) * ca * 0.10);
  over(vec3(0.31, 0.90, 1.0), smoothstep(0.92, 1.0, uv.x) * ca * 0.10);

  // 15. edge-smear: miekkie pasy (gradient zamiast blur8)
  over(vec3(1.0), (1.0 - smoothstep(0.0, 0.18, uv.y)) * smear * 0.8 * 0.10);
  over(vec3(1.0), smoothstep(0.82, 1.0, uv.y) * smear * 0.8 * 0.10);
  over(vec3(1.0), (1.0 - smoothstep(0.0, 0.12, uv.x)) * smear * 0.8 * 0.06);
  over(vec3(1.0), smoothstep(0.88, 1.0, uv.x) * smear * 0.8 * 0.06);

  // 16. bloom
  over(vec3(1.0, 0.86, 0.67),
      exp(-r2 * 5.0) * bloom * (0.55 + 0.30 * slow + 0.4 * min(vlevel, 1.0)) * 0.12);

  // 17. glass: odblask gorny + smuga diagonalna
  vec2 gq = (uv - vec2(0.3, 0.12)) * vec2(aspect, 1.0);
  over(vec3(1.0), exp(-dot(gq, gq) * 6.0) * glass * 0.20);
  float dg = (uv.x * 0.6 + uv.y) ;
  over(vec3(1.0), (1.0 - smoothstep(0.0, 0.25, abs(dg - 0.62))) * glass * 0.13);

  fragColor = vec4(acc, accA);
}
