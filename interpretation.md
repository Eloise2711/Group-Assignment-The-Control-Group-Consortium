# Control Group Consortium Query Interpretation

This section interprets Q1–Q8 in `queries.sql` using the enhanced `seed.sql`. The database contains 2,705 records across 28 tables, with operational activity covering January–June 2026. All people, institutions, activities, and prices are fictional. These results demonstrate the database's analytical capabilities; they are not findings about real institutions or facilities. Each query was executed against a newly created SQLite database. Foreign-key and business-validation checks returned no issues.

Times are interpreted in UTC. Monetary values are stored as integer USD cents and converted to dollars for reporting. Displayed hours are rounded to two decimal places; differences are calculated from unrounded durations.

## Q1 Monthly actual facility usage

**Business question:** How many actual usage hours did each facility record per month?

**What the query reveals:** This query compares recorded facility-use activity across facilities and months. It connects actual usage records to facility reservations and facility names, then sums actual durations by calendar month. A log crossing a month boundary is divided between the affected months.

**Results and interpretation:** The Optical Imaging Suite recorded 3.45 hours in January, increased to 18.12 hours in May, and fell to 8.32 hours in June. It had the highest monthly recorded usage among the four facilities in May; the Materials Testing Bay recorded 13.95 hours that month. The pattern identifies changes in logged demand and can help managers decide which periods warrant closer staffing or scheduling review. It does not establish why demand changed.

| Month | Facility | Actual usage hours |
|---|---|---:|
| January 2026 | Optical Imaging Suite | 3.45 |
| May 2026 | Optical Imaging Suite | 18.12 |
| May 2026 | Materials Testing Bay | 13.95 |
| June 2026 | Optical Imaging Suite | 8.32 |

**Why a database is needed:** Actual timestamps are stored in `UsageRecord`, reservation links in `EventFacility`, and facility descriptions in `Facility`. Manually matching these records and splitting cross-month logs would be error-prone. A simple count of reservations would also miss differences in actual duration.

**Scope:** The measure is cumulative logged usage hours, not a utilization percentage or unique room-occupancy time. Concurrent activities may both contribute hours. Calculating utilization would additionally require an explicit definition of available capacity and operating hours.

## Q2 Planned equipment maintenance and calibration

**Business question:** Which instruments had the most planned maintenance and calibration time?

**What the query reveals:** This query identifies instruments with the largest scheduled service commitment. It includes valid scheduled or completed reservations for maintenance and calibration events, excludes cancelled events and cancelled or replaced reservations, and keeps equipment with no qualifying reservations in the output.

| Equipment | Service events | Maintenance hours | Calibration hours | Total planned service hours |
|---|---:|---:|---:|---:|
| Confocal surface microscope | 7 | 12.75 | 2.50 | 15.25 |
| Universal test frame | 6 | 1.00 | 6.50 | 7.50 |
| Precision laser cutter | 0 | 0.00 | 0.00 | 0.00 |

**Results and interpretation:** The confocal surface microscope had the greatest planned service commitment: 15.25 hours across seven events. The universal test frame had 7.50 hours across six events, mostly calibration. The confocal microscope therefore warrants a closer review of service scheduling and its effect on research access. However, these figures alone do not show equipment reliability or justify replacement. Zero hours for the laser cutter means no qualifying service reservations are recorded in this dataset, not that the instrument never requires maintenance.

**Why a database is needed:** `Event` identifies the activity type, `EventEquipment` identifies the affected instrument and reserved interval, and `Equipment` supplies its name. The database joins these facts, filters historical reservation states, and compares instruments consistently. Listing events alone cannot provide the same equipment-level summary.

**Scope:** These are planned reservation hours, not measured repair labor or actual downtime. Cleaning and reconfiguration are separate event types and are not included in this query.

## Q3 Time to the first request decision by institution

**Business question:** How long does each institution wait for the first decision on a resource request?

**What the query reveals:** The query measures elapsed clock hours from submission to the earliest request-level approval, rejection, or alternative proposal. It separately counts requests without a qualifying decision, preventing them from being treated as zero-hour responses.

| Institution | Submitted requests | With a decision | Without a decision | Average hours to first decision |
|---|---:|---:|---:|---:|
| Westfield University | 16 | 15 | 1 | 42.73 |
| Meridian Research Institute | 31 | 30 | 1 | 37.02 |
| Harbor State University | 31 | 29 | 2 | 27.56 |
| Northbridge University | 24 | 24 | 0 | 23.55 |

