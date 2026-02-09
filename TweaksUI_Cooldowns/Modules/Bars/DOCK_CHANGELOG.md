# Timer Bars - Dock System Update

## New File: BarsDock.lua (448 lines)

Full dock container module that groups all timer bars into a single movable frame.

**Core features:**
- Single dock frame (`TUICD_BarsDock`) with dark backdrop and layout-mode label
- FIFO arrival order tracking (first bar to trigger gets center slot)
- Center-out positioning algorithm (matching icon dock behavior)
- Layout throttling at 0.02s to batch rapid show/hide changes
- Vertical and horizontal stacking orientations
- Start/Center/End justify modes
- Position persistence to saved variables

**Layout engine:**
- `DoLayout()` measures all visible bars, computes dock size, positions bars
- Vertical mode: stacks top-to-bottom, auto-sizes width to widest bar
- Horizontal mode: stacks left-to-right, auto-sizes height to tallest bar
- Center justify uses center-out algorithm; Start/End use sequential placement
- Empty dock: 1x1px invisible when not in layout mode, 220x50 placeholder in layout mode

**Layout mode integration:**
- `EnterLayoutMode()` - enables mouse drag, shows label, forces all bars visible
- `ExitLayoutMode()` - disables mouse, hides label, saves position
- Dock frame is draggable only during layout mode

**Enable/Disable switching:**
- `Enable()` - re-parents all bars from individual TUIFrames into dock, destroys TUIFrames
- `Disable()` - re-parents bars to UIParent, restores saved positions

---

## Modified: BarsData.lua

**Added dock settings** (line 122+):
```lua
DOCK_DEFAULTS = {
    enabled = false,         -- default standalone mode
    orientation = "VERTICAL",
    spacing = 2,             -- px between bars
    justify = "CENTER",      -- START, CENTER, END
    sortMode = "arrival",    -- arrival (FIFO) or list (alphabetical)
}
```

**New accessors:**
- `GetDockSettings()` - returns dock config table
- `SetDockSetting(key, value)` - updates and fires BARS_DATA_UPDATED
- `IsDockEnabled()` - boolean check

---

## Modified: BarsFrames.lua

**CreateBar branching:**
- Dock mode: parents bar frame directly to dock container (no TUIFrame)
- Standalone mode: creates individual TUIFrame per bar (existing behavior)

**Show/hide hooks:**
- `UpdateBarDisplay()` now tracks show/hide transitions via `wasShown = frame:IsShown()`
- Notifies `BarsDock:OnBarShown(barKey)` when bar transitions visible
- Notifies `BarsDock:OnBarHidden(barKey)` when bar transitions hidden or disabled

**DestroyBar cleanup:**
- Notifies dock of bar removal before destroying frame

**Layout mode delegation:**
- Dock enabled: delegates to `BarsDock:EnterLayoutMode()` / `ExitLayoutMode()`
- Standalone: existing per-bar drag behavior unchanged

**Config change notification:**
- `OnConfigChanged` notifies `BarsDock:OnBarConfigChanged()` for relayout on size changes

---

## Modified: BarsUI.lua

**Dock settings panel** (shown when no individual spell is selected):
- Enable/disable checkbox with mode indicator text
- Orientation toggle buttons (Vertical / Horizontal)
- Spacing slider (0-20px range)
- Justify toggle buttons (Start / Center / End)
- Sort mode toggle buttons (Arrival FIFO / Alphabetical)
- Info text explaining layout mode and sort behaviors

---

## TOC Load Order

BarsDock.lua should load **after** BarsData.lua and **before** or alongside BarsFrames.lua:

```
Modules\Bars\BarsData.lua
Modules\Bars\BarsDock.lua
Modules\Bars\BarsFrames.lua
Modules\Bars\BarsUI.lua
```

BarsFrames uses a lazy `GetDock()` resolver so load order between BarsDock and BarsFrames is flexible.

---

## Usage

1. Open bars settings (`/tuicd` > Timer Bars)
2. With no spell selected, the right panel shows Dock Settings
3. Check "Enable Dock" to switch from standalone to dock mode
4. Use orientation/spacing/justify/sort controls to configure layout
5. Use `/tuicdlayout` to move the dock container
