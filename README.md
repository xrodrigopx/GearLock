# GearLock

Never sell your gear by accident again. A World of Warcraft: Forever addon.

GearLock lets you lock items so they can't be lost to a misclick or "Sell All Junk". If a locked item gets sold anyway, GearLock buys it back instantly.

## Features

- Lock any item with a keybind or a slash command.
- Locked items show a padlock and a grayscale icon in your bags.
- Tooltip line shows why an item is locked.
- Automatic buyback if a locked item is sold.
- Optional automatic locking for items in your Equipment Manager sets.
- Optional "lock all gear" mode (weapons and armor, with a minimum quality you choose).
- Per-item exceptions, so automatic rules never get in your way.

## Installation

The easiest way is to install it from CurseForge. To install manually:

1. Download this repository as a ZIP and extract it.
2. Rename the extracted folder to `GearLock` and copy it into your Forever AddOns folder (`World of Warcraft/_forever_/Interface/AddOns/`).
3. Restart the game or type `/reload`.

## Usage

Hover an item in your bags and press your keybind (Options > Keybindings > AddOns > GearLock), or type `/gl toggle`. You can also use `/gl toggle [shift-click an item link]`.

| Command | What it does |
|---|---|
| `/gl toggle [link]` | Lock or unlock the hovered item (or the linked item) |
| `/gl list` | List manually locked items |
| `/gl sets` | Toggle locking for Equipment Manager set items |
| `/gl all` | Toggle "lock all gear" mode |
| `/gl quality N` | Minimum quality for that mode (2 = green, 3 = blue, 4 = epic) |
| `/gl debug` | Diagnostic info about detected bag slots |

`/gearlock` works as an alias for `/gl`.

## Notes

- Locking is per item type, not per copy: duplicates of a locked item are also locked.
- Buyback needs enough gold and free bag space.
- Built for WoW: Forever (interface 16001).

## Reporting bugs

Open an issue and include the output of `/gl debug` with your bags open.

## License

[MIT](LICENSE) © Rodrigo Perdomo
