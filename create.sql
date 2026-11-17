-- Control Group Consortium | Milestone 2 | SQLite 3.37+
-- RESET SCRIPT: drops the existing consortium tables and their data.
-- Run on a new or disposable database. Enable foreign_keys on every connection.
--
-- Identifiers follow the ERD. Dates are YYYY-MM-DD; timestamps are UTC
-- YYYY-MM-DD HH:MM:SS. Endpoints are exclusive for time intervals.
-- All monetary columns (including UnitPrice) are integer minor units in one
-- currency: e.g. 1250 means 12.50 for a currency with two decimal places.
-- AllocationPercentage is 0..100, not 0..1. Booleans are integers 0 and 1.
-- Status and type codes used by queries are lowercase snake_case.
--
-- At the end of each seed/import transaction, run:
--     SELECT * FROM ConsortiumValidationIssues;
-- Expect zero rows. This view reports cross-row checks that need to be
-- evaluated after all related rows are loaded, e.g. allocation totals.
-- Staff verify qualifications, funding restrictions, and staff availability.
-- Preserve historical decisions, rule coverage and finalized financial records
-- in write workflows. Add adjustments rather than rewriting finalized amounts.

PRAGMA foreign_keys = ON;
BEGIN;

DROP VIEW IF EXISTS ConsortiumValidationIssues;
DROP TABLE IF EXISTS AccessLog;
DROP TABLE IF EXISTS AccessPermission;
DROP TABLE IF EXISTS ChargeAllocation;
DROP TABLE IF EXISTS ChargeAdjustment;
DROP TABLE IF EXISTS Charge;
DROP TABLE IF EXISTS AllocationRuleFunding;
DROP TABLE IF EXISTS AllocationRule;
DROP TABLE IF EXISTS FundingSource;
DROP TABLE IF EXISTS UsageRecord;
DROP TABLE IF EXISTS StaffAssignment;
DROP TABLE IF EXISTS StaffAvailability;
DROP TABLE IF EXISTS EventEquipment;
DROP TABLE IF EXISTS EventFacility;
DROP TABLE IF EXISTS ScheduleDecision;
DROP TABLE IF EXISTS Event;
DROP TABLE IF EXISTS AccessRequest;
DROP TABLE IF EXISTS ExperimentResearcher;
DROP TABLE IF EXISTS Experiment;
DROP TABLE IF EXISTS Project;
DROP TABLE IF EXISTS EquipmentLocationHistory;
DROP TABLE IF EXISTS Equipment;
DROP TABLE IF EXISTS Facility;
DROP TABLE IF EXISTS ResponsibleParty;
DROP TABLE IF EXISTS Staff;
DROP TABLE IF EXISTS Researcher;
DROP TABLE IF EXISTS Site;
DROP TABLE IF EXISTS Department;
DROP TABLE IF EXISTS Institution;

-- People and institutions
CREATE TABLE Institution (
    InstitutionId INTEGER PRIMARY KEY,
    InstitutionName TEXT NOT NULL,
    ContactEmail TEXT
) STRICT;

CREATE TABLE Department (
    DepartmentId INTEGER PRIMARY KEY,
    InstitutionId INTEGER NOT NULL,
    DepartmentName TEXT NOT NULL,
    ContactEmail TEXT,
    FOREIGN KEY (InstitutionId) REFERENCES Institution(InstitutionId)
) STRICT;

CREATE TABLE Site (
    SiteId INTEGER PRIMARY KEY,
    InstitutionId INTEGER NOT NULL,
    SiteName TEXT NOT NULL,
    LocationDescription TEXT,
    FOREIGN KEY (InstitutionId) REFERENCES Institution(InstitutionId)
) STRICT;

CREATE TABLE Researcher (
    ResearcherId INTEGER PRIMARY KEY,
    InstitutionId INTEGER NOT NULL,
    ResearcherName TEXT NOT NULL,
    Email TEXT NOT NULL,
    FOREIGN KEY (InstitutionId) REFERENCES Institution(InstitutionId)
) STRICT;

CREATE TABLE Staff (
    StaffId INTEGER PRIMARY KEY,
    StaffName TEXT NOT NULL,
    Email TEXT NOT NULL,
    Expertise TEXT,
    Role TEXT NOT NULL
) STRICT;

