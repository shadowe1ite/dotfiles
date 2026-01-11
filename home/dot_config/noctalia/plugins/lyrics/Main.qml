import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Media

Item {
  id: root

  property var pluginApi: null

  property string currentLyric: {
    if (!MediaService.currentPlayer)
      return "";
    if (!MediaService.isPlaying)
      return (MediaService.trackTitle && isKnownMusic) ? "Music paused" : "";
    if (isLoading)
      return "Loading...";
    if (!isKnownMusic)
      return "";
    if (lastLyric !== "")
      return lastLyric;
    return "";
  }

  readonly property string trackTitle: MediaService.trackTitle
  readonly property string trackArtist: MediaService.trackArtist
  readonly property string trackAlbum: MediaService.trackAlbum
  readonly property string artUrl: MediaService.trackArtUrl
  readonly property bool isPlaying: MediaService.isPlaying
  readonly property bool hasTrack: MediaService.trackTitle !== ""

  property bool isKnownMusic: false
  property bool isLoading: false

  property string lastLyric: ""
  property string lastTitle: ""
  property bool manualRestart: false

  property var lyricsLines: []
  property int currentLineIndex: -1
  property string lastPlayerName: ""
  readonly property int visibleLinesBefore: 4
  readonly property int visibleLinesAfter: 4

  function addLyricLine(text) {
    if (text === "" || text === lastLyric)
      return;

    var lines = lyricsLines.slice();
    lines.push(text);

    if (lines.length > 50)
      lines.shift();

    lyricsLines = lines;
    currentLineIndex = lines.length - 1;
  }

  function clearLyrics() {
    lyricsLines = [];
    currentLineIndex = -1;
  }

  readonly property var previousLyrics: {
    if (lyricsLines.length === 0 || currentLineIndex < 0)
      return [];
    var prev = [];
    for (var i = Math.max(0, currentLineIndex - visibleLinesBefore); i < currentLineIndex; i++) {
      prev.push(lyricsLines[i]);
    }
    return prev;
  }

  readonly property var upcomingLyrics: {
    return [];
  }

  Timer {
    id: loadTimer
    interval: 5000
    repeat: false
    onTriggered: root.isLoading = false
  }

  Timer {
    id: restartTimer
    interval: 3000
    repeat: false
    onTriggered: sptlrxProc.running = true
  }

  Process {
    id: sptlrxProc
    command: ["sptlrx", "-p", "mpris", "pipe"]
    running: true

    stdout: SplitParser {
      onRead: data => {
                if (!root.isKnownMusic)
                return;

                const cleanText = data.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim();

                if (cleanText !== "" && cleanText !== root.lastLyric) {
                  loadTimer.stop();
                  root.isLoading = false;
                  root.addLyricLine(cleanText);
                  root.lastLyric = cleanText;
                }
              }
    }

    onRunningChanged: {
      if (!running && !root.manualRestart) {
        restartTimer.start();
      }
    }

    onExited: (code, status) => {
                if (root.manualRestart) {
                  root.manualRestart = false;
                  sptlrxProc.running = true;
                }
              }
  }

  Connections {
    target: MediaService

    function onTrackTitleChanged() {
      handleTrackChange();
    }

    function onTrackArtistChanged() {
      handleTrackChange();
    }

    function onCurrentPlayerChanged() {
      const currentPlayerName = MediaService.currentPlayer?.identity ?? "";

      // Player closed
      if (!MediaService.currentPlayer) {
        root.isLoading = false;
        root.isKnownMusic = false;
        loadTimer.stop();
        root.lastTitle = "";
        root.lastLyric = "";
        root.lastPlayerName = "";
        root.clearLyrics();

        // Stop sptlrx when no player
        root.manualRestart = false;
        sptlrxProc.running = false;
        restartTimer.stop();
        return;
      }

      // Player switched to a different one
      if (root.lastPlayerName !== "" && currentPlayerName !== root.lastPlayerName) {
        root.isLoading = false;
        root.isKnownMusic = false;
        loadTimer.stop();
        root.lastTitle = "";
        root.lastLyric = "";
        root.clearLyrics();

        // Restart sptlrx to pick up new player
        root.manualRestart = true;
        sptlrxProc.running = false;
      }

      root.lastPlayerName = currentPlayerName;
      handleTrackChange();
    }

    function onIsPlayingChanged() {
      if (!MediaService.isPlaying) {
        root.isLoading = false;
        loadTimer.stop();
      }
    }
  }

  function handleTrackChange() {
    const title = MediaService.trackTitle;
    const artist = MediaService.trackArtist;

    if (title !== root.lastTitle || artist !== root.trackArtist) {
      root.lastTitle = title;
      root.isKnownMusic = artist.trim() !== "";
      root.lastLyric = "";
      root.clearLyrics();

      if (root.isKnownMusic) {
        root.isLoading = true;
        loadTimer.restart();

        // Restart sptlrx to quickly pick up the new track
        root.manualRestart = true;
        sptlrxProc.running = false;
      } else {
        root.isLoading = false;
        loadTimer.stop();
      }
    }
  }

  Component.onCompleted: {
    Logger.i("Lyrics", "Plugin initialized");
    handleTrackChange();
  }
}
