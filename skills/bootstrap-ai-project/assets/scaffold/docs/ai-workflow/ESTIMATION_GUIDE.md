# Estimation Guide

Where this project's estimates come from. It ships empty on purpose: **fill it from this project's
own logged actuals**. Numbers copied from another project describe that project's team, stack and
client, not this one. Until the tables below hold real numbers, estimate in ranges and say out loud
that the estimate is uncalibrated.

Used by step 4 (`Estimated Complexity` in `TASK_TEMPLATE.md`).

## 1. Size buckets

Size the task before pricing it in hours. A bucket only means something once the work is
decomposed — "build the backend" has no size.

| Bucket | Definition | Median of actuals | Mean | Sample size |
|--------|------------|-------------------|------|-------------|
| S      |            |                   |      |             |
| M      |            |                   |      |             |
| L      |            |                   |      |             |

Fill the columns from tasks that were **logged**, not from what was estimated for them. Anchor on
the median and read the mean as the typical ceiling: one outlier moves the mean, not the median.

## 2. Overhead that bottom-up estimation misses

Adding up task estimates undershoots the project every time — the difference is real work that was
never a task. Budget each line **explicitly**, not as padding hidden inside the tasks.

| Line | What it covers | Share of build (fill in) |
|------|----------------|--------------------------|
| Testing | Tests written inside each task, plus dedicated end-to-end passes per stage. | |
| Integration | Wiring the pieces together, environment friction, third-party surprises. | |
| Requirements, meetings, documentation | Everything that is not building, when there is an active stakeholder. | |
| Hardening and stakeholder validation | Fix rounds, re-deploys, data sweeps, re-validation after "done". | |

Decomposing better does not remove overhead — it moves it. Work that stops showing up as large
tasks shows up as a validation queue at the end instead.

## 3. How to calibrate

1. Pull the **actuals** for a closed stage from the issue tracker (logged time, not estimates).
2. Tag each entry by type and bucket. Entries with no tag get inferred once, and the convention
   gets adopted going forward.
3. Compute median, mean and range per type and per bucket. Fill the tables above.
4. Record the extraction date and the stage the numbers came from — an estimate calibrated on a
   different stack or a different team size does not transfer.
5. Re-calibrate at the end of each release; keep the previous table so drift is visible.

**Extraction date:**
**Stages covered:**

## 4. How to read these numbers

- They describe **this team at this size**. They do not transfer to another person or another stack
  without an adjustment factor that is itself estimated.
- Estimates that were **capped to a budget** are not actuals: a task logging exactly what was
  planned is an artifact of the cap, not evidence of accuracy. Keep the two sources apart.
- A bucket median assumes decomposed, single-type work. If a task spans types, split it first.
- If a number here contradicts the last delivery, the number is stale — re-calibrate, don't argue
  with the delivery.
