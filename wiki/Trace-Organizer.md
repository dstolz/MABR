# Trace Organizer

The **Trace Organizer** (`abr.traces.Organizer`) is an interactive display window for visualizing, comparing, and managing collections of ABR waveforms (traces). It is used for post-acquisition inspection and can display data from a single session or multiple sessions.

---

## Opening the Trace Organizer

From the Control Panel's **Utilities** tab, click **Trace Organizer**, or launch it from the MATLAB Command Window:

```matlab
to = abr.traces.Organizer;
```

You can also load a saved Trace Organizer file directly:

```matlab
to = abr.traces.Organizer('path/to/organizer.mat');
```

---

## Interface Overview

The Trace Organizer displays all traces stacked vertically in a single axes. Traces are organized by group and sorted by user-defined properties (e.g., frequency or sound level).

---

## Mouse Interactions

| Action | Effect |
|--------|--------|
| **Left-Click on trace** | Select that trace (deselects all others) |
| **Left-Click on background** | Deselect all traces |
| **Ctrl + Left-Click** | Add or remove a trace from the current selection |
| **Shift + Left-Click** | Select a contiguous range of traces |
| **Ctrl + Shift + Left-Click** | Select all traces within the same group |

---

## Keyboard Shortcuts

### File Operations

| Key | Action |
|-----|--------|
| `s` | Save current Trace Organizer to file |
| `o` | Open a saved Trace Organizer file |
| `f` | Export the figure as an image (JPG, TIF, PNG, etc.) or vector file (PDF, EPS, etc.) |

### Display Adjustments

| Key | Action |
|-----|--------|
| `k` | Increase vertical spacing between traces |
| `m` | Decrease vertical spacing between traces |
| `j` | Increase trace amplitude (vertical scale) |
| `n` | Decrease trace amplitude (vertical scale) |
| `i` | Equalize vertical spacing between all traces |
| `v` | Overlap selected traces (remove spacing) |

### Trace Management

| Key | Action |
|-----|--------|
| `a` | Select all traces |
| `c` | Clear all traces from the display |
| `d` | Delete selected traces |
| `e` | Export selected traces to the MATLAB workspace |
| `g` | Group selected traces |
| `u` | Ungroup selected traces |
| `p` | Pop out selected trace(s) into a new Trace Organizer window |
| `q` | Change the color of selected traces |
| `h` | Toggle visibility of trace labels (selected traces, or all if none selected) |

---

## Grouping Traces

Traces can be grouped to visually associate related waveforms (e.g., all responses at a given frequency). Groups share a common color and can be selected, moved, and exported together.

- **Group:** Select two or more traces and press `g`.
- **Ungroup:** Select grouped traces and press `u`.
- **Group color:** Press `q` to assign a color to selected traces.

---

## Sorting and Organization

Traces are displayed in the order they were added, optionally sorted by one or more signal properties (e.g., frequency, sound level). Set the `SortBy` and `SortOrder` properties programmatically:

```matlab
to.SortBy    = {'frequency', 'soundLevel'};
to.SortOrder = {'ascend',    'descend'};
```

---

## Exporting Traces

### Export to Workspace

Select one or more traces and press `e`. The selected traces are exported as a structure array to the MATLAB workspace.

### Export Figure

Press `f` to open a save dialog. Supported formats include:
- Raster: JPG, TIF, PNG, BMP
- Vector: PDF, EPS, SVG

---

## Saving and Loading

- **Save (`s`):** Saves the current Trace Organizer (traces, grouping, display settings) to a `.mat` file.
- **Open (`o`):** Loads a previously saved Trace Organizer file.
- **Drag-and-Drop:** Drag a saved `.mat` file onto the Trace Organizer window to load it.

---

## Programmatic Usage

```matlab
% Create a Trace Organizer and add ABR objects
to = abr.traces.Organizer;
to.add_trace(myABRobject);

% Adjust display properties
to.YScaling = 0.5;   % vertical scale factor for all traces
to.YSpacing = 1.2;   % vertical spacing between traces
```
