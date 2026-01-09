import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "./components"
import "./tabs"
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // API properties
  property var pluginApi: null
  readonly property real contentPreferredWidth: 850 * Style.uiScaleRatio
  readonly property real contentPreferredHeight: 600 * Style.uiScaleRatio

  // State
  property bool sidebarExpanded: false
  property int currentTabIndex: 0

  // Tab config
  readonly property var tabs: [
    {
      icon: "code",
      title: "Data Encoder",
      text: "Encoder"
    },
    {
      icon: "hash",
      title: "Hash Generator",
      text: "Hash Generator"
    },
    {
      icon: "photo-question",
      title: "Steg Check",
      text: "Steg Check"
    }
  ]

  anchors.fill: parent

  // --- Main UI ---
  Rectangle {
    anchors.fill: parent
    color: "transparent" // FIX: String "transparent" instead of invalid Color property

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.marginL
      color: Color.mSurface
      radius: Style.radiusL
      border {
        color: Color.mOutline
        width: Style.borderS
      }
      clip: true

      RowLayout {
        anchors.fill: parent
        spacing: 0

        // === SIDEBAR ===
        Rectangle {
          id: sidebar
          Layout.fillHeight: true
          Layout.preferredWidth: root.sidebarExpanded ? 200 * Style.uiScaleRatio : 56 * Style.uiScaleRatio
          color: Color.mSurfaceVariant
          clip: true

          Behavior on Layout.preferredWidth {
            NumberAnimation {
              duration: 200
              easing.type: Easing.InOutQuad
            }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS

            // Toggle button
            NButton {
              icon: root.sidebarExpanded ? "layout-sidebar-right-expand" : "layout-sidebar-left-expand"
              Layout.preferredWidth: 40 * Style.uiScaleRatio
              Layout.preferredHeight: 40 * Style.uiScaleRatio
              onClicked: root.sidebarExpanded = !root.sidebarExpanded
            }

            Item {
              height: Style.marginS
              width: 1
            }

            // Tab items via Repeater
            Repeater {
              model: root.tabs
              delegate: SidebarItem {
                // Bind properties to root state
                currentTabIndex: root.currentTabIndex
                sidebarExpanded: root.sidebarExpanded

                // Handle the signal from the component
                onActivated: i => root.currentTabIndex = i
              }
            }

            Item {
              Layout.fillHeight: true
            }
          }

          // Right border
          Rectangle {
            anchors {
              right: parent.right
              top: parent.top
              bottom: parent.bottom
            }
            width: 1
            color: Color.mOutline
            opacity: 0.5
          }
        }

        // === MAIN CONTENT ===
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          // Header
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60 * Style.uiScaleRatio
            color: "transparent" // FIX: String "transparent"

            RowLayout {
              anchors.left: parent.left
              anchors.leftMargin: Style.marginL
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS

              // 1. Icon
              NIcon {
                icon: root.tabs[root.currentTabIndex].icon
                color: Color.mOnSurface
                pointSize: Style.fontSizeXL
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
              }

              // 2. Title using NText
              NText {
                text: root.tabs[root.currentTabIndex].title
                font.weight: Font.Bold
                pointSize: Style.fontSizeXL
                color: Color.mOnSurface
              }
            }
          }

          // Page Stack
          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTabIndex

            // --- Tab 0: Encoder ---
            Encoder {}

            // --- Tab 1: Hash ---
            Hash {}

            // --- Tab 2: Steg ---
            Steg {}
          }
        }
      }
    }
  }
}