**Results and interpretation:** Westfield had the longest average first-response time at 42.73 hours, compared with Northbridge's 23.55 hours. Four of the 102 submitted requests had no qualifying decision. These differences flag areas for reviewing the request-handling process, but they do not demonstrate unequal treatment: request complexity, resource requirements, and submission timing are not controlled for in this comparison.

**Why a database is needed:** Submission times reside in `AccessRequest`, decision history in `ScheduleDecision`, and institutional affiliation is obtained through `Researcher` and `Institution`. Each request may have several decisions. The database first selects the earliest qualifying decision per request, then calculates institutional averages without counting one request multiple times.

**Scope:** First response is not the same as final approval, and elapsed clock hours are not staff working hours. Pending responses do not contribute to the average, so the separate unanswered count must be considered alongside it.

## Q4 Actual versus planned staff work hours

**Business question:** Whose actual work hours differ most from planned assignment hours?

**What the query reveals:** This query compares actual logged work against completed assignments. It first combines all work-log segments for each assignment, so an assignment's planned duration is counted once even when its work is recorded in several segments.

| Staff member | Compared assignments | Planned hours | Actual hours | Actual minus planned hours |
|---|---:|---:|---:|---:|
| Robin Das | 12 | 23.00 | 27.55 | +4.55 |
| Jamie Torres | 24 | 35.33 | 34.12 | -1.22 |
| Charlie Reed | 36 | 58.33 | 58.68 | +0.35 |

**Results and interpretation:** Robin Das had the largest absolute net difference: 27.55 actual hours against 23.00 planned hours, an excess of 4.55 hours. This suggests reviewing whether the corresponding assignments need more realistic time allowances. Jamie Torres recorded 1.22 fewer hours than planned. These are scheduling observations, not employee performance ratings. Taylor Green had no completed assignments in this dataset; the resulting null hour values mean there is no comparable work, rather than measured zero-hour performance.

**Why a database is needed:** `StaffAssignment` stores planned work, while `UsageRecord` stores actual work segments and `Staff` identifies the worker. Joining raw segments directly to assignments would repeat planned hours. The database aggregates at the assignment level before calculating each staff member's totals.

**Scope:** Cancelled and replaced assignments are excluded. Completed assignments without work logs are reported separately and excluded from the comparable-hour totals. The signed net difference can hide offsetting overruns and underruns; it is not the sum of all absolute scheduling errors. Rounding displayed totals separately can also make their subtraction differ slightly from the displayed net difference.

## Q5 Monthly net costs by funding source

**Business question:** What net costs did each funding source cover each month?

**What the query reveals:** This query combines recorded allocations of finalized charges with the signed allocations of adjustments. Original costs are recognized in the charge month; refunds, waivers, and surcharges are recognized in the month of adjustment authorization. Estimated charges are excluded.

| May 2026 funding source | Base cost USD | Net adjustments USD | Net cost USD |
|---|---:|---:|---:|
| Equipment Access Grant | 1,085.33 | 0.00 | 1,085.33 |
| Materials Design Budget | 726.59 | -38.71 | 687.88 |
| Shared Infrastructure Fund | 559.04 | -21.98 | 537.06 |

**Results and interpretation:** In May, the Equipment Access Grant carried the largest net cost, USD 1,085.33. Credits reduced the Materials Design Budget's allocation by USD 38.71 and the Shared Infrastructure Fund's allocation by USD 21.98. Summing the monthly query output across all six months gives USD 19,745.86 in base costs and a net reduction of USD 70.15 from adjustments, for USD 19,675.71 in net allocated costs. This shows why reporting original charges alone would overstate costs in this dataset.

**Why a database is needed:** `ChargeAllocation` links each share to a `FundingSource` and either a `Charge` or a `ChargeAdjustment`. A charge can have several funding shares and several later adjustments. Separate query branches combined with `UNION ALL` keep these paths distinct and avoid multiplying original charges by their adjustment or allocation rows.

**Scope:** These amounts represent allocated costs, not cash payments, remaining grant balances, or total grant awards. Adjustments use their authorization month even when the original charge belongs to an earlier month.

## Q6 Shared costs across experiments and payers

**Business question:** Which actual uses had base costs shared by multiple experiments or responsible parties?

