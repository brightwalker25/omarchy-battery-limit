# Installing Battery Limit

The plugin is a bar widget for the Omarchy shell. It ships its own CLI, so
there is no separate binary to place on `PATH`. There is one privileged step,
run once, and it is the subject of most of this document.

For what the panel shows and why the controls are arranged the way they are,
see the [README](README.md).

## Requirements

| Needed | Used for |
|---|---|
| A battery exposing `charge_control_end_threshold` | everything |
| Omarchy shell with plugin support | the bar widget and panel |
| Python 3 | the CLI |
| systemd | reapplying the cap at boot and on resume, and expiring an override |

Check the attribute is there before installing anything:

```bash
cat /sys/class/power_supply/*/charge_control_end_threshold
```

A number means you are set. "No such file or directory" means no driver on this
machine exposes a charge threshold. On ASUS hardware that usually means the
`asus_nb_wmi` module is not loaded, which `lsmod | grep asus_nb_wmi` will tell
you. On other hardware it more often means the vendor's driver does not offer
one, or offers it only on a newer kernel. See the hardware support section of
[README.md](README.md#hardware-support), which also covers the ThinkPad start
threshold, machines with two packs, and batteries not named `BAT*`.

## Installing

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-battery-limit.git
omarchy plugin enable brightwalker25.battery-limit --section right
sudo ~/.config/omarchy/plugins/brightwalker25.battery-limit/bin/battery-limit-install
```

`omarchy plugin add` clones the repository into `~/.config/omarchy/plugins/`
and `enable` writes the widget into `bar.layout` in
`~/.config/omarchy/shell.json`. Passing `--enable` to `add` does both in one
step and prompts for the section.

Placement accepts more than a section. To put the cap next to the power widget
rather than at the end of the row:

```bash
omarchy plugin enable brightwalker25.battery-limit --section right --before omarchy.power
```

`--after <id>` and `--index <n>` work the same way. The section must be `left`,
`center` or `right`.

## What the privileged step installs

Everything the installer writes is listed here, because a script asking for
root should say what it is going to do. None of it points back at the plugin
directory, so the cap keeps holding if the plugin is later removed, and a
development checkout can be moved without breaking the machine.

| Path | Purpose |
|---|---|
| `/etc/omarchy-battery-limit.conf` | the standing cap and any travel override, as integers. Owned `root:wheel`, mode 664 |
| `/etc/udev/rules.d/99-omarchy-battery-limit.rules` | gives the `wheel` group write access to the threshold, on every boot |
| `/usr/local/lib/omarchy-battery-limit/apply` | a POSIX sh helper that puts the configured cap back |
| `/etc/systemd/system/omarchy-battery-limit.service` | applies the cap at boot |
| `/etc/systemd/system/omarchy-battery-limit-resume.service` | reapplies it after suspend or hibernate |
| `/etc/systemd/system/omarchy-battery-limit.timer` | runs the service every ten minutes so a travel override expires on its own |

The installer refuses to run if no battery exposes the attribute, if it cannot
tell which account to grant access to, or if that account is not in the `wheel`
group. It is safe to run again; it overwrites what it wrote before and leaves
an existing config file alone.

It grants access to the `wheel` group rather than to your user, because udev
sets a group on the attribute and cannot set an ACL entry for one account. On
this machine `wheel` is already the group with sudo, so it grants nothing that
was not available with a password.


## Installing for development

Working on the plugin means running it from a checkout rather than from a clone
that `omarchy plugin update` will overwrite. Two steps live outside the
repository, so cloning it alone does not install it.

```bash
git clone https://github.com/brightwalker25/omarchy-battery-limit.git ~/Work/omarchy-battery-limit
ln -s ~/Work/omarchy-battery-limit ~/.config/omarchy/plugins/brightwalker25.battery-limit
omarchy plugin enable brightwalker25.battery-limit --section right
sudo ~/Work/omarchy-battery-limit/bin/battery-limit-install
```

The symlink is what makes edits live: the plugin id is the link name, so it has
to be exactly `brightwalker25.battery-limit` whatever the checkout is called.
Changes to the CLI take effect on the next poll, and changes to the QML on the
next shell restart.

Validate the manifest after editing it:

```bash
omarchy plugin validate ~/Work/omarchy-battery-limit
```

## Running it from a terminal

The CLI makes every judgement the panel displays, so anything the panel reports
can be reproduced and read at the command line:

```bash
~/.config/omarchy/plugins/brightwalker25.battery-limit/bin/battery-limit --text
```

| Command | Effect |
|---|---|
| `status` | the cap, the charge, the health and the setup state. The default |
| `set <percent>` | set the standing cap, from 40 to 100, and clear any override |
| `set 100 --for 3d` | raise the cap as a travel override that expires in three days |
| `apply` | put the configured cap back, retiring an override that has run out |
| `clear-travel` | end an override now and return to the standing cap |

`--text` prints it for a human, `--pretty` indents the JSON, and both are
accepted on either side of the subcommand. Durations are `8h`, `3d`, `2w`,
`90m` and so on, or `off` for an override that does not expire.

Exit status is 0 when the operation succeeded and 1 when it did not. `status`
succeeds even on a machine with no controllable battery, and the answer is in
the JSON.

## Settings

Configured through the widget's settings in the Omarchy shell, or by hand in
the widget's entry in `~/.config/omarchy/shell.json`.

| Key | Default | Effect |
|---|---|---|
| `showLimitInBar` | true | print the cap next to the bar glyph |
| `presets` | `60, 70, 80, 90` | the one-click standing caps, as percentages |
| `travelDuration` | `24 hours` | how long a travel override lasts before reverting |
| `refreshIntervalMs` | 10000 | how often the panel re-reads the battery while open |

`presets` accepts values from 40 to 99. 100 is deliberately not available here;
it belongs to the travel button, which expires. Four presets fit comfortably on
one row.

## Binding it to a key

The panel answers on IPC, including two actions that need no panel at all, so
travel mode can be turned on from a keybinding on the way out of the door:

```lua
o.bind("SUPER SHIFT", "B", "Charge to full for travel",
  "omarchy-shell brightwalker25.battery-limit travel")
```

`standing` ends the override, `toggle` opens and closes the panel, and
`refresh` re-reads the battery.

## Troubleshooting

**The panel says the threshold is not writable.** The privileged step has not
been run, or it ran before the current boot. Run it, and confirm with
`ls -l /sys/class/power_supply/BAT*/charge_control_end_threshold`, which should
show group `wheel` and mode `-rw-rw-r--`.

**The cap is right but the panel says it will not survive a reboot.** The udev
rule is in place but the units are not, which happens if the installer was
interrupted. Run it again.

**The cap reads back as something other than what was set.** The firmware
rounded it. This is reported rather than hidden: the panel shows the value the
battery actually holds. Use one of the presets, which are round numbers most
firmware accepts as given.

**Omarchy's own battery panel shows a different limit from this one.** It is
wrong and this one is right, and nothing you can configure will reconcile them.
`omarchy-battery-status` reads `charge-end-threshold` from UPower and falls back
to sysfs only when UPower returns nothing. UPower always returns something: on
this hardware it reports a 75-80% pair that it would apply if asked, alongside
`ChargeThresholdEnabled = false`, and it never reads the threshold the firmware
is actually holding. So the fallback is dead code and the stock panel reports a
limit that is not in force. The cap that is in force is whatever
`cat /sys/class/power_supply/BAT*/charge_control_end_threshold` says, which is
what this plugin reads directly.

**The panel shows a cap that disagrees with what is configured.** Something
reset the threshold since the last apply. `battery-limit apply` puts the
configured value back, and `systemctl status omarchy-battery-limit.timer` will
say whether the ten-minute check is running.

**Charge sits below the cap and will not climb.** ASUS firmware does not
restart charging the moment you lower and raise the cap; it waits for the
charge to fall a few percent below the new ceiling first. Unplugging briefly
prompts it.

**The health figure looks wrong.** It is capacity now against capacity when
new, as the battery itself reports them. A pack that has not been through a
full discharge in a long time reports a stale full-charge figure, and the
number moves after one.

## Uninstalling

```bash
sudo ~/.config/omarchy/plugins/brightwalker25.battery-limit/bin/battery-limit-install --uninstall
omarchy plugin disable brightwalker25.battery-limit
omarchy plugin remove brightwalker25.battery-limit
```

The first line removes the udev rule, the helper and the units. `disable` takes
the widget out of the bar layout and leaves the files in place; `remove`
deletes the plugin directory too. For a development install, remove the symlink
rather than the checkout:

```bash
omarchy plugin disable brightwalker25.battery-limit
rm ~/.config/omarchy/plugins/brightwalker25.battery-limit
```

None of this changes the threshold currently on the battery, and none of it
deletes `/etc/omarchy-battery-limit.conf`. Uninstalling leaves the cap in force
rather than silently returning the machine to charging to full. To lift it:

```bash
echo 100 | sudo tee /sys/class/power_supply/BAT*/charge_control_end_threshold
sudo rm /etc/omarchy-battery-limit.conf
```