CREATE TABLE ResponsibleParty (
    ResponsiblePartyId INTEGER PRIMARY KEY,
    ResearcherId INTEGER UNIQUE,
    InstitutionId INTEGER UNIQUE,
    DepartmentId INTEGER UNIQUE,
    FOREIGN KEY (ResearcherId) REFERENCES Researcher(ResearcherId),
    FOREIGN KEY (InstitutionId) REFERENCES Institution(InstitutionId),
    FOREIGN KEY (DepartmentId) REFERENCES Department(DepartmentId),
    CHECK ((ResearcherId IS NOT NULL) + (InstitutionId IS NOT NULL)
           + (DepartmentId IS NOT NULL) = 1)
) STRICT;

-- Facilities and equipment
CREATE TABLE Facility (
    FacilityId INTEGER PRIMARY KEY,
    SiteId INTEGER NOT NULL,
    FacilityName TEXT NOT NULL,
    FacilityType TEXT NOT NULL,
    Capabilities TEXT,
    UsageRestrictions TEXT,
    QualificationRequirements TEXT,
    CurrentConfiguration TEXT,
    ConcurrentEventCapacity INTEGER NOT NULL DEFAULT 1 CHECK (ConcurrentEventCapacity > 0),
    Status TEXT NOT NULL,
    FOREIGN KEY (SiteId) REFERENCES Site(SiteId)
) STRICT;

CREATE TABLE Equipment (
    EquipmentId INTEGER PRIMARY KEY,
    EquipmentName TEXT NOT NULL,
    EquipmentType TEXT NOT NULL,
    Capabilities TEXT,
    UsageRestrictions TEXT,
    QualificationRequirements TEXT,
    CurrentConfiguration TEXT,
    IsMovable INTEGER NOT NULL CHECK (IsMovable IN (0, 1)),
    Status TEXT NOT NULL
) STRICT;

CREATE TABLE EquipmentLocationHistory (
    LocationHistoryId INTEGER PRIMARY KEY,
    EquipmentId INTEGER NOT NULL,
    FacilityId INTEGER NOT NULL,
    ValidFrom TEXT NOT NULL,
    ValidTo TEXT,
    FOREIGN KEY (EquipmentId) REFERENCES Equipment(EquipmentId),
    FOREIGN KEY (FacilityId) REFERENCES Facility(FacilityId),
    UNIQUE (EquipmentId, ValidFrom),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ValidFrom, '+0 seconds') IS ValidFrom),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ValidTo, '+0 seconds') IS ValidTo),
    CHECK (ValidTo IS NULL OR ValidTo > ValidFrom)
) STRICT;

CREATE UNIQUE INDEX uq_equipment_open_location
    ON EquipmentLocationHistory (EquipmentId) WHERE ValidTo IS NULL;

-- Projects and requests
CREATE TABLE Project (
    ProjectId INTEGER PRIMARY KEY,
    ProjectName TEXT NOT NULL,
    Description TEXT,
    ConfidentialityLevel TEXT NOT NULL,
    PlannedStart TEXT,
    PlannedEnd TEXT,
    CHECK (date(PlannedStart, '+0 days') IS PlannedStart),
    CHECK (date(PlannedEnd, '+0 days') IS PlannedEnd),
    CHECK (PlannedEnd IS NULL OR (PlannedStart IS NOT NULL AND PlannedEnd >= PlannedStart))
) STRICT;

CREATE TABLE Experiment (
    ExperimentId INTEGER PRIMARY KEY,
    ProjectId INTEGER NOT NULL,
    ExperimentName TEXT NOT NULL,
    Description TEXT,
    PlannedStart TEXT,
    PlannedEnd TEXT,
    Status TEXT NOT NULL,
    FOREIGN KEY (ProjectId) REFERENCES Project(ProjectId),
    CHECK (date(PlannedStart, '+0 days') IS PlannedStart),
    CHECK (date(PlannedEnd, '+0 days') IS PlannedEnd),
    CHECK (PlannedEnd IS NULL OR (PlannedStart IS NOT NULL AND PlannedEnd >= PlannedStart))
) STRICT;

CREATE TABLE ExperimentResearcher (
    ExperimentId INTEGER NOT NULL,
    ResearcherId INTEGER NOT NULL,
    ParticipationRole TEXT NOT NULL CHECK (ParticipationRole IN ('lead', 'collaborator')),
    PRIMARY KEY (ExperimentId, ResearcherId),
    FOREIGN KEY (ExperimentId) REFERENCES Experiment(ExperimentId),
    FOREIGN KEY (ResearcherId) REFERENCES Researcher(ResearcherId)
) STRICT;

