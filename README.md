# omarchy-battery-limit

A charge cap for the Omarchy bar. The glyph shows the ceiling your battery is
charging to, and the panel behind it sets that ceiling: four standing caps on a
row, a slider for the values between them, and one button that raises the cap
to 100% for travel and then puts it back on its own.

```bash
omarchy plugin add https://github.com/brightwalker25/omarchy-battery-limit.git
omarchy plugin enable brightwalker25.battery-limit --section right
sudo ~/.config/omarchy/plugins/brightwalker25.battery-limit/bin/battery-limit-install
```

The third line is the one that matters and it runs once. It grants your account
the right to set the threshold without a password, and installs the units that
put the cap back after a reboot or a resume. Without it the panel opens, reads
correctly, and refuses every change with the reason why.
[INSTALL.md](INSTALL.md) covers what that step writes, the development install,
running the tool from a terminal, and uninstalling.

## Why cap at all

Lithium cells age from time spent at a high state of charge, and a laptop that
lives on mains spends nearly all of its life there. Holding the charge at 60%
rather than 100% slows that down substantially. The cost is a smaller reserve
on the days you unplug, which is what the travel button is for.

The panel shows the health figure next to the cap for a reason. It is capacity
now against capacity when the pack was new, and it is the number that says
whether capping is worth doing on this machine or whether the argument is
already over.

## What it does

| Control | Effect |
|---|---|
| Preset row | Sets a standing cap. Default 60, 70, 80 and 90 percent. |
| Slider | Any cap from 40 to 99, for the values between the presets. |
| Travel button | Raises the cap to 100% for a fixed period, then reverts on its own. |

A standing cap is a decision you make once. A travel cap is an exception you
make on a particular day, and the two are kept apart on purpose: the presets
and the slider cannot reach 100%, and the travel button is the only control
that can. That is the whole design. A cap set to 100% and forgotten is the
state this plugin exists to get you out of, so the only route to 100% is the
one that expires.

The override lasts 24 hours by default, and 8 hours, 3 days, 1 week, or "until
I change it" are available in the widget's settings. Clicking the button again
ends it early. It reverts even if you never open the panel again, because the
expiry is checked by a system timer rather than by the panel.

## Design

A script prints one JSON snapshot and the QML panel renders it. This is the
same shape as `omarchy-system` and `omarchy-vpn-check`, and it means every
judgement lives in one testable file that runs fine from a terminal:

```bash
./bin/battery-limit --text          # cap, charge, health, and setup state
./bin/battery-limit --pretty        # the JSON the panel consumes
./bin/battery-limit set 60          # a standing cap
./bin/battery-limit set 100 --for 3d
```

### The firmware is the authority, not the request

Every write is read back, and it is the read-back that gets displayed. ASUS
firmware is free to round a request to its own steps, and on some models it
does. A panel that echoes your own request at you is reporting an intention
and calling it a state.

The same distinction runs through the whole tool. The bar reads the hardware
value; the config file holds what you asked for; and when they disagree the
panel says so rather than picking one. They disagree in exactly one situation
worth catching, which is a cap that was configured but did not survive
something, and hiding that is how you find out six months later that the cap
has not been on.

### Nothing runs as root, once

Writing the threshold needs root, and there is nowhere to type a password in a
bar panel. The installer resolves this once by handing the sysfs attribute to
the `wheel` group through a udev rule, after which the panel and the CLI are
ordinary unprivileged programs. No polkit agent, no password prompt, no sudo in
the hot path.

The units that reapply the cap at boot and on resume do run as root, and they
read the same config file the panel writes. That file is group-writable, so the
root helper parses it for integers rather than sourcing it. Sourcing a
group-writable file as root would quietly convert "can set a charge limit" into
"can run anything as root", which is not a trade worth making for three lines
of shell.

### Three units, not one

The obvious implementation is a single oneshot service wanted by both
`multi-user.target` and the sleep targets. It does not work. A oneshot with
`RemainAfterExit=yes` is still active when the machine resumes, so systemd sees
nothing to start and the cap is never reapplied; without `RemainAfterExit` the
unit shows as dead at boot instead. Boot, resume and expiry are three different
events and they get three units.

Whether the cap survives a suspend at all is model dependent. On this Zenbook
it does, and the resume unit is insurance that costs one file write.

## Requirements

