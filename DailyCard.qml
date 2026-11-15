import QtQuick
import qs.Commons
import qs.Ui

// DailyCard — pure presentational "today" overview: a compact summary
// row (total + peak hour), and a bar chart from the first used hour
// through now. Full clock-time ticks, no numeric axis — the accent
// peak bar anchors the scale. Unused leading hours collapse into one
// narrow block; hours after now collapse into a "later today" block.
// No data at all → empty state. Conventions copied from Panel.qml.
Column {
  id: root
  width: parent.width
  spacing: Style.space(6)

  // ── In: data + theming from host panel ────────────────────────────
  property string totalText: "0m"
  property var todayData: ({})
  property int maxSeconds: 3600
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // ── Geometry ──────────────────────────────────────────────────────
  // No axis column: the tall accent bar + the PEAK readout anchor the
  // scale, so the chart spans the full width.
  readonly property real chartH: Style.space(56)
  readonly property real gap: Style.space(4)
  readonly property real labelH: Style.space(18)
  readonly property real barsW: Math.max(1, width)

  // Hours before the first active hour collapse into one narrow block so
  // the hours you actually use get the width. Same at the tail end.
  readonly property int firstActive: {
    for (var h = 0; h < 24; ++h) {
      if (root.secondsAt(h) > 0) return h
    }
    return 23
  }
  readonly property int lastActive: {
    for (var h = 23; h >= 0; --h) {
      if (root.secondsAt(h) > 0) return h
    }
    return 0
  }
  readonly property bool hasData: {
    for (var h = 0; h < 24; ++h) {
      if (root.secondsAt(h) > 0) return true
    }
    return false
  }
  // Hours up to and including now are drawn (empty ones as faint
  // stubs — they really were empty); hours after now don't exist yet,
  // so they collapse into the "later today" block instead of pretending
  // to be unused.
  readonly property int nowHour: new Date().getHours()
  readonly property int shownEnd: Math.max(lastActive, nowHour)
  readonly property bool hasCollapsed: firstActive > 0
  readonly property bool hasTrailingCollapse: shownEnd < 23 && hasData
  readonly property int activeCount: Math.max(1, shownEnd - firstActive + 1)
  readonly property real collapsedW: hasCollapsed ? Math.max(Style.space(42), barsW * 0.09) : 0
  readonly property real trailingW: hasTrailingCollapse ? Math.max(Style.space(42), barsW * 0.09) : 0
  // The Row adds `gap` between every child — hour bars AND the two
  // collapse blocks — so the slot math has to account for those too.
  readonly property int gapCount: (activeCount - 1) + (hasCollapsed ? 1 : 0) + (hasTrailingCollapse ? 1 : 0)
  readonly property real slotW: Math.max(1, (barsW - collapsedW - trailingW - gapCount * gap) / activeCount)

  // Label every hour when it fits: full "HH:00" when slots are wide,
  // bare hour ("13") below that, and sparse ticks only on a full 24h day.
  readonly property bool labelFull: root.slotW >= 32
  readonly property bool labelAll: root.slotW >= 16

  function tickVisible(hour) {
    if (root.labelAll) return true
    return hour % (root.slotW >= 12 ? 3 : 6) === 0
  }

  function tickText(hour) {
    return root.labelFull ? root.hourLabel(hour) : String(hour)
  }

  // Busy hour of the day — gets accent paint and a "PEAK" readout.
  readonly property int peakHour: {
    var best = -1
    var bestSec = 0
    for (var h = 0; h < 24; ++h) {
      var s = root.secondsAt(h)
      if (s > bestSec) { bestSec = s; best = h }
    }
    return best
  }
  readonly property int peakSeconds: peakHour >= 0 ? root.secondsAt(peakHour) : 0

  // Horizontal position of "now" inside the bars area, or -1 when the
  // current hour precedes the first used hour. Evaluated when the panel
  // opens — the chart itself only refreshes then too.
  function markerX(date) {
    var nh = date.getHours()
    var frac = (date.getMinutes() + date.getSeconds() / 60) / 60
    if (nh < root.firstActive) return -1
    var acc = root.hasCollapsed ? root.collapsedW + root.gap : 0
    for (var h = root.firstActive; h <= root.shownEnd; ++h) {
      if (h === nh) return acc + frac * root.slotW
      acc += root.slotW + root.gap
    }
    return root.barsW
  }

  readonly property real nowX: root.markerX(new Date())
  readonly property string nowLabel: {
    var d = new Date()
    var hh = d.getHours()
    var mm = d.getMinutes()
    return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" + mm : mm)
  }

  // Hourly buckets are seconds of real screen time.
  function secondsAt(index) {
    var hr = (index < 10 ? "0" : "") + index
    return root.todayData[hr] || 0
  }

  // Compact duration from seconds: "45m", "2m", "1h", "1h 30m".
  // Minutes round to the nearest one — the tracker ticks in 5 second
  // steps, so flooring would drop the visible tail of a tick.
  function formatTime(sec) {
    var s = Math.floor(sec || 0)
    if (s <= 0) return "0m"
    var mins = Math.round(s / 60)
    var h = Math.floor(mins / 60)
    var mm = mins % 60
    if (h > 0) return mm > 0 ? h + "h " + mm + "m" : h + "h"
    return mm + "m"
  }

  function hourLabel(hour) {
    return (hour < 10 ? "0" : "") + hour + ":00"
  }

  // ── Summary: big total on the left, peak hour on the right ───────
  Item {
    width: parent.width
    height: Math.max(totalBlock.height, peakBlock.height)

    Column {
      id: totalBlock
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        text: "TODAY"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        color: Qt.darker(root.foreground, 1.5)
      }

      Text {
        text: root.totalText
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        color: root.foreground
      }
    }

    Column {
      id: peakBlock
      visible: root.hasData
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        anchors.right: parent.right
        text: "PEAK"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        color: Qt.darker(root.foreground, 1.5)
      }

      Text {
        anchors.right: parent.right
        text: root.peakHour >= 0 ? root.hourLabel(root.peakHour) + " · " + root.formatTime(root.peakSeconds) : ""
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        color: Color.accent
      }
    }
  }

  // ── Chart area ────────────────────────────────────────────────────
  Item {
    width: parent.width
    height: root.hasData ? root.chartH + root.labelH : Style.space(24)

    // ── Empty state ──────────────────────────────────────────────
    Text {
      visible: !root.hasData
      anchors.verticalCenter: parent.verticalCenter
      text: "No usage recorded today"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(root.foreground, 1.5)
    }

    // ── Baseline + mid gridline — no numeric axis, the accent peak
    // and PEAK readout carry the scale. ──────────────────────────
    Repeater {
      model: 2
      Item {
        required property int index
        visible: root.hasData
        width: parent.width
        height: 1
        y: index === 0 ? root.chartH : root.chartH / 2

        Rectangle {
          anchors.fill: parent
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, index === 0 ? 0.28 : 0.10)
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
        height: root.chartH + root.labelH

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.labelH
          width: parent.width
          height: 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(2)
          y: parent.height - root.labelH + Style.space(3)
          text: "<" + root.hourLabel(root.firstActive)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
        }

        PanelToolTip {
          visible: collapsedMouse.containsMouse
          text: "Nothing used before " + root.hourLabel(root.firstActive)
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
          height: root.chartH + root.labelH

          readonly property int hour: root.firstActive + index
          property int seconds: root.secondsAt(root.firstActive + index)
          readonly property bool isPeak: hour === root.peakHour && seconds > 0

          Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.labelH
            width: parent.width
            height: Math.max(1, (seconds / Math.max(1, root.maxSeconds)) * root.chartH)
            color: isPeak ? Color.accent : (seconds > 0 ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))
            radius: Style.cornerRadius > 0 ? width / 2 : 0
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - root.labelH + Style.space(3)
            visible: root.tickVisible(hour)
            text: root.tickText(hour)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: isPeak || hour === root.shownEnd
            color: isPeak ? Color.accent : Qt.darker(root.foreground, 1.5)
          }

          PanelToolTip {
            visible: hourMouse.containsMouse
            text: root.hourLabel(hour) + " · " + root.formatTime(seconds)
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

      // Collapsed trailing hours (the rest of the night).
      Item {
        visible: root.hasTrailingCollapse
        width: root.trailingW
        height: root.chartH + root.labelH

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.labelH
          width: parent.width
          height: 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(2)
          y: parent.height - root.labelH + Style.space(3)
          text: ">" + root.hourLabel(root.shownEnd)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
        }

        PanelToolTip {
          visible: trailingMouse.containsMouse
          text: "Hours " + (root.shownEnd + 1) + " to 23 — later today"
          fontFamily: root.fontFamily
        }

        MouseArea {
          id: trailingMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }
    }

    // ── "Now" marker: hairline + dot showing how far through the day
    // the bars run. Drawn over the bars. ───────────────────────────
    Item {
      visible: root.hasData && root.nowX >= 0
      x: Math.max(0, Math.min(parent.width - width, root.nowX - width / 2))
      y: 0
      width: Style.space(9)
      height: root.chartH

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 1
        height: parent.height
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height / 2
        width: Style.space(6)
        height: Style.space(6)
        radius: width / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.8)
      }

      PanelToolTip {
        visible: nowMouse.containsMouse
        text: "Now — " + root.nowLabel
        fontFamily: root.fontFamily
      }

      MouseArea {
        id: nowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
      }
    }
  }
}
