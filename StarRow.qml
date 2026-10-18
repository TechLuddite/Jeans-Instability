import QtQuick
import QtQuick.Layouts
import qs.Commons

// One unstarred repository: its plugin name and repository on the left, an
// empty star on the right. Clicking the star dissolves the text into braille
// gas that flows into the star while the star collapses to a dot. When the
// panel reports that GitHub accepted the star, the dot bursts into a filled
// star in the theme's accent colour. If GitHub refuses, the row comes back
// with the empty star.
Item {
  id: row

  property string name: ""
  property string repo: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // True while any star request is in flight, so only one runs at a time.
  property bool busy: false
  // True while the panel counts this repository as starred from here. A new
  // check clears it, and the row goes back to the empty star even if the
  // Repeater reuses this delegate for the same repository.
  property bool confirmed: false
  onConfirmedChanged: if (!confirmed && phase === "starred") reset()

  signal starClicked()
  signal openClicked()

  // idle -> collapsing -> waiting -> bursting -> starred, or back to idle.
  property string phase: "idle"
  property bool resultKnown: false
  property bool resultOk: false
  property real flow: 0
  property real burst: 0
  property real burstScale: 1
  property var particles: []
  property var sparks: []
  property string braille: ""

  readonly property string emptyStar: String.fromCodePoint(0xF04D2)
  readonly property string filledStar: String.fromCodePoint(0xF04CE)

  Layout.fillWidth: true
  implicitHeight: Math.max(textColumn.implicitHeight, starGlyph.implicitHeight) + Style.spacing.sm

  // Called by the panel when the helper finishes.
  function finish(ok) {
    resultKnown = true
    resultOk = ok
    if (phase === "waiting") settle()
  }

  function settle() {
    if (resultOk) {
      phase = "bursting"
      burstAnim.restart()
    } else {
      reset()
    }
  }

  function reset() {
    flowAnim.stop()
    burstAnim.stop()
    phase = "idle"
    flow = 0
    burst = 0
    braille = ""
    particles = []
    sparks = []
  }

  function start() {
    if (phase !== "idle" || busy) return
    resultKnown = false
    resultOk = false
    seed()
    phase = "collapsing"
    starClicked()
    flowAnim.restart()
  }

  // Braille cells across the text column, two text lines tall: each cell is
  // two dots wide and four high, so the gas field is 2*cols by 8 dots.
  readonly property int cols: Math.max(4, Math.floor(textColumn.width / Math.max(1, cellMetrics.advanceWidth)))

  // One or two particles per visible character, placed where the character
  // sits: the plugin name in the top half, the repository in the bottom half.
  function seed() {
    var out = []
    var lines = [name, "github.com/" + repo]
    for (var l = 0; l < 2; l++) {
      var s = lines[l]
      var n = Math.min(s.length, cols)
      for (var i = 0; i < n; i++) {
        if (s.charAt(i) === " ") continue
        for (var k = 0; k < 2; k++) {
          out.push({
            x0: 2 * i + Math.random() * 2,
            y0: 4 * l + Math.random() * 4,
            delay: (1 - i / Math.max(1, cols)) * 0.4 + Math.random() * 0.08,
            phase: Math.random() * 6.283,
            swirl: 0.8 + Math.random() * 1.6
          })
        }
      }
    }
    particles = out
  }

  function render() {
    var w = cols * 2
    var cells = []
    for (var c = 0; c < cols * 2; c++) cells.push(0)
    // Braille dot bits by (column, row) inside a cell.
    var bits = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]]
    function plot(x, y) {
      var xi = Math.round(x), yi = Math.round(y)
      if (xi < 0 || xi >= w || yi < 0 || yi > 7) return
      var cell = Math.floor(yi / 4) * cols + Math.floor(xi / 2)
      cells[cell] |= bits[xi % 2][yi % 4]
    }
    var tx = w - 1, ty = 3.5
    if (phase === "collapsing" || phase === "waiting") {
      for (var i = 0; i < particles.length; i++) {
        var p = particles[i]
        var u = Math.max(0, Math.min(1, (flow - p.delay) / 0.55))
        if (u >= 1) continue
        var e = u * u
        var wobble = Math.sin(p.phase + u * 9.4) * p.swirl * (1 - e)
        plot(p.x0 + (tx - p.x0) * e, p.y0 + (ty - p.y0) * e + wobble)
      }
    } else if (phase === "bursting") {
      for (var j = 0; j < sparks.length; j++) {
        var s = sparks[j]
        if (burst > s.life) continue
        plot(tx + Math.cos(s.angle) * s.speed * burst * 14, ty + Math.sin(s.angle) * s.speed * burst * 5)
      }
    }
    var lines = []
    for (var r = 0; r < 2; r++) {
      var line = ""
      for (var q = 0; q < cols; q++) line += String.fromCharCode(0x2800 + cells[r * cols + q])
      lines.push(line)
    }
    braille = lines.join("\n")
  }

  onFlowChanged: if (phase === "collapsing" || phase === "waiting") render()
  onBurstChanged: if (phase === "bursting") render()

  TextMetrics {
    id: cellMetrics
    font.family: row.fontFamily
    font.pixelSize: brailleText.font.pixelSize
    text: "⣿"
  }

  NumberAnimation {
    id: flowAnim
    target: row
    property: "flow"
    from: 0
    to: 1
    duration: 1800
    easing.type: Easing.Linear
    onFinished: {
      if (row.phase !== "collapsing") return
      row.phase = "waiting"
      row.braille = ""
      if (row.resultKnown) row.settle()
    }
  }

  SequentialAnimation {
    id: burstAnim
    ScriptAction {
      script: {
        var out = []
        for (var i = 0; i < 28; i++)
          out.push({ angle: Math.PI / 2 + Math.random() * Math.PI, speed: 0.4 + Math.random() * 0.6, life: 0.5 + Math.random() * 0.5 })
        row.sparks = out
        row.burst = 0
      }
    }
    ParallelAnimation {
      NumberAnimation { target: row; property: "burst"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
      SequentialAnimation {
        NumberAnimation { target: row; property: "burstScale"; from: 0.1; to: 1.5; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: row; property: "burstScale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
      }
    }
    ScriptAction {
      script: {
        row.phase = "starred"
        row.braille = ""
        row.sparks = []
      }
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: Style.spacing.sm

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      ColumnLayout {
        id: textColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: row.phase === "idle" || row.phase === "starred" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Plain {
          Layout.fillWidth: true
          text: row.name
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
          color: openArea.containsMouse ? row.accent : row.foreground
          font.family: row.fontFamily
        }
        Plain {
          Layout.fillWidth: true
          text: "github.com/" + row.repo
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
          color: row.foreground
          opacity: 0.6
          font.family: row.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Plain {
        id: brailleText
        anchors.fill: textColumn
        visible: row.braille !== ""
        text: row.braille
        wrapMode: Text.NoWrap
        color: row.accent
        font.family: row.fontFamily
        font.pixelSize: Math.max(6, Math.floor(textColumn.height / 2 / 1.25))
        lineHeightMode: Text.FixedHeight
        lineHeight: textColumn.height / 2
      }

      MouseArea {
        id: openArea
        anchors.fill: textColumn
        enabled: row.phase === "idle" || row.phase === "starred"
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.openClicked()
      }
    }

    Item {
      Layout.preferredWidth: starGlyph.implicitWidth
      Layout.fillHeight: true

      Plain {
        id: starGlyph
        anchors.centerIn: parent
        transformOrigin: Item.Center
        wrapMode: Text.NoWrap
        text: row.phase === "bursting" || row.phase === "starred" ? row.filledStar : row.emptyStar
        color: row.phase === "bursting" || row.phase === "starred" ? row.accent
          : (starArea.containsMouse && !row.busy ? row.accent : row.foreground)
        visible: row.phase !== "waiting"
        // The star shrinks with the gas flowing in, down to a dot's size.
        scale: row.phase === "collapsing" ? 1 - 0.9 * row.flow : (row.phase === "bursting" ? row.burstScale : 1)
        font.family: row.fontFamily
        font.pixelSize: Style.font.title
      }

      // The collapsed star: a dot that pulses while GitHub answers.
      Rectangle {
        anchors.centerIn: parent
        visible: row.phase === "waiting"
        width: Math.max(3, Style.space(4))
        height: width
        radius: width / 2
        color: row.accent
        SequentialAnimation on opacity {
          running: row.phase === "waiting"
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 380 }
          NumberAnimation { to: 1.0; duration: 380 }
        }
      }

      MouseArea {
        id: starArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.phase === "idle" && !row.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: row.start()
      }
    }
  }
}
