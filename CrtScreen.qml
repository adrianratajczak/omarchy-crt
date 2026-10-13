// CrtScreen.qml — obraz kineskopu na jednym ekranie.
// Port kolejności warstw z CRT Wrapper:
// grade -> chroma -> scanlines -> mask -> rolling -> persist-trail ->
// noise -> flicker -> persist-glow -> bulge -> vignette -> tubeglow ->
// edge-ca -> edge-smear -> bloom -> glass -> flash.
//
// W klatce ruszane TYLKO opacity i y (jak w oryginale transform+opacity).
// Statyczne gradienty maluje Canvas raz na zmianę ustawień (staticRevision).
// Całość ma pustą maskę wejścia (ustawia okno) = klikalność jak
// pointer-events:none w oryginale.

import QtQuick
import "CrtPresets.js" as CrtPresets

Item {
  id: screen
  property var svc: null

  readonly property real dpr: Screen.devicePixelRatio || 1

  function reqStatic() {
    if (!visible || !svc || !svc.powered) return;
    staticCv.requestPaint();
    glowCv.requestPaint();
    bloomCv.requestPaint();
    persistCv.requestPaint();
  }

  Connections {
    target: screen.svc
    function onStaticRevisionChanged() { screen.reqStatic(); }
  }

  onWidthChanged: screen.reqStatic()
  onHeightChanged: screen.reqStatic()
  onVisibleChanged: { if (visible) screen.reqStatic(); }

  // Kontener całości (degauss wobble — przybliżenie: rusza się nakładka,
  // nie treść pod spodem; treść jest poza zasięgiem overlayu).
  Item {
    id: layers
    anchors.fill: parent
    transformOrigin: Item.Center

    SequentialAnimation {
      id: wobbleAnim
      running: screen.svc && screen.svc.wobbling
      PropertyAnimation { target: layers; property: "x"; from: 0; to: 9; duration: 90; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: 9; to: -8; duration: 130; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: -8; to: 4; duration: 130; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: 4; to: 0; duration: 160; easing.type: Easing.OutQuad }
      PropertyAnimation { target: layers; property: "rotation"; from: 0; to: 0.35; duration: 140 }
      PropertyAnimation { target: layers; property: "rotation"; from: 0.35; to: -0.3; duration: 160 }
      PropertyAnimation { target: layers; property: "rotation"; to: 0; duration: 150 }
    }

    // ---- grade: przybliżenie (overlay jest NAD treścią, więc prawdziwy
    // saturate/sepia/brightness da tylko shader Hyprland — hypr/crt-grade.frag).
    // Tu: ciepły tint (warmth) + globalne przyciemnienie (vig). ----
    Rectangle {
      anchors.fill: parent
      color: "#ffb36b"
      opacity: screen.svc ? screen.svc.warmth * 0.10 : 0
    }
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: screen.svc ? screen.svc.vig * 0.10 : 0
    }

    // ---- statyczne szkło: chroma, scanlines, maska, soczewka, winieta,
    //      krawędzie, odblask (jeden Canvas, repaint tylko na zmianę) ----
    Canvas {
      id: staticCv
      anchors.fill: parent
      renderTarget: Canvas.FramebufferObject
      onPaint: {
        if (!screen.svc) return;
        var ctx = getContext("2d");
        var w = width, h = height;
        var s = screen.svc;
        ctx.clearRect(0, 0, w, h);

        // chroma: boczne tinty (jak .crt-chroma, op = chroma*.45)
        var ca = s.chroma * 0.45;
        if (ca > 0.003) {
          var gl = ctx.createLinearGradient(0, 0, w * 0.12, 0);
          gl.addColorStop(0, "rgba(255,60,110," + (0.08 * ca * 2).toFixed(3) + ")");
          gl.addColorStop(1, "rgba(255,60,110,0)");
          ctx.fillStyle = gl;
          ctx.fillRect(0, 0, w * 0.12, h);
          var gr = ctx.createLinearGradient(w, 0, w * 0.88, 0);
          gr.addColorStop(0, "rgba(60,220,255," + (0.08 * ca * 2).toFixed(3) + ")");
          gr.addColorStop(1, "rgba(60,220,255,0)");
          ctx.fillStyle = gr;
          ctx.fillRect(w * 0.88, 0, w * 0.12, h);
        }

        // scanlines (pitch wg reguły z dema, min 2px)
        var pitch = CrtPresets.scanlinePitchCss(h, screen.dpr);
        if (s.scan > 0.003 && pitch >= 2) {
          var half = Math.max(1, Math.round(pitch / 2));
          ctx.fillStyle = "rgba(0,0,0," + (0.55 * s.scan).toFixed(3) + ")";
          for (var y = 0; y < h; y += pitch) ctx.fillRect(0, y, w, half);
          ctx.fillStyle = "rgba(255,255,255," + (0.06 * s.scan).toFixed(3) + ")";
          for (var y2 = half; y2 < h; y2 += pitch) ctx.fillRect(0, y2, w, pitch - half);
        }

        // aperture grille (monochromatyczna, okres 3px)
        if (s.mask > 0.003) {
          ctx.fillStyle = "rgba(0,0,0," + (0.35 * s.mask).toFixed(3) + ")";
          for (var x = 0; x < w; x += 3) ctx.fillRect(x, 0, 1, h);
        }

        // soczewka: jasny środek, ściśnięte ciemne krawędzie (jak .crt-bulge)
        if (s.bulge > 0.003) {
          var rr = Math.max(w, h) * 0.62;
          var bg = ctx.createRadialGradient(w / 2, h * 0.46, 0, w / 2, h * 0.46, rr);
          bg.addColorStop(0, "rgba(255,255,255," + (0.06 * s.bulge).toFixed(3) + ")");
          bg.addColorStop(0.42, "rgba(255,255,255,0)");
          bg.addColorStop(0.74, "rgba(0,0,0," + (0.16 * s.bulge).toFixed(3) + ")");
          bg.addColorStop(1, "rgba(0,0,0," + (0.48 * s.bulge).toFixed(3) + ")");
          ctx.fillStyle = bg;
          ctx.fillRect(0, 0, w, h);
        }

        // winieta (siła .35 + vig*.65 jak w oryginale)
        var va = 0.35 + s.vig * 0.65;
        var vg = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, Math.max(w, h) * 0.72);
        vg.addColorStop(0.42, "rgba(0,0,0,0)");
        vg.addColorStop(0.68, "rgba(0,0,0," + (0.26 * va).toFixed(3) + ")");
        vg.addColorStop(1, "rgba(0,0,0," + (0.72 * va).toFixed(3) + ")");
        ctx.fillStyle = vg;
        ctx.fillRect(0, 0, w, h);

        // edge-ca: prążki R/C mocniej góra/dół (12%), słabiej boki (8%)
        if (s.ca > 0.003) {
          var top = ctx.createLinearGradient(0, 0, 0, h * 0.12);
          top.addColorStop(0, "rgba(255,70,70," + (0.14 * s.ca).toFixed(3) + ")");
          top.addColorStop(0.5, "rgba(255,70,70," + (0.04 * s.ca).toFixed(3) + ")");
          top.addColorStop(1, "rgba(255,70,70,0)");
          ctx.fillStyle = top;
          ctx.fillRect(0, 0, w, h * 0.12);
          var bot = ctx.createLinearGradient(0, h, 0, h * 0.88);
          bot.addColorStop(0, "rgba(80,230,255," + (0.14 * s.ca).toFixed(3) + ")");
          bot.addColorStop(0.5, "rgba(80,230,255," + (0.04 * s.ca).toFixed(3) + ")");
          bot.addColorStop(1, "rgba(80,230,255,0)");
          ctx.fillStyle = bot;
          ctx.fillRect(0, h * 0.88, w, h * 0.12);
          var lf = ctx.createLinearGradient(0, 0, w * 0.08, 0);
          lf.addColorStop(0, "rgba(255,70,70," + (0.10 * s.ca).toFixed(3) + ")");
          lf.addColorStop(1, "rgba(255,70,70,0)");
          ctx.fillStyle = lf;
          ctx.fillRect(0, 0, w * 0.08, h);
          var rt = ctx.createLinearGradient(w, 0, w * 0.92, 0);
          rt.addColorStop(0, "rgba(80,230,255," + (0.10 * s.ca).toFixed(3) + ")");
          rt.addColorStop(1, "rgba(80,230,255,0)");
          ctx.fillStyle = rt;
          ctx.fillRect(w * 0.92, 0, w * 0.08, h);
        }

        // edge-smear: miękkie pasy wzdłuż krawędzi (gradient zamiast blur8)
        if (s.smear > 0.003) {
          var sa = 0.8 * s.smear;
          var s1 = ctx.createLinearGradient(0, 0, 0, h * 0.18);
          s1.addColorStop(0, "rgba(255,255,255," + (0.10 * sa).toFixed(3) + ")");
          s1.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = s1;
          ctx.fillRect(0, 0, w, h * 0.18);
          var s2 = ctx.createLinearGradient(0, h, 0, h * 0.82);
          s2.addColorStop(0, "rgba(255,255,255," + (0.10 * sa).toFixed(3) + ")");
          s2.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = s2;
          ctx.fillRect(0, h * 0.82, w, h * 0.18);
          var s3 = ctx.createLinearGradient(0, 0, w * 0.12, 0);
          s3.addColorStop(0, "rgba(255,255,255," + (0.06 * sa).toFixed(3) + ")");
          s3.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = s3;
          ctx.fillRect(0, 0, w * 0.12, h);
          var s4 = ctx.createLinearGradient(w, 0, w * 0.88, 0);
          s4.addColorStop(0, "rgba(255,255,255," + (0.06 * sa).toFixed(3) + ")");
          s4.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = s4;
          ctx.fillRect(w * 0.88, 0, w * 0.12, h);
        }

        // glass: statyczny odblask szkła (alfa * glass, jak op warstwy)
        if (s.glass > 0.003) {
          var gg = ctx.createRadialGradient(w * 0.3, h * 0.12, 0, w * 0.3, h * 0.12, Math.max(w, h) * 0.45);
          gg.addColorStop(0, "rgba(255,255,255," + (0.20 * s.glass).toFixed(3) + ")");
          gg.addColorStop(0.5, "rgba(255,255,255," + (0.05 * s.glass).toFixed(3) + ")");
          gg.addColorStop(1, "rgba(255,255,255,0)");
          ctx.fillStyle = gg;
          ctx.fillRect(0, 0, w, h);
          ctx.save();
          ctx.translate(w / 2, h / 2);
          ctx.rotate(-0.35);
          var dg = ctx.createLinearGradient(-w, 0, w, 0);
          dg.addColorStop(0.5, "rgba(255,255,255,0)");
          dg.addColorStop(0.62, "rgba(255,255,255," + (0.13 * s.glass).toFixed(3) + ")");
          dg.addColorStop(0.74, "rgba(255,255,255,0)");
          ctx.fillStyle = dg;
          ctx.fillRect(-w, -h, w * 2, h * 2);
          ctx.restore();
        }
      }
    }

    // ---- rolling band (tylko y + opacity) ----
    Rectangle {
      visible: screen.svc ? (screen.svc.motion && screen.svc.roll > 0.01) : false
      width: parent.width
      height: parent.height * 2.2
      y: (-1.1 + (screen.svc ? screen.svc.rollPos : -0.3) * 2.2) * parent.height
      opacity: screen.svc ? screen.svc.rollOp : 0
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.09) }
        GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.16) }
        GradientStop { position: 0.58; color: Qt.rgba(1, 1, 1, 0.09) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    // ---- smuga powidoku: opóźniona kopia pasma (lag 0.12 jak w oryginale) ----
    Rectangle {
      visible: screen.svc ? screen.svc.motion : false
      width: parent.width
      height: parent.height * 2.2
      y: (-1.1 + ((screen.svc ? screen.svc.rollPos : -0.3) - 0.12) * 2.2) * parent.height
      opacity: screen.svc ? screen.svc.trailOp : 0
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.42; color: Qt.rgba(1, 0.84, 0.59, 0.07) }
        GradientStop { position: 0.50; color: Qt.rgba(1, 0.84, 0.59, 0.13) }
        GradientStop { position: 0.58; color: Qt.rgba(1, 0.84, 0.59, 0.07) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    // ---- szum fosforu: 192x108, max ~24 Hz (jak drawNoise co 42 ms) ----
    Canvas {
      id: noiseCv
      anchors.fill: parent
      canvasSize: Qt.size(192, 108)
      visible: screen.svc ? (screen.svc.motion && screen.svc.noise > 0.01) : false
      opacity: screen.svc ? screen.svc.noiseOp : 0
      onPaint: {
        if (!screen.svc) return;
        var ctx = getContext("2d");
        var img = ctx.createImageData(192, 108);
        var d = img.data;
        var a = Math.round(28 + screen.svc.noise * 60);
        for (var i = 0; i < d.length; i += 4) {
          var v = (Math.random() * 255) | 0;
          d[i] = v; d[i + 1] = v; d[i + 2] = v; d[i + 3] = a;
        }
        ctx.putImageData(img, 0, 0);
      }
    }
    Timer {
      interval: 42
      repeat: true
      running: noiseCv.visible && screen.visible
      onTriggered: noiseCv.requestPaint()
    }

    // ---- flicker: biała warstwa, tylko opacity ----
    Rectangle {
      anchors.fill: parent
      color: "white"
      visible: screen.svc ? (screen.svc.motion && screen.svc.flick > 0.01) : false
      opacity: screen.svc ? screen.svc.flickerOp : 0
    }

    // ---- powidok pełnoekranowy (ciepła poświata, opacity ze scroll-decay) ----
    Canvas {
      id: persistCv
      anchors.fill: parent
      canvasSize: Qt.size(480, 270)
      visible: screen.svc ? screen.svc.motion : false
      opacity: screen.svc ? screen.svc.persistOp : 0
      onPaint: {
        var ctx = getContext("2d");
        var w = 480, h = 270;
        ctx.clearRect(0, 0, w, h);
        var g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w * 0.55);
        g.addColorStop(0, "rgba(255,196,120,0.14)");
        g.addColorStop(0.45, "rgba(255,170,90,0.06)");
        g.addColorStop(0.7, "rgba(255,170,90,0)");
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
      }
    }

    // ---- tube glow: poświata lampy (reuse wolnej fali — tu via glowOp) ----
    Canvas {
      id: glowCv
      anchors.fill: parent
      canvasSize: Qt.size(480, 270)
      opacity: screen.svc ? screen.svc.glowOp : 0
      onPaint: {
        var ctx = getContext("2d");
        var w = 480, h = 270;
        ctx.clearRect(0, 0, w, h);
        var g = ctx.createRadialGradient(w / 2, h * 0.48, 0, w / 2, h * 0.48, w * 0.42);
        g.addColorStop(0, "rgba(255,196,120,0.10)");
        g.addColorStop(0.38, "rgba(255,178,102,0.05)");
        g.addColorStop(0.62, "rgba(255,178,102,0)");
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
        var e = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w * 0.62);
        e.addColorStop(0.68, "rgba(255,170,90,0)");
        e.addColorStop(0.88, "rgba(255,170,90,0.07)");
        e.addColorStop(1, "rgba(255,150,70,0.12)");
        ctx.fillStyle = e;
        ctx.fillRect(0, 0, w, h);
      }
    }

    // ---- namiastka bloom ----
    Canvas {
      id: bloomCv
      anchors.fill: parent
      canvasSize: Qt.size(480, 270)
      visible: screen.svc ? screen.svc.motion : false
      opacity: screen.svc ? screen.svc.bloomOp : 0
      onPaint: {
        var ctx = getContext("2d");
        var w = 480, h = 270;
        ctx.clearRect(0, 0, w, h);
        var g = ctx.createRadialGradient(w / 2, h * 0.46, 0, w / 2, h * 0.46, w * 0.5);
        g.addColorStop(0, "rgba(255,220,170,0.12)");
        g.addColorStop(0.45, "rgba(255,200,150,0.05)");
        g.addColorStop(0.7, "rgba(255,200,150,0)");
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
      }
    }

    // ---- flash (degauss / power) ----
    Rectangle {
      anchors.fill: parent
      color: "white"
      opacity: screen.svc ? screen.svc.flashOp : 0
    }

    // ---- power-off: czern + collapse do białej linii (jak .is-off) ----
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: screen.svc && screen.svc.dying ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 60 } }
    }
    Rectangle {
      id: powerLine
      anchors.verticalCenter: parent.verticalCenter
      x: parent.width * 0.04
      width: parent.width * 0.92
      height: 3
      color: "#eafcff"
      visible: screen.svc ? screen.svc.dying : false
      transform: Scale {
        id: lineScale
        origin.x: powerLine.width / 2
        origin.y: 1.5
        xScale: 1
      }
      SequentialAnimation {
        id: lineAnim
        running: powerLine.visible
        PropertyAnimation { target: lineScale; property: "xScale"; from: 1; to: 0.12; duration: 230; easing.type: Easing.OutQuad }
        PropertyAnimation { target: lineScale; property: "xScale"; from: 0.12; to: 0; duration: 150; easing.type: Easing.InQuad }
      }
    }
  }

  Component.onCompleted: reqStatic()
}
