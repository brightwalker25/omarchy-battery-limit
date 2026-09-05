# omarchy-battery-limit

A charge cap for the Omarchy bar. The glyph shows the ceiling your battery is
charging to, and the panel behind it sets that ceiling. It offers four standing
caps on a row, a slider for the values between them, and one button that raises
the cap to 100% for travel and then lowers it again on its own.

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-battery-limit.git
omarchy plugin enable brightwalker25.battery-limit --section right
sudo ~/.config/omarchy/plugins/brightwalker25.battery-limit/bin/battery-limit-install
```

The third line is the important one, and it is run once. It grants your account
the right to set the threshold without a password, and it installs the systemd
units that reapply the cap after a reboot or a resume. Without it the panel
still opens and reads the battery correctly, but it refuses every change and
explains why. [INSTALL.md](INSTALL.md) describes what that step writes, the
development install, running the tool from a terminal, and uninstalling.

## Why cap the charge

Lithium cells age from the time they spend at a high state of charge, and a
laptop that lives on mains power spends nearly all of its life in that state.
Holding the charge at 60% rather than 100% slows the process down
substantially. The cost is a smaller reserve on the days you unplug the
machine, which is what the travel button is for.

The panel shows a health figure next to the cap. It is the present capacity of
the pack measured against its capacity when new, and it is the figure that
indicates whether capping is still worth doing on a given machine.

## What it does

| Control | Effect |
|---|---|
| Preset row | Sets a standing cap. Default 60, 70, 80 and 90 percent. |
| Slider | Any cap from 40 to 99, for the values between the presets. |
| Travel button | Raises the cap to 100% for a fixed period, then reverts on its own. |

A standing cap is a decision made once. A travel cap is an exception made on a
particular day. The two are kept apart deliberately: the presets and the slider
cannot reach 100%, and the travel button is the only control that can. A cap
that has been set to 100% and forgotten is the situation this plugin is meant
to prevent, so the only route to 100% is the one that expires by itself.

The override lasts 24 hours by default. Periods of 8 hours, 3 days, 1 week, and
one that does not expire are available in the widget's settings. Clicking the
button again ends the override early. The expiry is checked by a system timer
rather than by the panel, so an override reverts even if the panel is never
opened again.

## Design

A script prints one JSON snapshot and the QML panel renders it. This is the
same arrangement used by `omarchy-system` and `omarchy-vpn-check`, and it keeps
every judgement in a single file that can be run from a terminal:

```bash
./bin/battery-limit --text          # cap, charge, health, and setup state
./bin/battery-limit --pretty        # the JSON the panel consumes
./bin/battery-limit set 60          # a standing cap
./bin/battery-limit set 100 --for 3d
```

### Reading the limit back from the firmware

Every write is followed by a read, and the value that is displayed is the value
that was read back. Firmware is free to round a request to steps of its own,
and some models do. A panel that displayed the request instead would be
reporting an intention while presenting it as a state.

The same distinction runs through the rest of the tool. The bar shows the value
held by the hardware, the configuration file holds the value you asked for, and
when the two disagree the panel reports the disagreement rather than choosing
between them. They disagree in one situation that matters, which is a cap that
was configured but did not survive some later event. Concealing that is how a
user discovers six months afterwards that the cap has not been in force.

### Privileges are granted once, by the installer

Writing the threshold requires root, and a bar panel offers nowhere to type a
password. The installer resolves this once by granting the `wheel` group access
to the sysfs attributes through a udev rule, after which the panel and the CLI
are ordinary unprivileged programs. There is no polkit agent, no password
prompt and no use of sudo while the tool is running.

The units that reapply the cap at boot and after resume do run as root, and
they read the same configuration file that the panel writes. Because that file
is group-writable, the root helper parses it for integers rather than sourcing
it. Sourcing a group-writable file as root would convert the ability to set a
charge limit into the ability to run any command as root, which is not a
reasonable price for three lines of shell.

### Why there are three systemd units

The obvious implementation is a single oneshot service wanted by both
`multi-user.target` and the sleep targets, and it does not work. A oneshot
service with `RemainAfterExit=yes` is still active when the machine resumes, so
systemd finds nothing to start and the cap is never reapplied. Without
`RemainAfterExit` the same unit instead shows as dead after boot. Boot, resume
and expiry are three different events, so they are handled by three units.

Whether the cap survives a suspend at all depends on the model. On this Zenbook
it does, and the resume unit is a precaution that costs one file write.

## Requirements

| Needed | Used for |
|---|---|
| A battery exposing `charge_control_end_threshold` | the cap itself |
| Omarchy shell with plugin support | the bar widget and panel |
| Python 3 | the CLI |
| systemd | reapplying the cap at boot, on resume, and expiring the override |

## Hardware support

Nothing in this plugin is specific to a vendor beyond the kernel driver that
exposes the attribute. Batteries are found by scanning `/sys/class/power_supply`
for nodes whose `type` is `Battery` and which carry
`charge_control_end_threshold`, so neither the name `BAT0` nor any particular
driver is assumed. One command establishes whether a given machine is
supported:

```bash
cat /sys/class/power_supply/*/charge_control_end_threshold
```

If that prints a number, the hardware side of the requirement is met. If it
prints nothing, no driver on the machine offers a charge threshold, and the
panel reports that rather than appearing to work.

The plugin has only ever been run on one machine, an ASUS Zenbook with
`asus_nb_wmi` loaded. The behaviour described below is taken from the code and
from the kernel drivers rather than from hardware in hand, so it should be
treated as a description of what the code does, not as a tested support matrix.

Machines with more than one battery are handled by setting the threshold on
every pack that exposes one. The panel and the `status` output take their
headline readings from the first pack, and report a warning if the packs are
capped at different values.

Some drivers, `thinkpad_acpi` among them, also expose
`charge_control_start_threshold`, which is the charge at which the machine
resumes charging, and they reject an end threshold below it. When a driver
refuses a write for that reason, the start threshold is lowered five points
below the new cap and the write is attempted again. The start threshold is
touched only after the driver has already refused the write, so on hardware
that does not impose the restriction it is left exactly as the firmware had it.
ThinkPad firmware also retains thresholds across a reboot without help, which
makes the boot and resume units redundant on those machines rather than
harmful.

Some vendors expose no such attribute at all. Many Lenovo IdeaPads offer a
`conservation_mode` toggle on the platform device instead, which is a fixed
preset rather than a threshold, and this plugin does not read it. Support for
Dell, Framework, MSI, System76 and Samsung machines arrived in different kernel
versions through different drivers, so on those the answer depends on the
kernel rather than on this plugin.

On a desktop, or on any machine with no battery, the widget still draws its
glyph and the panel displays a warning explaining that there is nothing to cap.

The firmware remains the authority throughout. It may round a requested cap to
steps of its own, refuse a value outright, or hold the charge below the cap and
decline to top it up, and none of that can be overridden from here. Since every
write is read back, what the panel displays is what the battery is holding.
This plugin cannot charge past a cap enforced elsewhere in firmware, discharge
a pack down to a target, or schedule anything by time of day.

The installer assumes a system of Arch's shape: `wheel` as the administrative
group, udev rules under `/etc/udev/rules.d`, and systemd. That is a reasonable
assumption for an Omarchy plugin, but on a Debian-derived system the group
would need to be `sudo`.

## Why the stock Omarchy battery panel disagrees

The stock `omarchy.power` panel reports a different limit from this one, and
the stock panel is the one that is wrong. `omarchy-battery-status` reads
`charge-end-threshold` from UPower and falls back to sysfs only when UPower
returns nothing, but UPower always returns something. On this hardware it
reports a 75-80% pair alongside `ChargeThresholdEnabled = false`. Those are the
values UPower would apply if something asked it to, not a reading of the
firmware, and setting the threshold to 60, 70 or 95 does not move them.

The sysfs fallback therefore never runs, and the stock panel reports a limit
that is not in force. This plugin reads sysfs directly and reports what the
battery is actually holding.

There is no way to correct this from outside Omarchy. UPower provides no method
to re-read the value: `Refresh()` is not implemented on the device interface,
and `EnableChargeThreshold` only toggles UPower's own preset. Raising a
synthetic udev event does not help either, which was tried before the cause was
understood. The fix belongs in `omarchy-battery-status`, which should either
prefer sysfs or check `ChargeThresholdEnabled` before trusting the pair of
values UPower reports.

## License

MIT. See [LICENSE](LICENSE), which also carries the notice for the Omarchy
plugins this widget's scaffolding is derived from.
