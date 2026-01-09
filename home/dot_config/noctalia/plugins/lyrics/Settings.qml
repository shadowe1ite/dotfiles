import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.System

ColumnLayout {
    id: root
    property var pluginApi: null

    property int draftWidth: pluginApi?.pluginSettings?.widgetWidth ?? 215
    property int draftSpeed: pluginApi?.pluginSettings?.scrollSpeed ?? 70
    property string draftMode: pluginApi?.pluginSettings?.scrollMode ?? "always"
    property int draftFontSize: pluginApi?.pluginSettings?.fontSize ?? 10
    property bool draftHideWhenEmpty: pluginApi?.pluginSettings?.hideWhenEmpty ?? true
    property string draftFontFamily: pluginApi?.pluginSettings?.fontFamily ?? "Inter"

    spacing: Style.marginM

    function saveSettings() {
        if (pluginApi) {
            pluginApi.pluginSettings.widgetWidth = draftWidth;
            pluginApi.pluginSettings.scrollSpeed = draftSpeed;
            pluginApi.pluginSettings.scrollMode = draftMode;
            pluginApi.pluginSettings.fontSize = draftFontSize;
            pluginApi.pluginSettings.hideWhenEmpty = draftHideWhenEmpty;
            // Save the selected font
            pluginApi.pluginSettings.fontFamily = draftFontFamily;
            pluginApi.saveSettings();
        }
    }

    NSearchableComboBox {
        label: "Font Family"
        description: "Select the font for lyrics."
        Layout.fillWidth: true

        model: FontService.availableFonts

        currentKey: draftFontFamily
        placeholder: "Select a font..."
        searchPlaceholder: "Search fonts..."
        popupHeight: 300

        onSelected: key => draftFontFamily = key
    }

    NLabel {
        label: "Font Size"
        description: "Text size in points."
    }

    RowLayout {
        Layout.fillWidth: true
        NSlider {
            Layout.fillWidth: true
            from: 8
            to: 32
            value: draftFontSize
            onValueChanged: draftFontSize = value
        }
        NText {
            text: Math.round(draftFontSize) + "pt"
        }
    }

    NDivider {
        Layout.fillWidth: true
    }

    NLabel {
        label: "Widget Width"
    }
    RowLayout {
        Layout.fillWidth: true
        NSlider {
            Layout.fillWidth: true
            from: 100
            to: 500
            value: draftWidth
            onValueChanged: draftWidth = value
        }
        NText {
            text: Math.round(draftWidth) + "px"
        }
    }

    NLabel {
        label: "Scroll Speed"
    }
    RowLayout {
        Layout.fillWidth: true
        NSlider {
            Layout.fillWidth: true
            from: 10
            to: 200
            value: draftSpeed
            onValueChanged: draftSpeed = value
        }
        NText {
            text: Math.round(draftSpeed) + " px/s"
        }
    }

    NComboBox {
        label: "Scroll Mode"
        Layout.fillWidth: true
        model: [
            {
                name: "Always Scroll",
                key: "always"
            },
            {
                name: "Scroll on Hover",
                key: "hover"
            },
            {
                name: "Don't Scroll",
                key: "none"
            }
        ]
        currentKey: draftMode
        onSelected: key => draftMode = key
    }

    NToggle {
        label: "Hide when empty"
        checked: draftHideWhenEmpty
        onToggled: newState => {
            draftHideWhenEmpty = newState;
        }
    }
}
