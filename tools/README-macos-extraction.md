# Reproducing the AppleHDA extraction

These three scripts reproduce the provenance chain behind
`docs/AMPLIFIER-PROTOCOL.md`. They download nothing but official Apple data and
execute nothing that was downloaded.

```
# 1. what Apple offers this board (no download)
./macbook91-fetch-macos-recovery info latest

# 2. fetch it (~650 MB)
./macbook91-fetch-macos-recovery download latest ./latest

# 3. verify Apple's RSA signature over the chunk table, and every chunk
./macbook91-verify-recovery-image latest/BaseSystem.dmg \
    latest/BaseSystem.chunklist /path/to/macrecovery.py

# 4. unpack (needs the 7zip package) and pull out the kernel collection
7z x -y -owork latest/BaseSystem.dmg \
    "macOS Base System/System/Library/KernelCollections/BaseSystemKernelExtensions.kc"

# 5. resolve symbols inside one kext of the collection
./macbook91-kc-symbols \
    "work/macOS Base System/System/Library/KernelCollections/BaseSystemKernelExtensions.kc" \
    com.apple.driver.AppleHDA TDMAmpTAS5758L FunctionGroupCS4208
```

Notes:

- The board id is read from this machine's own DMI
  (`/sys/class/dmi/id/board_name` = `Mac-9AE82516C7C6B903`), so the image is
  the one Apple ships for *this* model.
- `macbook91-verify-recovery-image` reads Apple's EFI ROM public key out of
  OpenCore's `macrecovery.py` **as data**. That script is never executed; the
  osrecovery protocol is reimplemented in
  `macbook91-fetch-macos-recovery` instead, so no downloaded code runs.
- `macrecovery.py` comes from OpenCorePkg (<https://github.com/acidanthera/OpenCorePkg>,
  path `Utilities/macrecovery/macrecovery.py`). The tools were written against
  revision `51535b667f288e219b64065d3a2ee6a5e82cb1ae`, where the file has the git
  blob id `5d53d2179bcea0f916bd6305d92db334b2e5737e`; compare with
  `git hash-object macrecovery.py` before use. It is not part of this repository.
- The downloaded images and anything extracted from them are proprietary Apple
  material. Keep them outside this repository. They are not redistributable.
