import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // Required plugin properties
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  readonly property var backend: pluginApi?.mainInstance
  readonly property string lyricText: {
    const lyric = backend?.currentLyric ?? "";
    if (lyric === "" && !hideWhenEmpty)
      return "404 Lyrics not Found";
    return lyric;
  }

  // Settings with defaults from manifest
  readonly property int widgetWidth: pluginApi?.pluginSettings?.widgetWidth ?? pluginApi?.manifest?.metadata?.defaultSettings?.widgetWidth ?? 300
  readonly property int scrollSpeed: pluginApi?.pluginSettings?.scrollSpeed ?? pluginApi?.manifest?.metadata?.defaultSettings?.scrollSpeed ?? 50
  readonly property string scrollMode: pluginApi?.pluginSettings?.scrollMode ?? pluginApi?.manifest?.metadata?.defaultSettings?.scrollMode ?? "always"
  readonly property int customFontSize: pluginApi?.pluginSettings?.fontSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.fontSize ?? 10
  readonly property bool hideWhenEmpty: pluginApi?.pluginSettings?.hideWhenEmpty ?? pluginApi?.manifest?.metadata?.defaultSettings?.hideWhenEmpty ?? true
  readonly property string customFontFamily: {
    const saved = pluginApi?.pluginSettings?.fontFamily;
    if (saved && saved !== "")
      return saved;
    return Settings.data.ui.fontDefault;
  }

  // Visibility logic
  readonly property bool shouldHide: hideWhenEmpty && lyricText === ""
  visible: !shouldHide

  // Bar position detection
  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  // Hover state
  property bool hovered: false

  // Displayed text with transition support
  property string displayedText: lyricText

  // Sizing
  implicitWidth: visible ? (isVertical ? Style.capsuleHeight : capsule.width) : 0
  implicitHeight: visible ? (isVertical ? Style.capsuleHeight : Style.capsuleHeight) : 0

  Behavior on implicitWidth {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  // Smooth fade transition when lyrics change
  onLyricTextChanged: {
    if (displayedText === "") {
      displayedText = lyricText;
    } else if (lyricText !== displayedText) {
      textTransition.restart();
    }
  }

  SequentialAnimation {
    id: textTransition

    NumberAnimation {
      target: textContainer
      property: "opacity"
      to: 0
      duration: 150
      easing.type: Easing.OutQuad
    }

    ScriptAction {
      script: {
        root.displayedText = root.lyricText;
      }
    }

    NumberAnimation {
      target: textContainer
      property: "opacity"
      to: 1
      duration: 200
      easing.type: Easing.InQuad
    }
  }

  // Convert scrollMode to NScrollText enum
  readonly property int nScrollMode: {
    switch (scrollMode) {
    case "always":
      return NScrollText.ScrollMode.Always;
    case "hover":
      return NScrollText.ScrollMode.Hover;
    case "none":
    default:
      return NScrollText.ScrollMode.Never;
    }
  }

  // Main capsule container
  Rectangle {
    id: capsule
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    width: isVertical ? Style.capsuleHeight : root.widgetWidth
    height: Style.capsuleHeight

    radius: Style.radiusM
    color: root.hovered ? Qt.lighter(Style.capsuleColor, 1.1) : Style.capsuleColor
    border.width: Style.capsuleBorderWidth
    border.color: Style.capsuleBorderColor
    clip: true

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    Behavior on width {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }

    // Horizontal layout (for top/bottom bar)
    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.marginS
      spacing: Style.marginS
      visible: !root.isVertical

      NIcon {
        Layout.alignment: Qt.AlignVCenter
        icon: "music"
        color: root.hovered ? Color.mPrimary : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeL

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }

      Item {
        id: textContainer
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        NScrollText {
          id: scrollText
          anchors.fill: parent
          anchors.verticalCenter: parent.verticalCenter

          text: root.displayedText
          maxWidth: parent.width
          scrollMode: root.nScrollMode
          scrollCycleDuration: Math.max(4000, (root.displayedText.length * 1000) / Math.max(1, root.scrollSpeed) * 10)
          waitBeforeScrolling: 700
          resettingDuration: 300

          // Keep paused at start while hovered
          Connections {
            target: scrollText
            function onStateChanged() {
              if (root.hovered && scrollText.state === NScrollText.ScrollState.None) {
                // Stay at None (paused) while hovered
              } else if (root.hovered && scrollText.state === NScrollText.ScrollState.Scrolling) {
                // Prevent scrolling while hovered
                scrollText.state = NScrollText.ScrollState.None;
              }
            }
          }

          delegate: NText {
            pointSize: root.customFontSize
            family: root.customFontFamily
            color: Color.mOnSurface
            font.weight: Style.fontWeightMedium
          }
        }
      }
    }

    // Vertical layout (for left/right bar) - icon only with tooltip
    Item {
      visible: root.isVertical
      anchors.centerIn: parent
      width: parent.width
      height: parent.height

      NIcon {
        anchors.centerIn: parent
        icon: "music"
        color: root.hovered ? Color.mPrimary : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeM

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }
    }

    HoverHandler {
      id: hoverHandler
      onHoveredChanged: {
        root.hovered = hovered;
        if (hovered) {
          if (root.isVertical && root.lyricText !== "") {
            TooltipService.show(root, root.lyricText, BarService.getTooltipDirection());
          }
        } else {
          if (root.isVertical) {
            TooltipService.hide();
          }
        }
      }
    }
  }
}
