# Fixture schema (T008)

Deterministic acceptance fixtures for policy hazards. No host mutation: consumers
are the in-process simulator (`camlid simulate`), SwiftPM tests, and M6 contract
runs. A simulator result never establishes lid/display behavior.

## Schema

```json
{
  "fixture": "policy-grace",
  "description": "what hazard this covers",
  "config": { "completionDelayMinutes": 2, "waitRetentionMinutes": 5,
               "batteryFloorPercent": 20, "runCapMinutes": 120 },
  "steps": [
    {
      "at": 10.0,
      "tasks": [{ "id": "t1", "state": "working", "kind": "lifecycle" }],
      "sensors": { "battery": 80, "power": "ac", "thermal": "nominal",
                   "lid": "open", "display": "awake" },
      "safety": [],
      "expect": "protected"
    }
  ]
}
```

- `at`: monotonic seconds. `tasks[].state`: working|waiting|idle|completed|failed|unknown.
  `tasks[].kind`: lifecycle|wrapper|process. Optional `waitUntil`/`unknownUntil` per task.
- `sensors`: battery/cpu numbers or null (missing); power ac|battery|unknown;
  thermal nominal|fair|serious|critical|unknown; lid open|closed|unknown;
  display asleep|awake|disconnected|unknown.
- `safety`: injected stop reasons (e.g. ["thermalCritical"]); [] means clear.
- `expect`: off|ready|protected|completionGrace|safetyStopped|expired|unavailable|recoveryRequired,
  plus optional `expectReasons` array.
