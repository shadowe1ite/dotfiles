import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Services.System
import qs.Widgets

NIconButton {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property var mainInstance: pluginApi?.mainInstance

    enabled: mainInstance?.isAvailable ?? false
    icon: "camera-video"
    tooltipText: mainInstance?.buildTooltip()
    tooltipDirection: BarService.getTooltipDirection()
    baseSize: Style.capsuleHeight
    applyUiScale: false
    customRadius: Style.radiusL
    colorBg: mainInstance?.isRecording ? Color.mPrimary : Style.capsuleColor
    colorFg: mainInstance?.isRecording ? Color.mOnPrimary : Color.mOnSurface
    colorBorder: "transparent"
    colorBorderHover: "transparent"
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    onClicked: {
        if (!enabled) {
            ToastService.showError(pluginApi.tr("messages.not-installed"), pluginApi.tr("messages.not-installed-desc"))
            return
        }

        if (mainInstance) {
            mainInstance.toggleRecording()
            if (!mainInstance.isRecording && !mainInstance.isPending) {
                // Recording was stopped, close control center if open
                var controlCenter = PanelService.getPanel("controlCenterPanel", screen)
                if (controlCenter) {
                    controlCenter.close()
                }
            }
        }
    }

    onRightClicked: {
        var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
        if (popupMenuWindow) {
            popupMenuWindow.showContextMenu(contextMenu);
            contextMenu.openAtItem(root, screen);
        }
    }


    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": I18n.tr("actions.widget-settings"),
                "action": "widget-settings",
                "icon": "settings"
            },
        ]

        onTriggered: action => {
            var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
            if (popupMenuWindow) {
                popupMenuWindow.close();
            }

            if (action === "widget-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            }
        }
    }

}