| Needed | Used for |
|---|---|
| A battery exposing `charge_control_end_threshold` | the cap itself |
| Omarchy shell with plugin support | the bar widget and panel |
| Python 3 | the CLI |
| systemd | reapplying the cap at boot, on resume, and expiring the override |

## Hardware support

Nothing here is specific to any vendor beyond the driver that exposes the
attribute. The battery is found by scanning `/sys/class/power_supply` for a
node whose `type` is `Battery` and which carries
`charge_control_end_threshold`, rather than by assuming `BAT0`, so in principle
this works on any laptop whose kernel driver provides that file. One command
settles it on a given machine:

```bash
cat /sys/class/power_supply/*/charge_control_end_threshold
```

A number means the hardware side is there. Nothing at all means this plugin
has nothing to drive, and the panel will say so rather than pretending.

What follows is the honest boundary of that claim.

It has only been used on one machine, an ASUS Zenbook with `asus_nb_wmi`
loaded. Everything below is read off the code and the kernel drivers rather
than off hardware in hand, so treat it as where to look first when something
misbehaves, not as a support matrix.

On ThinkPads the driver also exposes `charge_control_start_threshold`, and it
rejects an end threshold below the current start threshold. This plugin reads
the start threshold for display but never writes it, so if something has
already set one, typically TLP or the firmware itself, lowering the cap past it
fails and the panel reports the write error rather than the reason. Clearing or
lowering the start threshold by hand is the workaround. ThinkPad firmware also
keeps thresholds across a reboot on its own, which makes the boot and resume
units redundant there rather than harmful.

If the battery is not named `BAT0`, `BAT1` and so on, the udev rule will not
match it. The rule keys on `KERNEL=="BAT*"`, while the CLI accepts any node of
the right type, so on hardware that names the pack something else the panel
reads correctly and then refuses every write, pointing at an installer that has
already been run.

With two packs the two halves disagree. The panel and `status` act on the first
battery that carries the attribute, while the root helper that runs at boot
writes every one it can. On a machine with an external or secondary pack, the
boot cap and the panel cap cover different hardware.

Some vendors expose no such attribute. Many Lenovo IdeaPads offer a
`conservation_mode` toggle on the platform device instead, which is a fixed
preset rather than a threshold and is not something this reads. Support for
Dell, Framework, MSI, System76 and Samsung arrived in different kernel versions
through different drivers, so on those the answer depends on the kernel rather
than on this plugin.

On a desktop, or any machine with no battery at all, the widget still draws its
glyph and the panel carries a warning. It does not break; it just has nothing
to say.

The firmware remains the authority throughout. It is free to quantise a
requested cap to its own steps, to refuse a value outright, or to hold the
charge below the cap and decline to top it up, and none of that is something
this can override. Every write is read back and it is the read-back that is
displayed, so what the panel shows is what the battery is holding. What this
cannot do is charge past a cap the firmware enforces elsewhere, discharge a
pack down to a target, or schedule anything by time of day.

The installer assumes an Arch-shaped system: `wheel` as the administrative
group, udev under `/etc/udev/rules.d`, and systemd. It is an Omarchy plugin, so
that is a fair assumption, but on a Debian-derived system the group would need
to be `sudo`.

## Why Omarchy's own battery panel disagrees

The stock `omarchy.power` panel will report a different limit from this one,
and it is the stock panel that is wrong. `omarchy-battery-status` reads
`charge-end-threshold` from UPower and falls back to sysfs only when UPower
returns nothing. UPower always returns something. On this hardware it reports a
75-80% pair alongside `ChargeThresholdEnabled = false`, which are the values it
would apply if something asked it to, not a reading of the firmware. Setting
the threshold to 60, 70 or 95 does not move them.

So the sysfs fallback never runs, and the stock panel reports a limit that is
not in force. This plugin reads sysfs directly and reports what the battery is
actually holding.

There is no way to fix this from outside Omarchy. UPower has no method to
re-read the value: `Refresh()` is not implemented on the device interface, and
`EnableChargeThreshold` only toggles UPower's own preset. Raising a synthetic
udev event does not help either, which was tried before the cause was
understood. The fix belongs in `omarchy-battery-status`, which should either
prefer sysfs or check `ChargeThresholdEnabled` before trusting UPower's pair.

## License

MIT. See [LICENSE](LICENSE), which also carries the notice for the Omarchy
plugins this widget's scaffolding is derived from.
