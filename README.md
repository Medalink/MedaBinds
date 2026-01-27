# MedaBinds

A World of Warcraft addon that automatically displays keybind overlays on cooldown viewer icons, making it instantly clear which keys to press for your abilities, items, and utilities.

## Features

### Automatic Keybind Detection
- Scans all action bars (primary + 7 additional bars)
- Supports Bartender4 custom action bar addon
- Auto-detects trinket keybinds from equipped items
- Parses macros for spell/item bindings
- Recognizes talent-modified spells and class-specific bonus bars (Druid forms, etc.)

### Multi-Viewer Support
- **EssentialCooldownViewer** - Primary cooldowns display
- **UtilityCooldownViewer** - Utility abilities display
- **BuffIconCooldownViewer** - Buff icon overlays
- **BuffBarCooldownViewer** - Buff bar overlays

Each viewer can be toggled independently in settings.

### External Icon Tracking
- Track keybinds on icons from any addon, not just Blizzard viewers
- Persistent tracking across addon reloads
- Auto-reconnection when frames are recreated

### Customization
- **Global Font Settings**: Font family, size, weight, color, and shadow
- **Per-Spell Overrides**: Customize keybind display for individual spells/items
- **Custom Keybinds**: Manually set keybind text for any ability
- **Positioning**: Anchor text to any corner of the icon

### Config Mode
Click any icon while config mode is active (ALT+click by default) to:
- Edit its keybind display settings
- Preview changes in real-time
- See which addon created the frame
- Set custom keybind text

### Smart Keybind Abbreviation
Automatically condenses keybind text for cleaner display:
- Modifiers: `SHIFT` → `S`, `CTRL` → `C`, `ALT` → `A`
- Mouse: `MOUSEBUTTON3` → `M3`, `MOUSEWHEELUP` → `MWU`
- Numpad: `NUMPAD1` → `N1`, `NUMPADPLUS` → `N+`
- Special keys: `SPACEBAR` → `Spc`, `ENTER` → `Ent`

## Installation

1. Download the latest release
2. Extract to your `World of Warcraft/_retail_/Interface/AddOns/` folder
3. Ensure the folder is named `MedaBinds`
4. Restart WoW or reload your UI (`/reload`)

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/mbinds` or `/medab` | Open settings panel |
| `/mbinds config` | Toggle config mode |
| `/mbinds scan` | Force manual keybind rescan |
| `/mbinds reconnect` | Reconnect external icon overlays |
| `/mbinds reset` | Reset all settings to defaults |
| `/mbinds debug` | Toggle debug logging |

### Minimap Button
- **Left-click**: Open settings
- **Right-click**: Toggle config mode
- **Drag**: Reposition around minimap

## Configuration

### Global Style Settings
- Font selection (supports LibSharedMedia fonts if available)
- Font size and outline style
- Text color with alpha
- Shadow color and offset
- Anchor position on icons

### Viewer Toggles
Enable or disable keybind overlays on each type of cooldown viewer independently.

### Behavior Options
- Abbreviate keybinds (shorter text)
- Scan hidden action bars
- Parse macros for abilities
- Auto-disable scanning in combat
- Config mode modifier key (ALT/CTRL/SHIFT)

## Dependencies

MedaBinds includes all required libraries:
- **MedaUI** - UI framework for consistent theming
- **LibStub** - Library versioning
- **LibDataBroker-1.1** - Data broker for minimap button
- **LibDBIcon-1.0** - Minimap button management
- **CallbackHandler-1.0** - Event callbacks

## Supported WoW Versions

- Midnight (12.0+)

## License

MIT License - See [LICENSE](LICENSE) for details.

## Author

Medalink
