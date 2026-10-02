import QtQuick
import qs.Commons
import qs.Ui

// DailyCard — pure presentational "today" overview: big total, 24-hour
// bar chart with a right-hand value axis, and hour ticks underneath.
// Conventions copied exactly from Panel.qml.
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

  // ── Geometry ──────────────────────────────────────────────────────
  readonly property real chartH: Style.space(76)
  readonly property real axisW: Style.space(46)
  readonly property real gap: Style.space(4)
  readonly property real barsW: Math.max(1, width - axisW)

  // Hours before the first active hour collapse into one narrow block so
  // the hours you actually use get the width. No data at all → no chart.
  readonly property int firstActive: {
    for (var h = 0; h < 24; ++h) {
      if (root.minutesAt(h) > 0) return h
    }
    return 23
  }
  readonly property int lastActive: {
    for (var h = 23; h >= 0; --h) {
      if (root.minutesAt(h) > 0) return h
    }
    return 0
  }
  readonly property bool hasData: {
    for (var h = 0; h < 24; ++h) {
      if (root.minutesAt(h) > 0) return true
    }
    return false
  }
  readonly property bool hasCollapsed: firstActive > 0
  readonly property int activeCount: Math.max(1, lastActive - firstActive + 1)
  readonly property real collapsedW: hasCollapsed ? Math.max(Style.space(26), barsW * 0.08) : 0
  readonly property real slotW: Math.max(1, (barsW - collapsedW - (activeCount - 1) * gap) / activeCount)

  function minutesAt(index) {
    var hr = (index < 10 ? "0" : "") + index
    return root.todayData[hr] || 0
  }

  // Compact axis value: "0", "15m", "30m", "45m", "1h".
  function axisValue(minutes) {
    if (minutes <= 0) return "0"
    if (minutes >= 60) return Math.round(minutes / 60) + "h"
    return Math.round(minutes) + "m"
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
    height: root.hasData ? root.chartH + Style.space(18) : Style.space(24)

    // ── Empty state ──────────────────────────────────────────────
    Text {
      visible: !root.hasData
      anchors.verticalCenter: parent.verticalCenter
      text: "No usage recorded today"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(root.foreground, 1.5)
    }

    // ── Gridlines + right-hand value axis ─────────────────────────
    Repeater {
      model: 5
      Item {
        required property int index
        visible: root.hasData
        width: parent.width
        height: 1
        y: root.chartH - (root.chartH * (index / 4))

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, index === 0 ? 0.22 : 0.10)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: root.barsW + Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: root.axisValue(root.maxMinutes * (index / 4))
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
        }
      }
    }

    // ── Bars + hour ticks ────────────────────────────────────────
    Row {
      id: bars
      visible: root.hasData
      x: 0
      y: 0
      spacing: root.gap

      // Collapsed leading hours (usually the small hours nobody uses).
      Item {
        visible: root.hasCollapsed
        width: root.collapsedW
        height: root.chartH + Style.space(18)

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(18)
          width: parent.width
          height: 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height - Style.space(14)
          text: "0–" + (root.firstActive - 1)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.6)
        }

        PanelToolTip {
          visible: collapsedMouse.containsMouse
          text: "Hours 0 to " + (root.firstActive - 1) + " unused"
          fontFamily: root.fontFamily
        }

        MouseArea {
          id: collapsedMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }

      Repeater {
        model: root.hasData ? root.activeCount : 1

        Item {
          required property int index
          width: root.slotW
          height: root.chartH + Style.space(18)

          readonly property int hour: root.firstActive + index
          property int minutes: root.minutesAt(root.firstActive + index)

          Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(18)
            width: parent.width
            height: Math.max(1, (minutes / Math.max(1, root.maxMinutes)) * root.chartH)
            color: minutes > 0 ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
            radius: Style.cornerRadius > 0 ? width / 2 : 0
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - Style.space(14)
            visible: hour % 3 === 0 || hour === root.lastActive
            text: hour
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: hour === root.lastActive
            color: Qt.darker(root.foreground, 1.5)
          }

          PanelToolTip {
            visible: hourMouse.containsMouse
            text: hour + ":00 — " + minutes + " min"
            fontFamily: root.fontFamily
          }

          MouseArea {
            id: hourMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
          }
        }
      }
    }
  }
}
