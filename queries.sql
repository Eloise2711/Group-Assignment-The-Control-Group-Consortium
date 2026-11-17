-- Control Group Consortium | Milestone 2 | SQLite 3.37+
-- Read-only reports over the loaded data. Months use UTC timestamps.
-- From the project directory, run against the seed in an in-memory database:
-- sqlite3 -bail -header -column :memory: ".read create.sql" ".read seed.sql" ".read queries.sql"

-- Q1. How many actual usage hours did each facility record per month?
-- Split logs that cross midnight at a month boundary between both months.
-- Count facility-use logs only. This is recorded usage time, not a utilization
-- percentage or deduplicated room occupancy; concurrent uses can both count.
WITH RECURSIVE facility_months (FacilityId, StartAt, EndAt, MonthStart) AS (
    SELECT ef.FacilityId, u.ActualStart, u.ActualEnd,
           datetime(u.ActualStart, 'start of month')
    FROM UsageRecord AS u
    JOIN EventFacility AS ef ON ef.EventFacilityId = u.EventFacilityId
    UNION ALL
    SELECT FacilityId, StartAt, EndAt, datetime(MonthStart, '+1 month')
    FROM facility_months
    WHERE datetime(MonthStart, '+1 month') < EndAt
)
SELECT substr(m.MonthStart, 1, 7) AS UsageMonth,
       f.FacilityId, f.FacilityName,
       ROUND(SUM(
           unixepoch(MIN(m.EndAt, datetime(m.MonthStart, '+1 month')))
           - unixepoch(MAX(m.StartAt, m.MonthStart))
       ) / 3600.0, 2) AS ActualUsageHours
FROM facility_months AS m
JOIN Facility AS f ON f.FacilityId = m.FacilityId
GROUP BY m.MonthStart, f.FacilityId, f.FacilityName
ORDER BY m.MonthStart, ActualUsageHours DESC, f.FacilityId;

-- Q2. Which instruments had the most planned maintenance/calibration time?
-- Count only valid reservations on non-cancelled events. Include idle equipment
-- with zero service reservations for comparison.
WITH service_reservations AS (
    SELECT ee.EquipmentId, ee.EventId, e.EventType,
           unixepoch(ee.ReservedEnd) - unixepoch(ee.ReservedStart) AS Seconds
    FROM EventEquipment AS ee
    JOIN Event AS e ON e.EventId = ee.EventId
    WHERE e.EventType IN ('maintenance', 'calibration')
      AND e.Status <> 'cancelled'
      AND ee.ReservationStatus IN ('scheduled', 'completed')
)
SELECT eq.EquipmentId, eq.EquipmentName,
       COUNT(DISTINCT sr.EventId) AS ServiceEvents,
       ROUND(COALESCE(SUM(CASE WHEN sr.EventType = 'maintenance'
                               THEN sr.Seconds END), 0) / 3600.0, 2) AS MaintenanceHours,
       ROUND(COALESCE(SUM(CASE WHEN sr.EventType = 'calibration'
                               THEN sr.Seconds END), 0) / 3600.0, 2) AS CalibrationHours,
       ROUND(COALESCE(SUM(sr.Seconds), 0) / 3600.0, 2) AS PlannedServiceHours
FROM Equipment AS eq
LEFT JOIN service_reservations AS sr ON sr.EquipmentId = eq.EquipmentId
GROUP BY eq.EquipmentId, eq.EquipmentName
ORDER BY COALESCE(SUM(sr.Seconds), 0) DESC, eq.EquipmentId;

-- Q3. How long does each institution wait for the first request decision?
-- Count the first request-level approval, rejection or alternative proposal;
-- later decisions and event-level rescheduling do not change first response.
-- No qualifying decision: count separately; omit from average wait.
WITH first_decision AS (
    SELECT RequestId, MIN(DecidedAt) AS FirstDecidedAt
    FROM ScheduleDecision
    WHERE RequestId IS NOT NULL
      AND DecisionType IN ('approved', 'rejected', 'alternative_proposed')
    GROUP BY RequestId
)
SELECT i.InstitutionId, i.InstitutionName,
       COUNT(r.RequestId) AS SubmittedRequests,
       COUNT(d.FirstDecidedAt) AS RequestsWithDecision,
       COUNT(r.RequestId) - COUNT(d.FirstDecidedAt) AS RequestsWithoutDecision,
       ROUND(AVG(unixepoch(d.FirstDecidedAt) - unixepoch(r.SubmittedAt)) / 3600.0, 2)
           AS AvgHoursToFirstDecision
FROM Institution AS i
LEFT JOIN Researcher AS p ON p.InstitutionId = i.InstitutionId
LEFT JOIN AccessRequest AS r ON r.RequesterId = p.ResearcherId
LEFT JOIN first_decision AS d ON d.RequestId = r.RequestId
GROUP BY i.InstitutionId, i.InstitutionName
ORDER BY AvgHoursToFirstDecision DESC, i.InstitutionId;

