#!/bin/bash

# languagectl setup / uninstall in a throwaway HOME, with a fake hyprctl.
#
#   tests/test-setup.sh

set -uo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
CTL="$here/languagectl"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run"
mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy" "$T/bin" "$T/run"
printf -- '-- hyprland\n' >"$HOME/.config/hypr/hyprland.lua"

cat >"$T/bin/hyprctl" <<SH
#!/bin/bash
case "\$*" in
*getoption\ input:kb_layout*) echo '{"str":"us,ara"}' ;;
*getoption\ input:kb_variant*) echo '{"str":","}' ;;
*getoption\ input:kb_options*) echo '{"str":"compose:caps"}' ;;
*binds*) cat "$T/binds.json" 2>/dev/null || echo '[]' ;;
*devices*) echo '{"keyboards":[]}' ;;
*) echo ok ;;
esac
SH
chmod +x "$T/bin/hyprctl"
export PATH="$T/bin:$PATH"

passed=0 failed=0
ok() { passed=$((passed + 1)); printf '  \e[32m✓\e[0m %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf '  \e[31m✗ %s\e[0m\n' "$1"; }
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
has() { if [[ $2 == *"$3"* ]]; then ok "$1"; else bad "$1: [$2] lacks [$3]"; fi; }

SJ="$HOME/.config/omarchy/shell.json"
fresh() {
  cat >"$SJ" <<'J'
{
  "bar": {
    "layout": {
      "left": [{"id": "omarchy.menu"}],
      "center": [{"id": "omarchy.clock"}, {"id": "omarchy.keyboard-layout", "x": 1}, {"id": "omarchy.weather"}],
      "right": [{"id": "omarchy.tray"}, {"id": "blackcode.omalangy"}]
    }
  }
}
J
  rm -rf "$XDG_STATE_HOME" "$HOME/.config/hypr/keyboard-languages.lua"
}
ids() { jq -c "[.bar.layout.$1[].id]" "$SJ"; }

echo "Setup"
fresh
chmod 640 "$SJ"
out=$("$CTL" setup 2>&1)
has "says where it went" "$out" "where the built-in keyboard label was"
eq "takes the built-in's place in the center" "$(ids center)" '["omarchy.clock","blackcode.omalangy","omarchy.weather"]'
eq "leaves the right section without it" "$(ids right)" '["omarchy.tray"]'
eq "keeps the file mode" "$(stat -c %a "$SJ")" "640"
mod=$(cat "$HOME/.config/hypr/keyboard-languages.lua")
has "turns the next-language shortcut on" "$mod" '"SUPER + SHIFT + K"'
has "turns the panel shortcut on" "$mod" '"SUPER + CTRL + ALT + K"'
has "keeps the compose key option" "$mod" "compose:caps"
has "keeps the layouts Hyprland has" "$mod" 'kb_layout = "us,ara"'
has "hooks the module into hyprland.lua" "$(cat "$HOME/.config/hypr/hyprland.lua")" 'pcall(require, "hypr.keyboard-languages")'
eq "runs once" "$("$CTL" setup)" "already set up"

echo "Uninstall"
"$CTL" uninstall >/dev/null
eq "puts the built-in back where OmaLangy is, settings and all" "$(jq -c '.bar.layout.center' "$SJ")" \
  '[{"id":"omarchy.clock"},{"id":"omarchy.keyboard-layout","x":1},{"id":"blackcode.omalangy"},{"id":"omarchy.weather"}]'
"$CTL" uninstall >/dev/null
eq "a second uninstall adds no second label" "$(jq '[.bar.layout[][] | select(.id == "omarchy.keyboard-layout")] | length' "$SJ")" "1"

echo "Edge cases"
fresh
jq 'del(.bar.layout.center[1])' "$SJ" >"$SJ.t" && mv "$SJ.t" "$SJ"
has "no built-in label: bar left alone" "$("$CTL" setup)" "nothing to replace"
eq "and nothing moved" "$(ids right)" '["omarchy.tray","blackcode.omalangy"]'
fresh
echo '[{"modmask":65,"key":"k","description":"Something of mine","dispatcher":"exec","arg":"x"}]' >"$T/binds.json"
"$CTL" setup >/dev/null 2>"$T/err"
has "a taken shortcut is left off and said so" "$(cat "$T/err")" "next-language shortcut left off"
mod=$(cat "$HOME/.config/hypr/keyboard-languages.lua")
if [[ $mod != *'"SUPER + SHIFT + K"'* && $mod == *'"SUPER + CTRL + ALT + K"'* ]]; then ok "only the free shortcut is bound"; else bad "only the free shortcut is bound"; fi
rm -f "$T/binds.json"
fresh
printf -- '-- mine\n' >"$HOME/.config/hypr/keyboard-languages.lua"
"$CTL" setup >/dev/null 2>&1
eq "an existing module is left as it is" "$(cat "$HOME/.config/hypr/keyboard-languages.lua")" "-- mine"
fresh
echo "{nope" >"$SJ"
"$CTL" setup >/dev/null 2>&1
eq "broken shell.json: not touched" "$(cat "$SJ")" "{nope"

echo "Hyprland not answering"
fresh
cp "$T/bin/hyprctl" "$T/hyprctl.ok"
printf '#!/bin/bash\necho "HYPRLAND_INSTANCE_SIGNATURE not set" >&2\nexit 1\n' >"$T/bin/hyprctl"
out=$("$CTL" setup 2>&1); rc=$?
eq "setup does not fail" "$rc" "0"
has "says it will try again" "$out" "trying again on the next start"
eq "the bar step is done anyway" "$(ids center)" '["omarchy.clock","blackcode.omalangy","omarchy.weather"]'
if [[ ! -e $XDG_STATE_HOME/omalangy/setup-done ]]; then ok "no marker yet"; else bad "no marker yet"; fi
cp "$T/hyprctl.ok" "$T/bin/hyprctl"
"$CTL" setup >/dev/null 2>&1
has "next start finishes it" "$(cat "$HOME/.config/hypr/keyboard-languages.lua" 2>/dev/null)" '"SUPER + SHIFT + K"'
eq "and marks it done" "$("$CTL" setup)" "already set up"
eq "the bar is not changed twice" "$(ids center)" '["omarchy.clock","blackcode.omalangy","omarchy.weather"]'

echo
echo "$passed passed, $failed failed"
((failed == 0))
