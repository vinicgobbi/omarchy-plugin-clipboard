import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// Clipboard history popup. Same shape as the other bar-icon popups
// (power, network, ...) rather than a full-screen overlay: recent text
// and image copies in a scrollable list, with copy/paste/delete actions
// and an eye button that previews an image entry inline instead of
// showing every image inline by default.
Panel {
  id: root
  moduleName: "vinicgobbi.clipboard"
  ipcTarget: "vinicgobbi.clipboard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string captureScript: Qt.resolvedUrl("capture.sh").toString().replace(/^file:\/\//, "")
  property int historyLimit: 300

  property var history: []
  property string filterText: ""
  readonly property var displayRows: ClipboardHistory.displayRows(root.history, root.filterText, 50)

  property bool clearConfirmOpen: false
  property string previewPath: ""

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry)
    if (!normalized) return
    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line))
  }

  function removeRow(row) {
    root.history = ClipboardHistory.removeEntryAt(root.history, row.index)
    root.saveHistory()
  }

  function pasteRow(row) {
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.index)])
    }
    root.close()
  }

  function copyRow(row) {
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.index)])
    }
    root.close()
  }

  function openPreview(path) {
    if (!path) return
    root.previewPath = path
  }

  function closePreview() {
    root.previewPath = ""
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    root.clearConfirmOpen = true
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    root.clearConfirmOpen = false
  }

  onOpenedChanged: if (!opened) { root.clearConfirmOpen = false; root.closePreview() }

  Component.onCompleted: initProc.running = true

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // Reap watchers left behind by a previous shell instance, then start our
  // own. The pdeathsig on the watchers makes the kernel kill them whenever
  // the shell exits, however it exits, so no further lifecycle management.
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/vinicgobbi\\.clipboard/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  // A watcher that dies takes clipboard history with it, silently: copying still
  // works, the picker still opens, and the old entries are all still there, so
  // nothing recorded until the next shell reload. Bring it back instead.
  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  implicitWidth: 1
  implicitHeight: 1

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus
      onCloseRequested: {
        if (root.clearConfirmOpen) root.clearConfirmOpen = false
        else if (root.previewPath !== "") root.closePreview()
        else root.close()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, clearButton.implicitHeight)

          Text {
            id: title
            text: "Clipboard"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelActionButton {
            id: clearButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰧧"
            tooltipText: "Clear history"
            foreground: root.foreground
            hoverColor: root.urgent
            enabled: root.history.length > 0
            onClicked: root.requestClearHistory()
          }
        }

        TextField {
          id: filterField
          width: parent.width
          placeholderText: "Filter…"
          foreground: root.foreground
          text: root.filterText
          onTextChanged: root.filterText = text
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Text {
          visible: root.displayRows.length === 0
          width: parent.width
          text: root.filterText ? "No matches" : "No clipboard history yet"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        ListView {
          id: historyList
          visible: root.displayRows.length > 0
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: root.displayRows

          delegate: HistoryRow {
            required property var modelData
            width: ListView.view.width
            entry: modelData
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        opened: root.clearConfirmOpen
        message: "Clear all clipboard history?"
        confirmText: "Clear"
        onCanceled: root.clearConfirmOpen = false
        onConfirmed: root.confirmClearHistory()
      }

      // Inline image preview instead of a second popup window — a
      // PopupCard anchored off a row deep inside this already-popped-up
      // panel fought the outside-click/focus-grab handling of the panel
      // itself and could get stuck open with nothing rendered. This is
      // just another full-size layer over the same content, same as
      // ConfirmDialog above.
      Item {
        id: previewOverlay
        anchors.fill: parent
        visible: root.previewPath !== ""

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.background, 0.85)
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.closePreview()
        }

        BorderSurface {
          id: previewCard
          width: Math.min(parent.width, parent.height) - Style.space(24)
          height: width
          anchors.centerIn: parent
          color: Color.popups.background
          borderSpec: Border.flat(root.foreground, Style.normalBorderWidth)
          radius: Style.cornerRadius
          padding: Style.space(10)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Image {
            anchors.fill: parent
            source: root.previewPath ? Util.fileUrl(root.previewPath) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
          }

          PanelActionButton {
            anchors.top: parent.top
            anchors.right: parent.right
            iconText: "󰅖"
            tooltipText: "Close"
            foreground: root.foreground
            onClicked: root.closePreview()
          }
        }
      }
    }
  }

  component HistoryRow: CursorSurface {
    id: rowItem
    required property var entry
    readonly property bool isImage: entry.entryType === "image" || (entry.entryType === "file" && entry.previewImage !== "")

    implicitHeight: Style.space(44)
    foreground: root.foreground
    bordered: true

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: actions.width + Style.space(6)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: rowItem.hasCursor = true
      onExited: rowItem.hasCursor = false
      onClicked: root.pasteRow(rowItem.entry)
    }

    Row {
      anchors.left: parent.left
      anchors.right: actions.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: rowItem.isImage ? "󰥶" : "󰅍"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        width: parent.width - Style.space(28)
        text: rowItem.entry.previewText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      PanelActionButton {
        id: eyeButton
        visible: rowItem.isImage
        size: Style.space(24)
        iconText: "󰛐"
        tooltipText: "Preview"
        foreground: root.foreground
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.openPreview(rowItem.entry.previewImage, eyeButton)
      }

      PanelActionButton {
        size: Style.space(24)
        iconText: "󰆏"
        tooltipText: "Copy"
        foreground: root.foreground
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.copyRow(rowItem.entry)
      }

      PanelActionButton {
        size: Style.space(24)
        iconText: "󰅖"
        tooltipText: "Delete"
        foreground: root.foreground
        hoverColor: root.urgent
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.removeRow(rowItem.entry)
      }
    }
  }
}