CREATE TABLE AccessRequest (
    RequestId INTEGER PRIMARY KEY,
    ExperimentId INTEGER NOT NULL,
    RequesterId INTEGER NOT NULL,
    SubmittedAt TEXT NOT NULL,
    -- Acceptable scheduling window, not a reservation or actual-use interval.
    RequestedStart TEXT,
    RequestedEnd TEXT,
    -- Requested operating minutes within that window; may be shorter than it.
    -- For phased requests, this is the total requested operating time.
    RequestedDurationMinutes INTEGER CHECK (RequestedDurationMinutes > 0),
    ResourceRequirements TEXT NOT NULL,
    SafetyConsiderations TEXT,
    SpecialConditions TEXT,
    -- Descriptive estimate (time, samples, materials, etc.), not a versioned
    -- earlier forecast. In seed.sql, minute-only text mirrors requested minutes.
    EstimatedUsage TEXT,
    ExpectedOutcomes TEXT,
    Status TEXT NOT NULL,
    FOREIGN KEY (ExperimentId) REFERENCES Experiment(ExperimentId),
    FOREIGN KEY (RequesterId) REFERENCES Researcher(ResearcherId),
    -- The requester must be a participant in the experiment.
    FOREIGN KEY (ExperimentId, RequesterId)
        REFERENCES ExperimentResearcher(ExperimentId, ResearcherId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', SubmittedAt, '+0 seconds') IS SubmittedAt),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', RequestedStart, '+0 seconds') IS RequestedStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', RequestedEnd, '+0 seconds') IS RequestedEnd),
    CHECK ((RequestedStart IS NULL) = (RequestedEnd IS NULL)),
    CHECK (RequestedStart IS NULL OR RequestedEnd > RequestedStart),
    CHECK (RequestedStart IS NULL OR RequestedDurationMinutes IS NULL
        OR RequestedDurationMinutes * 60
           <= unixepoch(RequestedEnd) - unixepoch(RequestedStart)),
    CHECK (RequestedStart IS NOT NULL OR RequestedDurationMinutes IS NOT NULL)
) STRICT;

-- Scheduling and actual usage
-- EventType: experiment_session, setup, maintenance, calibration, cleaning,
-- inspection, or reconfiguration. Use maintenance/calibration for query 2.
CREATE TABLE Event (
    EventId INTEGER PRIMARY KEY,
    RequestId INTEGER,
    EventType TEXT NOT NULL,
    PlannedStart TEXT NOT NULL,
    PlannedEnd TEXT NOT NULL,
    Status TEXT NOT NULL,
    ActivityDetails TEXT,
    ResultDetails TEXT,
    FOREIGN KEY (RequestId) REFERENCES AccessRequest(RequestId),
    CHECK (EventType <> 'experiment_session' OR RequestId IS NOT NULL),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', PlannedStart, '+0 seconds') IS PlannedStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', PlannedEnd, '+0 seconds') IS PlannedEnd),
    CHECK (PlannedEnd > PlannedStart)
) STRICT;

-- Use approved, rejected, alternative_proposed for request decisions;
-- use rescheduled, cancelled, configuration_changed, etc. for event history.
CREATE TABLE ScheduleDecision (
    DecisionId INTEGER PRIMARY KEY,
    RequestId INTEGER,
    EventId INTEGER,
    DecidedByStaffId INTEGER NOT NULL,
    DecisionType TEXT NOT NULL,
    DecidedAt TEXT NOT NULL,
    Reason TEXT NOT NULL,
    BeforeDetails TEXT,
    AfterDetails TEXT,
    FOREIGN KEY (RequestId) REFERENCES AccessRequest(RequestId),
    FOREIGN KEY (EventId) REFERENCES Event(EventId),
    FOREIGN KEY (DecidedByStaffId) REFERENCES Staff(StaffId),
    CHECK ((RequestId IS NOT NULL) + (EventId IS NOT NULL) = 1),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', DecidedAt, '+0 seconds') IS DecidedAt)
) STRICT;

