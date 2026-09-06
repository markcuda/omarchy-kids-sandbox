// gridnav.js — pure tile-index math for the Level 1/2 launcher
// (share/launcher/shell.qml), shared between key navigation and the
// GridView layout so they can never disagree on how many columns the
// grid has (issue #43: key nav used a hardcoded `columns: 4` while the
// GridView actually drew five per row -- Down from row1/col4 landed on
// row2/col3 instead of row2/col4, and Right from row2/col3 didn't move
// at all).
//
// shell.qml imports this as `import "gridnav.js" as GridNav` and binds
// its own column count to `GridNav.columnsFor(grid.width, grid.cellWidth)`
// -- the exact inputs GridView itself uses to lay tiles out -- instead of
// a separate number that can drift out of sync. Plain top-level function
// declarations (no `.pragma library`) so this file is both a valid QML
// JS import and plain JS a `node -e` one-liner can `eval()` directly for
// test/shell.d/launcher-grid-test.sh, which has no Quickshell to run
// shell.qml itself against.
//
// Left/Right: this repo's design choice for "wrap to next/previous row
// (or clamp consistently, state which and why)" (issue #43) is a plain
// sequential index +/-1, clamped only at the very first/last tile.
// Tiles are laid out row-major (left to right, top to bottom), so
// index+1 from a row's last column already *is* the next row's first
// column -- no separate row-boundary check needed, and none of the kind
// that caused the bug (a hardcoded columns count baked into a `%`/`<`
// comparison). The only clamp is at the two global edges, so Right at
// the very last tile and Left at the very first tile hold still instead
// of wrapping all the way around the grid.
//
// Up/Down: clamp at the top/bottom edge -- if the tile directly above or
// below the highlight doesn't exist (top row, bottom row, or a ragged
// last row shorter than a full row), the highlight holds still rather
// than jumping to some other tile.

function columnsFor(width, cellWidth) {
    if (!width || width <= 0 || !cellWidth || cellWidth <= 0) return 1;
    return Math.max(1, Math.floor(width / cellWidth));
}

function moveLeft(index) {
    return index > 0 ? index - 1 : index;
}

function moveRight(index, length) {
    return index + 1 < length ? index + 1 : index;
}

function moveUp(index, columns) {
    return index - columns >= 0 ? index - columns : index;
}

function moveDown(index, columns, length) {
    return index + columns < length ? index + columns : index;
}

function visibleTiles(tiles, showMissing) {
    if (showMissing === true) return tiles;
    return tiles.filter(function(tile) {
        return tile && tile.installed === true;
    });
}

// Node-only: lets test/shell.d/launcher-grid-test.sh `eval()` this file
// after pre-declaring `module` and then call these via `module.exports`.
// The QML JS import environment never defines a global `module`, so this
// block is inert there.
if (typeof module !== "undefined") {
    module.exports = {
        columnsFor: columnsFor,
        moveLeft: moveLeft,
        moveRight: moveRight,
        moveUp: moveUp,
        moveDown: moveDown,
        visibleTiles: visibleTiles
    };
}
