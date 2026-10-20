# Keyboard Languages for Omarchy

A keyboard-language switcher for the Omarchy bar. It shows a small keyboard
icon and the current language code (`󰌌 EN`, `󰌌 AR`, ...). Click it to open a
panel where you can:

- **Switch** language by clicking it in the *Active* list
- **Add** any of the ~750 xkb layouts and variants: English, Arabic, French,
  Persian, Hebrew, Russian, Japanese and the rest. Search works in English or
  in the language itself (`Arabic`, `عربي`, `Français`, `日本語`)
- **Remove** a language (󰅖) or **reorder** it (󰁝)
- **Pick the switch shortcut**: Both Alt keys (Omarchy's default), Alt+Shift,
  Ctrl+Shift, or bar only

On the bar itself: **left-click** opens the panel, **right-click** or
**scroll** switches to the next language.

## Safe by design

- Your languages are saved to their own file, `~/.config/hypr/keyboard-languages.lua`.
  Your `input.lua` and other Hyprland files are never rewritten.
- `hyprland.lua` gets one line appended (a backup is saved next to it first):
  `pcall(require, "hypr.keyboard-languages")`. Because it runs through `pcall`,
  a missing or broken file can never stop Hyprland from loading.
- Your other keyboard options (Caps Lock compose key, both-Shifts Caps Lock, ...)
  are kept. Only the layout-switch shortcut (`grp:*`) is replaced.
- A Latin layout always stays first. Hyprland reads keybindings from the first
  layout, so this keeps `SUPER + ...` shortcuts working while you type Arabic.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell` bar)
- `hyprctl`, `jq` and `xkbcli`, which ship with Omarchy

## Install

From git:

```bash
omarchy plugin add https://github.com/alshareedah22/omarchy-language-plugin.git --enable
```

Or from a local copy:

```bash
mkdir -p ~/.config/omarchy/plugins/blackcode.language
cp manifest.json Panel.qml LanguageModel.js languagectl LICENSE ~/.config/omarchy/plugins/blackcode.language/
omarchy plugin enable blackcode.language --section center
```

Omarchy also ships a small built-in layout label (`omarchy.keyboard-layout`).
This plugin replaces it, so you may want to take that one off the bar to
avoid seeing the code twice. To put it back:

```bash
omarchy bar put omarchy.keyboard-layout --after omarchy.clock
```

## Settings

Show only the code, without the keyboard icon:

```bash
omarchy bar set blackcode.language showIcon false --json
```

Open the panel from a keybinding (e.g. in `~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + CTRL + K", "Keyboard languages", "omarchy-shell blackcode.language toggle")
```

## Remove

```bash
~/.config/omarchy/plugins/blackcode.language/languagectl uninstall
omarchy plugin remove blackcode.language
```

`languagectl uninstall` deletes `keyboard-languages.lua` and the line in
`hyprland.lua`, then reloads Hyprland so your own `input.lua` settings apply again.

## Command line

```bash
languagectl state                       # JSON: layouts, variants, options, active
languagectl apply "us,ara" "," grp:alts_toggle
languagectl switch next                 # or prev, or a layout index
languagectl uninstall
```
