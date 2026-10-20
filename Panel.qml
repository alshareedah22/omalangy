import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "LanguageModel.js" as LanguageModel

Panel {
  id: root
  moduleName: "blackcode.language"
  ipcTarget: "blackcode.language"
  manageIpc: true

  // Settings (shell.json → bar layout entry):
  //   "showIcon": false   show only the language code on the bar (default: keyboard icon + code)
  readonly property bool showIcon: setting("showIcon", true) !== false

  readonly property string ctl: decodeURIComponent(String(Qt.resolvedUrl("languagectl")).replace(/^file:\/\//, ""))
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : ""

  // ---- Live state, read from Hyprland ----
  property var layouts: []
  property var variants: []
  property string options: ""
  property int activeIndex: 0
  property string activeKeymap: ""
  property string errorText: ""

  property var catalog: []
  readonly property var active: LanguageModel.activeEntries(layouts, variants, catalog)
  readonly property var current: active.length > activeIndex ? active[activeIndex] : null
  readonly property string currentCode: current ? current.code : ""
  readonly property string toggle: LanguageModel.toggleFromOptions(options)

  readonly property var toggles: [
    { key: "grp:alts_toggle", label: "Both Alt" },
    { key: "grp:alt_shift_toggle", label: "Alt+Shift" },
    { key: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" },
    { key: "none", label: "Bar only" }
  ]

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

  function applyEntries(entries, toggleKey) {
    const list = LanguageModel.normalize(entries)
    const args = LanguageModel.toArgs(list)
    root.errorText = ""
    root.pendingApply = [root.ctl, "apply", args.layouts, args.variants, toggleKey || root.toggle]
    if (!applyProc.running) runPendingApply()
  }

  function runPendingApply() {
    if (!root.pendingApply) return
    applyProc.command = root.pendingApply
    root.pendingApply = null
    applyProc.running = true
  }

  function addEntry(entry) {
    if (!entry) return
    const next = root.active.concat([{ layout: entry.layout, variant: entry.variant, key: entry.key }])
    // A new layout with no switch shortcut yet gets Omarchy's usual one.
    applyEntries(next, root.active.length === 1 && root.toggle === "none" ? "grp:alts_toggle" : root.toggle)
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

  function ensureCatalog() {
    if (root.catalog.length === 0 && !catalogProc.running) catalogProc.running = true
  }

  Component.onCompleted: {
    ensureCatalog()
    refresh()
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
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") refreshTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: root.refresh()
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
        root.options = s.options || ""
        root.activeIndex = s.active || 0
        root.activeKeymap = s.activeKeymap || ""
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
    id: catalogProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.catalog = LanguageModel.parseCatalog(text)
    }
  }

  // ---- Bar button ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.currentCode === "" ? "󰌌" : (root.showIcon ? "󰌌 " + root.currentCode : root.currentCode)
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

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
            text: "Keyboard languages"
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

      // Switch shortcut
      PanelSectionHeader {
        text: "SWITCH WITH"
        foreground: root.fg
        fontFamily: root.fontFamily
        visible: root.active.length > 1
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.active.length > 1

        Repeater {
          model: root.toggles

          CursorSurface {
            id: chip
            required property var modelData
            readonly property bool selected: root.toggle === modelData.key

            width: chipLabel.implicitWidth + Style.space(18)
            height: chipLabel.implicitHeight + Style.space(10)
            current: selected
            outline: !selected
            hasCursor: chipMouse.containsMouse
            foreground: root.fg
            accent: Color.accent

            Text {
              id: chipLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: chip.modelData.label
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
              onClicked: if (!chip.selected) root.applyEntries(root.active, chip.modelData.key)
            }
          }
        }
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
        height: Style.space(220)
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
