.pragma library

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
