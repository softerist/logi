# Reverse MX Master 4 horizontal scrolling on Windows

Reverse the left and right scroll direction of the Logitech MX Master 4 thumb
wheel with a one-time PowerShell command.

## Quick start

Connect the mouse and open **Windows PowerShell as Administrator**. The script
needs administrator privileges to write the device setting under `HKLM` and
restart the mouse interface. The restart requires Windows 10 version 2004 or
later, or Windows 11. [Microsoft PnPUtil documentation][pnputil]

This downloads and runs the current GitHub version in memory. Review the
[PowerShell script][script] before running it.

```powershell
irm ('https://raw.githubusercontent.com/softerist/logi/main/' +
    'mx-master-4-revert-horizontal-scroll/Flip-Horizontal-Scroll.ps1') `
    -ErrorAction Stop |
    ForEach-Object { iex ("& {`n" + $_ + "`n}") }
```

The mouse may stop responding briefly while Windows restarts its interface.
Reboot if the script reports that Windows requires it. Test the thumb wheel in
an app with horizontal scrolling, such as a wide spreadsheet.

## Why Logi Options+ is optional

Windows handles standard mouse scrolling through its HID mouse driver. The
script uses Windows Plug and Play to find the mouse and writes the
`FlipFlopHScroll` DWORD under that device instance's `Device Parameters` key.
It then uses the built-in `pnputil.exe` to restart that interface so Windows can
pick up the setting. The registry value stays on this Windows installation
after the script exits, so this setting needs no Logi Options+ installation or
background process. The change applies to horizontal scrolling for the selected
device instance. A different PC or a connection that creates a new device
instance may need its own setting.

## Run locally, preview, or restore

Download [the script][script] or clone this repository, then open PowerShell in
the folder containing `Flip-Horizontal-Scroll.ps1`.

```powershell
# Preview the target and requested change
.\Flip-Horizontal-Scroll.ps1 -Value 1 -WhatIf

# Explicitly set reversed horizontal scrolling
.\Flip-Horizontal-Scroll.ps1 -Value 1

# Restore the standard horizontal scroll direction
.\Flip-Horizontal-Scroll.ps1 -Value 0
```

A run without `-Value` creates the setting with value `1` only if it is missing.
If the setting already exists, use `-Value 1` to set it explicitly. `-WhatIf`
skips the write and restart.

## If automatic detection fails

Automatic detection looks for the MX Master 4 name in the connected mouse
interface or its device metadata. If Windows reports a generic name or multiple
matches, use `-Identify` and follow the prompts to disconnect and reconnect only
the MX Master 4. Plug the Bolt receiver back into the same port if you unplug it.

```powershell
.\Flip-Horizontal-Scroll.ps1 -Identify -Value 1
```

You can also specify the exact Windows mouse instance ID if you know it.

```powershell
.\Flip-Horizontal-Scroll.ps1 -InstanceId '<exact mouse instance ID>' -Value 1
```

If the registry write succeeds and the device restart fails, open PowerShell as
Administrator and retry with `-RestartDevice`. Use the same `-InstanceId` or
`-Identify` selection if you needed one before.

## License

[MIT](LICENSE)

[pnputil]: https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax#restart-device
[script]: mx-master-4-revert-horizontal-scroll/Flip-Horizontal-Scroll.ps1
