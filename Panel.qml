import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The panel scaffolding here, the open/close and IPC contract, is derived from
// Omarchy's `omarchy.weather` and `omarchy.agents` plugins
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). See LICENSE for the full notice.

// The panel behind the bar glyph. It shows what the battery is capped at and
// what it has left to give, and it carries the controls that change the cap.
//
// The layout separates the two purposes a cap serves. The row of standing caps
// is the decision made once and then left alone. The travel button underneath
// is the exception made on a particular day, and it is the only control that
// reaches 100%, because a cap set to 100% and forgotten is the situation this
// plugin is meant to prevent.
//
// The panel renders whatever `bin/battery-limit` reports and decides nothing
// itself. Which limit is in force, whether a travel override has run out, and
// whether the firmware accepted the request are all determined in that script,
// which can be run from a terminal with no compositor involved.
Panel {
  id: root
  moduleName: "brightwalker25.battery-limit"
  ipcTarget: "brightwalker25.battery-limit"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Fixed rather than drawn from the theme, for the same reason the vpn-check
  // panel fixes its own: a theme is free to define its urgent colour as a soft
  // pink, and a warning rendered in a decorative colour does not read as a
  // warning.
  readonly property color okColor: "#3fb950"
  readonly property color warnColor: "#d29922"
  readonly property color badColor: "#f85149"

  readonly property int refreshMs: Math.max(2000, Number(setting("refreshIntervalMs", 10000)))
  readonly property string travelDuration: String(setting("travelDuration", "24 hours"))

  // This is parsed defensively, because it is a free-text setting and a typo
  // in it should cost the user one odd-looking button rather than a panel that
  // fails to load.
  readonly property var presets: {
    var raw = String(setting("presets", "60, 70, 80, 90")).split(",")
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var n = parseInt(String(raw[i]).replace(/[^0-9]/g, ""), 10)
      if (!isNaN(n) && n >= 40 && n < 100 && out.indexOf(n) === -1) out.push(n)
    }
    return out.length > 0 ? out : [60, 70, 80, 90]
  }

  readonly property string cli: String(Qt.resolvedUrl("bin/battery-limit")).replace(/^file:\/\//, "")

  property var rep: null
  property string error: ""
  property bool busy: false

  // Held between the moment a control is used and the moment the script
  // reports back, so the slider and the buttons do not visibly snap back to
  // the old value during the round trip.
  property int pending: 0

  readonly property int hardwareLimit: rep && rep.hardwareLimit ? Number(rep.hardwareLimit) : 0
  readonly property int shownLimit: pending > 0 ? pending : hardwareLimit
  readonly property bool travelling: rep ? rep.effectiveSource === "travel" : false
  readonly property int standingLimit: rep && rep.configuredLimit ? Number(rep.configuredLimit) : 0
  readonly property bool supported: rep ? rep.supported === true : true
  readonly property bool settable: rep && rep.setup ? rep.setup.writable === true : false
  readonly property bool persists: rep && rep.setup ? rep.setup.persists === true : false

  // 40 is the floor the script enforces, and the slider should not offer what
  // the script will refuse. 99 rather than 100 because raising the cap to 100
  // is the travel button's job, and a slider that can quietly reach 100 makes
  // the expiry easy to sidestep by accident.
  readonly property int sliderMin: rep && rep.minimum ? Number(rep.minimum) : 40
  readonly property int sliderMax: 99

  function fmtHealth() {
    if (!rep || rep.healthPercent === null || rep.healthPercent === undefined) return ""
    var s = rep.healthPercent + "% health"
    if (rep.cycleCount !== null && rep.cycleCount !== undefined)
      s += " · " + rep.cycleCount + " cycles"
    return s
  }

  function healthColor() {
    if (!rep || rep.healthPercent === null || rep.healthPercent === undefined) return root.dim
    var h = Number(rep.healthPercent)
    if (h >= 85) return root.okColor
    if (h >= 65) return root.warnColor
    return root.badColor
  }

  function fmtTravel() {
    if (!rep || rep.effectiveSource !== "travel") return ""
    var until = rep.travelUntil
    if (until === null || until === undefined)
      return "until you change it"
    var left = Number(until) - (Date.now() / 1000)
    if (left <= 0) return "expiring"
    if (left < 3600) return "for another " + Math.round(left / 60) + " min"
    if (left < 86400 * 2) return "for another " + Math.round(left / 3600) + " h"
    return "for another " + Math.round(left / 86400) + " days"
  }

  function durationFlag() {
    var d = root.travelDuration
    if (d.indexOf("8") === 0) return "8h"
    if (d.indexOf("24") === 0) return "24h"
    if (d.indexOf("3") === 0) return "3d"
    if (d.indexOf("1 week") === 0) return "1w"
    return "off"
  }

  // ------------------------------------------------------------- the script

  function poll() {
    if (reader.running) return
    reader.running = true
  }

  function ingest(text) {
    var parsed = null
    try {
      parsed = JSON.parse(String(text))
    } catch (e) {
      root.error = "Could not parse battery-limit output"
      return
    }
    if (!parsed || typeof parsed !== "object") return
    root.error = ""
    root.rep = parsed
    root.pending = 0
    // The bar reads the cap for itself, but not on this panel's schedule, so
    // it is nudged after every change rather than left to catch up.
    if (root.hostWidget && root.hostWidget.refresh) root.hostWidget.refresh()
  }

  // None of these gate on root.settable, and that is deliberate. The controls
  // in the panel are already disabled when the limit cannot be set, so the
  // only callers that reach here without a usable snapshot are the IPC
  // actions, which are meant to work from a keybinding on a panel that has
  // never been opened. The CLI refuses an impossible write by itself and says
  // why, and that message is worth more than a silent no-op.
  function setLimit(value) {
    if (writer.running) return
    root.pending = value
    root.busy = true
    writer.argv = ["set", String(value)]
    writer.running = true
  }

  function setTravel() {
    if (writer.running) return
    root.pending = 100
    root.busy = true
    writer.argv = ["set", "100", "--for", root.durationFlag()]
    writer.running = true
  }

  function clearTravel() {
    if (writer.running) return
    root.busy = true
    writer.argv = ["clear-travel"]
    writer.running = true
  }

  Process {
    id: reader
    command: [root.cli, "status"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
  }

  Process {
    id: writer
    property var argv: []
    // Every action already prints a fresh status when it is done, so a write
    // and the reread that follows it are one process rather than two, and the
    // panel can never draw the state from before its own change.
    command: [root.cli].concat(writer.argv)
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.error = t
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        root.pending = 0
        if (root.error === "") root.error = "battery-limit exited " + exitCode
      }
      root.poll()
    }
  }

  // Only while the panel is open. These are reads under /sys and cost close to
  // nothing, but there is no reason to make them at a window nobody is at.
  Timer {
    running: root.opened
    interval: root.refreshMs
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  // One read at startup, so the panel has a snapshot to draw before it is
  // first opened. Without it the first frame after a click is empty, and the
  // travel readouts an IPC action leaves behind have nothing to attach to.
  Component.onCompleted: root.poll()

  // ------------------------------------------------------- open/close contract

  property bool openedFromHotkey: false

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.poll()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.poll()
  }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      root.bar.switchPanelFrom(root.barIdentity, direction)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.poll() }
    // Exposed so a Hyprland binding can raise the cap on the way out of the
    // door without opening anything:
    // `omarchy-shell brightwalker25.battery-limit travel`.
    function travel(): void { root.setTravel() }
    function standing(): void { root.clearTravel() }
  }

  // ------------------------------------------------------------- components

  component Stat: Column {
    id: stat
    property string caption: ""
    property string reading: ""
    property color readingColor: root.foreground
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: stat.reading
      color: stat.readingColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: stat.caption.toUpperCase()
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.2
    }
  }

  // A line of explanation with a coloured rule down its left edge. An Item
  // rather than a Row because the rule has to match the height of text it is
  // sitting next to, and inside a Row that height is what the Row is still
  // working out.
  component Note: Item {
    id: note
    property string message: ""
    property color accent: root.warnColor
    visible: message !== ""
    implicitHeight: visible ? noteText.implicitHeight : 0

    Rectangle {
      id: rule
      anchors.left: parent.left
      width: Style.space(3)
      height: parent.height
      radius: 1
      color: note.accent
    }

    Text {
      id: noteText
      textFormat: Text.PlainText
      anchors.left: rule.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: parent.right
      text: note.message
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  // ------------------------------------------------------------------ layout

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.spacing.lg

          // ---- Hero: the cap, large, because it is the one number this panel
          // exists to show and the only one you can change from here.
          Column {
            width: parent.width
            spacing: Style.spacing.xxs

            Text {
              textFormat: Text.PlainText
              text: "CHARGE LIMIT"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Row {
              spacing: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.supported
                  ? (root.shownLimit > 0 ? root.shownLimit + "%" : "-")
                  : "n/a"
                color: root.foreground
                font.family: root.fontFamily
                // Hero read-out, deliberately outside the Style.font.* scale.
                font.pixelSize: 34
                font.bold: true
              }

              BorderSurface {
                visible: root.travelling
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: travelPill.implicitWidth + Style.space(12)
                implicitHeight: travelPill.implicitHeight + Style.space(5)
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.warnColor, root.warnColor)
                radius: Style.cornerRadius

                Text {
                  id: travelPill
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "TRAVEL"
                  color: root.warnColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.1
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: text !== ""
              text: {
                if (!root.supported) return "This machine does not expose a charge threshold."
                if (root.travelling) {
                  var s = "Raised for travel " + root.fmtTravel()
                  if (root.standingLimit > 0) s += ", then back to " + root.standingLimit + "%"
                  return s
                }
                if (root.shownLimit >= 100) return "Charging to full. Nothing is being held back."
                if (root.shownLimit > 0) return "Charging stops here and holds."
                return ""
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---- What the pack is doing and what is left of it. The health
          // figure is the argument for capping at all, so it is on the face of
          // the panel rather than buried.
          Row {
            width: parent.width
            visible: root.supported
            spacing: Style.spacing.lg

            Stat {
              caption: root.rep && root.rep.status ? root.rep.status : "charge"
              reading: root.rep && root.rep.charge !== null && root.rep.charge !== undefined
                ? root.rep.charge + "%" : "-"
            }

            Stat {
              visible: root.rep && root.rep.healthPercent !== null
                && root.rep.healthPercent !== undefined
              caption: root.rep && root.rep.cycleCount !== null && root.rep.cycleCount !== undefined
                ? root.rep.cycleCount + " cycles" : "health"
              reading: root.rep && root.rep.healthPercent !== null && root.rep.healthPercent !== undefined
                ? root.rep.healthPercent + "%" : "-"
              readingColor: root.healthColor()
            }
          }

          // ---- The standing caps. One row, one click, no confirmation: every
          // one of them is reversible by clicking another.
          Column {
            width: parent.width
            visible: root.supported
            spacing: Style.spacing.md

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "Set the limit"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              id: presetRow
              width: parent.width
              enabled: root.settable && !root.busy
              opacity: enabled ? 1.0 : 0.45
              options: {
                var out = []
                for (var i = 0; i < root.presets.length; i++)
                  out.push({ value: String(root.presets[i]),
                             label: root.presets[i] + "%" })
                return out
              }
              value: String(root.shownLimit)
              foreground: root.foreground
              background: root.bar ? root.bar.background : Color.background
              fontFamily: root.fontFamily
              focusable: false
              onChanged: function(v) { root.setLimit(parseInt(v, 10)) }
            }

            // The slider is for the values between the buttons. It stops at 99
            // by design; 100 is the travel button below, which expires.
            PanelSlider {
              width: parent.width
              bar: root.bar
              enabled: root.settable && !root.busy
              opacity: enabled ? 1.0 : 0.45
              minimum: root.sliderMin
              maximum: root.sliderMax
              value: Math.max(root.sliderMin, Math.min(root.sliderMax, root.shownLimit))
              step: 1
              integer: true
              // Only on release. Dragging across the track would otherwise
              // write every value it passed through to the firmware.
              onReleased: function(v) { root.setLimit(Math.round(v)) }
            }
          }

          // ---- Travel. Set apart from the row above because it is a
          // different kind of decision, and labelled with what it costs and
          // when it ends, so choosing it is never an accident.
          Column {
            width: parent.width
            visible: root.supported
            spacing: Style.spacing.md

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Button {
              width: parent.width
              enabled: root.settable && !root.busy
              opacity: enabled ? 1.0 : 0.45
              bordered: true
              selected: root.travelling
              text: root.travelling
                ? "Back to " + (root.standingLimit > 0 ? root.standingLimit + "%" : "the standing limit")
                : "Charge to 100% for travel"
              iconText: root.travelling ? "󰁽" : "󰂅"
              foreground: root.travelling ? root.foreground : root.warnColor
              accent: root.warnColor
              background: root.bar ? root.bar.background : Color.background
              fontFamily: root.fontFamily
              onClicked: {
                if (root.travelling) root.clearTravel()
                else root.setTravel()
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.travelling
                ? "Reverts on its own " + root.fmtTravel() + ". Click again to end it now."
                : ("Lasts " + root.travelDuration.toLowerCase()
                   + ", then reverts to "
                   + (root.standingLimit > 0 ? root.standingLimit + "%" : "your standing limit")
                   + " on its own. Change the duration in this widget's settings.")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---- Anything the script wants said. Setup that has not been done,
          // a firmware that quantised the request, a cap that does not match
          // what is configured. Shown rather than swallowed, because a panel
          // that silently draws a limit the machine is not keeping is the one
          // failure worth avoiding here.
          Column {
            width: parent.width
            spacing: Style.spacing.sm
            visible: root.error !== ""
              || (root.rep && root.rep.warnings && root.rep.warnings.length > 0)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Note {
              width: parent.width
              message: root.error
              accent: root.badColor
            }

            Repeater {
              model: root.rep && root.rep.warnings ? root.rep.warnings : []
              delegate: Note {
                required property var modelData
                width: column.width
                message: String(modelData)
                accent: root.settable ? root.warnColor : root.badColor
              }
            }
          }
        }
      }
    }
  }
}