-- Retain cancelled/replaced rows; exclude them from valid reservation and
-- assignment counts. Completed rows still count for historical scheduling.
CREATE TABLE EventFacility (
    EventFacilityId INTEGER PRIMARY KEY,
    EventId INTEGER NOT NULL,
    FacilityId INTEGER NOT NULL,
    ReservedStart TEXT NOT NULL,
    ReservedEnd TEXT NOT NULL,
    ConfigurationDetails TEXT,
    BlocksEntireFacility INTEGER NOT NULL DEFAULT 0 CHECK (BlocksEntireFacility IN (0, 1)),
    ReservationStatus TEXT NOT NULL
        CHECK (ReservationStatus IN ('scheduled', 'completed', 'cancelled', 'replaced')),
    FOREIGN KEY (EventId) REFERENCES Event(EventId),
    FOREIGN KEY (FacilityId) REFERENCES Facility(FacilityId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ReservedStart, '+0 seconds') IS ReservedStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ReservedEnd, '+0 seconds') IS ReservedEnd),
    CHECK (ReservedEnd > ReservedStart)
) STRICT;

CREATE TABLE EventEquipment (
    EventEquipmentId INTEGER PRIMARY KEY,
    EventId INTEGER NOT NULL,
    EquipmentId INTEGER NOT NULL,
    ReservedStart TEXT NOT NULL,
    ReservedEnd TEXT NOT NULL,
    ConfigurationDetails TEXT,
    ReservationStatus TEXT NOT NULL
        CHECK (ReservationStatus IN ('scheduled', 'completed', 'cancelled', 'replaced')),
    FOREIGN KEY (EventId) REFERENCES Event(EventId),
    FOREIGN KEY (EquipmentId) REFERENCES Equipment(EquipmentId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ReservedStart, '+0 seconds') IS ReservedStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ReservedEnd, '+0 seconds') IS ReservedEnd),
    CHECK (ReservedEnd > ReservedStart)
) STRICT;

CREATE TABLE StaffAvailability (
    AvailabilityId INTEGER PRIMARY KEY,
    StaffId INTEGER NOT NULL,
    StartTime TEXT NOT NULL,
    EndTime TEXT NOT NULL,
    AvailabilityType TEXT NOT NULL CHECK (AvailabilityType IN ('available', 'unavailable')),
    Reason TEXT,
    FOREIGN KEY (StaffId) REFERENCES Staff(StaffId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', StartTime, '+0 seconds') IS StartTime),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', EndTime, '+0 seconds') IS EndTime),
    CHECK (EndTime > StartTime)
) STRICT;

CREATE TABLE StaffAssignment (
    AssignmentId INTEGER PRIMARY KEY,
    EventId INTEGER NOT NULL,
    StaffId INTEGER NOT NULL,
    AssignedStart TEXT NOT NULL,
    AssignedEnd TEXT NOT NULL,
    Duty TEXT NOT NULL,
    AssignmentStatus TEXT NOT NULL
        CHECK (AssignmentStatus IN ('scheduled', 'completed', 'cancelled', 'replaced')),
    FOREIGN KEY (EventId) REFERENCES Event(EventId),
    FOREIGN KEY (StaffId) REFERENCES Staff(StaffId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AssignedStart, '+0 seconds') IS AssignedStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AssignedEnd, '+0 seconds') IS AssignedEnd),
    CHECK (AssignedEnd > AssignedStart)
) STRICT;

CREATE TABLE UsageRecord (
    UsageId INTEGER PRIMARY KEY,
    EventFacilityId INTEGER,
    EventEquipmentId INTEGER,
    AssignmentId INTEGER,
    ResearcherId INTEGER,
    StaffId INTEGER,
    ActualStart TEXT NOT NULL,
    ActualEnd TEXT NOT NULL,
    UsageQuantity REAL CHECK (UsageQuantity >= 0),
    UsageUnit TEXT,
    FOREIGN KEY (EventFacilityId) REFERENCES EventFacility(EventFacilityId),
    FOREIGN KEY (EventEquipmentId) REFERENCES EventEquipment(EventEquipmentId),
    FOREIGN KEY (AssignmentId) REFERENCES StaffAssignment(AssignmentId),
    FOREIGN KEY (ResearcherId) REFERENCES Researcher(ResearcherId),
    FOREIGN KEY (StaffId) REFERENCES Staff(StaffId),
    CHECK ((EventFacilityId IS NOT NULL) + (EventEquipmentId IS NOT NULL)
           + (AssignmentId IS NOT NULL) = 1),
    -- For work logs, StaffAssignment identifies the staff member.
    CHECK ((AssignmentId IS NOT NULL AND ResearcherId IS NULL AND StaffId IS NULL)
        OR (AssignmentId IS NULL AND (ResearcherId IS NOT NULL) + (StaffId IS NOT NULL) = 1)),
    CHECK ((UsageQuantity IS NULL) = (UsageUnit IS NULL)),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ActualStart, '+0 seconds') IS ActualStart),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ActualEnd, '+0 seconds') IS ActualEnd),
    CHECK (ActualEnd > ActualStart)
) STRICT;

