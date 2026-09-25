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
  // Pinned rows come first; `index` on each row still points at its real
  // position in `history`, which is what --history-index (paste, remove,
  // toggle-pin) needs, so only the display order changes here. Ordering is
  // done inside displayRows — never with Array.sort, which isn't stable in
  // the QML JS engine.
  readonly property var displayRows: ClipboardHistory.displayRows(root.history, root.filterText, 50)
  // "Clear history" only ever touches unpinned entries, so it has
  // nothing to do once everything left is pinned.
  readonly property bool hasClearableHistory: root.history.some(function(e) { return !e.pinned })

  property bool clearConfirmOpen: false
  // Preview is gated behind a size/dimension check before it ever reaches
  // Image: an "image" entry is whatever the system clipboard held (any app
  // can write to it, e.g. a web page's "copy image"), and a "file" entry's
  // previewImage is any local path a copied file:// line happens to end in
  // an image extension with — neither is validated at capture time beyond
  // capture.sh's byte cap, and Image has no built-in limit on decoded
  // pixel count. A small file claiming extreme dimensions would otherwise
  // make the shell allocate far more memory than a thumbnail needs, or
  // crash outright, the moment someone clicks the eye button.
  property string previewPath: ""
  property string _previewPendingPath: ""
  property int _previewGeneration: 0
  property int _previewPendingGeneration: 0
  readonly property int previewMaxBytes: 20 * 1024 * 1024
  readonly property int previewMaxDimension: 8192

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
  }

  function saveHistory() {
    // No slice to historyLimit here: addEntry already enforces the cap, and
    // it deliberately lets pinned entries exceed it. Slicing again would
    // cut the array's tail — exactly where old pins sit.
    historyFile.setText(JSON.stringify(root.history, null, 2) + "\n")
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

  function togglePin(row) {
    root.history = ClipboardHistory.togglePinned(root.history, row.index)
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

  readonly property string _previewCheckScript: [
    "p=\"$1\"",
    "size=$(stat -c%s -- \"$p\" 2>/dev/null) || exit 1",
    "[ \"$size\" -le \"$2\" ] || exit 1",
    "dims=$(timeout 5 identify -limit area 64MB -limit memory 64MB -limit map 64MB -format '%w %h' -- \"${p}[0]\" 2>/dev/null) || exit 1",
    "w=${dims%% *}",
    "h=${dims##* }",
    "case \"$w\" in ''|*[!0-9]*) exit 1;; esac",
    "case \"$h\" in ''|*[!0-9]*) exit 1;; esac",
    "[ \"$w\" -le \"$3\" ] && [ \"$h\" -le \"$3\" ]"
  ].join("\n")

  function _startPreviewCheck(path, generation) {
    previewCheckProcess.generation = generation
    previewCheckProcess.targetPath = path
    previewCheckProcess.command = ["bash", "-c", root._previewCheckScript, "_",
      path, String(root.previewMaxBytes), String(root.previewMaxDimension)]
    previewCheckProcess.running = true
  }

  function openPreview(path) {
    if (!path) return
    root._previewGeneration += 1
    var generation = root._previewGeneration
    // At most one check runs at a time, same reasoning as media's art
    // fetch: reassigning command/running on an already-running Process is
    // undefined here, so a second click while one is in flight replaces
    // the pending request instead of starting a second one.
    if (previewCheckProcess.running) {
      root._previewPendingPath = path
      root._previewPendingGeneration = generation
      return
    }
    root._startPreviewCheck(path, generation)
  }

  function closePreview() {
    // Bumping the generation means a check already in flight for the
    // preview being closed can't resurrect it once it lands.
    root._previewGeneration += 1
    root.previewPath = ""
    root._previewPendingPath = ""
  }

  function requestClearHistory() {
    if (!root.hasClearableHistory) return
    root.clearConfirmOpen = true
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory(root.history)
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

  Process {
    id: previewCheckProcess
    property string targetPath: ""
    property int generation: 0
    onExited: function(exitCode) {
      // Only publish a result that's still the one currently wanted — the
      // preview (or the whole popup) may have been closed, or a different
      // row clicked, while this check was in flight.
      if (exitCode === 0 && generation === root._previewGeneration) root.previewPath = targetPath

      var pending = root._previewPendingPath
      var pendingGeneration = root._previewPendingGeneration
      root._previewPendingPath = ""
      if (pending) root._startPreviewCheck(pending, pendingGeneration)
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
    // Grows past the list's own size while previewing an image, so there's
    // actually room to see what's in it instead of a postage stamp.
    contentWidth: panel.fittedContentWidth(root.previewPath !== "" ? Style.space(500) : Style.space(380))
    contentHeight: panel.fittedContentHeight(
      root.previewPath !== "" ? Style.space(500) : column.implicitHeight,
      root.previewPath !== "" ? Style.space(580) : Style.space(500))

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
            tooltipText: "Clear history (keeps pinned)"
            foreground: root.foreground
            hoverColor: root.urgent
            enabled: root.hasClearableHistory
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
          height: Math.min(contentHeight, Style.space(360))
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
        message: "Clear clipboard history? Pinned items are kept."
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
          anchors.fill: parent
          anchors.margins: Style.space(12)
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
    current: rowItem.entry.pinned

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
        textFormat: Text.PlainText
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
        size: Style.space(24)
        iconText: rowItem.entry.pinned ? "󰐃" : "󰤱"
        tooltipText: rowItem.entry.pinned ? "Unpin" : "Pin to top"
        foreground: rowItem.entry.pinned ? Color.accent : root.foreground
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.togglePin(rowItem.entry)
      }

      PanelActionButton {
        visible: rowItem.isImage
        size: Style.space(24)
        iconText: "󰛐"
        tooltipText: "Preview"
        foreground: root.foreground
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.openPreview(rowItem.entry.previewImage)
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
