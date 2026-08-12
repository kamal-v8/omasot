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

  property int totalMinutes: 0
  property var screentimeData: ({})
  property string displayText: (totalMinutes === 0) ? "0m" : ((Math.floor(totalMinutes / 60) > 0 ? Math.floor(totalMinutes / 60) + "h " : "") + (totalMinutes % 60) + "m")

  function refresh() {
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
          root.totalMinutes = data.total_minutes || 0
        } catch(e) {
          console.log("screentime error parsing: " + e)
        }
      }
    }
  }

  Timer {
    interval: 60000
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
    foreground: "#FFFFFF"
    text: "󰄉 " + root.displayText
    labelVisible: !root.vertical
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.refresh()
        root.togglePanel()
      }
    }
  }
}
