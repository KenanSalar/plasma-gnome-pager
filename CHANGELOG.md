# Changelog

Notable changes to Plasma Gnome Pager, newest first. Versions up to 1.8.2 are described on the
[GitHub Releases](https://github.com/KenanSalar/plasma-gnome-pager/releases) page.

## 1.8.3

### Fixed

- **The pager follows reordered desktops.** Moving a desktop, by dragging it in the Grid view or
  reordering it in System Settings, left the pager on the old order. The pill sat on the wrong dot,
  scrolling stepped to the wrong desktops, and the occupied markers and tooltip window lists landed
  on the wrong dots until you removed and re-added a desktop. The pager now picks up the new order
  the moment KWin changes it. This needs Plasma 6.5 or newer, since older versions don't announce a
  reorder.

### Known issues in KWin

These come from KWin itself, so a pager update can't fix them. Both are still present in
KWin 6.8.2.

- **Dragging a desktop's background in the Grid view moves the whole desktop.** The animation looks
  like you're moving its windows to another desktop, but KWin swaps the two desktops' positions
  instead. Drag the window thumbnails if you only want to move windows. Tracked as
  [KDE bug 522278](https://bugs.kde.org/show_bug.cgi?id=522278).
- **With more than one monitor, that move affects every monitor.** Desktops are shared by all
  monitors, even with "Switch desktops independently for each screen" turned on. Moving a desktop
  on one monitor also moves the other monitors' windows, and their Meta+T tiling layouts go with
  them. Tracked as [KDE bug 478132](https://bugs.kde.org/show_bug.cgi?id=478132).
