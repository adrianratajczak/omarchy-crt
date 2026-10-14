// CrtScreen.qml — obraz kineskopu na jednym ekranie: JEDEN quad GPU.
//
// Caly efekt (16 warstw w kolejnosci z css/crt-core.css) liczy fragment
// shader crt.frag.qsb na GPU. QML nie rusza pikseli — uniformy + czas.
// Stad zerowy koszt CPU (poprzednie podejscie z Canvas 2D dusilo glowny
// watek). Klikalnosc: okno ma pusta maske (ustawia Service).
//
// Kolejnosc uniformow w CrtScreen MUSI odpowiadac blokowi `buf` w crt.frag:
// resolution, time, scan, mask, vig, bulge, warmth, flick, roll, noise,
// chroma, glass, glow, persist, ca, smear, bloom, pitch, boost.

import QtQuick
import "CrtPresets.js" as CrtPresets

Item {
  id: screen
  property var svc: null

  readonly property real dpr: Screen.devicePixelRatio || 1
  readonly property real pitchPx: CrtPresets.scanlinePitchCss(height, screen.dpr)

  // Kontener calosci (degauss wobble — przyblizenie: rusza sie nakladka,
  // nie tresc pod spodem; tresc jest poza zasiegiem overlayu).
  Item {
    id: layers
    anchors.fill: parent
    transformOrigin: Item.Center

    SequentialAnimation {
      id: wobbleAnim
      running: screen.svc ? screen.svc.wobbling : false
      PropertyAnimation { target: layers; property: "x"; from: 0; to: 9; duration: 90; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: 9; to: -8; duration: 130; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: -8; to: 4; duration: 130; easing.type: Easing.InOutQuad }
      PropertyAnimation { target: layers; property: "x"; from: 4; to: 0; duration: 160; easing.type: Easing.OutQuad }
      PropertyAnimation { target: layers; property: "rotation"; from: 0; to: 0.35; duration: 140 }
      PropertyAnimation { target: layers; property: "rotation"; from: 0.35; to: -0.3; duration: 160 }
      PropertyAnimation { target: layers; property: "rotation"; to: 0; duration: 150 }
    }

    // ---- caly kineskop w jednym przejsciu GPU ----
    ShaderEffect {
      anchors.fill: parent
      property vector2d resolution: Qt.vector2d(width, height)
      property real time: screen.svc ? screen.svc.time : 0
      property real scan: screen.svc ? screen.svc.scan : 0
      property real mask: screen.svc ? screen.svc.mask : 0
      property real vig: screen.svc ? screen.svc.vig : 0
      property real bulge: screen.svc ? screen.svc.bulge : 0
      property real warmth: screen.svc ? screen.svc.warmth : 0
      property real flick: screen.svc ? screen.svc.flick : 0
      property real roll: screen.svc ? screen.svc.roll : 0
      property real noise: screen.svc ? screen.svc.noise : 0
      property real chroma: screen.svc ? screen.svc.chroma : 0
      property real glass: screen.svc ? screen.svc.glass : 0
      property real glow: screen.svc ? screen.svc.glow : 0
      property real persist: screen.svc ? screen.svc.persist : 0
      property real ca: screen.svc ? screen.svc.ca : 0
      property real smear: screen.svc ? screen.svc.smear : 0
      property real bloom: screen.svc ? screen.svc.bloom : 0
      property real pitch: screen.pitchPx
      property real boost: screen.svc ? screen.svc.degaussBoost : 0
      fragmentShader: "crt.frag.qsb"
    }

    // ---- flash (degauss / power) ----
    Rectangle {
      anchors.fill: parent
      color: "white"
      opacity: screen.svc ? screen.svc.flashOp : 0
    }

    // ---- power-off: czern + collapse do bialej linii (jak .is-off) ----
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
}
