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
  property int weekMaxMinutes: Math.max(60, weekData.reduce(function(a, d) { return Math.max(a, d.minutes || 0) }, 0))
  property bool showWeekly: hostWidget ? hostWidget.screentimeData.show_weekly !== false : true
  property bool weeklyExpanded: false
  property bool settingsExpanded: false

  function formatMinutes(m) {
    if (!m) return "0m"
    var h = Math.floor(m / 60)
    return (h > 0 ? h + "h " : "") + (m % 60) + "m"
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    if (hostWidget && typeof hostWidget.refresh === "function") hostWidget.refresh()
    root.controller.show()
  }
  
  function close() {
    root.controller.hide()
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

        Button {
          id: weeklyButton
          width: parent.width
          visible: root.showWeekly
          leftAlign: true
          text: "This week · " + root.formatMinutes(root.weekTotal)
          iconText: "󰅀"
          iconRotation: root.weeklyExpanded ? 180 : 0
          tooltipText: root.weeklyExpanded ? "Hide the 7-day breakdown" : "Show the 7-day breakdown"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.caption
          onClicked: root.weeklyExpanded = !root.weeklyExpanded
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.showWeekly && root.weeklyExpanded

          Item {
            width: parent.width
            height: Style.space(80)

            Row {
              anchors.fill: parent
              spacing: Style.space(4)

              Repeater {
                model: root.weekData
                Item {
                  required property var modelData
                  width: (parent.width - (6 * Style.space(4))) / 7
                  height: parent.height

                  property int minutes: modelData.minutes || 0

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(1, (minutes / root.weekMaxMinutes) * parent.height)
                    color: minutes > 0 ? root.contentForeground : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                    radius: Style.cornerRadius > 0 ? width / 2 : 0
                  }

                  PanelToolTip {
                    visible: dayMouse.containsMouse
                    text: modelData.label + " " + modelData.date + " - " + root.formatMinutes(minutes)
                    fontFamily: root.contentFontFamily
                  }

                  MouseArea {
                    id: dayMouse
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
              model: root.weekData
              Item {
                required property var modelData
                width: (parent.width - (6 * Style.space(4))) / 7
                height: Style.space(34)

                property int minutes: modelData.minutes || 0

                Column {
                  width: parent.width
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label || ""
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.contentForeground, 1.5)
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.formatMinutes(minutes)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    color: root.contentForeground
                  }
                }
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