-- Funding and charges
CREATE TABLE FundingSource (
    FundingSourceId INTEGER PRIMARY KEY,
    FundingSourceName TEXT NOT NULL,
    FundingType TEXT NOT NULL,
    ProviderDescription TEXT,
    UsageRestrictions TEXT
) STRICT;

CREATE TABLE AllocationRule (
    RuleId INTEGER PRIMARY KEY,
    ExperimentId INTEGER NOT NULL,
    AuthorizedByStaffId INTEGER NOT NULL,
    EffectiveFrom TEXT NOT NULL,
    EffectiveTo TEXT,
    AuthorizedAt TEXT NOT NULL,
    Reason TEXT,
    FOREIGN KEY (ExperimentId) REFERENCES Experiment(ExperimentId),
    FOREIGN KEY (AuthorizedByStaffId) REFERENCES Staff(StaffId),
    UNIQUE (ExperimentId, EffectiveFrom),
    CHECK (date(EffectiveFrom, '+0 days') IS EffectiveFrom),
    CHECK (date(EffectiveTo, '+0 days') IS EffectiveTo),
    CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AuthorizedAt, '+0 seconds') IS AuthorizedAt)
) STRICT;

CREATE TABLE AllocationRuleFunding (
    RuleId INTEGER NOT NULL,
    FundingSourceId INTEGER NOT NULL,
    AllocationPercentage REAL NOT NULL CHECK (AllocationPercentage > 0 AND AllocationPercentage <= 100),
    PRIMARY KEY (RuleId, FundingSourceId),
    FOREIGN KEY (RuleId) REFERENCES AllocationRule(RuleId),
    FOREIGN KEY (FundingSourceId) REFERENCES FundingSource(FundingSourceId)
) STRICT;

-- A default rule is looked up by ExperimentId and ChargeDate. Do not store
-- RuleId on Charge. ChargeAllocation records the actual approved split.
CREATE TABLE Charge (
    ChargeId INTEGER PRIMARY KEY,
    ExperimentId INTEGER NOT NULL,
    ResponsiblePartyId INTEGER NOT NULL,
    UsageId INTEGER,
    AllocationAuthorizedByStaffId INTEGER,
    ChargeType TEXT NOT NULL,
    Description TEXT,
    Quantity REAL NOT NULL CHECK (Quantity > 0),
    Unit TEXT NOT NULL,
    UnitPrice INTEGER NOT NULL CHECK (UnitPrice >= 0),
    EstimatedAmount INTEGER CHECK (EstimatedAmount >= 0),
    FinalAmount INTEGER CHECK (FinalAmount >= 0),
    ChargeDate TEXT NOT NULL,
    Status TEXT NOT NULL CHECK (Status IN ('draft', 'estimated', 'finalized', 'cancelled')),
    AllocationExceptionReason TEXT,
    AllocationAuthorizedAt TEXT,
    FOREIGN KEY (ExperimentId) REFERENCES Experiment(ExperimentId),
    FOREIGN KEY (ResponsiblePartyId) REFERENCES ResponsibleParty(ResponsiblePartyId),
    FOREIGN KEY (UsageId) REFERENCES UsageRecord(UsageId),
    FOREIGN KEY (AllocationAuthorizedByStaffId) REFERENCES Staff(StaffId),
    CHECK (date(ChargeDate, '+0 days') IS ChargeDate),
    CHECK ((Status = 'finalized') = (FinalAmount IS NOT NULL)),
    CHECK (Status <> 'estimated' OR EstimatedAmount IS NOT NULL),
    CHECK ((AllocationAuthorizedByStaffId IS NULL) = (AllocationExceptionReason IS NULL)
       AND (AllocationAuthorizedByStaffId IS NULL) = (AllocationAuthorizedAt IS NULL)),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AllocationAuthorizedAt, '+0 seconds') IS AllocationAuthorizedAt)
) STRICT;

