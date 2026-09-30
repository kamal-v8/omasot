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

  property bool showWeekly: hostWidget ? hostWidget.screentimeData.show_weekly !== false : true
  property bool settingsExpanded: false

  property bool showApps: hostWidget ? hostWidget.screentimeData.show_apps !== false : true
  property bool showAppIcons: hostWidget ? hostWidget.screentimeData.show_app_icons !== false : true
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
    contentWidth: panel.fittedContentWidth(Style.space(950))
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
          height: Math.max(titleText.height, modeRow.height, Math.max(settingsButton.height, modeHelp.height))

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
            anchors.right: modeHelp.left
            anchors.rightMargin: Style.space(4)
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

          PanelActionButton {
            id: modeHelp
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "?"
            tooltipText: "Always counts all screen-on time. Active pauses while idle."
            foreground: Qt.darker(root.contentForeground, 1.2)
            fontFamily: root.contentFontFamily
            fontSize: Style.font.caption
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

        Column {
          width: parent.width
          visible: root.settingsExpanded
          spacing: Style.space(12)

          Column {
            width: parent.width
            spacing: Style.space(4)

            Row {
              spacing: Style.space(16)

              Row {
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Weekly"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.2)
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showWeekly
                  foreground: root.contentForeground
                  busy: settingsProcess.running
                  onToggled: root.runSettings(["toggle-weekly"])
                }
              }

              Row {
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Apps"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.2)
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showApps
                  foreground: root.contentForeground
                  busy: settingsProcess.running
                  onToggled: root.runSettings(["toggle-apps-show"])
                }
              }

              Row {
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Icons"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.2)
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: root.showAppIcons
                  foreground: root.contentForeground
                  busy: settingsProcess.running
                  onToggled: root.runSettings(["toggle-app-icons"])
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(16)

              Column {
                spacing: Style.space(4)

                Row {
                  spacing: Style.space(4)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "App identification"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.contentForeground, 1.2)
                  }

                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "?"
                    tooltipText: "Simple groups by window class like zen or foot. Smart resolves the program running inside terminals, e.g. opencode instead of foot."
                    foreground: Qt.darker(root.contentForeground, 1.2)
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                  }
                }

                ButtonGroup {
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
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Simple tracks window names. Smart also sees inside terminals."
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.5)
                }
              }

              Column {
                spacing: Style.space(4)

                Row {
                  spacing: Style.space(4)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Keep history (" + root.retentionDays + " days)"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.contentForeground, 1.2)
                  }

                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "?"
                    tooltipText: "How many days of per-day history are kept. Older days are pruned automatically."
                    foreground: Qt.darker(root.contentForeground, 1.2)
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                  }
                }

                ButtonGroup {
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
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)

          BorderSurface {
            width: (parent.width - 2 * Style.space(12)) / 3
            implicitHeight: appsCardCol.implicitHeight + 24
            visible: root.showApps && root.appMode !== "off"
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: appsCardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

              AppList {
                id: appList
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                showIcons: root.showAppIcons
              }
            }
          }

          BorderSurface {
            width: (parent.width - 2 * Style.space(12)) / 3
            implicitHeight: dailyCardCol.implicitHeight + 24
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: dailyCardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

              DailyCard {
                totalText: hostWidget ? hostWidget.displayText : "0m"
                todayData: root.todayData
                maxMinutes: root.maxMinutes
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }
            }
          }

          BorderSurface {
            width: (parent.width - 2 * Style.space(12)) / 3
            implicitHeight: weeklyCardCol.implicitHeight + 24
            visible: root.showWeekly
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: weeklyCardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

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
            }
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

        Item {
          width: parent.width
          height: Style.space(12)
        }
        }
      }
    }
  }
}
