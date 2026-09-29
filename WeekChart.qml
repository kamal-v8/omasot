import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// WeekChart — self-contained per-app weekly overview (Mon–Sun).
// Data contract: `tracker.py apps-week <offset>` prints
// {"week_label": str, "days": [{"date": "YYYY-MM-DD", "label": "Mon",
// "total": seconds, "apps": [{name, seconds}] up to 8} x7],
// "week_total": seconds, "week_share": float}. Offset 0 = current week.
Column {
  id: root
  width: parent.width
  spacing: Style.space(8)

  // ── In: theming from host panel ─────────────────────────────────
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // ── State ───────────────────────────────────────────────────────
  property int weekOffset: 0
  property string weekLabel: ""
  property var days: []
  property int weekTotal: 0
  property real weekShare: 0
  property string selectedDate: ""

  signal daySelected(string dateStr, var dayData)

  // YYYY-MM-DD for today, built manually from Date parts.
  readonly property string todayStr: {
    var d = new Date()
    var mo = d.getMonth() + 1
    var dy = d.getDate()
    var mStr = mo < 10 ? "0" + mo : "" + mo
    var dStr = dy < 10 ? "0" + dy : "" + dy
    return d.getFullYear() + "-" + mStr + "-" + dStr
  }

  // Bar denominator: never below 1h so an empty week stays flat and safe.
  readonly property int maxDayTotal: {
    var m = 0
    if (root.days) {
      for (var i = 0; i < root.days.length; i++) {
        var t = root.days[i].total || 0
        if (t > m)
          m = t
      }
    }
    return Math.max(3600, m)
  }

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

  function refresh() {
    weekProcess.command = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "apps-week", String(root.weekOffset)]
    if (weekProcess.running)
      weekProcess.running = false
    weekProcess.running = true
  }

  onWeekOffsetChanged: root.refresh()
  Component.onCompleted: root.refresh()

  // ── Header: week navigation + title + summary ───────────────────
  Item {
    id: header
    width: parent.width
    height: Math.max(prevButton.height, nextButton.height, titleText.height, summaryText.height)

    PanelActionButton {
      id: prevButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      // U+F0141 chevron-left (same glyph as clock panel "Previous month").
      iconText: "󰅁"
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
      iconText: "󰅂"
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
      anchors.right: summaryText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.weekLabel
      textFormat: Text.PlainText
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      color: Qt.darker(root.foreground, 1.2)
    }

    Text {
      id: summaryText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.formatTime(root.weekTotal) + " · " + root.weekShare + "%"
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: Qt.darker(root.foreground, 1.5)
    }
  }

  // ── Bars: one bottom-anchored column per day ────────────────────
  Item {
    id: bars
    width: parent.width
    height: Style.space(80)

    Row {
      anchors.fill: parent
      spacing: Style.space(4)

      Repeater {
        model: root.days

        Item {
          required property var modelData
          width: (parent.width - (6 * Style.space(4))) / 7
          height: parent.height

          property int total: modelData.total || 0
          property string dayDate: modelData.date || ""
          property bool isSelected: root.selectedDate !== "" && root.selectedDate === dayDate

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, (total / root.maxDayTotal) * parent.height)
            color: isSelected ? Color.accent : (total > 0 ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1))
            radius: Math.min(Style.space(4), width / 2)
          }

          PanelToolTip {
            visible: barMouse.containsMouse
            text: (modelData.label || "") + " " + dayDate + " - " + root.formatTime(total)
            fontFamily: root.fontFamily
          }

          MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            // LeftButton (not NoButton): this area is clickable — it sets
            // the selection and emits daySelected. Hover-only areas below
            // use Qt.NoButton per the Panel pattern.
            acceptedButtons: Qt.LeftButton
            onClicked: {
              root.selectedDate = dayDate
              root.daySelected(dayDate, modelData)
            }
          }
        }
      }
    }
  }

  // ── Day labels (today in bold) ──────────────────────────────────
  Row {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.days

      Item {
        required property var modelData
        width: (parent.width - (6 * Style.space(4))) / 7
        height: Style.space(20)

        property bool isToday: (modelData.date || "") === root.todayStr && (modelData.date || "") !== ""

        Text {
          anchors.centerIn: parent
          text: modelData.label || ""
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: isToday
          color: Qt.darker(root.foreground, 1.5)
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
