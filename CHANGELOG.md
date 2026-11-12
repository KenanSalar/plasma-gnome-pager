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
- **Rename Current Desktop… renames this screen's desktop.** With "Switch desktops independently
  for each screen" turned on, the menu entry could open the desktop that was current on another
  monitor.

### Changed

- **A longer pill by default.** The current desktop's pill is now 4.5 times as long as it is
  thick, up from 3.5. If you picked another Pill length, yours stays; set it to 3.5 for the old
  look.
- **Occupied desktops are marked by default.** A desktop with open windows now gets a hollow ring
  around its dot out of the box, where before the markers were off. In the Filled & ring style,
  whose dots are already rings, the ring fills in instead. If you had the markers on with the
  Sliding pill and the Filled style, they switch to the hollow ring too; pick Filled under
  Occupied desktops to keep it. To go back to plain dots, turn off "Highlight desktops with open
  windows".
- **Behind-the-scenes cleanup.** The widget's code now uses standard JavaScript modules, which
  lets the project check and format it with oxlint and oxfmt. Apart from the changes above,
  nothing should look or behave differently.

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
