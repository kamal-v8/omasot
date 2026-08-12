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

  // Timer to record every minute
  Timer {
    id: recordTimer
    interval: 60000
    repeat: true
    running: true
    onTriggered: {
      if (!idleMonitor.isIdle) {
        recordProcess.running = true
      }
    }
  }

  Process {
    id: recordProcess
    command: ["python3", Qt.resolvedUrl("tracker.py").toString().replace("file://", ""), "record"]
  }

  Component.onCompleted: console.log("Screentime service started.")
}
