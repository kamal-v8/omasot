import QtQuick
import Quickshell
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
    contentHeight: panel.fittedContentHeight(Style.space(260))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(16)

        Text {
          text: "Screen Time Today"
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          color: Qt.darker(root.contentForeground, 1.2)
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
      }
    }
  }
}
