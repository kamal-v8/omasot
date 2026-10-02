import QtQuick
import qs.Commons
import qs.Ui

// DailyCard — pure presentational "today" overview: big total, 24-hour
// bar chart, and hour labels. Conventions copied exactly from Panel.qml.
Column {
  id: root
  width: parent.width
  spacing: Style.space(6)

  // ── In: data + theming from host panel ────────────────────────────
  property string totalText: "0m"
  property var todayData: ({})
  property int maxMinutes: 60
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  function formatMinutes(m) {
    if (!m) return "0m"
    var h = Math.floor(m / 60)
    return (h > 0 ? h + "h " : "") + (m % 60) + "m"
  }

  function minutesAt(index) {
    var hr = (index < 10 ? "0" : "") + index
    return root.todayData[hr] || 0
  }

  Text {
    text: root.totalText
    font.family: root.fontFamily
    font.pixelSize: 46
    font.bold: true
    color: root.foreground
  }

  Item {
    width: parent.width
    height: Style.space(72)

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
          property int minutes: root.minutesAt(index)

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, (minutes / root.maxMinutes) * parent.height)
            color: minutes > 0 ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
            radius: Style.cornerRadius > 0 ? width / 2 : 0
          }

          PanelToolTip {
            visible: mouse.containsMouse
            text: index + ":00 - " + minutes + " min"
            fontFamily: root.fontFamily
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
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
        height: Style.space(32)

        Column {
          anchors.centerIn: parent
          spacing: 0
          visible: index % 4 === 0

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: index
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Qt.darker(root.foreground, 1.4)
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.formatMinutes(root.minutesAt(index))
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Qt.darker(root.foreground, 1.5)
          }
        }
      }
    }
  }
}
