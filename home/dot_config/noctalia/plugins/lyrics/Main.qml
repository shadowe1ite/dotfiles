import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    property var pluginApi: null
    property string lastLyric: ""
    property bool isKnownMusic: false
    property string lastTitle: ""
    property string lastPlayer: ""
    property bool manualRestart: false
    property bool isLoading: false
    property string playStatus: "Stopped"

    property string currentLyric: {
        if (playStatus === "Stopped" || playStatus === "")
            return "No Lyrics";
        if (playStatus === "Paused")
            return isKnownMusic ? "Music paused" : "No Lyrics";

        if (isLoading)
            return "Wait Loading 🪿";
        if (!isKnownMusic)
            return "No Lyrics";
        if (lastLyric !== "")
            return lastLyric;

        return "Lyrics not found 🥲";
    }

    Timer {
        id: loadTimer
        interval: 5000
        repeat: false
        onTriggered: root.isLoading = false
    }

    Process {
        id: sptlrxProc
        command: ["stdbuf", "-oL", "sptlrx", "-p", "mpris", "pipe"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const cleanText = data.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "").trim();

                if (!root.isKnownMusic)
                    return;

                if (cleanText !== "") {
                    loadTimer.stop();
                    root.isLoading = false;
                    root.lastLyric = cleanText;
                }
            }
        }

        onExited: (code, status) => {
            if (root.manualRestart) {
                root.manualRestart = false;
                sptlrxProc.running = true;
            } else {
                restartTimer.start();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        repeat: false
        onTriggered: sptlrxProc.running = true
    }

    Process {
        id: statusProc
        command: ["playerctl", "metadata", "--format", "{{ playerName }}:::{{ status }}:::{{ xesam:artist }}:::{{ xesam:title }}", "-F"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(":::");
                const playerName = parts[0] || "";
                const status = parts[1] || "";
                const artist = parts[2] || "";
                const title = parts[3] || "";

                root.playStatus = status;

                if (!status || status === "Stopped") {
                    root.isLoading = false;
                    loadTimer.stop();
                    return;
                }

                if (root.lastPlayer !== "" && root.lastPlayer !== playerName) {
                    root.manualRestart = true;
                    sptlrxProc.running = false;

                    root.lastTitle = "";
                    root.lastLyric = "";
                }
                root.lastPlayer = playerName;

                if (title !== root.lastTitle) {
                    root.lastTitle = title;
                    root.isKnownMusic = (artist.trim() !== "");
                    root.lastLyric = "";

                    if (root.isKnownMusic) {
                        root.isLoading = true;
                        loadTimer.restart();
                    } else {
                        root.isLoading = false;
                        loadTimer.stop();
                    }
                }

                if (status !== "Playing") {
                    root.isLoading = false;
                    loadTimer.stop();
                }
            }
        }
    }
}
