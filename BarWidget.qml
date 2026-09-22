import QtQuick
import qs.Ui

// Bar icon that toggles the Clipboard.qml overlay (kind "overlay",
// module id vinicgobbi.clipboard). Follows the omarchy.menu pattern:
// the overlay is a separate top-level module, so the widget just
// forwards to the shell's generic toggle IPC rather than loading it
// directly — the shell owns opening/closing overlay modules.
BarWidget {
  id: root
  moduleName: "vinicgobbi.clipboard"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅍"
    tooltipText: "Clipboard"
    onPressed: function(b) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle vinicgobbi.clipboard")
    }
  }
}
