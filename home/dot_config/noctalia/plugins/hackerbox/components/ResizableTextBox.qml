import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: textBox

  property alias text: textArea.text
  property string placeholderText: ""
  property real initialHeight: 150 * Style.uiScaleRatio
  property bool readOnly: false
  property color textColor: Color.mOnSurface

  function selectAll() {
    textArea.selectAll();
  }
  function copy() {
    textArea.copy();
  }
  function deselect() {
    textArea.deselect();
  }

  Layout.fillWidth: true
  spacing: 0

  ScrollView {
    id: textScrollView
    Layout.fillWidth: true
    Layout.preferredHeight: textBox.initialHeight
    Layout.leftMargin: Style.marginL
    Layout.rightMargin: Style.marginL
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AlwaysOn

    TextArea {
      id: textArea
      placeholderText: textBox.placeholderText
      color: textBox.textColor
      readOnly: textBox.readOnly
      wrapMode: Text.Wrap
      selectByMouse: true

      background: Rectangle {
        color: Color.mSurfaceVariant
        radius: Style.radiusM
        border.color: Color.mOutline
      }
    }
  }

  // Resize handle
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 14 * Style.uiScaleRatio
    Layout.leftMargin: Style.marginL
    Layout.rightMargin: Style.marginL
    color: "transparent"

    Rectangle {
      anchors.centerIn: parent
      width: 40
      height: 4
      radius: 2
      color: Color.mOutline
      opacity: resizeMouse.containsMouse || resizeMouse.pressed ? 1 : 0.5

      Behavior on opacity {
        NumberAnimation {
          duration: 150
        }
      }
    }

    MouseArea {
      id: resizeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.SizeVerCursor
      preventStealing: true

      property real lastY: 0

      onPressed: mouse => lastY = mapToItem(textBox, mouse.x, mouse.y).y

      onPositionChanged: mouse => {
                           if (pressed) {
                             let currentY = mapToItem(textBox, mouse.x, mouse.y).y;
                             let delta = currentY - lastY;
                             let newHeight = textScrollView.Layout.preferredHeight + delta;

                             if (newHeight > 50) {
                               textScrollView.Layout.preferredHeight = newHeight;
                               lastY = currentY;
                             }
                           }
                         }
    }
  }
}
