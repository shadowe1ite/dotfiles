import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property var backend: pluginApi?.mainInstance
    property string lyricText: backend?.currentLyric || ""
    property bool isPlaying: backend?.isPlaying ?? false

    property int widgetWidth: pluginApi?.pluginSettings?.widgetWidth ?? 215
    property int scrollSpeed: pluginApi?.pluginSettings?.scrollSpeed ?? 70
    property string scrollMode: pluginApi?.pluginSettings?.scrollMode ?? "always"
    property int customFontSize: pluginApi?.pluginSettings?.fontSize ?? 10
    property bool hideWhenEmpty: pluginApi?.pluginSettings?.hideWhenEmpty ?? true
    property string customFontFamily: pluginApi?.pluginSettings?.fontFamily ?? Settings.data.ui.fontDefault

    visible: !hideWhenEmpty || (lyricText !== "No Lyrics" && lyricText !== "")

    property bool hovered: false
    property real scaling: 1.0

    readonly property int iconSize: Math.round(18 * scaling)
    readonly property int verticalSize: Math.round((Style.baseWidgetSize - 5) * scaling)
    readonly property bool isVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

    implicitWidth: visible ? (isVertical ? verticalSize : container.width) : 0
    implicitHeight: visible ? (isVertical ? verticalSize : Style.capsuleHeight) : 0

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutCubic
        }
    }

    Rectangle {
        id: container
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        width: isVertical ? verticalSize : root.widgetWidth
        height: isVertical ? verticalSize : Style.capsuleHeight

        radius: Style.radiusM
        color: Style.capsuleColor
        border.width: Style.capsuleBorderWidth
        border.color: Style.capsuleBorderColor
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.InOutCubic
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.InOutCubic
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: isVertical ? 0 : Style.marginS * scaling
            spacing: Style.marginS * scaling
            visible: !isVertical

            NIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: iconSize
                Layout.preferredHeight: iconSize
                icon: "music"
                color: root.hovered ? Color.mPrimary : Color.mOnSurfaceVariant
                pointSize: Style.fontSizeL * scaling
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollingText {
                    anchors.fill: parent
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.lyricText
                    textColor: Color.mOnSurface

                    fontSize: root.customFontSize * scaling
                    fontFamily: root.customFontFamily

                    mode: root.scrollMode
                    speed: root.scrollSpeed
                    needsScroll: titleMetrics.contentWidth > parent.width
                }
            }
        }

        Item {
            visible: isVertical
            anchors.centerIn: parent
            width: parent.width
            height: parent.height

            NIcon {
                anchors.centerIn: parent
                icon: "music"
                color: root.hovered ? Color.mPrimary : Color.mOnSurfaceVariant
                pointSize: Style.fontSizeM * scaling
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                root.hovered = true;
                if (isVertical)
                    TooltipService.show(root, root.lyricText, "right");
            }
            onExited: {
                root.hovered = false;
                TooltipService.hide();
            }
        }
    }

    NText {
        id: titleMetrics
        visible: false
        text: root.lyricText
        applyUiScale: false
        pointSize: root.customFontSize * scaling
        family: root.customFontFamily
        font.weight: Style.fontWeightMedium
    }

    component ScrollingText: Item {
        id: scrollText
        property string text
        property string _displayedText: ""
        property color textColor
        property real fontSize
        property string fontFamily
        property string mode
        property int speed
        property bool needsScroll

        implicitHeight: titleText.height
        clip: true
        opacity: 1.0

        property bool isScrolling: false
        property bool isResetting: false

        onTextChanged: {
            if (_displayedText === "") {
                _displayedText = text;
                if (needsScroll && mode === "always")
                    scrollTimer.restart();
                return;
            }
            transitionAnim.restart();
        }

        onNeedsScrollChanged: {
            if (!needsScroll) {
                isScrolling = false;
                isResetting = false;
                scrollTimer.stop();
            } else {
                updateState();
            }
        }

        SequentialAnimation {
            id: transitionAnim
            NumberAnimation {
                target: scrollText
                property: "opacity"
                to: 0
                duration: 150
                easing.type: Easing.OutQuad
            }
            ScriptAction {
                script: {
                    scrollText._displayedText = scrollText.text;
                    scrollText.isScrolling = false;
                    scrollText.isResetting = false;
                    scrollContainer.scrollX = 0;
                }
            }
            NumberAnimation {
                target: scrollText
                property: "opacity"
                to: 1
                duration: 200
                easing.type: Easing.InQuad
            }
            ScriptAction {
                script: {
                    if (scrollText.needsScroll && scrollText.mode === "always") {
                        scrollTimer.restart();
                    }
                }
            }
        }

        Timer {
            id: scrollTimer
            interval: 700
            onTriggered: {
                if (mode === "always" && needsScroll) {
                    scrollText.isScrolling = true;
                    scrollText.isResetting = false;
                }
            }
        }

        function updateState() {
            if (mode === "none") {
                isScrolling = false;
                isResetting = false;
            } else if (mode === "always") {
                if (needsScroll) {
                    if (root.hovered) {
                        isScrolling = false;
                        isResetting = true;
                    } else {
                        if (!transitionAnim.running)
                            scrollTimer.restart();
                    }
                } else {
                    isScrolling = false;
                }
            } else if (mode === "hover") {
                isScrolling = root.hovered && needsScroll;
                isResetting = !root.hovered && needsScroll;
            }
        }

        onWidthChanged: updateState()
        Connections {
            target: root
            function onHoveredChanged() {
                scrollText.updateState();
            }
        }
        onModeChanged: updateState()

        Item {
            id: scrollContainer
            height: parent.height
            property real scrollX: 0
            x: scrollX

            RowLayout {
                spacing: 50

                NText {
                    id: titleText
                    text: scrollText._displayedText
                    color: textColor
                    pointSize: fontSize
                    family: scrollText.fontFamily
                    applyUiScale: false
                    font.weight: Style.fontWeightMedium
                }

                NText {
                    text: scrollText._displayedText
                    color: textColor
                    pointSize: fontSize
                    family: scrollText.fontFamily
                    applyUiScale: false
                    font.weight: Style.fontWeightMedium
                    visible: scrollText.needsScroll && scrollText.isScrolling
                }
            }

            NumberAnimation on scrollX {
                running: scrollText.isResetting
                to: 0
                duration: 300
                easing.type: Easing.OutQuad
                onFinished: scrollText.isResetting = false
            }

            NumberAnimation on scrollX {
                running: scrollText.isScrolling && !scrollText.isResetting
                from: 0
                to: -(titleMetrics.contentWidth + 50)
                duration: Math.max(1000, ((titleMetrics.contentWidth + 50) / Math.max(1, scrollText.speed)) * 1000)
                loops: Animation.Infinite
                easing.type: Easing.Linear
            }
        }
    }
}
