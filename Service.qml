import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root
  property var shell: null
  
  IdleMonitor {
    id: idleMonitor
    timeout: 60
    respectInhibitors: true
  }

  Process {
    id: recordProcess
  }

  // Timer to record every minute
  Timer {
    id: recordTimer
    interval: 60000
    repeat: true
    running: true
    onTriggered: {
      var isIdleStr = idleMonitor.isIdle ? "idle" : "active"
      recordProcess.command = ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "record", isIdleStr]
      recordProcess.running = true
    }
  }

  Component.onCompleted: console.log("Screentime service started.")
}
