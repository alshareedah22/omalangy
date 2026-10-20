// Qt-free helpers for the language widget, so they can be checked under node:
//   node -e 'const m=require("./LanguageModel.js"); ...'

// Layouts that can't type Latin letters. Same list Omarchy's default
// hypr/input.lua uses: Hyprland resolves keybindings (SUPER + W, ...) against
// the FIRST layout, so a non-Latin one must never lead or the desktop's
// shortcuts stop working.
var NON_LATIN = " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "

function isLatin(layout) {
  return NON_LATIN.indexOf(" " + layout + " ") === -1
}

// Native names so a language can be found by how its speakers write it.
var NATIVE = {
  ar: "العربية عربي", fa: "فارسی", ur: "اردو", he: "עברית", ps: "پښتو", ku: "Kurdî کوردی",
  en: "English", fr: "Français", de: "Deutsch", es: "Español", pt: "Português", it: "Italiano",
  nl: "Nederlands", ru: "Русский", uk: "Українська", pl: "Polski", tr: "Türkçe", el: "Ελληνικά",
  zh: "中文", ja: "日本語", ko: "한국어", hi: "हिन्दी", bn: "বাংলা", ta: "தமிழ்", th: "ไทย",
  vi: "Tiếng Việt", id: "Indonesia", ms: "Melayu", sv: "Svenska", no: "Norsk", da: "Dansk",
  fi: "Suomi", cs: "Čeština", sk: "Slovenčina", hu: "Magyar", ro: "Română", bg: "Български",
  sr: "Српски", hr: "Hrvatski", ka: "ქართული", hy: "Հայերեն", am: "አማርኛ", sw: "Kiswahili"
}

// `xkbcli list` prints YAML. Every layout / variant block in the `layouts:`
// section looks like:
//   - layout: 'ara'
//     variant: 'digits'
//     brief: 'ar'
//     description: Arabic (Eastern Arabic numerals)
function parseCatalog(text) {
  var out = []
  var inLayouts = false
  var cur = null

  function push() {
    if (cur && cur.layout && cur.description) out.push(cur)
    cur = null
  }

  String(text || "").split("\n").forEach(function (line) {
    if (/^[a-z]+:\s*$/.test(line)) {
      push()
      inLayouts = line.indexOf("layouts:") === 0
      return
    }
    if (!inLayouts) return

    var m = line.match(/^- layout: '(.*)'$/)
    if (m) {
      push()
      cur = { layout: m[1], variant: "", brief: "", description: "" }
      return
    }
    if (!cur) return

    m = line.match(/^  (variant|brief|description): (.*)$/)
    if (m) cur[m[1]] = m[2].replace(/^'|'$/g, "")
  })
  push()

  out.forEach(function (e) {
    e.key = e.layout + ":" + e.variant
    e.code = shortCode(e)
    e.native = NATIVE[e.code.toLowerCase()] || ""
    e.search = (e.description + " " + e.layout + " " + e.variant + " " + e.brief + " " + e.native).toLowerCase()
  })
  return out
}

function shortCode(entry) {
  var brief = entry && entry.brief ? String(entry.brief).split("-")[0] : ""
  var label = brief || String(entry && entry.layout || "")
  return label.substring(0, 3).toUpperCase()
}

// Rank: base layouts before variants, prefix matches before substring ones.
function search(catalog, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  var results = []

  for (var i = 0; i < catalog.length; i++) {
    var e = catalog[i]
    if (q && e.search.indexOf(q) === -1) continue
    var score = (e.variant ? 2 : 0)
    if (q) {
      var d = e.description.toLowerCase()
      if (d.indexOf(q) === 0 || e.layout === q || e.brief === q) score -= 1
      else score += 1
    }
    results.push({ entry: e, score: score, order: i })
  }

  results.sort(function (a, b) { return a.score - b.score || a.order - b.order })
  return results.slice(0, limit || 60).map(function (r) { return r.entry })
}

// Pair Hyprland's comma lists into entries the panel can show.
function activeEntries(layouts, variants, catalog) {
  var byKey = {}
  ;(catalog || []).forEach(function (e) { byKey[e.key] = e })

  return (layouts || []).filter(function (l) { return l !== "" }).map(function (layout, i) {
    var variant = (variants || [])[i] || ""
    var found = byKey[layout + ":" + variant] || byKey[layout + ":"]
    return {
      layout: layout,
      variant: variant,
      key: layout + ":" + variant,
      code: found ? found.code : layout.substring(0, 3).toUpperCase(),
      description: found ? (variant && found.variant !== variant ? found.description + " (" + variant + ")" : found.description) : layout + (variant ? " (" + variant + ")" : "")
    }
  })
}

// Keep a Latin layout first so Omarchy's keybindings keep working.
function normalize(entries) {
  var list = entries.slice()
  if (list.length === 0) return [{ layout: "us", variant: "", key: "us:" }]
  if (isLatin(list[0].layout)) return list

  var idx = -1
  for (var i = 0; i < list.length; i++) if (isLatin(list[i].layout)) { idx = i; break }
  if (idx === -1) return [{ layout: "us", variant: "", key: "us:" }].concat(list)

  var latin = list.splice(idx, 1)[0]
  return [latin].concat(list)
}

function toArgs(entries) {
  return {
    layouts: entries.map(function (e) { return e.layout }).join(","),
    variants: entries.map(function (e) { return e.variant || "" }).join(",")
  }
}

function toggleFromOptions(options) {
  var parts = String(options || "").split(",")
  for (var i = 0; i < parts.length; i++) if (parts[i].indexOf("grp:") === 0) return parts[i]
  return "none"
}

if (typeof module !== "undefined") {
  module.exports = {
    activeEntries: activeEntries,
    isLatin: isLatin,
    normalize: normalize,
    parseCatalog: parseCatalog,
    search: search,
    shortCode: shortCode,
    toArgs: toArgs,
    toggleFromOptions: toggleFromOptions
  }
}
