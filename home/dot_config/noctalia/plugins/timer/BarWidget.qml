import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root
  
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool isActive: mainInstance && (mainInstance.timerRunning || mainInstance.timerElapsedSeconds > 0 || mainInstance.timerRemainingSeconds > 0)
  
  implicitWidth: {
    if (barIsVertical) return Style.capsuleHeight
    if (isActive) return contentRow.implicitWidth + Style.marginM * 2
    return Style.capsuleHeight
  }
  implicitHeight: Style.capsuleHeight
  
  readonly property string barPosition: Settings.data.bar.position || "top"
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  
  color: Style.capsuleColor
  
  radius: Style.radiusL
  
  function formatTime(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    if (hours > 0) {
      return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  
  RowLayout {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.marginS
    
    NIcon {
      icon: {
        if (mainInstance && mainInstance.timerSoundPlaying) return "bell-ringing"
        if (mainInstance && mainInstance.timerStopwatchMode) return "stopwatch"
        return "hourglass"
      }
      applyUiScale: false
      color: {
         if (mainInstance && (mainInstance.timerRunning || mainInstance.timerSoundPlaying)) {
            return Color.mPrimary
         }
         return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
      }
    }
    
    NText {
      visible: !barIsVertical && mainInstance && (mainInstance.timerRunning || mainInstance.timerElapsedSeconds > 0 || mainInstance.timerRemainingSeconds > 0)
      text: {
        if (!mainInstance) return ""
        if (mainInstance.timerStopwatchMode) {
            return formatTime(mainInstance.timerElapsedSeconds)
        }
        return formatTime(mainInstance.timerRemainingSeconds)
      }
      color: {
         if (mainInstance && (mainInstance.timerRunning || mainInstance.timerSoundPlaying)) {
            return Color.mPrimary
         }
         return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
      }
      pointSize: Style.fontSizeS
      font.weight: Font.Medium
    }
  }
  
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    
    onEntered: {
        if (!mainInstance || (!mainInstance.timerRunning && !mainInstance.timerSoundPlaying)) {
             root.color = Color.mHover
        }
    }
    
    onExited: {
        if (!mainInstance || (!mainInstance.timerRunning && !mainInstance.timerSoundPlaying)) {
             root.color = Style.capsuleColor
        }
    }
    
    onClicked: {
      if (pluginApi) {
        pluginApi.openPanel(root.screen, root)
      }
    }
    
    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            if (mainInstance) {
                if (mainInstance.timerSoundPlaying) {
                    mainInstance.timerReset()
                } else if (mainInstance.timerRunning) {
                    mainInstance.timerPause()
                }
            }
        }
    }
  }
}
