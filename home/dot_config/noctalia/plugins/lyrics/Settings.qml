import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.System

ColumnLayout {
    id: root

    property var pluginApi: null

    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? {}

    property int draftWidth: pluginApi?.pluginSettings?.widgetWidth ?? defaults.widgetWidth ?? 300
    property int draftSpeed: pluginApi?.pluginSettings?.scrollSpeed ?? defaults.scrollSpeed ?? 50
    property string draftMode: pluginApi?.pluginSettings?.scrollMode ?? defaults.scrollMode ?? "always"
    property int draftFontSize: pluginApi?.pluginSettings?.fontSize ?? defaults.fontSize ?? 10
    property bool draftHideWhenEmpty: pluginApi?.pluginSettings?.hideWhenEmpty ?? defaults.hideWhenEmpty ?? true
    property string draftFontFamily: pluginApi?.pluginSettings?.fontFamily ?? defaults.fontFamily ?? ""

    spacing: Style.marginM

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("Lyrics", "Cannot save: pluginApi is null");
            return;
        }

        pluginApi.pluginSettings.widgetWidth = draftWidth;
        pluginApi.pluginSettings.scrollSpeed = draftSpeed;
        pluginApi.pluginSettings.scrollMode = draftMode;
        pluginApi.pluginSettings.fontSize = draftFontSize;
        pluginApi.pluginSettings.hideWhenEmpty = draftHideWhenEmpty;
        pluginApi.pluginSettings.fontFamily = draftFontFamily;

        pluginApi.saveSettings();
    }

    NLabel {
        label: "Typography"
        Layout.fillWidth: true
    }

    NSearchableComboBox {
        label: "Font Family"
        description: "Select the font for lyrics display."
        Layout.fillWidth: true

        model: FontService.availableFonts
        currentKey: draftFontFamily
        placeholder: "System Default"
        searchPlaceholder: "Search fonts..."
        popupHeight: 300
        defaultValue: defaults.fontFamily ?? ""

        onSelected: key => draftFontFamily = key
    }

    NValueSlider {
        label: "Font Size"
        description: "Text size in points."
        Layout.fillWidth: true

        from: 8
        to: 32
        stepSize: 1
        value: draftFontSize
        text: Math.round(draftFontSize) + "pt"
        defaultValue: defaults.fontSize ?? 10

        onMoved: value => draftFontSize = Math.round(value)
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    NLabel {
        label: "Widget Appearance"
        Layout.fillWidth: true
    }

    NValueSlider {
        label: "Widget Width"
        description: "Width of the lyrics widget in the bar."
        Layout.fillWidth: true

        from: 100
        to: 500
        stepSize: 10
        value: draftWidth
        text: Math.round(draftWidth) + "px"
        defaultValue: defaults.widgetWidth ?? 300

        onMoved: value => draftWidth = Math.round(value)
    }

    NToggle {
        label: "Hide When Empty"
        description: "Hide the widget when no lyrics are available."
        Layout.fillWidth: true

        checked: draftHideWhenEmpty
        defaultValue: defaults.hideWhenEmpty ?? true

        onToggled: newState => draftHideWhenEmpty = newState
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    NLabel {
        label: "Scrolling Behavior"
        Layout.fillWidth: true
    }

    NComboBox {
        label: "Scroll Mode"
        description: "When to scroll long lyrics text."
        Layout.fillWidth: true

        model: [
            { name: "Always Scroll", key: "always" },
            { name: "Scroll on Hover", key: "hover" },
            { name: "Don't Scroll", key: "none" }
        ]
        currentKey: draftMode
        defaultValue: defaults.scrollMode ?? "always"

        onSelected: key => draftMode = key
    }

    NValueSlider {
        label: "Scroll Speed"
        description: "Speed of the scrolling animation."
        Layout.fillWidth: true

        from: 10
        to: 200
        stepSize: 5
        value: draftSpeed
        text: Math.round(draftSpeed) + " px/s"
        defaultValue: defaults.scrollSpeed ?? 50
        enabled: draftMode !== "none"

        onMoved: value => draftSpeed = Math.round(value)
    }

    Item {
        Layout.fillHeight: true
    }
}
