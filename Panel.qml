import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "LanguageModel.js" as LanguageModel

Panel {
  id: root
  moduleName: "blackcode.omalangy"
  ipcTarget: "blackcode.omalangy"
  manageIpc: true

  // ---- Settings (shell.json → this widget's bar entry; see manifest schema) ----
  // Change them from the panel's Settings section, or:
  //   omarchy bar set blackcode.omalangy <key> "<value>"
  readonly property string labelStyle: {
    const v = setting("label", "")
    if (v) return String(v)
    return setting("showIcon", true) === false ? "Code only" : "Icon and code" // 1.0 setting
  }
  readonly property string switchKeys: String(setting("switchKeys", "Both Alt keys"))
  readonly property string nextLanguageKey: String(setting("nextLanguageKey", "SUPER + SHIFT + K"))
  readonly property string panelKey: String(setting("panelKey", "SUPER + CTRL + ALT + K"))

  readonly property var labelOptions: ["Icon and code", "Code only", "Icon only"]
  // Only keys Omarchy leaves free. Alt+Shift and Ctrl+Shift are not offered:
  // Omarchy binds Shift+Alt+Tab and web-app Shift+Alt shortcuts, and terminals
  // use Ctrl+Shift+C / V, so an xkb toggle there would fire on every copy.
  readonly property var switchOptions: [
    { label: "Both Alt keys", value: "alts" },
    { label: "Menu key", value: "menu" },
    { label: "Right Ctrl", value: "rctrl" },
    { label: "Off", value: "off" }
  ]
  readonly property string switchValue: {
    for (let i = 0; i < switchOptions.length; i++)
      if (switchOptions[i].label === switchKeys) return switchOptions[i].value
    return "alts"
  }

  readonly property string ctl: decodeURIComponent(String(Qt.resolvedUrl("languagectl")).replace(/^file:\/\//, ""))
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : ""

  // ---- Live state, read from Hyprland ----
  property bool stateLoaded: false
  property var layouts: []
  property var variants: []
  property int activeIndex: 0
  property string activeKeymap: ""
  property string appliedArgs: ""
  property bool moduleCurrent: true
  property var nextKeyStatus: ({ combo: "", status: "off", conflict: "" })
  property var panelKeyStatus: ({ combo: "", status: "off", conflict: "" })
  property string errorText: ""

  property var catalog: []
  readonly property var active: LanguageModel.activeEntries(layouts, variants, catalog)
  readonly property var current: active.length > activeIndex ? active[activeIndex] : null
  readonly property string currentCode: current ? current.code : ""

  // ---- Position on the bar (read from shell.json, changed with `omarchy bar move`) ----
  property var barLayout: ({})

  function entryId(entry) {
    return typeof entry === "string" ? entry : (entry && entry.id ? String(entry.id) : "")
  }

  readonly property var placement: {
    const sections = ["left", "center", "right"]
    for (let i = 0; i < sections.length; i++) {
      const ids = (root.barLayout[sections[i]] || []).map(root.entryId)
      const at = ids.indexOf(root.moduleName)
      if (at !== -1) return { section: sections[i], index: at, ids: ids }
    }
    return { section: "", index: -1, ids: [] }
  }
  readonly property bool clockInSection: placement.ids.indexOf("omarchy.clock") !== -1
  readonly property string order: {
    const p = placement
    if (p.index === -1) return ""
    if (p.index > 0 && p.ids[p.index - 1] === "omarchy.clock") return "Next to clock"
    if (p.index === 0) return "Start"
    if (p.index === p.ids.length - 1) return "End"
    return ""
  }

  function moveTo(section, where) {
    if (!root.bar) return
    const others = (root.barLayout[section] || []).map(root.entryId).filter(function(id) { return id !== root.moduleName })
    let place = "--section " + section + " --index " + (where === "Start" ? 0 : others.length)
    if (where === "Next to clock" && others.indexOf("omarchy.clock") !== -1) place = "--after omarchy.clock"
    root.close()
    root.bar.run("omarchy bar move " + root.moduleName + " " + place)
  }

  FileView {
    id: shellConfig
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.barLayout = (JSON.parse(text()).bar || {}).layout || {} } catch (e) {}
    }
  }

  // ---- Search ----
  property string query: ""
  property int resultIndex: 0
  readonly property var results: {
    const taken = {}
    root.active.forEach(function(e) { taken[e.key] = true })
    return LanguageModel.search(root.catalog, root.query, 80).filter(function(e) { return !taken[e.key] })
  }
  onResultsChanged: resultIndex = 0

  // ---- Actions ----
  property var pendingApply: null

  function refresh() {
    if (stateProc.running) { refreshTimer.restart(); return }
    stateProc.running = true
  }

  function switchTo(target) {
    if (root.bar) root.bar.run(Util.shellQuote(root.ctl) + " switch " + Util.shellQuote(String(target)))
  }

  function argsFor(entries) {
    const a = LanguageModel.toArgs(LanguageModel.normalize(entries))
    return [a.layouts, a.variants, root.switchValue, root.nextLanguageKey.trim(), root.panelKey.trim()]
  }

  function applyEntries(entries) {
    root.errorText = ""
    root.pendingApply = [root.ctl, "apply"].concat(argsFor(entries))
    if (!applyProc.running) runPendingApply()
  }

  function runPendingApply() {
    if (!root.pendingApply) return
    applyProc.command = root.pendingApply
    root.pendingApply = null
    applyProc.running = true
  }

  // Settings live in shell.json; Hyprland follows them. Nothing is written to
  // the user's Hyprland config until they act in the plugin (add, remove or
  // reorder a language, or change a setting): installing it alone never edits
  // their config. Once set up, re-apply whenever shell.json and Hyprland disagree.
  readonly property bool managed: root.appliedArgs !== ""
  property bool settingsTouched: false

  function syncSettings() {
    if (!root.stateLoaded || applyProc.running || root.active.length === 0) return
    if (!root.managed && !root.settingsTouched) return
    // An older plugin version wrote the module: rewrite it in the current shape.
    if (argsFor(root.active).join("|") !== root.appliedArgs || (root.managed && !root.moduleCurrent)) applyEntries(root.active)
  }

  function settingChanged() {
    // Settings arriving with the widget at startup are not a user action.
    if (settingsReady.running) return
    root.settingsTouched = true
    settingsTimer.restart()
  }

  function setSetting(key, value) {
    if (root.bar) root.bar.run("omarchy bar set " + root.moduleName + " " + key + " " + Util.shellQuote(String(value)))
  }

  function addEntry(entry) {
    if (!entry) return
    applyEntries(root.active.concat([{ layout: entry.layout, variant: entry.variant, key: entry.key }]))
    searchField.text = ""
  }

  function removeAt(i) {
    if (root.active.length <= 1) return
    const next = root.active.slice()
    next.splice(i, 1)
    applyEntries(next)
  }

  function moveUp(i) {
    if (i <= 0) return
    const next = root.active.slice()
    const item = next.splice(i, 1)[0]
    next.splice(i - 1, 0, item)
    if (i - 1 === 0 && !LanguageModel.isLatin(item.layout)) {
      root.errorText = "A Latin layout stays first so Omarchy shortcuts keep working."
      return
    }
    applyEntries(next)
  }

  function keyText(status) {
    if (!status || status.status === "off" || !status.combo) return "Off"
    return status.combo
  }

  function ensureCatalog() {
    if (root.catalog.length === 0 && !catalogProc.running) catalogProc.running = true
  }

  Component.onCompleted: {
    ensureCatalog()
    refresh()
  }

  onSwitchValueChanged: settingChanged()
  onNextLanguageKeyChanged: settingChanged()
  onPanelKeyChanged: settingChanged()

  Timer {
    id: settingsReady
    interval: 3000
    running: true
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      ensureCatalog()
      root.errorText = ""
      searchField.text = ""
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      const name = String(event.name)
      if (name.indexOf("activelayout") !== -1) refreshTimer.restart()
      // After any reload (an Omarchy update, an edit to bindings.lua), give up
      // a shortcut something else now owns, so the two never fire together.
      if (name === "configreloaded") checkTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: root.refresh()
  }

  Timer {
    id: settingsTimer
    interval: 400
    onTriggered: root.syncSettings()
  }

  Timer {
    id: checkTimer
    interval: 500
    onTriggered: if (!checkProc.running && !applyProc.running) checkProc.running = true
  }

  Process {
    id: stateProc
    command: [root.ctl, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let s
        try { s = JSON.parse(text) } catch (e) { return }
        root.layouts = s.layouts || []
        root.variants = s.variants || []
        root.activeIndex = s.active || 0
        root.activeKeymap = s.activeKeymap || ""
        root.appliedArgs = s.applied || ""
        root.moduleCurrent = s.current !== false
        root.nextKeyStatus = s.nextKey || root.nextKeyStatus
        root.panelKeyStatus = s.panelKey || root.panelKeyStatus
        root.stateLoaded = true
        settingsTimer.restart()
      }
    }
  }

  Process {
    id: applyProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim()
    }
    onExited: {
      refreshTimer.restart()
      root.runPendingApply()
    }
  }

  Process {
    id: checkProc
    command: [root.ctl, "check"]
    onExited: refreshTimer.restart()
  }

  Process {
    id: catalogProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.catalog = LanguageModel.parseCatalog(text)
    }
  }

  // ---- Small building blocks for the Settings section ----
  component SettingLabel: Text {
    textFormat: Text.PlainText
    color: Qt.darker(root.fg, 1.3)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  component Chip: CursorSurface {
    id: chip
    property string label: ""
    property bool selected: false
    signal picked()

    width: chipText.implicitWidth + Style.space(18)
    height: chipText.implicitHeight + Style.space(10)
    current: selected
    outline: !selected
    hasCursor: chipMouse.containsMouse
    foreground: root.fg
    accent: Color.accent

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: chip.selected ? Color.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: chip.selected
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!chip.selected || chip.label === "On") chip.picked()
    }
  }

  // ---- Bar button ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.currentCode === "" || root.labelStyle === "Icon only" ? "󰌌"
      : (root.labelStyle === "Code only" ? root.currentCode : "󰌌 " + root.currentCode)
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: (root.activeKeymap || "Keyboard language") + (root.active.length > 1 ? "\nRight-click or scroll to switch" : "")
    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.switchTo("next")
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.switchTo(delta < 0 ? "next" : "prev") }
  }

  // ---- Popup ----
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(1100))

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(10)

      // Header
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰌌"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: "OmaLangy"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: root.activeKeymap.toUpperCase()
            visible: text !== ""
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            width: parent.width
            elide: Text.ElideRight
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      // Active languages
      PanelSectionHeader {
        text: "ACTIVE"
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.active

          CursorSurface {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === root.activeIndex

            width: parent.width
            height: rowLabel.implicitHeight + Style.space(14)
            current: isCurrent
            hasCursor: rowMouse.containsMouse
            foreground: root.fg
            accent: Color.accent

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.switchTo(row.index)
            }

            Text {
              id: rowCode
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              text: row.modelData.code
              color: row.isCurrent ? Color.accent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              id: rowLabel
              textFormat: Text.PlainText
              anchors.left: rowCode.right
              anchors.right: rowActions.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.description + (row.index === 0 ? "  · shortcuts" : "")
              color: root.fg
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              id: rowActions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                // Never offer to put a non-Latin layout first: Hyprland reads
                // keybindings from the first layout.
                visible: row.index > 1 || (row.index === 1 && LanguageModel.isLatin(row.modelData.layout))
                text: "󰁝"
                color: upMouse.containsMouse ? Color.accent : Qt.darker(root.fg, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                MouseArea {
                  id: upMouse
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.moveUp(row.index)
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: root.active.length > 1
                text: "󰅖"
                color: delMouse.containsMouse ? Color.urgent : Qt.darker(root.fg, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                MouseArea {
                  id: delMouse
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.removeAt(row.index)
                }
              }
            }
          }
        }
      }

      // Settings
      PanelSectionHeader {
        text: "SETTINGS"
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      SettingLabel { text: "Position on top bar" }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
          model: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }]
          Chip {
            required property var modelData
            label: modelData.label
            selected: root.placement.section === modelData.value
            onPicked: root.moveTo(modelData.value, modelData.value === "center" ? "Next to clock" : "End")
          }
        }
      }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.placement.section !== ""
        Repeater {
          model: root.clockInSection ? ["Start", "Next to clock", "End"] : ["Start", "End"]
          Chip {
            required property var modelData
            label: modelData
            selected: root.order === modelData
            onPicked: root.moveTo(root.placement.section, modelData)
          }
        }
      }

      SettingLabel { text: "Switch keys" }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
          model: root.switchOptions
          Chip {
            required property var modelData
            label: modelData.label
            selected: root.switchKeys === modelData.label
            onPicked: root.setSetting("switchKeys", modelData.label)
          }
        }
      }

      SettingLabel { text: "Bar label" }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
          model: root.labelOptions
          Chip {
            required property var modelData
            label: modelData
            selected: root.labelStyle === modelData
            onPicked: root.setSetting("label", modelData)
          }
        }
      }

      SettingLabel { text: "Keybindings" }
      Text {
        width: parent.width
        visible: !root.managed
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: "Not set up yet. Your Hyprland config is untouched until you add a language or change a setting here."
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Repeater {
        model: [
          { title: "Switch to next language", key: "nextLanguageKey", value: root.nextLanguageKey, status: root.nextKeyStatus, fallback: "SUPER + SHIFT + K",
            command: "hyprctl switchxkblayout all next" },
          { title: "Open keyboard languages panel", key: "panelKey", value: root.panelKey, status: root.panelKeyStatus, fallback: "SUPER + CTRL + ALT + K",
            command: "omarchy-shell blackcode.omalangy toggle" }
        ]

        Item {
          id: keyRow
          required property var modelData
          readonly property bool enabledKey: modelData.value.trim() !== ""
          readonly property bool conflict: modelData.status && modelData.status.status === "conflict"

          width: parent.width
          implicitHeight: keyColumn.implicitHeight + Style.space(6)

          Column {
            id: keyColumn
            anchors.left: parent.left
            anchors.right: keyToggle.left
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              text: keyRow.modelData.title
              color: keyRow.conflict ? Color.urgent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              text: keyRow.enabledKey ? keyRow.modelData.value.toUpperCase() : "Off"
              color: keyRow.conflict ? Color.urgent : Qt.darker(root.fg, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: keyRow.conflict
              wrapMode: Text.Wrap
              text: "Used by Omarchy: \"" + (keyRow.modelData.status ? keyRow.modelData.status.conflict : "") + "\" · left off"
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WrapAnywhere
              text: "Runs: " + keyRow.modelData.command
              color: Qt.darker(root.fg, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Chip {
            id: keyToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: keyRow.enabledKey ? "On" : "Off"
            selected: keyRow.enabledKey && !keyRow.conflict
            onPicked: root.setSetting(keyRow.modelData.key, keyRow.enabledKey ? "" : keyRow.modelData.fallback)
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        text: "Change a key:\n  omarchy bar set " + root.moduleName + " nextLanguageKey \"SUPER + ALT + L\"\n  omarchy bar set " + root.moduleName + " panelKey \"SUPER + CTRL + ALT + J\""
        color: Qt.darker(root.fg, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.fg }

      // Add language
      PanelSectionHeader {
        text: "ADD LANGUAGE  ·  " + root.catalog.length + " LAYOUTS"
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      TextField {
        id: searchField
        width: parent.width
        foreground: root.fg
        placeholderText: "Search: Arabic, عربي, French, 日本語…"
        onTextChanged: root.query = text

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (text !== "") text = ""
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.resultIndex = Math.min(root.results.length - 1, root.resultIndex + 1)
            resultList.positionViewAtIndex(root.resultIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.resultIndex = Math.max(0, root.resultIndex - 1)
            resultList.positionViewAtIndex(root.resultIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.query !== "") root.addEntry(root.results[root.resultIndex])
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.switchPanel(event.key === Qt.Key_Backtab ? -1 : 1)
            event.accepted = true
          }
        }
      }

      ListView {
        id: resultList
        width: parent.width
        height: Style.space(150)
        clip: true
        model: root.results
        boundsBehavior: Flickable.StopAtBounds

        delegate: CursorSurface {
          id: result
          required property var modelData
          required property int index

          width: ListView.view.width
          height: resultLabel.implicitHeight + Style.space(12)
          hasCursor: resultMouse.containsMouse || (root.query !== "" && root.resultIndex === index)
          foreground: root.fg
          accent: Color.accent

          Text {
            id: resultCode
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            text: result.modelData.code
            color: Qt.darker(root.fg, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            id: resultLabel
            textFormat: Text.PlainText
            anchors.left: resultCode.right
            anchors.right: resultAdd.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: result.modelData.description + (result.modelData.native && !result.modelData.variant ? "  " + result.modelData.native.split(" ")[0] : "")
            color: root.fg
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: resultAdd
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐕"
            color: result.hasCursor ? Color.accent : Qt.darker(root.fg, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          MouseArea {
            id: resultMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.addEntry(result.modelData)
          }
        }
      }

      Text {
        width: parent.width
        visible: root.errorText !== ""
        textFormat: Text.PlainText
        text: root.errorText
        color: Color.urgent
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
