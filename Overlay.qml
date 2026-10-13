// Overlay.qml — pełnoekranowy panel ustawień kineskopu.
// Przywołanie: omarchy-shell -q shell toggle crt.kineskop
// (np. keybind w Hyprland) albo LPM w widget na barze.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  readonly property string pluginId: (manifest && manifest.id) || "crt.kineskop"

  function open(payloadJson) {
    root.opened = true;
    Qt.callLater(function() { keyScope.forceActiveFocus(); });
  }

  function close() {
    root.opened = false;
  }

  function dismiss() {
    root.opened = false;
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId);
  }

  function toggle() {
    if (root.opened) root.dismiss();
    else root.open("{}");
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "crt-kineskop-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int cardWidth: Math.min(440, panel.width - Style.gapsOut * 2)
    readonly property int cardMaxHeight: panel.height - Style.gapsOut * 2

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: panel.cardWidth
      height: Math.min(flick.contentHeight + contentTopInset + contentBottomInset,
        panel.cardMaxHeight)
      anchors.centerIn: parent
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyScope
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; }
        }

        Flickable {
          id: flick
          anchors.fill: parent
          clip: true
          contentWidth: width
          contentHeight: settingsForm.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          CrtSettingsForm {
            id: settingsForm
            width: flick.width
          }
        }
      }
    }
  }
}