-- Q4. Whose actual and planned work hours differ most?
-- Compare completed assignments with at least one work log. Show unlogged
-- completed assignments separately; missing logs do not mean zero work.
-- Roll up log segments first so each assignment's planned time counts once.
WITH work_by_assignment AS (
    SELECT AssignmentId,
           SUM(unixepoch(ActualEnd) - unixepoch(ActualStart)) AS ActualSeconds
    FROM UsageRecord
    WHERE AssignmentId IS NOT NULL
    GROUP BY AssignmentId
),
completed AS (
    SELECT a.AssignmentId, a.StaffId,
           unixepoch(a.AssignedEnd) - unixepoch(a.AssignedStart) AS PlannedSeconds,
           w.ActualSeconds
    FROM StaffAssignment AS a
    LEFT JOIN work_by_assignment AS w ON w.AssignmentId = a.AssignmentId
    WHERE a.AssignmentStatus = 'completed'
)
SELECT s.StaffId, s.StaffName,
       COUNT(c.AssignmentId) AS CompletedAssignments,
       COUNT(c.ActualSeconds) AS ComparedAssignments,
       COUNT(c.AssignmentId) - COUNT(c.ActualSeconds) AS CompletedWithoutWorkLog,
       ROUND(SUM(CASE WHEN c.ActualSeconds IS NOT NULL THEN c.PlannedSeconds END)
             / 3600.0, 2) AS ComparablePlannedHours,
       ROUND(SUM(c.ActualSeconds) / 3600.0, 2) AS ActualWorkHours,
       ROUND(SUM(c.ActualSeconds - c.PlannedSeconds) / 3600.0, 2)
           AS ActualMinusPlannedHours
FROM Staff AS s
LEFT JOIN completed AS c ON c.StaffId = s.StaffId
GROUP BY s.StaffId, s.StaffName
ORDER BY ABS(SUM(c.ActualSeconds - c.PlannedSeconds)) DESC, s.StaffId;

-- Q5. What net costs did each funding source cover each month?
-- Use recorded splits for finalized charges and signed adjustments. Book base
-- costs in ChargeDate's month and adjustments in their authorization month.
-- Keep cents as integers during aggregation; convert to USD for display.
WITH funding_entries AS (
    SELECT a.FundingSourceId, substr(c.ChargeDate, 1, 7) AS BillingMonth,
           a.AllocatedAmount AS BaseCents, 0 AS AdjustmentCents
    FROM ChargeAllocation AS a
    JOIN Charge AS c ON c.ChargeId = a.ChargeId
    WHERE c.Status = 'finalized'
    UNION ALL
    SELECT a.FundingSourceId, substr(j.AuthorizedAt, 1, 7),
           0, a.AllocatedAmount
    FROM ChargeAllocation AS a
    JOIN ChargeAdjustment AS j ON j.AdjustmentId = a.AdjustmentId
    JOIN Charge AS c ON c.ChargeId = j.ChargeId
    WHERE c.Status = 'finalized'
)
SELECT e.BillingMonth, f.FundingSourceId, f.FundingSourceName,
       ROUND(SUM(e.BaseCents) / 100.0, 2) AS BaseUSD,
       ROUND(SUM(e.AdjustmentCents) / 100.0, 2) AS AdjustmentsUSD,
       ROUND(SUM(e.BaseCents + e.AdjustmentCents) / 100.0, 2) AS NetUSD
FROM funding_entries AS e
JOIN FundingSource AS f ON f.FundingSourceId = e.FundingSourceId
GROUP BY e.BillingMonth, f.FundingSourceId, f.FundingSourceName
ORDER BY e.BillingMonth, SUM(e.BaseCents + e.AdjustmentCents) DESC, f.FundingSourceId;

-- Q6. Which actual uses had base costs shared by experiments or payers?
-- First identify shared usages from finalized charges. Then show one row per
-- charge for those usages, naming the cost-bearing experiment and payer.
-- These are original final amounts; later adjustments are reported in Q5.
WITH shared_usage AS (
    SELECT UsageId,
           COUNT(DISTINCT ExperimentId) AS CostBearingExperiments,
           COUNT(DISTINCT ResponsiblePartyId) AS Payers,
           SUM(FinalAmount) AS SharedBaseCents
    FROM Charge
    WHERE Status = 'finalized' AND UsageId IS NOT NULL
    GROUP BY UsageId
    HAVING COUNT(DISTINCT ExperimentId) > 1
        OR COUNT(DISTINCT ResponsiblePartyId) > 1
)
SELECT u.UsageId, u.ActualStart,
       CASE WHEN u.EventFacilityId IS NOT NULL THEN 'facility'
            WHEN u.EventEquipmentId IS NOT NULL THEN 'equipment'
            ELSE 'staff_work' END AS UsageType,
       COALESCE(f.FacilityName, eq.EquipmentName, worker.StaffName) AS ResourceOrWorker,
       su.CostBearingExperiments, su.Payers,
       ROUND(su.SharedBaseCents / 100.0, 2) AS UsageBaseTotalUSD,
       c.ChargeId, x.ExperimentId, x.ExperimentName,
       rp.ResponsiblePartyId,
       CASE WHEN rp.ResearcherId IS NOT NULL THEN 'researcher'
            WHEN rp.InstitutionId IS NOT NULL THEN 'institution'
            ELSE 'department' END AS PayerType,
       COALESCE(person.ResearcherName, inst.InstitutionName, dept.DepartmentName) AS PayerName,
       ROUND(c.FinalAmount / 100.0, 2) AS ChargeUSD
