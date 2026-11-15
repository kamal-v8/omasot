import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var shell: null

  Process {
    id: tickProcess
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
      tickProcess.command = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "tick"]
      tickProcess.running = true
    }
  }

  Component.onCompleted: console.log("Screentime service started (presence-based ticker).")
}
