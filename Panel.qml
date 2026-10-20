import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// TMOG-style system summary: SYS gauges, CPU overview, top processes, memory,
// pressure, network, disk and GPU. A small sampler runs only while the panel is open.
Panel {
  id: root

  moduleName: "io.github.rodrigondec.tmog"
  ipcTarget: "io.github.rodrigondec.tmog"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property bool expanded: false
  property var snap: null
  property var cpuHistory: []
  property var memHistory: []
  property var coreHistory: []

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Color.muted
  readonly property int historySamples: Math.max(20, Math.min(240,
    Math.round(Number(setting("historySamples", 60)) || 60)))
  readonly property int processCount: Math.max(3, Math.min(25,
    Math.round(Number(setting("processCount", 10)) || 10)))
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string samplerPath: decodeURIComponent(
    String(Qt.resolvedUrl("tmog-sampler")).replace("file://", ""))

  function load(color, value) {
    return value >= 85 ? urgent : (value >= 60 ? "#e0a030" : color)
  }

  function bytes(value, suffix) {
    var v = Number(value) || 0
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (i === 0 ? Math.round(v) : v.toFixed(v >= 100 ? 0 : 1)) + " " + units[i] + (suffix || "")
  }

  function push(list, value) {
    var next = list.concat([value])
    return next.length > historySamples ? next.slice(next.length - historySamples) : next
  }

  function consume(line) {
    var s
    try { s = JSON.parse(line) } catch (e) { return }
    cpuHistory = push(cpuHistory, s.cpu)
    memHistory = push(memHistory, s.mem.total ? 100 * s.mem.used / s.mem.total : 0)
    var ch = coreHistory.slice()
    for (var i = 0; i < s.cores.length; i++)
      ch[i] = push(ch[i] || [], s.cores[i])
    coreHistory = ch
    snap = s
  }

  function toggleExpanded() { expanded = !expanded }

  onOpenedChanged: {
    if (opened) {
      snap = null; cpuHistory = []; memHistory = []; coreHistory = []
    } else {
      expanded = false
    }
  }

  Process {
    id: sampler
    running: root.opened
    command: [root.samplerPath, String(root.processCount)]
    stdout: SplitParser { onRead: function(line) { root.consume(line) } }
  }

  Process {
    id: launcher
    // Focus the running TMOG window, otherwise start the app.
    command: ["bash", "-c",
      "hyprctl clients -j | grep -q com.tmog.taskmanager "
      + "&& hyprctl dispatch 'hl.dsp.focus({ window = \"class:com.tmog.taskmanager\" })' "
      + "|| gtk-launch tmog"]
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐰"
    tooltipText: "TMOG"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && root.setting("openTmogOnMiddleClick", true))
        launcher.running = true
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(root.expanded ? Style.space(760) : Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onActivateRequested: root.toggleExpanded()
      onCloseRequested: root.expanded ? root.toggleExpanded() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (String(text).toLowerCase() === "e") root.toggleExpanded()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        // Header
        Row {
          width: parent.width
          Text {
            text: "TMOG"
            color: root.accent
            font.family: root.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Item { width: parent.width - openButton.width - hint.implicitWidth - 48 - Style.spacing.lg; height: 1 }
          Rectangle {
            id: openButton
            width: openLabel.implicitWidth + Style.space(16)
            height: openLabel.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: openArea.containsMouse ? Util.alpha(root.accent, 0.25) : Util.alpha(root.foreground, 0.08)
            border.width: 1
            border.color: Util.alpha(root.accent, 0.5)
            Text {
              id: openLabel
              anchors.centerIn: parent
              text: "open TMOG"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: openArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                launcher.running = true
                root.close()
              }
            }
          }
          Item { width: Style.spacing.lg; height: 1 }
          Text {
            id: hint
            text: root.expanded ? "e  collapse" : "e  per-core"
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        // SYS gauges + CPU overview
        Row {
          width: parent.width
          height: Style.space(110)
          spacing: Style.spacing.md

          Row {
            id: gauges
            height: parent.height
            spacing: Style.spacing.md
            Repeater {
              model: [
                { k: "CPU", v: root.snap ? root.snap.cpu : 0, t: root.snap ? Math.round(root.snap.cpu) + "%" : "—" },
                { k: "CLK", v: root.snap ? Math.min(100, root.snap.mhz / 50) : 0, t: root.snap ? (root.snap.mhz / 1000).toFixed(1) + "G" : "—" },
                { k: "TMP", v: root.snap && root.snap.temp ? Math.min(100, root.snap.temp) : 0, t: root.snap && root.snap.temp ? Math.round(root.snap.temp) + "°" : "—" },
                { k: "GPU", v: root.snap && root.snap.gpu && root.snap.gpu.util !== undefined && root.snap.gpu.util !== null ? root.snap.gpu.util : 0, t: root.snap && root.snap.gpu && root.snap.gpu.util !== undefined && root.snap.gpu.util !== null ? Math.round(root.snap.gpu.util) + "%" : "—" }
              ]
              delegate: Column {
                width: Style.space(30)
                height: gauges.height
                spacing: Style.spacing.sm
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.k
                  color: root.dim
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }
                Item {
                  width: Style.space(14)
                  height: parent.height - Style.space(36)
                  anchors.horizontalCenter: parent.horizontalCenter
                  Rectangle { anchors.fill: parent; color: Util.alpha(root.foreground, 0.08); radius: 2 }
                  Rectangle {
                    width: parent.width
                    height: parent.height * Math.max(0, Math.min(100, modelData.v)) / 100
                    anchors.bottom: parent.bottom
                    radius: 2
                    color: root.load(root.accent, modelData.v)
                  }
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.t
                  color: root.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          Column {
            width: parent.width - gauges.width - parent.spacing
            height: parent.height
            spacing: Style.spacing.sm
            Row {
              width: parent.width
              Text {
                text: "CPU OVERVIEW"
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
              }
              Item { width: parent.width - cpuNow.implicitWidth - 110; height: 1 }
              Text {
                id: cpuNow
                text: root.snap ? root.snap.cpu.toFixed(1) + "%" : "—"
                color: root.load(root.accent, root.snap ? root.snap.cpu : 0)
                font.family: root.family
                font.pixelSize: Style.font.body
              }
            }
            Sparkline {
              width: parent.width
              height: parent.height - Style.space(18)
              values: root.cpuHistory
              ceiling: 100
              lineColor: root.accent
            }
          }
        }

        // Per-core grid (expanded)
        Grid {
          visible: root.expanded
          width: parent.width
          columns: 8
          spacing: Style.spacing.sm
          Repeater {
            model: root.expanded ? root.coreHistory.length : 0
            delegate: Column {
              width: (content.width - 7 * Style.spacing.sm) / 8
              spacing: 2
              Text {
                text: "CPU " + index
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.bodySmall
              }
              Sparkline {
                width: parent.width
                height: Style.space(34)
                values: root.coreHistory[index] || []
                ceiling: 100
                lineColor: root.accent
              }
            }
          }
        }

        // Top processes
        Column {
          width: parent.width
          spacing: 2
          Row {
            width: parent.width
            Text { width: parent.width * 0.14; text: "PID"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall }
            Text { width: parent.width * 0.46; text: "TOP CPU PROCESSES"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall }
            Text { width: parent.width * 0.16; text: "CPU"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignRight }
            Text { width: parent.width * 0.24; text: "MEMORY"; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignRight }
          }
          Repeater {
            model: root.snap ? root.snap.processes : []
            delegate: Row {
              width: content.width
              Text { width: parent.width * 0.14; text: modelData.pid; color: root.dim; font.family: root.family; font.pixelSize: Style.font.body }
              Text { width: parent.width * 0.46; text: modelData.name; color: root.foreground; elide: Text.ElideRight; font.family: root.family; font.pixelSize: Style.font.body }
              Text { width: parent.width * 0.16; text: modelData.cpu.toFixed(1) + "%"; color: root.load(root.foreground, modelData.cpu * 4); font.family: root.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
              Text { width: parent.width * 0.24; text: root.bytes(modelData.mem); color: root.foreground; font.family: root.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignRight }
            }
          }
        }

        // Memory
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Row {
            width: parent.width
            Text {
              text: "MEMORY"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
            }
            Item { width: parent.width - memNow.implicitWidth - 70; height: 1 }
            Text {
              id: memNow
              text: root.snap ? root.bytes(root.snap.mem.used) + " / " + root.bytes(root.snap.mem.total) : "—"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.body
            }
          }
          Sparkline {
            width: parent.width
            height: Style.space(46)
            values: root.memHistory
            ceiling: 100
            lineColor: "#b080e0"
          }
          Text {
            text: root.snap ? "Cached " + root.bytes(root.snap.mem.cached)
              + "  ·  Available " + root.bytes(root.snap.mem.available)
              + "  ·  Swap " + root.bytes(root.snap.mem.swapUsed) : ""
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Pressure / Network / Disk / GPU
        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.spacing.panelGap
          rowSpacing: Style.spacing.md

          Repeater {
            model: {
              if (!root.snap) return []
              var p = root.snap.pressure, g = root.snap.gpu || {}
              var stall = Math.max(p.cpu_some, p.memory_some, p.io_some)
              var level = stall >= 20 ? "HIGH" : (stall >= 5 ? "MEDIUM" : "LOW")
              var gpuLine = g.name
                ? (g.util !== null ? Math.round(g.util) + "%" : "—") + " · "
                  + (g.power !== null ? g.power.toFixed(1) + " W" : "—") + " · "
                  + (g.temp !== null ? Math.round(g.temp) + "°C" : "—")
                : "No GPU data"
              return [
                { t: "SYSTEM PRESSURE", v: level + " · " + stall.toFixed(1) + "%",
                  d: "cpu " + p.cpu_some.toFixed(1) + "  mem " + p.memory_some.toFixed(1) + "  io " + p.io_some.toFixed(1) },
                { t: "NETWORK", v: "↓ " + root.bytes(root.snap.down, "/s"), d: "↑ " + root.bytes(root.snap.up, "/s") },
                { t: "DISK", v: "R " + root.bytes(root.snap.diskRead, "/s"), d: "W " + root.bytes(root.snap.diskWrite, "/s") },
                { t: g.name || "GPU", v: gpuLine,
                  d: g.memTotal ? "VRAM " + root.bytes(g.memUsed) + " / " + root.bytes(g.memTotal) : "" }
              ]
            }
            delegate: Column {
              width: (content.width - Style.spacing.panelGap) / 2
              spacing: 1
              Text { text: modelData.t; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: parent.width }
              Text { text: modelData.v; color: root.foreground; font.family: root.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width }
              Text { text: modelData.d; color: root.dim; font.family: root.family; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: parent.width }
            }
          }
        }

        Text {
          text: root.snap ? root.snap.procCount + " processes" : "Sampling…"
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
