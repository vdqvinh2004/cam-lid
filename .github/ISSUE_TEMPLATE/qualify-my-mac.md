---
name: Qualify my Mac
about: Report the results of the closed-lid trials on a Mac that is not yet supported
title: "Qualify: <model>, macOS <build>"
labels: qualification
---

**Do not run this on a Mac you need to keep working: a failed trial can leave it awake with the lid closed until you
run `sudo pmset -a disablesleep 0` or restart.**

- Model (`sysctl -n hw.model`):
- macOS build (`sw_vers -buildVersion`):
- CamLid version:
- Mode tried (Standard / Strict):
- On battery or charger:

Results (see `specs/014-persistent-helper/g2-trial.md` and `specs/016-strict-lid-only/tasks.md`):

| Trial | Did the Mac stay awake with the lid closed? | Did it sleep when the session ended or the app/helper died? |
|---|---|---|
| Session with the lid closed | | |
| App killed with the lid closed | | |
| Helper killed with the lid closed | | |
| Restart during a session | | |

Attach: `/var/log/com.camlid.power-helper.log` (last 50 lines around the trial) and the relevant lines of `pmset -g log`.