**What the query reveals:** The query identifies shared usage records through distinct experiment or payer counts, then explains the resulting charge shares by resource, experiment, payer type, and payer name.

**Results and interpretation:** The result contains 24 charge rows representing 12 distinct shared usage records. Their original finalized charge shares total USD 692.73. For example, usage record 6 is a digital hardness tester session with a USD 39.20 base cost:

| Usage ID | Cost-bearing experiment | Payer | Charge USD |
|---|---|---|---:|
| 6 | Coating wear | Harbor State University, institution | 25.48 |
| 6 | Joint loading | Avery Chen, researcher | 13.72 |

The example demonstrates that one physical use can support more than one cost-bearing experiment, and that an institution and an individual researcher can assume different shares of its cost. It also distinguishes a responsible party from a funding source: the named payer is not necessarily the source to which the expense is ultimately allocated.

**Why a database is needed:** The shared relationship is not visible from `UsageRecord` alone. It requires grouping `Charge` records by usage, then joining experiments, responsible parties, their underlying identities, and the relevant resource or staff-work source. Manual matching would make it easy to confuse a single usage with several independent uses or to overlook individual payer shares.

**Scope:** The query reports original finalized base charges; subsequent adjustments are handled in Q5. `UsageBaseTotalUSD` is repeated on each charge row for the same usage, so it must not be summed across all detail rows. Use the individual charge shares or aggregate once per usage ID.

## Q7 Monthly resource access denial rates

**Business question:** Which facilities or instruments had the highest monthly denial rates?

**What the query reveals:** This query compares denied attempts with all recorded attempts for each resource and month. Facility and equipment identities remain separate, even when their numeric IDs are equal.

| Month | Resource | Attempts | Denied | Denial rate |
|---|---|---:|---:|---:|
| March 2026 | Confocal surface microscope | 7 | 3 | 42.86% |
| April 2026 | Confocal surface microscope | 8 | 3 | 37.50% |
| May 2026 | Precision laser cutter | 1 | 1 | 100.00% |

**Results and interpretation:** The confocal surface microscope had three denied attempts in both March and April, suggesting a recurring access issue worth investigating. The laser cutter had a higher rate in May, but it was based on only one attempt; it does not establish a more widespread problem. Across the full query output, there were 24 denials among 310 recorded attempts. This comparison shows why attempt counts must accompany percentages.

**Why a database is needed:** `AccessLog` contains attempts and outcomes, while resource names are stored in `Facility` or `Equipment`. The database combines the two resource paths and calculates a separate denominator for each resource-month. Looking only at denied rows cannot produce an accurate denial rate.

**Scope:** These are attempt counts, not counts of distinct people, and successful entry and equipment-start events can be separate attempts. The aggregate does not establish a denial's cause; individual log details and permission history must be examined before attributing it to expired authorization, incomplete training, or another issue.

## Q8 Cross-institution collaboration by project

**Business question:** Which projects have the most experiments involving researchers from more than one institution?

**What the query reveals:** This query first counts distinct current institutions represented in each experiment, then counts and compares cross-institution experiments within each project.

| Project | Total experiments | Cross-institution experiments | Cross-institution share |
|---|---:|---:|---:|
| Recycled Polymer Prototypes | 2 | 2 | 100.00% |
| Optical Surface Mapping | 2 | 2 | 100.00% |
| Lightweight Panel Design | 2 | 2 | 100.00% |
| Prototype Joint Testing | 2 | 1 | 50.00% |
| Coating Reliability | 2 | 0 | 0.00% |
| Dimensional Reference Standards | 2 | 0 | 0.00% |

**Results and interpretation:** Three projects tie for the largest number of cross-institution experiments, with two each. Prototype Joint Testing has one, while the remaining two projects have none. Seven of the twelve experiments involve more than one institution. This identifies which projects have broader institutional participation and may require more coordination across institutions. It measures collaboration structure, not research quality or productivity.

**Why a database is needed:** The relationship spans `Project`, `Experiment`, the `ExperimentResearcher` bridge, and each researcher's institution. Several researchers may belong to the same institution, so counting participants would overstate institutional breadth. The database counts distinct institutions per experiment before aggregating to projects, avoiding repeated experiment counts.

**Scope:** Affiliations are current values because affiliation history is outside the schema's scope. This is a comparison of the loaded project and team records, not a historical reconstruction of institutional membership at each experiment date.
