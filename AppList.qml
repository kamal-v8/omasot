import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Self-contained per-app screen-time breakdown list.
// Conventions copied from Panel.qml weekly rows: horizontal rows with a
// name label, dim track + foreground fill pill bar, and a value label;
// PanelToolTip on row hover; Button with text/tooltipText/foreground/
// fontFamily/fontSize/onClicked for the show more/less toggle.
Column {
  id: root
  width: parent.width
  spacing: Style.space(6)

  property string title: ""
  property int totalSeconds: 0
  property var apps: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool showMore: false
  property bool showIcons: true

  // Themed-icon lookup copied from the shell kit (NotificationCard /
  // AppLibrary): Quickshell.iconPath resolves a desktop Icon= name to a
  // file/image URL; absolute paths and URLs pass through untouched.
  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function formatTime(sec) {
    if (!sec || sec <= 0) return "0m"
    var m = Math.floor(sec / 60)
    if (m <= 0) return "0m"
    var h = Math.floor(m / 60)
    return (h > 0 ? h + "h " : "") + (m % 60) + "m"
  }

  // Collapsed view shows the first 6 apps plus an aggregated "Other" row
  // summing the rest. `apps` is expected pre-sorted descending by seconds.
  function visibleApps() {
    var list = root.apps || []
    if (root.showMore) return list
    if (list.length <= 6) return list
    var first = list.slice(0, 6)
    var rest = 0
    for (var i = 6; i < list.length; ++i) rest += (list[i].seconds || 0)
    first.push({ name: "Other", seconds: rest })
    return first
  }

  Item {
    width: parent.width
    height: Math.max(headerText.height, helpButton.height)

    Text {
      id: headerText
      anchors.left: parent.left
      anchors.right: helpButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: (root.title.length > 0 ? root.title + " · " : "") + root.formatTime(root.totalSeconds)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      color: Qt.darker(root.foreground, 1.2)
    }

    PanelActionButton {
      id: helpButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "?"
      tooltipText: "Top apps by focused time. Click a day in the weekly chart to inspect it."
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  Repeater {
    model: root.visibleApps()

    Item {
      required property var modelData
      width: parent.width
      height: Style.space(20)

      property int seconds: modelData.seconds || 0
      property int pct: Math.round(100 * seconds / Math.max(1, root.totalSeconds))
      property string appIcon: (modelData.icon || "")
      property bool hasIcon: root.showIcons && appIcon !== ""

      Image {
        id: appIconImage
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        height: Style.space(14)
        fillMode: Image.PreserveAspectFit
        // Decode at physical pixels — a logical-size decode leaves
        // PNG icons upscaled and blurry on HiDPI displays (kit pattern).
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: hasIcon ? root.iconSource(appIcon) : ""
        asynchronous: true
        // Hide the slot when the themed name is missing from the user's
        // icon theme — avoids Qt's broken-image placeholder.
        visible: hasIcon && status !== Image.Error
      }

      Text {
        id: nameLabel
        anchors.left: parent.left
        anchors.leftMargin: appIconImage.visible ? appIconImage.width + Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(90) - (appIconImage.visible ? appIconImage.width + Style.space(6) : 0)
        elide: Text.ElideRight
        text: modelData.name || ""
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: Qt.darker(root.foreground, 1.2)
      }

      Text {
        id: valueLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(76)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.formatTime(seconds) + " · " + pct + "%"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: root.foreground
      }

      Item {
        anchors.left: nameLabel.right
        anchors.leftMargin: Style.space(8)
        anchors.right: valueLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(12)

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
          radius: height / 2
        }

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(parent.width, Math.max(0, (seconds / Math.max(1, root.totalSeconds)) * parent.width))
          height: parent.height
          color: root.foreground
          radius: height / 2
          visible: seconds > 0
        }
      }

      PanelToolTip {
        visible: rowMouse.containsMouse
        text: (modelData.name || "") + " — " + root.formatTime(seconds) + " (" + pct + "%)"
        fontFamily: root.fontFamily
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
      }
    }
  }

  Text {
    visible: (root.apps || []).length === 0
    text: "No app data for this period yet."
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    color: Qt.darker(root.foreground, 1.5)
  }

  Button {
    visible: (root.apps || []).length > 6
    text: root.showMore ? "Show less" : "Show more (" + ((root.apps || []).length - 6) + ")"
    tooltipText: root.showMore ? "Show fewer apps" : "Show all apps"
    foreground: Qt.darker(root.foreground, 1.2)
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    horizontalPadding: Style.spacing.controlGap
    verticalPadding: Style.spacing.labelGap
    onClicked: root.showMore = !root.showMore
  }
}
