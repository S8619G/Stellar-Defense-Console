"""1.1.0: let Windows choose the graphics chip for an exported Windows game.

The Godot 4.7 Windows export template sets two values, NvOptimusEnablement and
AmdPowerXpressRequestHighPerformance, to 1. On laptops with two graphics chips that
forces the game onto the gaming (Nvidia or AMD) chip and ignores the player's own
choice in Windows Graphics settings, Nvidia Control Panel or AMD Software.

This step sets both values to 0 in an exported EXE. The game then runs on the chip
Windows, Nvidia Control Panel or AMD Software chooses for it (usually the power-saving
built-in chip), and players can still pick the gaming chip there.

Usage: python3 patch_windows_gpu.py <game.exe> [<game.exe> ...]
       python3 patch_windows_gpu.py --check <game.exe>   (report only, no change)
Needs the pefile package (pip install pefile).
"""
import struct
import sys

import pefile

NAMES = (b"NvOptimusEnablement", b"AmdPowerXpressRequestHighPerformance")


def values(path):
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"]])
    found = {}
    for sym in getattr(pe, "DIRECTORY_ENTRY_EXPORT", None).symbols if hasattr(pe, "DIRECTORY_ENTRY_EXPORT") else []:
        if sym.name in NAMES:
            found[sym.name.decode()] = (pe.get_offset_from_rva(sym.address), pe.get_dword_at_rva(sym.address))
    pe.close()
    return found


def patch(path):
    found = values(path)
    if len(found) != len(NAMES):
        raise SystemExit(f"{path}: expected both graphics-chip values, found {sorted(found)}")
    with open(path, "r+b") as f:
        for name, (offset, _) in found.items():
            f.seek(offset)
            f.write(struct.pack("<I", 0))
    after = values(path)
    if any(v != 0 for _, v in after.values()):
        raise SystemExit(f"{path}: patch did not take: {after}")
    print(f"{path}: " + ", ".join(f"{n} {found[n][1]} -> 0" for n in sorted(found)))


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    if not paths:
        raise SystemExit(__doc__)
    for p in paths:
        if check:
            print(p, {n: v for n, (_, v) in values(p).items()})
        else:
            patch(p)


if __name__ == "__main__":
    main(sys.argv[1:])
