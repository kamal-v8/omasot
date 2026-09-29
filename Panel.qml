import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omasot"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var todayData: hostWidget ? (hostWidget.screentimeData.today_data || ({})) : ({})
  property int maxMinutes: Math.max(60, Object.values(todayData).reduce(function(a, b) { return Math.max(a, b) }, 0))

  property var weekData: hostWidget ? (hostWidget.screentimeData.week_data || []) : []
  property int weekTotal: hostWidget ? (hostWidget.screentimeData.week_total || 0) : 0
  // Weekly bars are measured against a full 24-hour day.
  property int weekMaxMinutes: 24 * 60
  property bool showWeekly: hostWidget ? hostWidget.screentimeData.show_weekly !== false : true
  property bool weeklyExpanded: false
  property bool settingsExpanded: false

  property bool showApps: hostWidget ? hostWidget.screentimeData.show_apps !== false : true
  property string appMode: hostWidget ? (hostWidget.screentimeData.app_mode || "class") : "class"
  property int retentionDays: hostWidget ? (hostWidget.screentimeData.retention_days || 365) : 365
  property var appsToday: hostWidget ? (hostWidget.screentimeData.apps_today || {}) : {}

  function runSettings(args) {
    var cmd = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", "")]
    settingsProcess.command = cmd.concat(args)
    if (settingsProcess.running) settingsProcess.running = false
    settingsProcess.running = true
  }

  function syncAppList() {
    if (weekChart.selectedDate === "" || weekChart.selectedDate === weekChart.todayStr) {
      var t = root.appsToday
      weekChart.selectedDate = weekChart.todayStr
      appList.title = "Today"
      appList.totalSeconds = t.total || 0
      appList.apps = t.apps || []
    }
  }

  function formatMinutes(m) {
    if (!m) return "0m"
    var h = Math.floor(m / 60)
    return (h > 0 ? h + "h " : "") + (m % 60) + "m"
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
    weekChart.refresh()
    root.syncAppList()
    root.controller.show()
  }
  
  function close() {
    root.controller.hide()
  }

  Connections {
    target: root.hostWidget
    function onScreentimeDataChanged() { root.syncAppList() }
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: contentScroll
        anchors.fill: parent
        anchors.margins: Style.space(24)
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: contentScroll.width
          spacing: Style.space(16)

        Item {
          width: parent.width
          height: Math.max(titleText.height, modeRow.height, settingsButton.height)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Screen Time Today"
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            color: Qt.darker(root.contentForeground, 1.2)
          }

          Row {
            id: modeRow
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (hostWidget && hostWidget.screentimeData.mode === "always") ? "Always" : "Active"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              color: Qt.darker(root.contentForeground, 1.2)
            }

            ToggleSwitch {
              id: modeSwitch
              anchors.verticalCenter: parent.verticalCenter
              checked: hostWidget ? hostWidget.screentimeData.mode === "always" : false
              busy: toggleProcess.running
              foreground: root.contentForeground
              onToggled: toggleProcess.running = true
            }

            PanelToolTip {
              visible: modeSwitch.containsMouse
              text: (hostWidget && hostWidget.screentimeData.mode === "always") ? "Tracking all screen-on time. Click to track active use only." : "Tracking active use only. Click to track all screen-on time."
              fontFamily: root.contentFontFamily
            }
          }

          Button {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒓"
            tooltipText: root.settingsExpanded ? "Hide settings" : "Show settings"
            foreground: Qt.darker(root.contentForeground, 1.2)
            fontFamily: root.contentFontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.labelGap
            onClicked: root.settingsExpanded = !root.settingsExpanded
          }

          Process {
            id: toggleProcess
            command: ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "toggle"]
            stdout: StdioCollector {
              waitForEnd: true
              onStreamFinished: {
                try {
                  var line = String(text || "").trim()
                  if (!line) return
                  var data = JSON.parse(line)
                  if (hostWidget) hostWidget.screentimeData = data
                } catch(e) {}
              }
            }
          }
        }

        Toggle {
          width: parent.width
          visible: root.settingsExpanded
          label: "Weekly stats"
          description: "Show the 7-day breakdown section in this panel."
          checked: root.showWeekly
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: weeklyProcess.running = true
        }

        Toggle {
          width: parent.width
          visible: root.settingsExpanded
          label: "App stats"
          description: "Show the per-app breakdown section in this panel."
          checked: root.showApps
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.runSettings(["toggle-apps-show"])
        }

        Text {
          visible: root.settingsExpanded
          width: parent.width
          text: "App identification"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.contentForeground, 1.2)
        }

        ButtonGroup {
          visible: root.settingsExpanded
          options: [
            { value: "off", label: "Off", tooltip: "Stop per-app tracking" },
            { value: "class", label: "Simple", tooltip: "Track window class only" },
            { value: "smart", label: "Smart", tooltip: "Resolve processes inside terminals" }
          ]
          value: root.appMode
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.caption
          focusable: false
          onChanged: function(v) { root.runSettings(["set-app-mode", v]) }
        }

        Text {
          visible: root.settingsExpanded
          width: parent.width
          text: "Keep history (" + root.retentionDays + " days)"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.contentForeground, 1.2)
        }

        ButtonGroup {
          visible: root.settingsExpanded
          options: [
            { value: "30", label: "30d", tooltip: "Keep 30 days" },
            { value: "90", label: "90d", tooltip: "Keep 90 days" },
            { value: "180", label: "6mo", tooltip: "Keep 6 months" },
            { value: "365", label: "12mo", tooltip: "Keep 12 months" }
          ]
          value: String(root.retentionDays)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.caption
          focusable: false
          onChanged: function(v) { root.runSettings(["set-retention-days", v]) }
        }

        Button {
          id: weeklyButton
          width: parent.width
          visible: root.showWeekly
          leftAlign: true
          bordered: true
          text: "This week · " + root.formatMinutes(root.weekTotal)
          iconText: "󰅀"
          iconRotation: root.weeklyExpanded ? 180 : 0
          tooltipText: root.weeklyExpanded ? "Hide the 7-day breakdown" : "Show the 7-day breakdown"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.body
          onClicked: root.weeklyExpanded = !root.weeklyExpanded
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.showWeekly && root.weeklyExpanded

          Repeater {
            model: root.weekData

            Item {
              required property var modelData
              width: parent.width
              height: Style.space(20)

              property int minutes: modelData.minutes || 0

              Text {
                id: dayLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                text: modelData.label || ""
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Qt.darker(root.contentForeground, 1.2)
              }

              Text {
                id: valueLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(64)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: root.formatMinutes(minutes)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: root.contentForeground
              }

              Item {
                anchors.left: dayLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.right: valueLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(12)

                Rectangle {
                  anchors.fill: parent
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                  radius: height / 2
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(parent.width, Math.max(0, (minutes / root.weekMaxMinutes) * parent.width))
                  height: parent.height
                  color: root.contentForeground
                  radius: height / 2
                  visible: minutes > 0
                }
              }

              PanelToolTip {
                visible: rowMouse.containsMouse
                text: modelData.label + " " + modelData.date + " - " + root.formatMinutes(minutes)
                fontFamily: root.contentFontFamily
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }
        }

        Text {
          text: hostWidget ? hostWidget.displayText : "0m"
          font.family: root.contentFontFamily
          font.pixelSize: 52
          font.bold: true
          color: root.contentForeground
        }

        Item {
          width: parent.width
          height: Style.space(80)

          Row {
            anchors.fill: parent
            spacing: Style.space(4)

            Repeater {
              model: 24
              Item {
                required property int index
                width: (parent.width - (23 * Style.space(4))) / 24
                height: parent.height

                property string hr: (index < 10 ? "0" : "") + index
                property int minutes: root.todayData[hr] || 0

                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(1, (minutes / root.maxMinutes) * parent.height)
                  color: minutes > 0 ? root.contentForeground : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                  radius: Style.cornerRadius > 0 ? width / 2 : 0
                }
                
                PanelToolTip {
                  visible: mouse.containsMouse
                  text: index + ":00 - " + minutes + " min"
                  fontFamily: root.contentFontFamily
                }
                
                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  hoverEnabled: true
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: 24
            Item {
              required property int index
              width: (parent.width - (23 * Style.space(4))) / 24
              height: Style.space(20)

              Text {
                anchors.centerIn: parent
                text: index % 4 === 0 ? index : ""
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.contentForeground, 1.5)
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.showApps && root.appMode !== "off"

          WeekChart {
            id: weekChart
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onDaySelected: function(dateStr, dayData) {
              appList.title = (dayData.label || "") + " " + (dateStr || "")
              appList.totalSeconds = dayData.total || 0
              appList.apps = dayData.apps || []
            }
          }

          AppList {
            id: appList
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }
        }

        Process {
          id: settingsProcess
          stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
              try {
                var line = String(text || "").trim()
                if (!line) return
                var data = JSON.parse(line)
                if (hostWidget) hostWidget.screentimeData = data
              } catch(e) {}
            }
          }
        }

        Process {
          id: weeklyProcess
          command: ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "toggle-weekly"]
          stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
              try {
                var line = String(text || "").trim()
                if (!line) return
                var data = JSON.parse(line)
                if (hostWidget) hostWidget.screentimeData = data
              } catch(e) {}
            }
          }
        }
        }
      }
    }
  }
}
