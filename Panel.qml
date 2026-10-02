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

  property string currentView: "daily"

  // Inspector state shared with whichever view is instantiated. Views
  // come and go via viewLoader, so selection lives here, not in them.
  property string selectedDateStr: ""
  property string inspectorTitle: "Today"
  property int inspectorTotal: 0
  property int inspectorDayTotal: 0
  property int inspectorUnattributed: 0
  property var inspectorApps: []

  readonly property string todayStr: {
    var d = new Date()
    var mo = d.getMonth() + 1
    var dy = d.getDate()
    return d.getFullYear() + "-" + (mo < 10 ? "0" + mo : "" + mo) + "-" + (dy < 10 ? "0" + dy : "" + dy)
  }

  function runSettings(args) {
    var cmd = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", "")]
    settingsProcess.command = cmd.concat(args)
    if (settingsProcess.running) settingsProcess.running = false
    settingsProcess.running = true
  }

  function syncAppList() {
    if (root.selectedDateStr === "" || root.selectedDateStr === root.todayStr) {
      var t = root.appsToday
      root.selectedDateStr = root.todayStr
      root.inspectorTitle = "Today"
      root.inspectorTotal = t.total || 0
      root.inspectorDayTotal = t.day_total || 0
      root.inspectorUnattributed = t.unattributed || 0
      root.inspectorApps = t.apps || []
    }
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Panel breathing room. These margins sit inside the card, so the card
  // must also be grown by them — fittedContentHeight only accounts for
  // the card's own fixed padding, not ours.
  readonly property real contentPad: Style.space(16)

  function open() {
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
    root.syncAppList()
    if (viewLoader.item && typeof viewLoader.item.refresh === "function") viewLoader.item.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(content.implicitHeight + root.contentPad * 2)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: contentScroll
        anchors.fill: parent
        anchors.margins: root.contentPad
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: contentScroll.width
          spacing: Style.space(12)

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
            tooltipText: "Always counts all screen-on time. Active pauses while idle. Per-app stats only count focused use."
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

          BorderSurface {
            width: parent.width
            implicitHeight: sectionsBox.implicitHeight + 24
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: sectionsBox
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: Style.space(8)

              Text {
                text: "SECTIONS"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Qt.darker(root.contentForeground, 1.2)
              }

              Row {
                spacing: Style.space(16)

              Row {
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "WEEKLY"
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
                  text: "APPS"
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
                  text: "ICONS"
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
          }

          BorderSurface {
            width: parent.width
            implicitHeight: identBox.implicitHeight + 24
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: identBox
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: Style.space(8)

              Row {
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "APP IDENTIFICATION"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
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
          }

          BorderSurface {
            width: parent.width
            implicitHeight: historyBox.implicitHeight + 24
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

            Column {
              id: historyBox
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: Style.space(8)

              Row {
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "KEEP HISTORY (" + root.retentionDays + " DAYS)"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
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

        ButtonGroup {
          id: viewSwitch
          visible: root.showWeekly || (root.showApps && root.appMode !== "off")
          options: {
            var opts = [{ value: "daily", label: "DAILY", tooltip: "Today's screen time" }]
            if (root.showWeekly)
              opts.push({ value: "weekly", label: "WEEKLY", tooltip: "7-day breakdown" })
            if (root.showApps && root.appMode !== "off")
              opts.push({ value: "apps", label: "APPS", tooltip: "Per-app usage" })
            return opts
          }
          value: root.currentView
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.body
          focusable: false
          onChanged: function(v) { root.currentView = v }
        }

        Loader {
          id: viewLoader
          width: parent.width
          sourceComponent: root.currentView === "weekly" && root.showWeekly ? weeklyComp : (root.currentView === "apps" && root.showApps && root.appMode !== "off") ? appsComp : dailyComp
        }

        Component {
          id: dailyComp

          DailyCard {
            totalText: hostWidget ? hostWidget.displayText : "0m"
            todayData: root.todayData
            maxMinutes: root.maxMinutes
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }
        }

        Component {
          id: weeklyComp

          WeekChart {
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            selectedDate: root.selectedDateStr
            onDaySelected: function(dateStr, dayData) {
              root.selectedDateStr = dateStr
              root.inspectorTitle = (dayData.label || "") + " " + (dateStr || "")
              root.inspectorTotal = dayData.total || 0
              root.inspectorDayTotal = dayData.day_total || 0
              root.inspectorUnattributed = dayData.unattributed || 0
              root.inspectorApps = dayData.apps || []
            }
          }
        }

        Component {
          id: appsComp

          AppList {
            title: root.inspectorTitle
            totalSeconds: root.inspectorTotal
            dayTotalSeconds: root.inspectorDayTotal
            unattributedSeconds: root.inspectorUnattributed
            apps: root.inspectorApps
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            showIcons: root.showAppIcons
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
                var m = data.app_mode || "class"
                if (root.currentView === "apps" && (data.show_apps === false || m === "off")) root.currentView = "daily"
                if (root.currentView === "weekly" && data.show_weekly === false) root.currentView = "daily"
              } catch(e) {}
            }
          }
        }
        }
      }
    }
  }
}
