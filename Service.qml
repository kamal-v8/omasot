import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root
  property var shell: null

  readonly property string trackerPath: Qt.resolvedUrl("tracker.py").toString().replace("file://", "")

  // ── Screen time reminders ────────────────────────────────────────
  // The ticker publishes a fresh reminder to a small state file when a
  // continuous-use interval is crossed. `tracker.py tick` already returns
  // the validated reminder in its JSON payload, so the pill is driven from
  // that single process — no second Python poll on the same 5s cadence.
  property bool reminderShown: false
  property string reminderApp: ""
  property int reminderSeconds: 0
  property int reminderInterval: 30
  property int lastReminderNonce: -1

  readonly property int reminderDisplayMs: 12000

  function formatTime(sec) {
    var s = Math.max(0, Math.floor(sec || 0))
    if (s <= 0) return "0m"
    var mins = Math.round(s / 60)
    var h = Math.floor(mins / 60)
    var mm = mins % 60
    if (h > 0) return mm > 0 ? h + "h " + mm + "m" : h + "h"
    return mm + "m"
  }

  function handleTick(data) {
    var reminder = data && data.reminder
    if (!reminder || typeof reminder !== "object") return
    var app = (typeof reminder.app === "string") ? reminder.app : ""
    var nonce = (typeof reminder.nonce === "number") ? reminder.nonce : -1
    // Ignore empty payloads, malformed data and reminders already shown.
    if (!app || nonce < 0 || nonce === root.lastReminderNonce) return
    root.lastReminderNonce = nonce
    root.reminderApp = app.slice(0, 200)
    root.reminderSeconds = Math.max(0, Math.floor(reminder.app_seconds || 0))
    root.reminderInterval = Math.max(1, Math.floor(reminder.interval_minutes || 30))
    root.reminderShown = true
    reminderHideTimer.restart()
  }

  function dismissReminder() {
    root.reminderShown = false
  }

  Process {
    id: tickProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        if (!line) return
        var data
        try {
          data = JSON.parse(line)
        } catch (e) {
          return
        }
        if (!data || typeof data !== "object") return
        root.handleTick(data)
      }
    }
  }

  // One accounting tick every 5 seconds. The tracker derives the elapsed
  // time from its own _last_tick stamp, so a skipped tick is credited on
  // the next one — nothing is lost, and there is nothing to fix here.
  Timer {
    id: tickTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: {
      if (tickProcess.running)
        return
      tickProcess.command = ["python3", root.trackerPath, "tick"]
      tickProcess.running = true
    }
  }

  Timer {
    id: reminderHideTimer
    interval: root.reminderDisplayMs
    onTriggered: root.reminderShown = false
  }

  Component.onCompleted: console.log("Screentime service started (presence-based ticker).")

  // Resolve the focused app's themed icon for the card (same lookup the
  // panel's app list uses). Falls back to the screen-time glyph below.
  readonly property string reminderIcon: root.reminderApp
    ? Quickshell.iconPath(root.reminderApp, true) : ""

  // App name shown in the pill; trimmed so a long window class cannot grow
  // the pill across the screen.
  readonly property string pillAppName: {
    var name = root.reminderApp || "this app"
    return name.length > 22 ? name.slice(0, 21) + "\u2026" : name
  }

  // Text colour that stays legible on the accent pill in every theme.
  readonly property color pillTextColor: {
    var c = Commons.Color.accent
    return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.5
      ? "#101010" : "#ffffff"
  }

  OverlayWindow {
    id: reminderWindow
    // Keep the surface mapped through the short fade-out, then release it.
    shown: root.reminderShown || pill.opacity > 0.01
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omasot-screen-time-reminder"
    // Only the pill takes pointer input; the rest of the fullscreen surface
    // is click-through to the app below (the shell OSD pattern).
    mask: Region { item: root.reminderShown ? pill : null }

    // A single, flat heads-up pill: app icon + "Used for <time>".
    // No shadow — a flat surface keeps the pill and its contents visually
    // aligned on every scale factor.
    Rectangle {
      id: pill
      width: pillRow.implicitWidth + Style.space(20)
      height: Style.space(40)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(44)
      radius: height / 2
      color: Commons.Color.accent
      opacity: root.reminderShown ? 1 : 0
      scale: root.reminderShown ? 1 : 0.97

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Item {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)

        Row {
          id: pillRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(9)

          Rectangle {
            width: Style.space(30)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.24)

            Image {
              id: appIconImage
              anchors.centerIn: parent
              width: Style.space(19)
              height: width
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: Math.round(width * Screen.devicePixelRatio)
              sourceSize.height: Math.round(height * Screen.devicePixelRatio)
              source: root.reminderIcon
              visible: root.reminderIcon !== "" && status !== Image.Error
            }

            Text {
              anchors.centerIn: parent
              visible: !appIconImage.visible
              text: "󰅐" // clock glyph fallback when the app has no icon
              textFormat: Text.PlainText
              font.family: Style.font.resolvedFamily
              font.pixelSize: Style.font.body
              color: root.pillTextColor
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.pillAppName + " · Used for " + root.formatTime(root.reminderSeconds)
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            color: root.pillTextColor
          }
        }
      }

      // Clicking the pill dismisses it early; no buttons, like the Android pill.
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismissReminder()
      }
    }
  }
}
