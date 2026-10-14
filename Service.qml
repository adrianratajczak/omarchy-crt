// Service.qml — crt.kineskop: kineskop na froncie pulpitu.
//
// Architektura: caly efekt liczy JEDEN fragment shader GPU na ekran
// (CrtScreen + crt.frag.qsb). QML nie rusza pikseli — serwis trzyma stan,
// persistencje, zasilanie i czas; uniformy aktualizuja sie same.
// Koszt CPU ~0 (poprzednie podejscie z Canvas 2D dusilo glowny watek).
//
// Ustawienia: ~/.local/state/omarchy/crt-kineskop/config.json (poza katalogiem
// wtyczki, zeby zapis nie przeladowywal wtyczki). Serwis jest jedynym pisarzem;
// widget i overlay czytaja ten sam plik (FileView + watchChanges) i pisza
// wylacznie przez IPC. Okna: przezroczyste PanelWindow na kazdym ekranie
// z pusta maska wejscia (= klikalnosc jak pointer-events:none w oryginale).

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

  // ---------------- stan zycia ----------------
  property real time: 0
  property real degaussBoost: 0
  property bool dying: false
  property real flashOp: 0
  property bool wobbling: false
  property string lastWritten: ""
  property int loadFails: 0

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
    for (var k in clean) root[k] = clean[k];
    if (patch.enabled !== undefined) {
      var want = !!patch.enabled;
      if (want && !root.powered) root.powerOn();
      else if (!want && root.powered) root.powerOff();
    }
    if (patch.motion !== undefined) root.motion = !!patch.motion;
  }

  function markCustom() {
    if (root.presetName !== "custom") root.presetName = "custom";
  }

  function setPreset(name) {
    if (!CrtPresets.PRESETS[name]) return "bad-preset";
    var p = CrtPresets.PRESETS[name];
    for (var k in p) root[k] = p[k];
    root.presetName = name;
    saveSoon();
    return "ok";
  }

  function resetAll() {
    var keepPower = root.powered, keepMotion = root.motion;
    setPreset("light");
    if (!keepPower && root.powered) root.powerOff();
    if (keepPower && !root.powered) root.powerOn();
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
    root.flashOp = 0.5; // rozblysk wlaczenia jak w demie (turn-on)
    flashFade.duration = 550;
    flashFade.restart();
  }

  function degauss() {
    if (!root.powered || root.dying) return "off";
    root.degaussBoost = 0.8; // dopalacz fosforu jak persistV += 0.8 w silniku
    root.wobbling = true;
    wobbleTimer.restart();
    degaussRestore.restart();
    root.flashOp = 0.7;
    flashFade.duration = 500;
    flashFade.restart();
    return "ok";
  }

  // ---------------- czas shadera (jedyna praca na klatke: jedna liczba) ----------------
  Timer {
    id: engine
    interval: 33
    repeat: true
    running: root.powered && root.motion && !root.dying
    onTriggered: root.time += 0.033
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

  Timer {
    id: degaussRestore
    interval: 600
    repeat: false
    onTriggered: root.degaussBoost = 0
  }

  // ---------------- persystencja ----------------
  FileView {
    id: cfgView
    path: root.configFile
    watchChanges: true
    onLoaded: {
      root.loadFails = 0;
      root.applyFile(text());
    }
    onLoadFailed: function(err) {
      // Brak pliku (pierwszy start) albo przejsciowy blad IO — sprobuj
      // jeszcze kilka razy zanim utworzysz defaulty (zapis defaultow
      // z enabled:true skasowalby swiadoma decyzje uzytkownika).
      if (root.loadFails++ < 5) loadRetry.restart();
      else root.writeDefaults();
    }
    onFileChanged: cfgView.reload()
    onSaveFailed: function(err) {
      console.warn("[crt] zapis ustawien nieudany: " + err);
      root.lastWritten = ""; // sprobuj ponownie przy nastepnym zapisie
    }
  }

  Timer {
    id: loadRetry
    interval: 500
    repeat: false
    onTriggered: cfgView.reload()
  }

  function writeDefaults() {
    var d = {
      enabled: true, motion: true, preset: "light"
    };
    for (var k in CrtPresets.DEFAULTS) {
      if (d[k] === undefined) d[k] = CrtPresets.DEFAULTS[k];
    }
    var json = JSON.stringify(d);
    root.lastWritten = json;
    root.applyPatch(d);
    root.presetName = "light";
    cfgView.setText(json);
  }

  function applyFile(text) {
    if (text === root.lastWritten || !text) return;
    var obj;
    try {
      obj = JSON.parse(text);
    } catch (e) {
      console.warn("[crt] uszkodzony config.json, ignoruje");
      return;
    }
    root.lastWritten = text;
    root.applyPatch(obj || {});
    if (obj.preset === "light" || obj.preset === "heavy" || obj.preset === "custom")
      root.presetName = obj.preset;
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

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
    onExited: function(code) {
      if (code === 0) cfgView.reload();
    }
  }

  // ---------------- IPC (m.in. dla widgetu, overlayu, bin/crt-kineskop) ----------------
  IpcHandler {
    target: root.pluginId
    function status(): string { return JSON.stringify(root.snapshot()); }
    function toggle(): string { return root.togglePower(); }
    function power(state: string): string {
      if (state === "on") root.powerOn();
      else if (state === "off") root.powerOff();
      else return root.togglePower();
      return root.powered ? "on" : "off";
    }
    function motion(state: string): string {
      root.motion = (state === "on");
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
      // Pusta maska = klikalnosc jak pointer-events:none w oryginale.
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
    mkdirProc.running = true;
    console.log("[crt] kineskop start");
  }
}
