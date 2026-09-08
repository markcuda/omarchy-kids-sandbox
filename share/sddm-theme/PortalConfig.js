.pragma library

function geometryNumber(value, fallback, maximum) {
  if (value === undefined || value === null || typeof value === "boolean" || String(value).trim() === "") return fallback
  var n = Number(value)
  return isFinite(n) && n >= 0 && n <= maximum ? n : fallback
}

function colorChannels(value) {
  if (value === "transparent") return [0, 0, 0, 0]
  if (/^#[0-9a-f]{3}$/.test(value)) {
    value = "#" + value[1] + value[1] + value[2] + value[2] + value[3] + value[3]
  }
  if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/.test(value)) return null
  return [parseInt(value.slice(1, 3), 16) / 255, parseInt(value.slice(3, 5), 16) / 255,
          parseInt(value.slice(5, 7), 16) / 255, value.length === 9 ? parseInt(value.slice(7, 9), 16) / 255 : 1]
}

function decodePortalField(value) {
  return decodeURIComponent(String(value))
}

function parsePortalConfig(parentValue, parentsValue, kidsValue) {
  var result = { parent: "", parents: {}, kids: {}, loaded: false }
  try {
    var parentVal = String(parentValue || "")
    var parentsVal = String(parentsValue || "")
    var kidsVal = String(kidsValue || "")
    if (parentVal.length > 0 || parentsVal.length > 0 || kidsVal.length > 0) {
      result.parent = parentVal
      if (parentVal.length > 0) result.parents[parentVal] = true
      if (parentsVal.length > 0) {
        var parentEntries = parentsVal.split(",")
        for (var p = 0; p < parentEntries.length; p++) {
          if (parentEntries[p].length > 0) result.parents[parentEntries[p]] = true
        }
      }
      if (kidsVal.length > 0) {
        var entries = kidsVal.split(",")
        for (var i = 0; i < entries.length; i++) {
          var parts = entries[i].split(":")
          if (parts.length === 3 && parts[0].length > 0) {
            var account = decodePortalField(parts[0])
            result.kids[account] = {
              name: decodePortalField(parts[1]),
              avatar: decodePortalField(parts[2])
            }
          }
        }
      }
      result.loaded = true
    }
  } catch (e) {
    // Malformed config leaves both allowlists empty and fails closed.
    return { parent: "", parents: {}, kids: {}, loaded: false }
  }
  return result
}
