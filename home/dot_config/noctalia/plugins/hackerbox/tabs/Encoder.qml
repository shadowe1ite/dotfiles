import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../components"
import "utils/Encoder.js" as EncoderScript
import qs.Commons
import qs.Widgets

Item {
  id: encoderRoot

  // Kept exactly as you had it (no new algorithms added)
  readonly property var algorithms: [
    {
      key: "Base64",
      name: "Base64"
    },
    {
      key: "Hex",
      name: "Hex"
    },
    {
      key: "URL",
      name: "URL"
    }
  ]

  ScrollView {
    anchors.fill: parent
    contentWidth: availableWidth
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: parent.width
      anchors.margins: Style.marginL
      spacing: 0

      // Input area
      ResizableTextBox {
        id: inputBox
        placeholderText: "Input text here..."
        initialHeight: 215 * Style.uiScaleRatio
      }

      // Action buttons (Moved to Right)
      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Style.marginL
        Layout.rightMargin: Style.marginL
        Layout.topMargin: Style.marginM
        Layout.bottomMargin: Style.marginM
        spacing: Style.marginS

        // 1. Spacer here pushes everything to the Right
        Item {
          Layout.fillWidth: true
        }

        NComboBox {
          id: algoSelector
          Layout.fillWidth: false
          model: encoderRoot.algorithms
          currentKey: "Base64"
          onSelected: key => currentKey = key
        }

        NButton {
          text: "Encode"
          icon: "lock"
          onClicked: outputBox.text = EncoderScript.encode(inputBox.text, algoSelector.currentKey)
        }

        NButton {
          text: "Decode"
          icon: "lock-open"
          onClicked: outputBox.text = EncoderScript.decode(inputBox.text, algoSelector.currentKey)
        }
      }

      Item {
        Layout.preferredHeight: 5
      }

      // Output area
      ResizableTextBox {
        id: outputBox
        placeholderText: "Result will appear here..."
        initialHeight: 150 * Style.uiScaleRatio
        readOnly: true
        textColor: Color.mPrimary
      }

      // Copy/Clear buttons (Moved to Right)
      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Style.marginL
        Layout.rightMargin: Style.marginL
        Layout.topMargin: Style.marginM
        Layout.bottomMargin: Style.marginM
        spacing: Style.marginS

        // 2. Spacer here pushes everything to the Right
        Item {
          Layout.fillWidth: true
        }

        NButton {
          id: copyBtn
          property bool justCopied: false

          icon: justCopied ? "clipboard-check" : "clipboard"
          text: justCopied ? "Copied!" : "Copy"
          color: justCopied ? "#27D796" : Color.mPrimary
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          onClicked: {
            outputBox.selectAll();
            outputBox.copy();
            outputBox.deselect();
            justCopied = true;
            copyResetTimer.restart();
          }

          Timer {
            id: copyResetTimer
            interval: 1000
            onTriggered: copyBtn.justCopied = false
          }
        }

        NButton {
          text: "Clear All"
          icon: "trash"
          color: Color.mError
          onClicked: outputBox.text = ""
        }
      }

      Item {
        Layout.preferredHeight: Style.marginL
      }
    }
  }
}
