# Reverse MX Master 4 horizontal scrolling on Windows

Reverse the left and right scroll direction of the Logitech MX Master 4 thumb
wheel with a one-time PowerShell command.

## Quick start

Connect the mouse and open **Windows PowerShell as Administrator**. The script
needs administrator privileges to write the device setting under `HKLM` and
restart the mouse interface. The restart requires Windows 10 version 2004 or
later, or Windows 11. [Microsoft PnPUtil documentation][pnputil]

The Logi Options+ thumb-wheel direction setting can conflict with this script.
Use one method to control horizontal scrolling. If you prefer to set the
direction in Logi Options+, restore the Windows setting with `-Value 0`.
[Logitech thumb-wheel settings][options-plus]

This downloads and runs the current GitHub version in memory. Review the
[PowerShell script][script] before running it.

```powershell
irm 'https://github.com/softerist/logi/raw/main/Flip-Horizontal-Scroll.ps1' | iex
```

If Windows shows the Logi Bolt receiver in place of the mouse name, the script
prompts you to unplug the receiver and reconnect it to the same USB port. It
checks that the same mouse interface disappears and returns. If Windows is
slow to detect the change, wait a moment and press Enter to check again.
Press Q at either prompt to cancel.

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
.\Flip-Horizontal-Scroll.ps1 -WhatIf

# Explicitly set reversed horizontal scrolling
.\Flip-Horizontal-Scroll.ps1

# Restore the standard horizontal scroll direction
.\Flip-Horizontal-Scroll.ps1 -Value 0
```

The default value is `1`, which reverses horizontal scrolling. `-WhatIf`
skips the write and restart.

## Device selection and restart

A [Bolt receiver can pair with multiple devices][bolt]. Use the receiver for
your MX Master 4 when prompted. If detection still fails, run the local script
with `-Identify` and follow the prompts to disconnect and reconnect the mouse
or its receiver.

You can also specify the exact Windows mouse instance ID if you know it.

```powershell
.\Flip-Horizontal-Scroll.ps1 -InstanceId '<exact mouse instance ID>' -Value 1
```

If the value is already set and the direction still looks wrong, use
`-RestartDevice` from an administrator PowerShell to reload the setting. Keep
the same device selection.

## License

[MIT](LICENSE)

[bolt]: https://www.logitech.com/en-us/shop/p/logi-bolt-usb-receiver
[options-plus]: https://support.logi.com/hc/en-ca/articles/28321445268247-Getting-Started-MX-Master-4
[pnputil]: https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax#restart-device
[script]: Flip-Horizontal-Scroll.ps1