CREATE TABLE ChargeAdjustment (
    AdjustmentId INTEGER PRIMARY KEY,
    ChargeId INTEGER NOT NULL,
    AuthorizedByStaffId INTEGER NOT NULL,
    AdjustmentAmount INTEGER NOT NULL CHECK (AdjustmentAmount <> 0),
    Reason TEXT NOT NULL,
    AuthorizedAt TEXT NOT NULL,
    FOREIGN KEY (ChargeId) REFERENCES Charge(ChargeId),
    FOREIGN KEY (AuthorizedByStaffId) REFERENCES Staff(StaffId),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AuthorizedAt, '+0 seconds') IS AuthorizedAt)
) STRICT;

CREATE TABLE ChargeAllocation (
    ChargeAllocationId INTEGER PRIMARY KEY,
    ChargeId INTEGER,
    AdjustmentId INTEGER,
    FundingSourceId INTEGER NOT NULL,
    AllocatedAmount INTEGER NOT NULL,
    FOREIGN KEY (ChargeId) REFERENCES Charge(ChargeId),
    FOREIGN KEY (AdjustmentId) REFERENCES ChargeAdjustment(AdjustmentId),
    FOREIGN KEY (FundingSourceId) REFERENCES FundingSource(FundingSourceId),
    CHECK ((ChargeId IS NOT NULL) + (AdjustmentId IS NOT NULL) = 1),
    CHECK (ChargeId IS NULL OR AllocatedAmount >= 0),
    UNIQUE (ChargeId, FundingSourceId),
    UNIQUE (AdjustmentId, FundingSourceId)
) STRICT;

-- Permissions and access
CREATE TABLE AccessPermission (
    PermissionId INTEGER PRIMARY KEY,
    ResearcherId INTEGER,
    StaffId INTEGER,
    FacilityId INTEGER,
    EquipmentId INTEGER,
    ProjectId INTEGER,
    GrantedByStaffId INTEGER NOT NULL,
    PermissionType TEXT NOT NULL CHECK (PermissionType IN ('resource_use', 'information_view')),
    GrantedAt TEXT NOT NULL,
    ValidFrom TEXT NOT NULL,
    ValidTo TEXT,
    QualificationResult TEXT,
    QualificationCheckedAt TEXT,
    Conditions TEXT,
    RevokedAt TEXT,
    FOREIGN KEY (ResearcherId) REFERENCES Researcher(ResearcherId),
    FOREIGN KEY (StaffId) REFERENCES Staff(StaffId),
    FOREIGN KEY (FacilityId) REFERENCES Facility(FacilityId),
    FOREIGN KEY (EquipmentId) REFERENCES Equipment(EquipmentId),
    FOREIGN KEY (ProjectId) REFERENCES Project(ProjectId),
    FOREIGN KEY (GrantedByStaffId) REFERENCES Staff(StaffId),
    CHECK ((ResearcherId IS NOT NULL) + (StaffId IS NOT NULL) = 1),
    CHECK ((FacilityId IS NOT NULL) + (EquipmentId IS NOT NULL) + (ProjectId IS NOT NULL) = 1),
    CHECK ((PermissionType = 'information_view') = (ProjectId IS NOT NULL)),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', GrantedAt, '+0 seconds') IS GrantedAt),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ValidFrom, '+0 seconds') IS ValidFrom),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', ValidTo, '+0 seconds') IS ValidTo),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', QualificationCheckedAt, '+0 seconds') IS QualificationCheckedAt),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', RevokedAt, '+0 seconds') IS RevokedAt),
    CHECK (ValidTo IS NULL OR ValidTo > ValidFrom),
    CHECK (RevokedAt IS NULL OR RevokedAt >= GrantedAt)
) STRICT;

CREATE TABLE AccessLog (
    AccessLogId INTEGER PRIMARY KEY,
    ResearcherId INTEGER,
    StaffId INTEGER,
    FacilityId INTEGER,
    EquipmentId INTEGER,
    AccessTime TEXT NOT NULL,
    AccessAction TEXT NOT NULL,
    AccessResult TEXT NOT NULL CHECK (AccessResult IN ('granted', 'denied')),
    Details TEXT,
    FOREIGN KEY (ResearcherId) REFERENCES Researcher(ResearcherId),
    FOREIGN KEY (StaffId) REFERENCES Staff(StaffId),
    FOREIGN KEY (FacilityId) REFERENCES Facility(FacilityId),
    FOREIGN KEY (EquipmentId) REFERENCES Equipment(EquipmentId),
    CHECK ((ResearcherId IS NOT NULL) + (StaffId IS NOT NULL) = 1),
    CHECK ((FacilityId IS NOT NULL) + (EquipmentId IS NOT NULL) = 1),
    CHECK (strftime('%Y-%m-%d %H:%M:%S', AccessTime, '+0 seconds') IS AccessTime)
) STRICT;

