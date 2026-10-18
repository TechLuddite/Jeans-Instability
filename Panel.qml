import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Jeans Instability: which of your enabled third-party plugins live in a
// GitHub repository you have not starred.
//
// All file reading and network access happens in bin/jeans-instability, a
// separate Python process with fixed paths, a single API host, response caps
// and an overall deadline. This panel only starts it, reads at most
// maxReportChars of its JSON output, and shows the result. Nothing is
// written to disk. The only change made on GitHub is a star, and only when
// you click a row's star.
Panel {
  id: root
  moduleName: "io.github.techluddite.jeans-instability"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string pluginDir:
    String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  // A fixed PATH plus what the helper needs: the Wayland display and runtime
  // directory to reach the shell's IPC for the plugin list, OMARCHY_PATH for
  // where that IPC lives, and the config directory and session bus so gh can
  // read its stored login. The helper reads the token from gh's output
  // itself, so it never passes through this panel.
  readonly property var processEnvironment: ({
    PATH: "/usr/bin:/bin",
    HOME: Quickshell.env("HOME"),
    LANG: "C.UTF-8",
    OMARCHY_PATH: Quickshell.env("OMARCHY_PATH") || "",
    WAYLAND_DISPLAY: Quickshell.env("WAYLAND_DISPLAY") || "",
    XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME") || "",
    XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || "",
    DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS") || ""
  })

  readonly property int maxReportChars: 262144
  readonly property int maxErrorChars: 2000
  readonly property int maxRows: 200
  readonly property int staleAfterMs: 10 * 60 * 1000

  property string reportBuffer: ""
  property string errorBuffer: ""
  property bool overflowed: false
  property int generation: 0
  property bool running: false
  property double checkedAt: 0

  property string login: ""
  property var unstarredRows: []
  property var starredRows: []
  property var otherRows: []
  property int ownExcluded: 0
  // Repositories starred from this panel since the last check, as
  // { "owner/repo": true }. Their rows stay, with a filled star, until the
  // next check drops them from the list.
  property var justStarred: ({})
  property string starringRepo: ""
  property string starBuffer: ""
  property int starGeneration: 0
  readonly property int maxStarChars: 4096
  signal starFinished(string repo, bool ok)
  property string errorText: ""
  readonly property int unstarredCount: {
    var n = 0
    for (var i = 0; i < unstarredRows.length; i++) if (!justStarred[unstarredRows[i].repo]) n++
    return n
  }

  readonly property color foreground: bar ? bar.foreground : Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var repoPattern: /^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9._-]{1,100}$/

  function startCheck() {
    if (root.running || root.starringRepo !== "") return
    root.generation += 1
    root.reportBuffer = ""
    root.errorBuffer = ""
    root.overflowed = false
    root.errorText = ""
    root.running = true
    checkProc.runGeneration = root.generation
    checkProc.command = ["/usr/bin/timeout", "-k", "5", "90",
                         "/usr/bin/python3", "-I", "-S", root.pluginDir + "/bin/jeans-instability", "--json"]
    checkProc.running = true
  }

  function stopCheck() {
    if (checkProc.running) checkProc.running = false
    root.running = false
  }

  function text(v, max) {
    return typeof v === "string" ? v.slice(0, max) : ""
  }

  function finish(code, gen) {
    if (gen !== root.generation) return
    root.running = false
    if (root.overflowed) {
      root.errorText = "The helper printed more than the panel accepts."
      return
    }
    var data = null
    try { data = JSON.parse(root.reportBuffer) } catch (e) { data = null }
    root.reportBuffer = ""
    if (data && typeof data.error === "string") {
      root.errorText = data.error.slice(0, 300)
      return
    }
    if (!data || !Array.isArray(data.plugins) || data.plugins.length > root.maxRows) {
      if (code === 124 || code === 137) root.errorText = "GitHub took longer than 90 seconds. Try again."
      else {
        var err = root.errorBuffer.trim().slice(0, 300)
        root.errorText = err !== "" ? err : "The check failed (exit " + code + ")."
      }
      return
    }
    var unstarred = [], starred = [], other = []
    for (var i = 0; i < data.plugins.length; i++) {
      var p = data.plugins[i]
      if (!p || typeof p !== "object") continue
      var row = {
        name: root.text(p.name, 80) || root.text(p.id, 128),
        repo: root.repoPattern.test(String(p.repo)) ? String(p.repo) : "",
        note: root.text(p.note, 80)
      }
      if (p.starred === false && row.repo !== "") unstarred.push(row)
      else if (p.starred === true && row.repo !== "") starred.push(row)
      else other.push(row)
    }
    root.login = root.text(data.login, 39)
    root.ownExcluded = Math.max(0, Math.min(Number(data.ownExcluded) || 0, root.maxRows))
    root.unstarredRows = unstarred
    root.starredRows = starred
    root.otherRows = other
    root.justStarred = ({})
    root.checkedAt = Date.now()
  }

  // Star one repository through the helper, which checks again that it is an
  // enabled plugin's unstarred repository before sending the PUT.
  function requestStar(repo) {
    if (root.starringRepo !== "" || !root.repoPattern.test(repo)) {
      root.starFinished(repo, false)
      return
    }
    root.starGeneration += 1
    root.starringRepo = repo
    root.starBuffer = ""
    root.errorText = ""
    starProc.runGeneration = root.starGeneration
    starProc.runRepo = repo
    starProc.command = ["/usr/bin/timeout", "-k", "5", "90",
                        "/usr/bin/python3", "-I", "-S", root.pluginDir + "/bin/jeans-instability", "--json", "--star", repo]
    starProc.running = true
  }

  function finishStar(code, gen, repo) {
    if (gen !== root.starGeneration) return
    var data = null
    try { data = JSON.parse(root.starBuffer) } catch (e) { data = null }
    root.starBuffer = ""
    root.starringRepo = ""
    var ok = code === 0 && data !== null && typeof data.starred === "string"
      && data.starred.toLowerCase() === repo.toLowerCase()
    if (ok) {
      var copy = Object.assign({}, root.justStarred)
      copy[repo] = true
      root.justStarred = copy
    } else {
      root.errorText = data && typeof data.error === "string"
        ? data.error.slice(0, 300) : "Starring " + repo + " failed (exit " + code + ")."
    }
    root.starFinished(repo, ok)
  }

  function openRepo(repo) {
    if (root.repoPattern.test(repo)) Qt.openUrlExternally("https://github.com/" + repo)
  }

  onOpenedChanged: {
    if (opened && !running && Date.now() - checkedAt > staleAfterMs) startCheck()
    if (opened) Qt.callLater(function () { keys.forceActiveFocus() })
  }

  Component.onDestruction: {
    stopCheck()
    if (starProc.running) starProc.running = false
  }

  Process {
    id: starProc
    property int runGeneration: 0
    property string runRepo: ""
    clearEnvironment: true
    environment: root.processEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function (chunk) {
        if (starProc.runGeneration !== root.starGeneration) return
        if (root.starBuffer.length + chunk.length > root.maxStarChars) {
          root.starBuffer = ""
          starProc.signal(15)
          return
        }
        root.starBuffer += chunk
      }
    }
    onExited: function (code) { root.finishStar(code, starProc.runGeneration, starProc.runRepo) }
  }

  // One check shortly after the shell starts so the bar count is right, then
  // every six hours. Opening the panel refreshes anything older than ten minutes.
  Timer {
    interval: 8000
    running: true
    onTriggered: root.startCheck()
  }
  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.startCheck()
  }

  Process {
    id: checkProc
    property int runGeneration: 0
    clearEnvironment: true
    environment: root.processEnvironment
    stdout: SplitParser {
      splitMarker: ""
      onRead: function (chunk) {
        if (checkProc.runGeneration !== root.generation || root.overflowed) return
        if (root.reportBuffer.length + chunk.length > root.maxReportChars) {
          root.overflowed = true
          root.reportBuffer = ""
          checkProc.signal(15)
          return
        }
        root.reportBuffer += chunk
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function (chunk) {
        if (root.errorBuffer.length < root.maxErrorChars)
          root.errorBuffer = (root.errorBuffer + chunk).slice(0, root.maxErrorChars)
      }
    }
    onExited: function (code) { root.finish(code, checkProc.runGeneration) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_R) { root.startCheck(); event.accepted = true }
      }

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.md

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          ColumnLayout {
            spacing: Style.spacing.xs
            // Halfway between the title and display sizes, in the theme's accent.
            Plain {
              text: "Jeans Instability"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Math.round((Style.font.title + Style.font.display) / 2)
              font.bold: true
            }
            Plain {
              text: root.login !== ""
                ? "Enabled plugins whose repository " + root.login + " has not starred."
                : "Enabled plugins whose repository you have not starred."
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item { Layout.fillWidth: true }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: "Check again (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.startCheck()
          }
          PanelActionButton {
            iconText: "󰅖"
            tooltipText: "Close (Esc)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.close()
          }
        }

        // Sets the header apart from the list below it.
        PanelSeparator {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xs
          Layout.bottomMargin: Style.spacing.xs
          foreground: root.foreground
        }

        Plain {
          Layout.fillWidth: true
          visible: root.running || root.errorText !== ""
          text: root.running ? "Checking GitHub." : root.errorText
          color: root.errorText !== "" && !root.running ? root.urgent : root.foreground
          opacity: root.running ? 0.7 : 1.0
          font.family: root.fontFamily
        }

        Plain {
          Layout.fillWidth: true
          visible: !root.running && root.errorText === "" && root.checkedAt > 0 && root.unstarredRows.length === 0
          text: "You have starred the repository of every enabled plugin."
          color: root.foreground
          font.family: root.fontFamily
        }

        Flickable {
          Layout.fillWidth: true
          Layout.fillHeight: true
          implicitHeight: body.implicitHeight
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: body
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: root.unstarredRows
              delegate: StarRow {
                id: entry
                required property var modelData
                name: modelData.name
                repo: modelData.repo
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                busy: root.starringRepo !== ""
                confirmed: root.justStarred[modelData.repo] === true
                onStarClicked: root.requestStar(repo)
                onOpenClicked: root.openRepo(repo)
                Connections {
                  target: root
                  function onStarFinished(repo, ok) { if (repo === entry.repo) entry.finish(ok) }
                }
              }
            }

            PanelSeparator {
              Layout.fillWidth: true
              foreground: root.foreground
              visible: root.otherRows.length > 0
            }

            Repeater {
              model: root.otherRows
              delegate: Plain {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.name + ": " + modelData.note
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Plain {
          Layout.fillWidth: true
          visible: root.checkedAt > 0
          text: (root.starredRows.length + Object.keys(root.justStarred).length) + " already starred"
            + (root.ownExcluded > 0 ? ", " + root.ownExcluded + " in your own repositories left out" : "")
            + ". Click a name to open it on GitHub, or the star to star it."
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
