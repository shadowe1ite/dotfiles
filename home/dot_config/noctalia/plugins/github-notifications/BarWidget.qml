import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "services"
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  // Configuration
  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string githubToken: cfg.githubToken || defaults.githubToken || ""
  readonly property int checkInterval: cfg.checkInterval ?? defaults.checkInterval ?? 300
  readonly property bool showOnlyUnread: cfg.showOnlyUnread ?? defaults.showOnlyUnread ?? false
  readonly property int maxNotifications: cfg.maxNotifications ?? defaults.maxNotifications ?? 30

  // Visual Styling
  icon: "brand-github"
  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: GitHubService.error ? Color.mError : Color.mOnSurface
  colorBgHover: Color.mHover
  colorFgHover: Color.mOnHover
  colorBorder: "transparent"
  colorBorderHover: "transparent"

  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  tooltipText: {
    if (!githubToken)
      return "GitHub Notifications\nToken not configured";
    if (GitHubService.loading)
      return "GitHub Notifications\nLoading...";
    if (GitHubService.error)
      return "GitHub Notifications\nError: " + (GitHubService.errorMessage || "Unknown");

    var text = "GitHub Notifications";
    if (GitHubService.unreadCount > 0)
      text += "\n" + GitHubService.unreadCount + " unread";
    else
      text += "\nNo new notifications";

    text += "\nRight-click to refresh";
    return text;
  }
  tooltipDirection: BarService.getTooltipDirection()

  // Green Dot Indicator
  Rectangle {
    visible: GitHubService.unreadCount > 0
    width: 8
    height: 8
    radius: 4
    color: Color.mSuccess

    anchors {
      top: parent.top
      right: parent.right
      topMargin: 3
      rightMargin: 3
    }

    border.width: 2
    border.color: root.colorBg
  }

  // Push config to service when it changes
  onGithubTokenChanged: GitHubService.githubToken = githubToken
  onCheckIntervalChanged: GitHubService.checkInterval = checkInterval
  onShowOnlyUnreadChanged: GitHubService.showOnlyUnread = showOnlyUnread
  onMaxNotificationsChanged: GitHubService.maxNotifications = maxNotifications

  Component.onCompleted: {
    // Initialize service with config
    GitHubService.githubToken = githubToken;
    GitHubService.checkInterval = checkInterval;
    GitHubService.showOnlyUnread = showOnlyUnread;
    GitHubService.maxNotifications = maxNotifications;

    Logger.i("GitHubNotifications", "BarWidget initialized");
  }

  // Timer for periodic updates
  Timer {
    id: updateTimer
    interval: checkInterval * 1000
    running: githubToken !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      GitHubService.refresh();
    }
  }

  // Interaction Handlers
  onClicked: {
    for (var slot = 1; slot <= 2; slot++) {
      var panel = PanelService.getPanel("pluginPanel" + slot, screen);
      if (panel && panel.currentPluginId === "github-notifications") {
        panel.toggle(root);
        return;
      }
    }

    for (var slot = 1; slot <= 2; slot++) {
      var panel = PanelService.getPanel("pluginPanel" + slot, screen);
      if (panel && panel.currentPluginId === "") {
        panel.currentPluginId = "github-notifications";
        panel.loadPluginPanel("github-notifications");
        panel.open(root);
        return;
      }
    }

    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      panel1.unloadPluginPanel();
      panel1.currentPluginId = "github-notifications";
      panel1.loadPluginPanel("github-notifications");
      panel1.open(root);
    }
  }

  onRightClicked: {
    GitHubService.refresh();
    ToastService.showNotice("Refreshing GitHub notifications...");
  }
}
