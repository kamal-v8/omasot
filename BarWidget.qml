import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omasot"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The tracker counts real elapsed seconds; the label shows whole
  // hours and minutes, so the conversion happens at display time.
  property int totalSeconds: 0
  property var screentimeData: ({})
  property string displayText: (totalSeconds === 0) ? "0m" : ((Math.floor(totalSeconds / 3600) > 0 ? Math.floor(totalSeconds / 3600) + "h " : "") + (Math.floor((totalSeconds % 3600) / 60)) + "m")

  // A left/right bar is one slot wide (Style.bar.sizeVertical), so the
  // horizontal `󰄉 3h 38m` label cannot fit. The rows below are what the
  // vertical bar paints instead: the screen-time glyph, then hours and
  // minutes on their own lines — one icon-slot tall per line, the way the
  // shell's clock stacks its vertical format. The minute line is dropped
  // when a whole number of hours already says it (`2h`), and the hour line
  // is absent below an hour (`38m`).
  readonly property var verticalRows: {
    var rows = [{ text: "󰄉", icon: true }]
    var hours = Math.floor(root.totalSeconds / 3600)
    var minutes = Math.floor((root.totalSeconds % 3600) / 60)
    if (hours > 0) rows.push({ text: hours + "h", icon: false })
    if (hours === 0 || minutes > 0) rows.push({ text: minutes + "m", icon: false })
    return rows
  }

  function refresh() {
    if (readProcess.running) readProcess.running = false
    readProcess.running = true
  }

  Process {
    id: readProcess
    command: ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var line = String(text || "").trim()
          if (!line) return
          var data = JSON.parse(line)
          root.screentimeData = data
          // `total_seconds` is canonical; the minutes field is only a
          // fallback for a backend that predates the seconds unit.
          root.totalSeconds = data.total_seconds || ((data.total_minutes || 0) * 60)
        } catch(e) {
          console.log("screentime error parsing: " + e)
        }
      }
    }
  }

  // The tracker counts in 5 second steps, so poll often enough for the
  // number to feel live.
  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Bar framework panel contract — required for proper open/close coordination
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Vertical bars paint their own glyph/hours/minutes stack below, so the
    // text label is horizontal-only. Keeping it empty while vertical is what
    // lets `labelVisible` hide the label without hiding the widget's only
    // content: the icon is part of the same string.
    text: root.vertical ? "" : "󰄉 " + root.displayText
    labelVisible: !root.vertical
    hasVisualContent: true
    fixedHeight: root.vertical ? root.verticalRows.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.refresh()
        root.togglePanel()
      }
    }

    Column {
      visible: root.vertical
      anchors.fill: parent
      spacing: 0

      Repeater {
        model: root.verticalRows

        delegate: Item {
          id: row
          required property var modelData

          readonly property bool isIcon: modelData.icon === true
          readonly property string lineText: String(modelData.text)
          // Room the line has to live in: the slot is narrow, so a line is
          // scaled down to fit rather than clipped at the bar edge.
          readonly property real availableWidth: Math.max(1, width - Style.space(3) * 2)
          readonly property real fittedFontSize: {
            if (isIcon || rowMetrics.tightBoundingRect.width <= 0) return Style.font.body
            return Math.max(1, Math.floor(Style.font.body
              * Math.min(1, availableWidth / rowMetrics.tightBoundingRect.width)))
          }

          width: button.width
          height: Style.bar.iconSlot

          TextMetrics {
            id: rowMetrics
            font.family: button.fontFamily
            font.pixelSize: Style.font.body
            text: row.isIcon ? "" : row.lineText
          }

          OpticalGlyph {
            anchors.fill: parent
            text: row.lineText
            fontFamily: button.fontFamily
            fontSize: row.fittedFontSize
            // The glyph fits the shared icon target like every other bar
            // icon; text keeps its native rendering and its own metrics.
            paintedSize: row.isIcon ? Style.bar.iconSize : 0
            color: button.foreground
          }
        }
      }
    }
  }
}
