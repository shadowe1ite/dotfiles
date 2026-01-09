import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: sideItem

  // Define the signal so the parent can listen to it
  signal activated(int index)

  // Data properties
  required property var modelData
  required property int index

  // Config properties
  property int currentTabIndex: 0
  property bool sidebarExpanded: false
  property string iconName: modelData.icon
  property string itemText: modelData.text
  property int idx: index

  Layout.fillWidth: true
  Layout.preferredHeight: 40 * Style.uiScaleRatio
  radius: Style.radiusS

  // FIX: Use theme colors instead of hardcoded RGBA
  color: currentTabIndex === idx ? Color.mSurface : (itemMouse.containsMouse ? Color.mOnPrimary : "transparent")

  // Active indicator bar
  Rectangle {
    visible: currentTabIndex === sideItem.idx
    width: 3
    height: 16
    radius: 2
    color: Color.mPrimary
    anchors {
      left: parent.left
      verticalCenter: parent.verticalCenter
      leftMargin: 4
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 12
    spacing: 12

    NIcon {
      icon: sideItem.iconName
      // FIX: Use Primary color for active state
      color: currentTabIndex === sideItem.idx ? Color.mPrimary : Color.mOnSurface
      Layout.preferredWidth: 24
      Layout.preferredHeight: 24
    }

    Text {
      text: sideItem.itemText
      // FIX: Use Primary color for active state
      color: currentTabIndex === sideItem.idx ? Color.mPrimary : Color.mOnSurface
      font.weight: currentTabIndex === sideItem.idx ? Font.DemiBold : Font.Normal
      opacity: sidebarExpanded ? 1 : 0
      Layout.fillWidth: true
      elide: Text.ElideRight

      Behavior on opacity {
        NumberAnimation {
          duration: 150
        }
      }
    }
  }

  MouseArea {
    id: itemMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: sideItem.activated(sideItem.idx)
  }
}
