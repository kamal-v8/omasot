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

  // today_data holds SECONDS per hour, so the scale floor is one hour
  // in seconds (3600).
  property int maxSeconds: Math.max(3600, Object.values(todayData).reduce(function(a, b) { return Math.max(a, b) }, 0))

  property bool showWeekly: hostWidget ? hostWidget.screentimeData.show_weekly !== false : true
  property bool settingsExpanded: false

  property bool showApps: hostWidget ? hostWidget.screentimeData.show_apps !== false : true
  property bool showAppIcons: hostWidget ? hostWidget.screentimeData.show_app_icons !== false : true
  property string appMode: hostWidget ? (hostWidget.screentimeData.app_mode || "class") : "class"
  property int retentionDays: hostWidget ? (hostWidget.screentimeData.retention_days || 365) : 365
  property var appsToday: hostWidget ? (hostWidget.screentimeData.apps_today || {}) : {}

  // Screen time reminders (Android Digital Wellbeing style). On by default,
  // like Android. The floating overlay reads the same settings from the
  // tracker's JSON payload through `tracker.py reminder`.
  property bool remindersEnabled: hostWidget ? hostWidget.screentimeData.screen_time_reminders !== false : true
  property int reminderInterval: hostWidget ? (hostWidget.screentimeData.reminder_interval_minutes || 30) : 30

  property string currentView: "daily"

  // Inspector state shared with whichever view is instantiated. Views
  // come and go via viewLoader, so selection lives here, not in them.
  property string selectedDateStr: ""
  property string weekBasis: "focused"
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
  readonly property real contentPad: Style.space(12)

  // Daily gets the narrow width — the active-hour collapse (both ends)
  // keeps the bars filling it.
  readonly property int viewWidth: root.currentView === "daily" ? Style.space(400) : Style.space(440)

  function open() {
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
    root.syncAppList()
    if (viewLoader.item && typeof viewLoader.item.refresh === "function") viewLoader.item.refresh()
    root.controller.show()
    // A click on the bar widget can leave keyboard focus on the bar, which
    // would swallow Escape. Make sure the key catcher inside the panel owns
    // focus so Escape always reaches onCloseRequested.
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    // Without a focus target no item inside the layer-shell surface gets
    // active focus, so PanelKeyCatcher never sees Escape and the panel
    // cannot be closed with the keyboard.
    focusTarget: keyCatcher
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(root.viewWidth)
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
          spacing: Style.space(8)

        Item {
          width: parent.width
          height: Math.max(titleText.height, modeRow.height, Math.max(settingsButton.height, modeHelp.height))

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Screen Time"
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
              text: (hostWidget && hostWidget.screentimeData.mode === "always") ? "Tracking all screen-on time, even with no window focused. Click to track focused use only." : "Tracking only while the screen is on, unlocked and a window is focused. Click to track all screen-on time."
              fontFamily: root.contentFontFamily
            }
          }

          PanelActionButton {
            id: modeHelp
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "?"
            tooltipText: "Always counts all screen-on time. Active counts only while a window is focused. Per-app stats follow the focused window."
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

        // All settings in one compact box instead of a tall stack of cards.
        BorderSurface {
          width: parent.width
          visible: root.settingsExpanded
          implicitHeight: compactSettings.implicitHeight + Style.space(18)
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
          radius: Style.cornerRadius
          borderSpec: Border.flat(Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10), 1)

          Column {
            id: compactSettings
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(9)
            spacing: Style.space(6)

            // One label column for every row so "REMIND AFTER" is never
            // clipped and the option groups line up vertically.
            readonly property int labelWidth: Style.space(80)

            // Row 1 — the four on/off switches, inline.
            Item {
              width: parent.width
              height: Style.space(60)

              Grid {
                id: toggles
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                columns: 2
                rowSpacing: Style.space(5)
                columnSpacing: Style.space(18)

                Row {
                  spacing: Style.space(3)
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
                  spacing: Style.space(3)
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
                  spacing: Style.space(3)
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

                Row {
                  spacing: Style.space(3)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "REMIND"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.contentForeground, 1.2)
                  }
                  ToggleSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.remindersEnabled
                    foreground: root.contentForeground
                    busy: settingsProcess.running
                    onToggled: root.runSettings(["toggle-reminders"])
                  }
                }
              }
            }

            // Row 2 — reminder interval.
            Item {
              width: parent.width
              height: Style.space(28)
              visible: root.remindersEnabled

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  width: compactSettings.labelWidth
                  anchors.verticalCenter: parent.verticalCenter
                  text: "REMIND AFTER"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.5)
                }

                ButtonGroup {
                  options: [
                    { value: "5", label: "5m", tooltip: "Remind after 5 minutes in the same app" },
                    { value: "10", label: "10m", tooltip: "Remind after 10 minutes in the same app" },
                    { value: "20", label: "20m", tooltip: "Remind after 20 minutes in the same app" },
                    { value: "30", label: "30m", tooltip: "Remind after 30 minutes in the same app" }
                  ]
                  value: String(root.reminderInterval)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  focusable: false
                  onChanged: function(v) { root.runSettings(["set-reminder-interval", v]) }
                }

                PanelActionButton {
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "?"
                  tooltipText: "A small pill shows how long you've used the focused app. Requires app identification to be Simple or Smart."
                  foreground: Qt.darker(root.contentForeground, 1.2)
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                }
              }
            }

            // Row 3 — app identification.
            Item {
              width: parent.width
              height: Style.space(28)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  width: compactSettings.labelWidth
                  anchors.verticalCenter: parent.verticalCenter
                  text: "APP ID"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.5)
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

                PanelActionButton {
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "?"
                  tooltipText: "Simple groups by window class like zen or foot. Smart resolves the program running inside terminals, e.g. opencode instead of foot."
                  foreground: Qt.darker(root.contentForeground, 1.2)
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                }
              }
            }

            // Row 4 — history retention.
            Item {
              width: parent.width
              height: Style.space(28)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  width: compactSettings.labelWidth
                  anchors.verticalCenter: parent.verticalCenter
                  text: "HISTORY"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.5)
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

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.retentionDays + "d"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.contentForeground, 1.5)
                }
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
            maxSeconds: root.maxSeconds
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
            basis: root.weekBasis
            onBasisChanged: root.weekBasis = basis
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
