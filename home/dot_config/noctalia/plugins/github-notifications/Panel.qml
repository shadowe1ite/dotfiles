import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "services"
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 420 * Style.uiScaleRatio
  property real contentPreferredHeight: 500 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  anchors.fill: parent

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string githubToken: cfg.githubToken || defaults.githubToken || ""

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "brand-github"
          pointSize: Style.fontSizeL
          color: Color.mPrimary
        }

        NText {
          Layout.fillWidth: true
          text: pluginApi?.tr("widget.title", "GitHub Notifications") || "GitHub Notifications"
          pointSize: Style.fontSizeM
          font.weight: Font.Bold
          color: Color.mOnSurface
        }

        NIconButton {
          icon: "bookmarks"
          enabled: GitHubService.unreadCount > 0 && !GitHubService.loading
          tooltipText: pluginApi?.tr("widget.markAllRead", "Mark all as read") || "Mark all as read"
          onClicked: GitHubService.markAllAsRead()
        }

        NIconButton {
          icon: "refresh"
          enabled: !GitHubService.loading
          colorFg: GitHubService.loading ? Color.mOnSurfaceVariant : Color.mOnSurface
          tooltipText: pluginApi?.tr("widget.refresh", "Refresh") || "Refresh"
          onClicked: GitHubService.refresh()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: GitHubService.notifications.length > 0

        NText {
          Layout.fillWidth: true
          text: {
            var count = GitHubService.notifications.length;
            var text = count + " notifications";
            if (GitHubService.unreadCount > 0)
              text += " • " + GitHubService.unreadCount + " unread";
            return text;
          }
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        // No token state
        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginL
          visible: !githubToken

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "user-circle"
            pointSize: Style.fontSizeXXL * 2
            color: Color.mOnSurfaceVariant
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: "Token not configured"
            pointSize: Style.fontSizeM
            font.weight: Font.Medium
            color: Color.mOnSurface
          }
        }

        // Error state
        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginL
          visible: GitHubService.error && githubToken

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: GitHubService.errorMessage || "Failed to fetch notifications"
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }
        }

        // Loading state
        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginL
          visible: GitHubService.loading && GitHubService.notifications.length === 0

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("widget.loading", "Loading...") || "Loading..."
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }
        }

        // Empty list
        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginL
          visible: !GitHubService.loading && !GitHubService.error && GitHubService.notifications.length === 0 && githubToken

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("widget.no-notifications", "No notifications") || "No notifications"
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }
        }

        NScrollView {
          anchors.fill: parent
          anchors.margins: Style.marginS
          visible: GitHubService.notifications.length > 0 && !GitHubService.error

          ListView {
            model: GitHubService.notifications
            spacing: Style.marginS
            clip: true

            delegate: Rectangle {
              id: notifCard
              width: ListView.view.width
              height: cardContent.implicitHeight + Style.marginM * 2
              color: cardMouse.containsMouse ? Qt.lighter(Color.mSurface, 1.05) : Color.mSurface
              radius: Style.radiusM

              Behavior on color {
                ColorAnimation {
                  duration: 100
                }
              }

              property var notification: modelData

              Rectangle {
                visible: notification.unread
                width: 3
                height: parent.height - 16
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 4
                color: Color.mPrimary
                radius: 2
              }

              RowLayout {
                id: cardContent
                anchors {
                  left: parent.left
                  right: parent.right
                  verticalCenter: parent.verticalCenter
                  margins: Style.marginM
                  leftMargin: notification.unread ? Style.marginM + 6 : Style.marginM
                }
                spacing: Style.marginM

                Rectangle {
                  Layout.preferredWidth: 36
                  Layout.preferredHeight: 36
                  Layout.alignment: Qt.AlignTop
                  radius: 18
                  color: Qt.alpha(Color.mOnSurface, 0.05)

                  NIcon {
                    anchors.centerIn: parent
                    icon: getNotificationIcon(notification)
                    pointSize: Style.fontSizeL
                    color: notification.unread ? Color.mPrimary : Color.mOnSurfaceVariant
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    NText {
                      text: notification.repository?.full_name || ""
                      pointSize: Style.fontSizeS
                      font.weight: Font.Bold
                      color: Color.mOnSurface
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    NText {
                      text: formatRelativeTime(notification.updated_at)
                      pointSize: Style.fontSizeXS
                      color: Color.mOnSurfaceVariant
                    }
                  }

                  NText {
                    Layout.fillWidth: true
                    text: notification.subject?.title || ""
                    pointSize: Style.fontSizeS
                    color: notification.unread ? Color.mOnSurface : Color.mOnSurfaceVariant
                    font.weight: notification.unread ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 2
                  }

                  // Avatar and reason badge row
                  RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: Style.marginS
                    visible: notification.reason

                    NImageRounded {
                      Layout.preferredWidth: 18
                      Layout.preferredHeight: 18
                      radius: 9
                      // Only show actual avatar once actorAvatarUrl is fetched to avoid glitch
                      imagePath: notification.actorAvatarUrl || ""
                      fallbackIcon: "user"
                      fallbackIconSize: Style.fontSizeXS
                    }

                    Rectangle {
                      Layout.preferredHeight: 18
                      Layout.preferredWidth: reasonText.implicitWidth + Style.marginS * 2
                      radius: 9
                      color: getReasonColor(notification.reason)

                      NText {
                        id: reasonText
                        anchors.centerIn: parent
                        text: formatReason(notification.reason)
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                      }
                    }

                    Item {
                      Layout.fillWidth: true
                    }
                  }
                }
              }

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                  // Open URL first before marking as read
                  // (markAsRead triggers array update which can invalidate notification reference)
                  var url = notification.subject?.url ? convertApiUrlToWeb(notification) : "";
                  var isUnread = notification.unread;
                  var notifId = notification.id;

                  if (url) {
                    Qt.openUrlExternally(url);
                  }
                  if (isUnread) {
                    GitHubService.markAsRead(notifId);
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  function getNotificationIcon(notification) {
    const type = notification.subject?.type || "";
    switch (type) {
    case "Issue":
      return "circle-dot";
    case "PullRequest":
      return "git-pull-request";
    case "Release":
      return "tag";
    case "CheckSuite":
      return "circle-check";
    case "Discussion":
      return "message-circle";
    case "Commit":
      return "git-commit";
    default:
      return "bell";
    }
  }

  function getActorAvatar(notification) {
    // Use fetched actor avatar, falls back to repo owner
    return notification.actorAvatarUrl || notification.repository?.owner?.avatar_url || "";
  }

  function formatReason(reason) {
    switch (reason) {
    case "mention":
      return "mentioned";
    case "subscribed":
      return "subscribed";
    case "author":
      return "author";
    case "review_requested":
      return "review requested";
    case "assign":
      return "assigned";
    case "team_mention":
      return "team mentioned";
    case "comment":
      return "commented";
    case "state_change":
      return "state changed";
    case "ci_activity":
      return "CI activity";
    default:
      return reason || "";
    }
  }

  function getReasonColor(reason) {
    switch (reason) {
    case "mention":
    case "team_mention":
      return Qt.alpha(Color.mPrimary, 0.2);
    case "review_requested":
    case "assign":
      return Qt.alpha(Color.mWarning, 0.2);
    case "author":
      return Qt.alpha(Color.mSuccess, 0.2);
    default:
      return Qt.alpha(Color.mOnSurface, 0.1);
    }
  }

  function formatRelativeTime(isoString) {
    if (!isoString)
      return "";
    var date = new Date(isoString);
    var now = new Date();
    var diffMs = now - date;
    var diffSec = Math.floor(diffMs / 1000);
    var diffMin = Math.floor(diffSec / 60);
    var diffHour = Math.floor(diffMin / 60);
    var diffDay = Math.floor(diffHour / 24);

    if (diffMin < 1)
      return "now";
    if (diffMin < 60)
      return diffMin + "m ago";
    if (diffHour < 24)
      return diffHour + "h ago";
    return diffDay + "d ago";
  }

  function convertApiUrlToWeb(notification) {
    const url = notification.subject?.url || "";
    if (url.includes("/repos/")) {
      return url.replace("api.github.com/repos/", "github.com/").replace("/pulls/", "/pull/").replace("/issues/", "/issues/");
    }
    return url;
  }
}
