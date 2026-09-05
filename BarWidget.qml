import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Derived from Omarchy's own `omarchy.weather` bar widget
// (https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson). The injectPanel / open / close / closeForPopoutSwitch contract
// below is what the bar requires of any widget hosting a panel, and this file
// follows that implementation closely. See LICENSE for the full notice.

// The cap, in the bar. The glyph is a battery outline and stays that way at
// every charge level, because the charge is already in the bar next to this
// and a second reading of the same number is noise. The number here is the
// ceiling, which nothing else in the bar reports.
//
// The widget reads the cap for itself rather than asking the panel, so the bar
// is right from the moment the shell starts and stays right when the limit is
// changed from a terminal.
BarWidget {
  id: root
  moduleName: "brightwalker25.battery-limit"

  // nf-md-battery_outline. A shape that does not imply a level.
  readonly property string glyph: "󰂎"

  readonly property bool showLimit: setting("showLimitInBar", true) !== false
  readonly property int refreshMs: Math.max(2000, Number(setting("refreshIntervalMs", 10000)))

  readonly property string cli: String(Qt.resolvedUrl("bin/battery-limit")).replace(/^file:\/\//, "")

  property int cap: 0
  property bool travelling: false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // The panel calls this after every change so the bar does not wait out a
  // poll interval showing a cap that is no longer in force.
  function refresh() {
    if (!probe.running) probe.running = true
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: probe
    command: [root.cli, "status"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rep = JSON.parse(String(text))
          // The hardware reading, not the configured one. The bar should show
          // what the battery is doing, and those differ exactly when
          // something has gone wrong and is worth seeing.
          root.cap = Number(rep.hardwareLimit) || 0
          root.travelling = rep.effectiveSource === "travel"
        } catch (e) {
          root.cap = 0
        }
      }
    }
  }

  // Cheap: three or four reads under /sys and no network, so this can afford
  // to run while the panel is closed, which is what keeps the bar honest.
  Timer {
    running: true
    interval: root.refreshMs
    repeat: true
    onTriggered: if (!probe.running) probe.running = true
  }

  readonly property bool labelled: showLimit && cap > 0 && !button.vertical

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Written as a ceiling rather than as a bare number. The bar's own power
    // widget sits next to this one by default and reads "99%", and two
    // adjacent numbers with nothing to tell them apart read as one number.
    // The relation is also what the figure actually means.
    text: root.labelled ? root.glyph + " ≤" + root.cap : root.glyph
    // The same doubling the power widget uses when it carries a percentage.
    // Without it the label is squeezed into a slot sized for one glyph.
    slotSize: Style.bar.iconSlot * (root.labelled ? 2 : 1)

    // The one state worth colouring. A travel cap is temporary by
    // construction, and the whole point of it expiring is that you are not
    // supposed to have to remember it. Colour here cannot go stale the way a
    // network verdict can: it is re-read from a local file every few seconds.
    useActiveColor: true
    active: root.travelling

    tooltipText: root.cap > 0
      ? (root.travelling
        ? "Charging to " + root.cap + "% for travel, then back down"
        : "Charging to " + root.cap + "% and holding")
      : "Charge limit"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