-- Indexes for relationship joins, timeline queries, and validation.
CREATE INDEX idx_researcher_institution ON Researcher (InstitutionId);
CREATE INDEX idx_experiment_project ON Experiment (ProjectId);
CREATE INDEX idx_participation_researcher ON ExperimentResearcher (ResearcherId);
CREATE INDEX idx_request_requester ON AccessRequest (RequesterId, SubmittedAt);
CREATE INDEX idx_decision_request_time ON ScheduleDecision (RequestId, DecidedAt);
CREATE INDEX idx_facility_reservation_time ON EventFacility (FacilityId, ReservedStart);
CREATE INDEX idx_equipment_reservation_time ON EventEquipment (EquipmentId, ReservedStart);
CREATE INDEX idx_staff_assignment_time ON StaffAssignment (StaffId, AssignedStart);
CREATE INDEX idx_usage_facility ON UsageRecord (EventFacilityId, ActualStart);
CREATE INDEX idx_usage_equipment ON UsageRecord (EventEquipmentId, ActualStart);
CREATE INDEX idx_usage_assignment ON UsageRecord (AssignmentId, ActualStart);
CREATE INDEX idx_charge_date ON Charge (ChargeDate);
CREATE INDEX idx_charge_usage ON Charge (UsageId);
CREATE INDEX idx_adjustment_charge ON ChargeAdjustment (ChargeId, AuthorizedAt);
CREATE INDEX idx_allocation_source ON ChargeAllocation (FundingSourceId);
CREATE INDEX idx_log_facility ON AccessLog (FacilityId, AccessTime);
CREATE INDEX idx_log_equipment ON AccessLog (EquipmentId, AccessTime);

-- Batch validation. Run after writing related rows, before committing the
-- seed/import transaction. The view reports issues; it does not reject writes.
CREATE VIEW ConsortiumValidationIssues (Issue, RecordId) AS
WITH valid_facility_reservations AS (
    SELECT * FROM EventFacility
    WHERE ReservationStatus IN ('scheduled', 'completed')
),
facility_start_points AS (
    SELECT DISTINCT FacilityId, ReservedStart
    FROM valid_facility_reservations
),
facility_load AS (
    SELECT p.FacilityId, p.ReservedStart,
           COUNT(DISTINCT r.EventId) AS EventCount,
           MAX(r.BlocksEntireFacility) AS IsBlocked
    FROM facility_start_points AS p
    JOIN valid_facility_reservations AS r
      ON r.FacilityId = p.FacilityId
     AND r.ReservedStart <= p.ReservedStart
     AND r.ReservedEnd > p.ReservedStart
    GROUP BY p.FacilityId, p.ReservedStart
)
SELECT 'overlapping_equipment_locations', a.LocationHistoryId
FROM EquipmentLocationHistory AS a
JOIN EquipmentLocationHistory AS b
  ON a.EquipmentId = b.EquipmentId AND a.LocationHistoryId < b.LocationHistoryId
 AND (a.ValidTo IS NULL OR b.ValidFrom < a.ValidTo)
 AND (b.ValidTo IS NULL OR a.ValidFrom < b.ValidTo)
UNION ALL
SELECT 'facility_capacity_or_block_violation', l.FacilityId
FROM facility_load AS l
JOIN Facility AS f ON f.FacilityId = l.FacilityId
WHERE l.EventCount > f.ConcurrentEventCapacity OR (l.IsBlocked = 1 AND l.EventCount > 1)
UNION ALL
SELECT 'overlapping_equipment_reservations', a.EventEquipmentId
FROM EventEquipment AS a
JOIN EventEquipment AS b
  ON a.EquipmentId = b.EquipmentId AND a.EventEquipmentId < b.EventEquipmentId
 AND a.ReservedStart < b.ReservedEnd AND b.ReservedStart < a.ReservedEnd
WHERE a.ReservationStatus IN ('scheduled', 'completed')
  AND b.ReservationStatus IN ('scheduled', 'completed')
