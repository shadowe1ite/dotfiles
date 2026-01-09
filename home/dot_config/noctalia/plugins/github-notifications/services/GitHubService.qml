pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: service

  // Configuration - set by BarWidget on init
  property string githubToken: ""
  property int checkInterval: 300
  property bool showOnlyUnread: false
  property int maxNotifications: 30

  // Shared state - both BarWidget and Panel read from here
  property var notifications: []
  property int unreadCount: 0
  property bool loading: false
  property bool error: false
  property string errorMessage: ""

  // Internal state for actor fetching
  property var _actorFetchQueue: []
  property int _activeFetches: 0
  property int _maxConcurrentFetches: 3

  // Fetch process
  property var _fetchProcess: Process {
    id: fetchProcess
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    property bool isFetching: false

    onExited: exitCode => {
      if (!isFetching)
      return;
      isFetching = false;

      if (exitCode !== 0 || !stdout.text || stdout.text.trim() === "") {
        service.loading = false;
        service.error = true;
        service.errorMessage = "Failed to fetch";
        return;
      }

      try {
        const data = JSON.parse(stdout.text);
        if (data && data.message) {
          service.loading = false;
          service.error = true;
          service.errorMessage = data.message;
          service.notifications = [];
          service.unreadCount = 0;
          return;
        }

        if (Array.isArray(data)) {
          var notifs = data.slice(0, service.maxNotifications);
          service.notifications = notifs;
          service.unreadCount = data.filter(n => n.unread).length;
          service.error = false;
          service.errorMessage = "";

          // Now fetch actor avatars for each notification
          service._fetchActorAvatars(notifs);
        } else {
          service.loading = false;
          service.error = true;
          service.errorMessage = "Invalid response";
        }
      } catch (e) {
        service.loading = false;
        service.error = true;
        service.errorMessage = "Parse error";
      }
    }
  }

  function _fetchActorAvatars(notifs) {
    // Build queue of notifications that need actor fetching
    service._actorFetchQueue = [];

    for (var i = 0; i < notifs.length; i++) {
      var notif = notifs[i];
      // Try to get latest_comment_url first, fall back to subject.url
      var url = notif.subject?.latest_comment_url || notif.subject?.url;
      if (url && notif.id) {
        service._actorFetchQueue.push({
                                        id: notif.id,
                                        url: url
                                      });
      }
    }

    // Start fetching (with concurrency limit)
    if (service._actorFetchQueue.length > 0) {
      service._processActorQueue();
    } else {
      service.loading = false;
    }
  }

  function _processActorQueue() {
    while (service._activeFetches < service._maxConcurrentFetches && service._actorFetchQueue.length > 0) {
      var item = service._actorFetchQueue.shift();
      service._fetchSingleActor(item.id, item.url);
    }

    // Check if all done
    if (service._activeFetches === 0 && service._actorFetchQueue.length === 0) {
      service.loading = false;
    }
  }

  function _fetchSingleActor(notificationId, url) {
    service._activeFetches++;

    // Find available process from pool
    var proc = null;
    for (var i = 0; i < _actorProcessPool.length; i++) {
      if (!_actorProcessPool[i].busy) {
        proc = _actorProcessPool[i];
        break;
      }
    }

    if (!proc) {
      // All busy, requeue
      service._activeFetches--;
      service._actorFetchQueue.unshift({
                                         id: notificationId,
                                         url: url
                                       });
      return;
    }

    proc.busy = true;
    proc.notificationId = notificationId;
    proc.command = ["curl", "-s", "-H", "Authorization: token " + service.githubToken, "-H", "Accept: application/vnd.github.v3+json", url];
    proc.running = true;
  }

  function _onActorFetched(notificationId, avatarUrl) {
    if (!avatarUrl)
      return;

    // Update the notification with the actor avatar
    var updated = [];
    var changed = false;
    for (var i = 0; i < notifications.length; i++) {
      var notif = notifications[i];
      if (notif.id === notificationId && !notif.actorAvatarUrl) {
        var copy = JSON.parse(JSON.stringify(notif));
        copy.actorAvatarUrl = avatarUrl;
        updated.push(copy);
        changed = true;
      } else {
        updated.push(notif);
      }
    }

    if (changed) {
      notifications = updated;
    }
  }

  // Actor fetch process pool
  property var _actorProcessPool: []
  property int _poolSize: 5

  Component.onCompleted: {
    // Create process pool for actor fetching
    for (var i = 0; i < _poolSize; i++) {
      var proc = actorProcessComponent.createObject(service, {
                                                      poolIndex: i
                                                    });
      _actorProcessPool.push(proc);
    }
  }

  property var actorProcessComponent: Component {
    Process {
      property int poolIndex: 0
      property string notificationId: ""
      property bool busy: false

      running: false
      stdout: StdioCollector {}
      stderr: StdioCollector {}

      onExited: exitCode => {
        busy = false;
        service._activeFetches--;

        if (exitCode === 0 && stdout.text) {
          try {
            var data = JSON.parse(stdout.text);
            // Handle different response types
            var avatarUrl = "";
            if (data.user?.avatar_url) {
              // Comment response
              avatarUrl = data.user.avatar_url;
            } else if (data.actor?.avatar_url) {
              // Event response
              avatarUrl = data.actor.avatar_url;
            } else if (data.author?.avatar_url) {
              // Commit response
              avatarUrl = data.author.avatar_url;
            } else if (data.avatar_url) {
              // Direct user response
              avatarUrl = data.avatar_url;
            }

            if (avatarUrl && notificationId) {
              service._onActorFetched(notificationId, avatarUrl);
            }
          } catch (e) {
            // Silently fail, will use fallback avatar
          }
        }

        service._processActorQueue();
      }
    }
  }

  // Mark single notification as read
  property var _markReadProcess: Process {
    id: markReadProcess
    running: false
    stdout: StdioCollector {}
  }

  // Mark all as read
  property var _markAllReadProcess: Process {
    id: markAllReadProcess
    running: false
    stdout: StdioCollector {}
  }

  function refresh() {
    if (!githubToken || loading)
      return;

    loading = true;
    error = false;
    errorMessage = "";

    // Reset actor fetch state
    _actorFetchQueue = [];
    _activeFetches = 0;

    const url = showOnlyUnread ? "https://api.github.com/notifications" : "https://api.github.com/notifications?all=true";

    fetchProcess.command = ["curl", "-s", "-H", "Authorization: token " + githubToken, "-H", "Accept: application/vnd.github.v3+json", url];
    fetchProcess.isFetching = true;
    fetchProcess.running = true;
  }

  function markAsRead(notificationId) {
    if (!githubToken)
      return;

    // Optimistic update
    var updated = [];
    for (var i = 0; i < notifications.length; i++) {
      var notif = notifications[i];
      if (notif.id === notificationId) {
        var copy = JSON.parse(JSON.stringify(notif));
        copy.unread = false;
        updated.push(copy);
      } else {
        updated.push(notif);
      }
    }
    notifications = updated;
    unreadCount = updated.filter(n => n.unread).length;

    // API call
    const url = "https://api.github.com/notifications/threads/" + notificationId;
    markReadProcess.command = ["curl", "-s", "-X", "PATCH", "-H", "Authorization: token " + githubToken, "-H", "Accept: application/vnd.github.v3+json", url];
    markReadProcess.running = true;
  }

  function markAllAsRead() {
    if (!githubToken)
      return;

    // Optimistic update
    var updated = [];
    for (var i = 0; i < notifications.length; i++) {
      var copy = JSON.parse(JSON.stringify(notifications[i]));
      copy.unread = false;
      updated.push(copy);
    }
    notifications = updated;
    unreadCount = 0;

    // API call
    const url = "https://api.github.com/notifications";
    markAllReadProcess.command = ["curl", "-s", "-X", "PUT", "-H", "Authorization: token " + githubToken, "-H", "Accept: application/vnd.github.v3+json", url];
    markAllReadProcess.running = true;
  }
}
