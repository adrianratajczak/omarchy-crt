// BarWidget.qml — przełącznik CRT na barze.
// L: panel ustawień (overlay) · P: zasilanie · Ś: degauss.
// Kropka = stan zasilania z config.json (FileView + watchChanges, zero pollingu).

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "crt.kineskop"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginId: "crt.kineskop"
  readonly property string cfgPath: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/crt-kineskop/config.json"

  property bool powered: true

  FileView {
    id: cfgView
    path: root.cfgPath
    watchChanges: true
    onLoaded: {
      try {
        var o = JSON.parse(text());
        if (o && o.enabled !== undefined) root.powered = !!o.enabled;
      } catch (e) {}
    }
    onFileChanged: cfgView.reload()
  }

  function svcIpc(args) {
    Quickshell.execDetached(["omarchy-shell", "-q", root.pluginId].concat(args));
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.powered ? "◉ CRT" : "○ CRT"
    active: root.powered
    tooltipText: "CRT Kineskop — Left: settings · Right: on/off · Middle: degauss / L: ustawienia · P: wl/wyl · S: degauss"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", root.pluginId]);
      } else if (buttonCode === Qt.RightButton) {
        root.svcIpc(["toggle"]);
      } else if (buttonCode === Qt.MiddleButton) {
        root.svcIpc(["degauss"]);
      }
    }
  }
}
