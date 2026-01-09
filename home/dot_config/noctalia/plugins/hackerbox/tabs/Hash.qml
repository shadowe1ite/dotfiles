import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import qs.Commons
import qs.Widgets

Item {
  id: hasherRoot

  readonly property var hashes: [
    {
      key: "md5sum",
      name: "MD5"
    },
    {
      key: "sha1sum",
      name: "SHA-1"
    },
    {
      key: "sha224sum",
      name: "SHA-224"
    },
    {
      key: "sha256sum",
      name: "SHA-256"
    },
    {
      key: "sha384sum",
      name: "SHA-384"
    },
    {
      key: "sha512sum",
      name: "SHA-512"
    },
    {
      key: "b2sum",
      name: "BLAKE2"
    }
  ]

  function getSafeCommand(text, algo) {
    var escaped = text.replace(/'/g, "'\\''");
    return "echo -n '" + escaped + "' | " + algo;
  }

  Process {
    id: hashProc
    stdout: StdioCollector {
      onStreamFinished: {
        var cleanHash = text.split(" ")[0].trim();
        outputBox.text = cleanHash;
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          outputBox.text = "Error: " + text;
      }
    }
  }

  ScrollView {
    anchors.fill: parent
    contentWidth: availableWidth
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: parent.width
      anchors.margins: Style.marginL
      spacing: 0

      // Input
      ResizableTextBox {
        id: inputBox
        placeholderText: "Enter text to hash..."
        initialHeight: 190 * Style.uiScaleRatio
      }

      // Controls (Moved to Right)
      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Style.marginL
        Layout.rightMargin: Style.marginL
        Layout.topMargin: Style.marginM
        Layout.bottomMargin: Style.marginM
        spacing: Style.marginS

        // 1. Add spacer to push content to the right
        Item {
          Layout.fillWidth: true
        }

        NComboBox {
          id: hashSelector
          Layout.preferredWidth: 140
          model: hasherRoot.hashes
          currentKey: "sha256sum"
          onSelected: key => currentKey = key
        }

        NButton {
          text: "Generate Hash"
          icon: "fingerprint"
          // 2. Remove Layout.fillWidth: true so it doesn't stretch

          onClicked: {
            if (hashProc.running) {
              hashProc.running = false;
            }
            if (inputBox.text !== "") {
              var cmd = hasherRoot.getSafeCommand(inputBox.text, hashSelector.currentKey);
              hashProc.command = ["bash", "-c", cmd];
              hashProc.running = true;
            }
          }
        }
      }

      Item {
        Layout.preferredHeight: 5
      }

      // Output
      ResizableTextBox {
        id: outputBox
        placeholderText: "Hash will appear here..."
        initialHeight: 190 * Style.uiScaleRatio
        readOnly: true
        textColor: Color.mPrimary
      }

      // Copy/Clear Buttons (Already on Right)
      RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: Style.marginL
        Layout.topMargin: Style.marginS

        Item {
          Layout.fillWidth: true
        }

        NButton {
          id: copyBtn
          property bool justCopied: false
          icon: justCopied ? "clipboard-check" : "clipboard"
          text: justCopied ? "Copied" : "Copy Hash"
          color: justCopied ? "#27D796" : Color.mPrimary

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
    }
  }
}
