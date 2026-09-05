# Changelog

Notable changes to the Battery Limit plugin. Versions follow
[semantic versioning](https://semver.org), and the format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
