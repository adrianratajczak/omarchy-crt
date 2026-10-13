// Service.qml — crt.kineskop: silnik efektu kineskopu na froncie pulpitu.
//
// Port logiki extension/content.js + js/crt-engine.js + crt-overlay.js:
// jedna pętla FrameAnimation, w klatce ruszane TYLKO opacity i y warstw
// (rolling/trail) — scanlines/maska/winieta/krawędzie to statyczny Canvas
// malowany raz na zmianę ustawień. Szum: Canvas 192x108, max ~24 Hz.
// Pauza: okna są odmapowane przy zgaszonym zasilaniu (zero-cost, jak
// destroy() w oryginale); motion OFF chowa warstwy ruchome (jak .motion-off).
//
// Ustawienia: ~/.local/state/omarchy/crt-kineskop/config.json (poza katalogiem
// wtyczki, żeby zapis nie przeładowywał wtyczki — wzorowane na auto-workspace).
// Serwis jest jedynym pisarzem; widget i overlay czytają ten sam plik
// (FileView + watchChanges) i piszą wyłącznie przez IPC.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "CrtPresets.js" as CrtPresets

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "crt.kineskop"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string configDir: stateHome + "/omarchy/crt-kineskop"
  readonly property string configFile: configDir + "/config.json"

  // ---------------- ustawienia (lustro CrtPresets.DEFAULTS) ----------------
  property bool powered: true
  property bool motion: true
  property string presetName: "light"
  property real scan: 0.43
  property real mask: 0.35
  property real vig: 0.32
  property real bulge: 0.55
  property real warmth: 0.0
  property real sat: 1.06
  property real flick: 0.35
  property real roll: 0.5
  property real noise: 0.25
  property real chroma: 0.4
  property real glass: 0.1
  property real glow: 0.35
  property real persist: 0.3
  property real ca: 0.4
  property real smear: 0.3
  property real bloom: 0.3

  // ---------------- stan silnika (klatka) ----------------
  property real rollPos: -0.3
  property real persistV: 0
  property real slowWave: 0.5
  property real flickerOp: 0
  property real rollOp: 0.25
  property real trailOp: 0.1
  property real glowOp: 0.35
  property real bloomOp: 0.16
  property real persistOp: 0.05
  property real noiseOp: 0.09
  property real lastT: 0
  property int staticRevision: 0
  property bool dying: false
  property real flashOp: 0
  property bool wobbling: false
  property string lastWritten: ""

  function snapshot() {
    return {
      enabled: root.powered, motion: root.motion, preset: root.presetName,
      scan: root.scan, mask: root.mask, vig: root.vig, bulge: root.bulge,
      warmth: root.warmth, sat: root.sat, flick: root.flick, roll: root.roll,
      noise: root.noise, chroma: root.chroma, glass: root.glass,
      glow: root.glow, persist: root.persist,
      ca: root.ca, smear: root.smear, bloom: root.bloom
    };
  }

  function applyPatch(patch) {
    var clean = CrtPresets.sanitized(patch);
    var touchedStatic = false;
    for (var k in clean) {
      if (root[k] !== clean[k]) {
        root[k] = clean[k];
        touchedStatic = true;
      }
    }
    if (patch.enabled !== undefined) root.powered = !!patch.enabled;
    if (patch.motion !== undefined) root.motion = !!patch.motion;
    if (touchedStatic) bumpStaticSoon();
  }

  function markCustom() {
    if (root.presetName !== "custom") root.presetName = "custom";
  }

  function setPreset(name) {
    if (!CrtPresets.PRESETS[name]) return "bad-preset";
    var p = CrtPresets.PRESETS[name];
    for (var k in p) root[k] = p[k];
    root.presetName = name;
    bumpStaticSoon();
    saveSoon();
    return "ok";
  }

  function resetAll() {
    var keepPower = root.powered, keepMotion = root.motion;
    setPreset("light");
    root.powered = keepPower;
    root.motion = keepMotion;
    return "ok";
  }

  function togglePower() {
    if (root.powered) powerOff();
    else powerOn();
    return root.powered ? "on" : "off";
  }

  function powerOff() {
    if (!root.powered || root.dying) return;
    root.dying = true; // okna jeszcze zmapowane: czern + linia collapse
    dieTimer.restart();
  }

  function powerOn() {
    dieTimer.stop();
    root.dying = false;
    root.powered = true;
    saveSoon();
    root.persistV = Math.min(1.2, root.persistV + 0.5);
    root.flashOp = 0.5; // rozbłysk włączenia jak w demie (turn-on)
    flashFade.duration = 550;
    flashFade.restart();
  }

  function degauss() {
    if (!root.powered || root.dying) return "off";
    root.persistV = Math.min(1.2, root.persistV + 0.8); // poświata jak fosfor
    root.wobbling = true;
    wobbleTimer.restart();
    root.flashOp = 0.7;
    flashFade.duration = 500;
    flashFade.restart();
    return "ok";
  }

  // ---------------- pętla silnika (port loop() z crt-engine.js) ----------------
  function tick() {
    var now = Date.now();
    if (!root.lastT) root.lastT = now;
    var dtMs = Math.min(100, now - root.lastT);
    root.lastT = now;
    var dt = dtMs / 1000;
    var t = now / 1000;

    if (root.roll > 0.01) {
      root.rollPos += dt * 0.07 * (0.4 + root.roll);
      if (root.rollPos > 1.35) root.rollPos = -0.35;
    }
    root.rollOp = root.roll * 0.5;
    root.trailOp = root.persist * 0.35;

    var fast = Math.sin(t * 720.0) * 0.5 + Math.sin(t * 631.0 + 1.7) * 0.5;
    var slow = Math.sin(t * 7.3) * 0.5 + 0.5; // ta sama fala dla glow/bloom
    root.slowWave = slow;
    root.flickerOp = root.flick > 0.01
      ? Math.max(0, root.flick * (0.012 + 0.010 * fast + 0.014 * slow)) : 0;
    root.glowOp = root.glow * (0.75 + 0.25 * slow);

    root.persistV *= Math.pow(0.92, dtMs / 16.7);
    // Adaptacja na pulpit: brak sygnału prędkości scrolla, więc fosfor
    // minimalnie oddycha zamiast gasnąć do zera (degauss i tak go podbija).
    root.persistV = Math.max(root.persistV, 0.06 + 0.05 * slow);

    root.bloomOp = Math.max(0,
      root.bloom * (0.55 + 0.30 * slow + 0.4 * Math.min(1, root.persistV)));
    root.persistOp = Math.max(0,
      root.persist * (0.18 + Math.min(1, root.persistV) * 0.5));
    root.noiseOp = root.noise * 0.35;
  }

  FrameAnimation {
    id: engine
    running: root.powered && root.motion && !root.dying
    onTriggered: root.tick()
  }

  NumberAnimation {
    id: flashFade
    target: root
    property: "flashOp"
    to: 0
    duration: 500
    easing.type: Easing.OutCubic
  }

  Timer {
    id: dieTimer
    interval: 420
    repeat: false
    onTriggered: {
      root.powered = false; // odmapowanie okien = zero-cost off
      root.dying = false;
      root.saveSoon();
    }
  }

  Timer {
    id: wobbleTimer
    interval: 700
    repeat: false
    onTriggered: root.wobbling = false
  }

  // ---------------- persystencja ----------------
  FileView {
    id: cfgView
    path: root.configFile
    watchChanges: true
    onLoaded: root.applyFile(text())
    onLoadFailed: function(err) {
      // Brak pliku (pierwszy start) — zapisz defaulty.
      root.saveSoon();
    }
    onFileChanged: cfgView.reload()
    onSaveFailed: function(err) {
      console.warn("[crt] zapis ustawień nieudany: " + err);
    }
  }

  function applyFile(text) {
    if (text === root.lastWritten || !text) return;
    var obj;
    try {
      obj = JSON.parse(text);
    } catch (e) {
      console.warn("[crt] uszkodzony config.json, ignoruję");
      return;
    }
    root.lastWritten = text;
    var hadPower = root.powered;
    root.applyPatch(obj || {});
    if (obj.preset === "light" || obj.preset === "heavy" || obj.preset === "custom")
      root.presetName = obj.preset;
    // Zmiana zasilania z zewnątrz (np. ręczna edycja pliku).
    if (root.powered && !hadPower) root.powerOn();
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: root.saveNow()
  }

  function saveSoon() {
    saveTimer.restart();
  }

  function saveNow() {
    var json = JSON.stringify(root.snapshot());
    if (json === root.lastWritten) return;
    root.lastWritten = json;
    cfgView.setText(json);
  }

  Timer {
    id: staticTimer
    interval: 120
    repeat: false
    onTriggered: root.staticRevision++
  }

  function bumpStaticSoon() {
    staticTimer.restart();
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
  }

  // ---------------- IPC (m.in. dla widgetu, overlayu, bin/crt-kineskop) ----------------
  IpcHandler {
    target: root.pluginId
    function status(): string { return JSON.stringify(root.snapshot()); }
    function toggle(): string { return root.togglePower(); }
    function power(on: string): string {
      if (on === "on") root.powerOn();
      else if (on === "off") root.powerOff();
      else return root.togglePower();
      return root.powered ? "on" : "off";
    }
    function motion(on: string): string {
      root.motion = (on === "on");
      root.saveSoon();
      return root.motion ? "on" : "off";
    }
    function preset(name: string): string { return root.setPreset(name); }
    function configure(patchJson: string): string {
      var patch;
      try {
        patch = JSON.parse(patchJson || "{}");
      } catch (e) {
        return "bad-json";
      }
      root.applyPatch(patch || {});
      root.markCustom();
      root.saveSoon();
      return "ok";
    }
    function reset(): string { return root.resetAll(); }
    function degauss(): string { return root.degauss(); }
  }

  // ---------------- okna na wszystkich ekranach ----------------
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: crtWindow
      required property var modelData
      screen: modelData
      visible: root.powered
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      // Pusta maska = klikalność jak pointer-events:none w oryginale.
      mask: Region {}
      WlrLayershell.namespace: "crt-kineskop"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      CrtScreen {
        anchors.fill: parent
        svc: root
      }
    }
  }

  Component.onCompleted: {
    root.lastT = Date.now();
    mkdirProc.running = true;
    console.log("[crt] kineskop start");
  }
}