FROM shared_usage AS su
JOIN UsageRecord AS u ON u.UsageId = su.UsageId
JOIN Charge AS c ON c.UsageId = su.UsageId AND c.Status = 'finalized'
JOIN Experiment AS x ON x.ExperimentId = c.ExperimentId
JOIN ResponsibleParty AS rp ON rp.ResponsiblePartyId = c.ResponsiblePartyId
LEFT JOIN Researcher AS person ON person.ResearcherId = rp.ResearcherId
LEFT JOIN Institution AS inst ON inst.InstitutionId = rp.InstitutionId
LEFT JOIN Department AS dept ON dept.DepartmentId = rp.DepartmentId
LEFT JOIN EventFacility AS ef ON ef.EventFacilityId = u.EventFacilityId
LEFT JOIN Facility AS f ON f.FacilityId = ef.FacilityId
LEFT JOIN EventEquipment AS ee ON ee.EventEquipmentId = u.EventEquipmentId
LEFT JOIN Equipment AS eq ON eq.EquipmentId = ee.EquipmentId
LEFT JOIN StaffAssignment AS sa ON sa.AssignmentId = u.AssignmentId
LEFT JOIN Staff AS worker ON worker.StaffId = sa.StaffId
ORDER BY u.ActualStart, u.UsageId, c.ChargeId;

-- Q7. Which facilities or instruments had the highest monthly denial rates?
-- Group the two resource types separately, even if their numeric IDs match.
-- Show attempt counts beside rates so a high rate on few attempts is visible.
WITH resource_attempts AS (
    SELECT substr(l.AccessTime, 1, 7) AS AccessMonth, 'facility' AS ResourceType,
           f.FacilityId AS ResourceId, f.FacilityName AS ResourceName, l.AccessResult
    FROM AccessLog AS l
    JOIN Facility AS f ON f.FacilityId = l.FacilityId
    UNION ALL
    SELECT substr(l.AccessTime, 1, 7), 'equipment',
           eq.EquipmentId, eq.EquipmentName, l.AccessResult
    FROM AccessLog AS l
    JOIN Equipment AS eq ON eq.EquipmentId = l.EquipmentId
),
monthly_counts AS (
    SELECT AccessMonth, ResourceType, ResourceId, ResourceName,
           COUNT(*) AS Attempts,
           SUM(CASE WHEN AccessResult = 'denied' THEN 1 ELSE 0 END) AS Denied
    FROM resource_attempts
    GROUP BY AccessMonth, ResourceType, ResourceId, ResourceName
)
SELECT AccessMonth, ResourceType, ResourceId, ResourceName,
       Attempts, Denied, ROUND(100.0 * Denied / Attempts, 2) AS DenialPct
FROM monthly_counts
ORDER BY AccessMonth, 1.0 * Denied / Attempts DESC, Attempts DESC, ResourceType, ResourceId;

-- Q8. Which projects have the most cross-institution experiments?
-- Count distinct current institutions per experiment before grouping by project.
-- Also show total experiments so project size is visible.
WITH experiment_institutions AS (
    SELECT e.ExperimentId, e.ProjectId, COUNT(DISTINCT r.InstitutionId) AS Institutions
    FROM Experiment AS e
    LEFT JOIN ExperimentResearcher AS er ON er.ExperimentId = e.ExperimentId
    LEFT JOIN Researcher AS r ON r.ResearcherId = er.ResearcherId
    GROUP BY e.ExperimentId, e.ProjectId
)
SELECT p.ProjectId, p.ProjectName,
       COUNT(x.ExperimentId) AS TotalExperiments,
       SUM(CASE WHEN x.Institutions > 1 THEN 1 ELSE 0 END) AS CrossInstitutionExperiments,
       ROUND(100.0 * SUM(CASE WHEN x.Institutions > 1 THEN 1 ELSE 0 END)
             / NULLIF(COUNT(x.ExperimentId), 0), 2) AS CrossInstitutionPct
FROM Project AS p
LEFT JOIN experiment_institutions AS x ON x.ProjectId = p.ProjectId
GROUP BY p.ProjectId, p.ProjectName
ORDER BY CrossInstitutionExperiments DESC, CrossInstitutionPct DESC, p.ProjectId;