UNION ALL
SELECT 'overlapping_staff_assignments', a.AssignmentId
FROM StaffAssignment AS a
JOIN StaffAssignment AS b
  ON a.StaffId = b.StaffId AND a.AssignmentId < b.AssignmentId
 AND a.AssignedStart < b.AssignedEnd AND b.AssignedStart < a.AssignedEnd
WHERE a.AssignmentStatus IN ('scheduled', 'completed')
  AND b.AssignmentStatus IN ('scheduled', 'completed')
UNION ALL
SELECT 'assignment_during_staff_unavailability', a.AssignmentId
FROM StaffAssignment AS a
WHERE a.AssignmentStatus IN ('scheduled', 'completed') AND EXISTS (
    SELECT 1 FROM StaffAvailability AS s
    WHERE s.StaffId = a.StaffId AND s.AvailabilityType = 'unavailable'
      AND a.AssignedStart < s.EndTime AND s.StartTime < a.AssignedEnd
)
UNION ALL
SELECT 'decision_before_request_submission', d.DecisionId
FROM ScheduleDecision AS d
JOIN AccessRequest AS r ON r.RequestId = d.RequestId
WHERE d.DecidedAt < r.SubmittedAt
UNION ALL
SELECT 'session_without_prior_approval', e.EventId
FROM Event AS e
WHERE e.EventType = 'experiment_session' AND e.Status <> 'cancelled'
  AND NOT EXISTS (
    SELECT 1 FROM ScheduleDecision AS d
    JOIN AccessRequest AS r ON r.RequestId = d.RequestId
    WHERE d.RequestId = e.RequestId AND d.DecisionType = 'approved'
      AND d.DecidedAt BETWEEN r.SubmittedAt AND e.PlannedStart
)
UNION ALL
SELECT 'active_experiment_without_participants', e.ExperimentId
FROM Experiment AS e
WHERE e.Status IN ('active', 'completed') AND NOT EXISTS (
    SELECT 1 FROM ExperimentResearcher AS er WHERE er.ExperimentId = e.ExperimentId
)
UNION ALL
SELECT 'overlapping_allocation_rule_versions', a.RuleId
FROM AllocationRule AS a
JOIN AllocationRule AS b
  ON a.ExperimentId = b.ExperimentId AND a.RuleId < b.RuleId
 AND (a.EffectiveTo IS NULL OR b.EffectiveFrom < a.EffectiveTo)
 AND (b.EffectiveTo IS NULL OR a.EffectiveFrom < b.EffectiveTo)
UNION ALL
SELECT 'rule_funding_does_not_sum_to_100', r.RuleId
FROM AllocationRule AS r
LEFT JOIN AllocationRuleFunding AS f ON f.RuleId = r.RuleId
GROUP BY r.RuleId
HAVING COUNT(f.FundingSourceId) = 0 OR ABS(SUM(f.AllocationPercentage) - 100.0) > 0.000001
UNION ALL
SELECT 'final_charge_without_default_rule_or_exception', c.ChargeId
FROM Charge AS c
WHERE c.Status = 'finalized' AND c.AllocationAuthorizedByStaffId IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM AllocationRule AS r
    WHERE r.ExperimentId = c.ExperimentId AND r.EffectiveFrom <= c.ChargeDate
      AND (r.EffectiveTo IS NULL OR c.ChargeDate < r.EffectiveTo)
)
UNION ALL
SELECT 'final_charge_allocations_do_not_balance', c.ChargeId
FROM Charge AS c
LEFT JOIN ChargeAllocation AS a ON a.ChargeId = c.ChargeId
WHERE c.Status = 'finalized'
GROUP BY c.ChargeId, c.FinalAmount
HAVING COUNT(a.ChargeAllocationId) = 0 OR SUM(a.AllocatedAmount) <> c.FinalAmount
UNION ALL
SELECT 'adjustment_on_nonfinal_charge', a.AdjustmentId
FROM ChargeAdjustment AS a
JOIN Charge AS c ON c.ChargeId = a.ChargeId
WHERE c.Status <> 'finalized'
UNION ALL
SELECT 'adjustment_allocations_do_not_balance', a.AdjustmentId
FROM ChargeAdjustment AS a
LEFT JOIN ChargeAllocation AS f ON f.AdjustmentId = a.AdjustmentId
GROUP BY a.AdjustmentId, a.AdjustmentAmount
HAVING COUNT(f.ChargeAllocationId) = 0 OR SUM(f.AllocatedAmount) <> a.AdjustmentAmount;

COMMIT;
