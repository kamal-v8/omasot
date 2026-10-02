import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// WeekChart — self-contained weekly overview (Mon–Sun) with a basis
// switch: FOCUSED (time attributed to an app) or OVERALL (total
// screen-on time, idle included).
// Data contract: `tracker.py apps-week <offset>` prints
// {"week_label": str, "days": [{"date", "label", "total": focused_sec,
// "day_total": screen_on_sec, "unattributed": sec, "apps": [...]} x7],
// "week_total": focused_sec, "week_share": float}. Offset 0 = current week.
Column {
  id: root
  width: parent.width
  spacing: Style.space(8)

  // ── In: theming from host panel ─────────────────────────────────
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // "focused" | "overall" — owned by the host panel so it survives view
  // switches (this component is recreated by a Loader each time).
  property string basis: "focused"

  // ── State ───────────────────────────────────────────────────────
  property int weekOffset: 0
  property string weekLabel: ""
  property var days: []
  property int weekTotal: 0
  property real weekShare: 0
  property string selectedDate: ""

  signal daySelected(string dateStr, var dayData)

  readonly property string todayStr: {
    var d = new Date()
    var mo = d.getMonth() + 1
    var dy = d.getDate()
    return d.getFullYear() + "-" + (mo < 10 ? "0" + mo : "" + mo) + "-" + (dy < 10 ? "0" + dy : "" + dy)
  }

  readonly property bool overall: basis === "overall"

  // Value for a day under the active basis.
  function dayValue(day) {
    if (!day) return 0
    return root.overall ? (day.day_total || 0) : (day.total || 0)
  }

  readonly property int basisTotal: {
    var t = 0
    if (root.days) {
      for (var i = 0; i < root.days.length; i++)
        t += root.dayValue(root.days[i])
    }
    return t
  }

  readonly property real basisShare: Math.round(1000 * root.basisTotal / (7 * 24 * 3600)) / 10

  // Bar denominator: the busiest day on the active basis, floor 1h.
  readonly property int maxDayTotal: {
    var m = 0
    if (root.days) {
      for (var i = 0; i < root.days.length; i++) {
        var t = root.dayValue(root.days[i])
        if (t > m) m = t
      }
    }
    return Math.max(3600, m)
  }

  readonly property real axisW: Style.space(44)
  readonly property real barsW: Math.max(1, width - root.axisW)

  function formatTime(sec) {
    var s = Math.floor(sec || 0)
    if (s <= 0)
      return "0m"
    var mins = Math.floor(s / 60)
    var h = Math.floor(mins / 60)
    var mm = mins % 60
    if (h > 0)
      return h + "h " + mm + "m"
    return mm + "m"
  }

  // Compact label for the narrow day columns: "11.8h", "45m", "0m".
  function dayHours(sec) {
    var s = Math.floor(sec || 0)
    if (s <= 0)
      return "0m"
    if (s < 3600)
      return Math.floor(s / 60) + "m"
    return (s / 3600).toFixed(1) + "h"
  }

  function refresh() {
    weekProcess.command = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "apps-week", String(root.weekOffset)]
    if (weekProcess.running)
      weekProcess.running = false
    weekProcess.running = true
  }

  onWeekOffsetChanged: root.refresh()
  Component.onCompleted: root.refresh()

  // ── Header: week navigation + title ───────────────────────────
  Item {
    id: header
    width: parent.width
    height: Math.max(prevButton.height, nextButton.height, titleText.height)

    PanelActionButton {
      id: prevButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      // U+F0141 chevron-left (same glyph as clock panel "Previous month").
      iconText: ""
      tooltipText: "Previous week"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.weekOffset--
    }

    PanelActionButton {
      id: nextButton
      anchors.left: prevButton.right
      anchors.verticalCenter: parent.verticalCenter
      // U+F0142 chevron-right (same glyph as clock panel "Next month").
      iconText: ""
      tooltipText: "Next week"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: root.weekOffset < 0
      onClicked: root.weekOffset++
    }

    Text {
      id: titleText
      anchors.left: nextButton.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.weekLabel.toUpperCase()
      textFormat: Text.PlainText
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      color: Qt.darker(root.foreground, 1.2)
    }
  }

  // ── Basis switch + summary ─────────────────────────────────────
  // Plain Item, not a Row: a Row would size itself from the spacer below,
  // which in turn measures the Row — a circular binding that collapsed
  // the whole strip.
  Item {
    width: parent.width
    height: Math.max(basisGroup.implicitHeight, summaryText.height, helpButton.height)

    ButtonGroup {
      id: basisGroup
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      options: [
        { value: "focused", label: "FOCUSED", tooltip: "Time attributed to a focused app" },
        { value: "overall", label: "OVERALL", tooltip: "All screen-on time, including idle" }
      ]
      value: root.basis
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      focusable: false
      onChanged: function(v) { root.basis = v }
    }

    Text {
      id: summaryText
      anchors.right: helpButton.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - basisGroup.width - helpButton.width - Style.space(24))
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: root.formatTime(root.basisTotal) + " · " + root.basisShare + "%"
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(root.foreground, 1.5)
    }

    PanelActionButton {
      id: helpButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "?"
      tooltipText: "Weekly totals, Monday to Sunday. Focused counts only time attributed to an app; overall adds idle, lock and empty-desktop time. Click a bar to inspect that day."
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  // ── Bars with a right-hand value axis ─────────────────────────
  Item {
    id: bars
    width: parent.width
    height: Style.space(72)

    Repeater {
      model: 3
      Item {
        required property int index
        width: parent.width
        height: 1
        y: parent.height - parent.height * (index / 2)

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
          text: root.dayHours(root.maxDayTotal * (index / 2))
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
        }
      }
    }

    Row {
      id: barsRow
      width: root.barsW
      height: parent.height
      spacing: Style.space(4)

      Repeater {
        model: root.days

        Item {
          required property var modelData
          width: (parent.width - (6 * Style.space(4))) / 7
          height: parent.height

          property int value: root.dayValue(modelData)
          property string dayDate: modelData.date || ""
          property bool isSelected: root.selectedDate !== "" && root.selectedDate === dayDate

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, (value / root.maxDayTotal) * parent.height)
            color: isSelected ? Color.accent : (value > 0 ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))
            radius: Math.min(Style.space(4), width / 2)
          }

          PanelToolTip {
            visible: barMouse.containsMouse
            text: (modelData.label || "") + " " + dayDate + " — " + root.formatTime(modelData.total || 0) + " focused, " + root.formatTime(modelData.day_total || 0) + " total"
            fontFamily: root.fontFamily
          }

          MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            // LeftButton (not NoButton): this area is clickable — it emits
            // daySelected. Hover-only areas use Qt.NoButton per the Panel
            // pattern so panel scrolling still works.
            acceptedButtons: Qt.LeftButton
            onClicked: root.daySelected(dayDate, modelData)
          }
        }
      }
    }
  }

  // ── Day labels (today in bold) ──────────────────────────────────
  Row {
    width: root.barsW
    spacing: Style.space(4)

    Repeater {
      model: root.days

      Item {
        required property var modelData
        width: (parent.width - (6 * Style.space(4))) / 7
        height: Style.space(32)

        property bool isToday: (modelData.date || "") === root.todayStr && (modelData.date || "") !== ""

        Column {
          anchors.centerIn: parent
          spacing: 0

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (modelData.label || "").toUpperCase()
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: isToday
            color: Qt.darker(root.foreground, 1.5)
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dayHours(root.dayValue(modelData))
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: isToday
            color: Qt.darker(root.foreground, 1.5)
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }
    }
  }

  Process {
    id: weekProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var line = String(text || "").trim()
          if (!line)
            return
          var data = JSON.parse(line)
          root.weekLabel = data.week_label || ""
          root.days = data.days || []
          root.weekTotal = data.week_total || 0
          root.weekShare = data.week_share || 0
        } catch (e) {}
      }
    }
  }
}
