// CrtSettingsForm.qml — formularz ustawień kineskopu (port popup.html/js).
// Używany przez Overlay (pełny ekran). Odczyt: config.json przez FileView
// z watchChanges. Zapis: wyłącznie IPC do serwisu (debounce 100 ms),
// serwis aplikuje na żywo i persistuje — jeden pisarz, zero wyścigów.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "CrtPresets.js" as CrtPresets

Column {
  id: form
  spacing: Style.spacing.rowGap

  readonly property string pluginId: "crt.kineskop"
  readonly property string cfgPath: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/crt-kineskop/config.json"

  property bool powered: true
  property bool motion: true
  property string presetName: "light"
  property var values: ({})

  function num(key, fb) {
    var v = Number(form.values[key]);
    return isFinite(v) ? v : fb;
  }

  FileView {
    id: cfgView
    path: form.cfgPath
    watchChanges: true
    onLoaded: {
      try {
        var o = JSON.parse(text() || "{}");
        if (o.enabled !== undefined) form.powered = !!o.enabled;
        if (o.motion !== undefined) form.motion = !!o.motion;
        if (o.preset !== undefined) form.presetName = String(o.preset);
        var v = {};
        for (var i = 0; i < CrtPresets.SETTING_DEFS.length; i++) {
          var k = CrtPresets.SETTING_DEFS[i].key;
          v[k] = o[k] !== undefined ? Number(o[k]) : CrtPresets.DEFAULTS[k];
        }
        form.values = v;
      } catch (e) {}
    }
    onFileChanged: cfgView.reload()
  }

  // Debounced, scalony zapis przez IPC (jak popup.js: debounce + custom).
  property var pendingPatch: ({})
  property bool patchQueued: false
  Timer {
    id: patchTimer
    interval: 100
    repeat: false
    onTriggered: {
      form.patchQueued = false;
      var keys = [];
      for (var k in form.pendingPatch) keys.push(k);
      if (!keys.length) return;
      var patch = {};
      for (var i = 0; i < keys.length; i++) patch[keys[i]] = form.pendingPatch[keys[i]];
      form.pendingPatch = {};
      Quickshell.execDetached(["omarchy-shell", "-q", form.pluginId, "configure", JSON.stringify(patch)]);
    }
  }

  function send(key, value) {
    var cur = Object.assign({}, form.values);
    cur[key] = value;
    form.values = cur;
    form.presetName = "custom";
    form.pendingPatch[key] = value;
    if (!form.patchQueued) {
      form.patchQueued = true;
      patchTimer.restart();
    } else {
      patchTimer.restart();
    }
  }

  function svcCall(args) {
    Quickshell.execDetached(["omarchy-shell", "-q", form.pluginId].concat(args));
  }

  // ---- nagłówek: status + power ----
  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Rectangle {
      width: 10; height: 10; radius: 5
      anchors.verticalCenter: parent.verticalCenter
      color: form.powered ? Commons.Color.accent : Commons.Color.urgent
    }
    Text {
      text: "CRT Kineskop"
      color: Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
    Item { width: 8; height: 1 }
    Rectangle {
      width: 64; height: 30; radius: Style.cornerRadius
      anchors.verticalCenter: parent.verticalCenter
      color: form.powered ? Commons.Color.accent : Commons.Color.menu.selectedBackground
      Text {
        anchors.centerIn: parent
        text: "⏻"
        font.pixelSize: Style.font.title
        color: form.powered ? Commons.Color.background : Commons.Color.menu.text
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: form.svcCall(["toggle"])
      }
    }
  }

  // ---- presety ----
  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Repeater {
      model: ["light", "heavy", "custom"]
      Rectangle {
        required property string modelData
        width: 84; height: 30; radius: Style.cornerRadius
        color: form.presetName === modelData
          ? Commons.Color.accent : Commons.Color.menu.selectedBackground
        Text {
          anchors.centerIn: parent
          text: modelData === "light" ? "Light" : (modelData === "heavy" ? "Heavy" : "Custom")
          font.pixelSize: Style.font.body
          font.family: Style.font.family
          color: form.presetName === modelData
            ? Commons.Color.background : Commons.Color.menu.text
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: modelData === "custom" ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: {
            if (modelData !== "custom") form.svcCall(["preset", modelData]);
          }
        }
      }
    }
  }

  // ---- ruch ----
  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Text {
      text: "Ruch (flicker / rolling / szum)"
      color: Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
    Rectangle {
      width: 46; height: 26; radius: 13
      anchors.verticalCenter: parent.verticalCenter
      color: form.motion ? Commons.Color.accent : Commons.Color.menu.selectedBackground
      Rectangle {
        width: 20; height: 20; radius: 10
        anchors.verticalCenter: parent.verticalCenter
        x: form.motion ? parent.width - width - 3 : 3
        color: Commons.Color.background
        Behavior on x { NumberAnimation { duration: 120 } }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: form.svcCall(["motion", form.motion ? "off" : "on"])
      }
    }
  }

  // ---- suwaki (grupy jak w popup.html) ----
  Repeater {
    model: ["Szkło", "Ruch", "Soczewka"]
    Column {
      required property string modelData
      width: form.width
      spacing: Style.spacing.labelGap
      Text {
        text: modelData
        color: Commons.Color.menu.text
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Repeater {
        model: CrtPresets.SETTING_DEFS.filter(function(d) { return d.group === modelData; })
        Row {
          required property var modelData
          width: form.width
          spacing: Style.spacing.controlGap
          Text {
            width: 118
            text: modelData.label
            color: Commons.Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
          }
          PanelSlider {
            width: parent.width - 118 - 52 - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            value: form.num(modelData.key, CrtPresets.DEFAULTS[modelData.key])
            minimum: modelData.min
            maximum: modelData.max
            step: modelData.step
            onMoved: function(v) { form.send(modelData.key, v); }
            onReleased: function(v) { form.send(modelData.key, v); }
          }
          Text {
            width: 52
            text: form.num(modelData.key, 0).toFixed(2)
            color: Commons.Color.menu.text
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  // ---- stopka: degauss + reset ----
  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Rectangle {
      width: 110; height: 32; radius: Style.cornerRadius
      color: Commons.Color.menu.selectedBackground
      Text {
        anchors.centerIn: parent
        text: "Degauss"
        color: Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: form.svcCall(["degauss"])
      }
    }
    Rectangle {
      width: 110; height: 32; radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: Commons.Color.menu.border
      Text {
        anchors.centerIn: parent
        text: "Reset"
        color: Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: form.svcCall(["reset"])
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Shortcut: omarchy-shell crt.kineskop toggle · bin/crt-kineskop for Hyprland keybinds. / Skrot: omarchy-shell crt.kineskop toggle · bin/crt-kineskop do keybindow Hyprland."
    color: Commons.Color.menu.text
    opacity: 0.55
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
