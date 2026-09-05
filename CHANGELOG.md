# Changelog

Notable changes to the Battery Limit plugin. Versions follow
[semantic versioning](https://semver.org), and the format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-09-05

### Added

- A hardware support section in the README, describing what is handled on
  machines other than the ASUS Zenbook this was written on, and what the
  firmware decides regardless of what the tool asks for.
- `status` now lists every battery that exposes a threshold, and warns when
  two packs are capped at different values.

### Changed

- The udev rule matches batteries by device type rather than by the name
  `BAT*`, so hardware that names its pack something else is granted access
  rather than silently left read-only. It also grants
  `charge_control_start_threshold` where the driver provides one.
- The limit is set on every battery that exposes a threshold, rather than on
  the first one found. The helper that runs at boot already did this, so a
  machine with two packs no longer holds one cap at boot and another after a
  change from the panel.
- The plugin description and the CLI help no longer name a vendor, since
  nothing in the tool is specific to one.

### Fixed

- Drivers that reject an end threshold below `charge_control_start_threshold`,
  `thinkpad_acpi` among them, are now handled by lowering the start threshold
  five points below the new cap and writing again. It is touched only after
  such a driver has refused the write.

## [0.1.0] - 2026-09-05

First release.

### Added

- A bar widget showing the cap the battery is charging to, read from the
  hardware rather than from the configuration, so it stays right when the
  limit is changed from a terminal.
- A panel with four standing caps on a row, a slider for the values between
  them, and the charge and health readings that justify capping at all.
- A travel button, the only control that reaches 100%, which raises the cap for
  a fixed period and then reverts on its own. 8 hours, 24 hours, 3 days, 1 week
  or indefinitely, chosen in the widget's settings.
- `bin/battery-limit`, which makes every judgement the panel displays and runs
  from a terminal with no compositor involved.
- `bin/battery-limit-install`, a single privileged step that grants the `wheel`
  group write access to the threshold through a udev rule and installs the
  units that reapply the cap at boot, after resume, and every ten minutes so an
  override expires without the panel being open.
- IPC actions `travel` and `standing`, so a keybinding can raise and lower the
  cap without opening anything.
