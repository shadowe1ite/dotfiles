import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property real baseSize: Style.capsuleHeight
  property bool applyUiScale: false
  property bool hovering: false

  // Customize your colors here
  property color colorBg: Color.mSurfaceVariant
  property color colorFg: Color.mPrimary
  property color colorBgHover: Color.mHover
  property color colorFgHover: Color.mOnHover

  implicitWidth: applyUiScale ? Math.round(baseSize * Style.uiScaleRatio) : Math.round(baseSize)
  implicitHeight: applyUiScale ? Math.round(baseSize * Style.uiScaleRatio) : Math.round(baseSize)

  color: hovering ? colorBgHover : colorBg
  radius: Math.min(Style.radiusL, width / 2)
  border.color: Color.mOutline
  border.width: Style.borderS

  NIcon {
    anchors.centerIn: parent
    icon: "brand-redhat" // Change this icon
    color: hovering ? colorFgHover : colorFg
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: root.hovering = true
    onExited: root.hovering = false
    onClicked: {
      if (pluginApi)
        pluginApi.openPanel(root.screen);
    }
  }

  Behavior on color {
    ColorAnimation {
      duration: 150
    }
  }
}
