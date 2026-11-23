-- =====================================================================
--  AUB Mediterraneo Admissions Database
--  INDE 513 Information Systems, Project Phase II
--  File 1 of 4: schema (tables, constraints, triggers, views)
--  Target DBMS: SQLite 3
-- =====================================================================

PRAGMA foreign_keys = ON;

-- Drop in reverse dependency order so the script can be re-run
DROP VIEW  IF EXISTS vApplicationSummary;
DROP VIEW  IF EXISTS vApplicant;
DROP TABLE IF EXISTS FinancialAidAward;
DROP TABLE IF EXISTS AdmissionDecision;
DROP TABLE IF EXISTS Review;
DROP TABLE IF EXISTS ApplicationDocument;
DROP TABLE IF EXISTS Application;
DROP TABLE IF EXISTS ApplicantNationality;
DROP TABLE IF EXISTS ApplicantPhone;
DROP TABLE IF EXISTS Applicant;
DROP TABLE IF EXISTS Professor;
DROP TABLE IF EXISTS ProgramRequirement;
DROP TABLE IF EXISTS Requirement;
DROP TABLE IF EXISTS Program;
DROP TABLE IF EXISTS Department;

-- ---------------------------------------------------------------------
-- Strong entities
-- ---------------------------------------------------------------------

CREATE TABLE Department (
    DepartmentID    CHAR(4)      PRIMARY KEY
                    CHECK (length(DepartmentID) = 4 AND DepartmentID = upper(DepartmentID)),
    DepartmentName  VARCHAR(60)  NOT NULL UNIQUE
                    CHECK (length(DepartmentName) <= 60)
);

-- Department Offers Program (1:N): DepartmentID is a required FK in Program
CREATE TABLE Program (
    ProgramID       CHAR(5)      PRIMARY KEY
                    CHECK (length(ProgramID) = 5 AND ProgramID = upper(ProgramID)),
    ProgramName     VARCHAR(80)  NOT NULL UNIQUE
                    CHECK (length(ProgramName) <= 80),
    DegreeLevel     VARCHAR(13)  NOT NULL
                    CHECK (DegreeLevel IN ('Undergraduate', 'Graduate')),
    ProgramStatus   VARCHAR(8)   NOT NULL DEFAULT 'Active'
                    CHECK (ProgramStatus IN ('Active', 'Planned', 'Inactive')),
    DepartmentID    CHAR(4)      NOT NULL,
    FOREIGN KEY (DepartmentID) REFERENCES Department(DepartmentID)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE Requirement (
    RequirementID   INTEGER      PRIMARY KEY,
    RequirementName VARCHAR(60)  NOT NULL UNIQUE
                    CHECK (length(RequirementName) <= 60),
    RequirementType VARCHAR(17)  NOT NULL
                    CHECK (RequirementType IN ('Academic Record', 'Standardized Exam',
                                               'Recommendation', 'Statement',
                                               'Language', 'Identification')),
    Description     VARCHAR(200)
                    CHECK (Description IS NULL OR length(Description) <= 200)
);

-- Program Requires Requirement (M:N) becomes its own table
CREATE TABLE ProgramRequirement (
    ProgramID       CHAR(5)      NOT NULL,
    RequirementID   INTEGER      NOT NULL,
    IsMandatory     CHAR(1)      NOT NULL DEFAULT 'Y'
                    CHECK (IsMandatory IN ('Y', 'N')),
    PRIMARY KEY (ProgramID, RequirementID),
    FOREIGN KEY (ProgramID)     REFERENCES Program(ProgramID)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (RequirementID) REFERENCES Requirement(RequirementID)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Professor BelongsTo Department (N:1): required FK
CREATE TABLE Professor (
    ProfessorID     INTEGER      PRIMARY KEY,
    FirstName       VARCHAR(30)  NOT NULL CHECK (length(FirstName) <= 30),
    LastName        VARCHAR(30)  NOT NULL CHECK (length(LastName)  <= 30),
    Email           VARCHAR(60)  UNIQUE
                    CHECK (Email IS NULL OR (length(Email) <= 60 AND Email LIKE '%_@_%._%')),
    DepartmentID    CHAR(4)      NOT NULL,
    FOREIGN KEY (DepartmentID) REFERENCES Department(DepartmentID)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Applicant: ApplicantID = primary key, PassportNo = secondary (candidate) key.
-- Name is composite -> FirstName, MiddleName (optional), LastName.
-- Age is derived from DateOfBirth and is NOT stored (see view vApplicant).
CREATE TABLE Applicant (
    ApplicantID     INTEGER      PRIMARY KEY,
    PassportNo      VARCHAR(12)  NOT NULL UNIQUE
                    CHECK (length(PassportNo) BETWEEN 6 AND 12),
    FirstName       VARCHAR(30)  NOT NULL CHECK (length(FirstName) <= 30),
    MiddleName      VARCHAR(30)  CHECK (MiddleName IS NULL OR length(MiddleName) <= 30),
    LastName        VARCHAR(30)  NOT NULL CHECK (length(LastName) <= 30),
    DateOfBirth     DATE         NOT NULL
                    CHECK (DateOfBirth = date(DateOfBirth) AND DateOfBirth > '1950-01-01'),
    Email           VARCHAR(60)  NOT NULL UNIQUE
                    CHECK (length(Email) <= 60 AND Email LIKE '%_@_%._%')
);

-- Multivalued attribute PhoneNumber -> separate table
CREATE TABLE ApplicantPhone (
    ApplicantID     INTEGER      NOT NULL,
    PhoneNumber     VARCHAR(16)  NOT NULL
                    CHECK (length(PhoneNumber) BETWEEN 8 AND 16 AND PhoneNumber LIKE '+%'),
    PRIMARY KEY (ApplicantID, PhoneNumber),
    FOREIGN KEY (ApplicantID) REFERENCES Applicant(ApplicantID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- Multivalued attribute Nationality -> separate table (ISO 3166 alpha-3 code)
CREATE TABLE ApplicantNationality (
    ApplicantID     INTEGER      NOT NULL,
    CountryCode     CHAR(3)      NOT NULL
                    CHECK (length(CountryCode) = 3 AND CountryCode = upper(CountryCode)),
    PRIMARY KEY (ApplicantID, CountryCode),
    FOREIGN KEY (ApplicantID) REFERENCES Applicant(ApplicantID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- Application: Applicant Submits Application (1:N) and Application Targets Program (N:1).
-- DaysSinceSubmission is derived and NOT stored (see view vApplicationSummary).
CREATE TABLE Application (
    ApplicationID     INTEGER     PRIMARY KEY,
    AdmissionYear     SMALLINT    NOT NULL
                      CHECK (AdmissionYear BETWEEN 2023 AND 2100),
    AdmissionTerm     CHAR(4)     NOT NULL DEFAULT 'Fall'
                      CHECK (AdmissionTerm = 'Fall'),                       -- BR4
    SubmissionDate    DATE        NOT NULL
                      CHECK (SubmissionDate = date(SubmissionDate)),
    AdmissionRound    VARCHAR(7)  NOT NULL DEFAULT 'Regular'
                      CHECK (AdmissionRound IN ('Early', 'Regular')),
    ApplicationStatus VARCHAR(12) NOT NULL DEFAULT 'Submitted'
                      CHECK (ApplicationStatus IN ('Submitted', 'Under Review', 'Decided')),
    ApplicantID       INTEGER     NOT NULL,
    ProgramID         CHAR(5)     NOT NULL,
    -- BR3: one application per program per admission cycle
    UNIQUE (ApplicantID, ProgramID, AdmissionYear),
    -- Application must be submitted during the cycle (before 1 August of the admission year)
    CHECK (SubmissionDate < printf('%04d-08-01', AdmissionYear)),
    -- BR6: Early only if submitted on/before the early deadline (assumed 15 December of the prior year)
    CHECK (AdmissionRound = 'Regular'
           OR SubmissionDate <= printf('%04d-12-15', AdmissionYear - 1)),
    FOREIGN KEY (ApplicantID) REFERENCES Applicant(ApplicantID)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (ProgramID)   REFERENCES Program(ProgramID)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- Weak entity: ApplicationDocument, owned by Application (identifying 1:N)
-- Key = owner key + discriminator DocumentNo.  BR12: cascade delete.
-- ---------------------------------------------------------------------
CREATE TABLE ApplicationDocument (
    ApplicationID   INTEGER      NOT NULL,
    DocumentNo      SMALLINT     NOT NULL CHECK (DocumentNo BETWEEN 1 AND 20),
    DocumentType    VARCHAR(25)  NOT NULL
                    CHECK (DocumentType IN ('Grade 11 Transcript', 'Grade 12 Transcript',
                                            'University Transcript', 'Exam Score',
                                            'Passport Copy', 'Recommendation Letter',
                                            'Statement of Purpose', 'English Proficiency',
                                            'Other')),
    UploadDate      DATE         NOT NULL CHECK (UploadDate = date(UploadDate)),
    PRIMARY KEY (ApplicationID, DocumentNo),
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- Professor Reviews Application (M:N) with relationship attributes
-- BR16: one review per professor per application (composite PK), score 0-100
-- ---------------------------------------------------------------------
CREATE TABLE Review (
    ProfessorID     INTEGER      NOT NULL,
    ApplicationID   INTEGER      NOT NULL,
    ReviewScore     SMALLINT     NOT NULL CHECK (ReviewScore BETWEEN 0 AND 100),
    ReviewDate      DATE         NOT NULL CHECK (ReviewDate = date(ReviewDate)),
    Comments        VARCHAR(500) CHECK (Comments IS NULL OR length(Comments) <= 500),
    PRIMARY KEY (ProfessorID, ApplicationID),
    FOREIGN KEY (ProfessorID)   REFERENCES Professor(ProfessorID)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 1:1 relationships: FK placed on the side with total participation,
-- declared NOT NULL UNIQUE (same pattern as Porder.purchaseId in Anna's Books)
-- ---------------------------------------------------------------------
CREATE TABLE AdmissionDecision (
    DecisionID      INTEGER      PRIMARY KEY,
    DecisionType    VARCHAR(10)  NOT NULL
                    CHECK (DecisionType IN ('Accepted', 'Rejected', 'Waitlisted')),
    DecisionDate    DATE         NOT NULL CHECK (DecisionDate = date(DecisionDate)),
    ApplicationID   INTEGER      NOT NULL UNIQUE,                         -- BR18: at most one decision
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE FinancialAidAward (
    AwardID         INTEGER      PRIMARY KEY,
    AidType         VARCHAR(12)  NOT NULL DEFAULT 'Need-Based'
                    CHECK (AidType IN ('Need-Based', 'Early Merit', 'Merit + Need')),
    AidPercentage   DECIMAL(5,2) NOT NULL
                    CHECK (AidPercentage > 0 AND AidPercentage <= 100),
    ApplicationID   INTEGER      NOT NULL UNIQUE,                         -- BR20: at most one award
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- Indexes on foreign keys used for searching (Index = Y(Y) in the data dictionary)
-- ---------------------------------------------------------------------
CREATE INDEX idx_program_dept       ON Program(DepartmentID);
CREATE INDEX idx_professor_dept     ON Professor(DepartmentID);
CREATE INDEX idx_application_appl   ON Application(ApplicantID);
CREATE INDEX idx_application_prog   ON Application(ProgramID);
CREATE INDEX idx_review_application ON Review(ApplicationID);

-- ---------------------------------------------------------------------
-- Triggers: business rules that a single-row CHECK cannot express
-- ---------------------------------------------------------------------

-- BR3: at most 3 applications per applicant per admission cycle
CREATE TRIGGER trg_application_max3
BEFORE INSERT ON Application
WHEN (SELECT COUNT(*) FROM Application
      WHERE ApplicantID = NEW.ApplicantID AND AdmissionYear = NEW.AdmissionYear) >= 3
BEGIN
    SELECT RAISE(ABORT, 'BR3: an applicant may submit at most 3 applications per admission cycle');
END;

-- BR15: a reviewer must belong to the department that offers the program
CREATE TRIGGER trg_review_same_department
BEFORE INSERT ON Review
WHEN (SELECT DepartmentID FROM Professor WHERE ProfessorID = NEW.ProfessorID)
  <> (SELECT p.DepartmentID FROM Application a JOIN Program p ON p.ProgramID = a.ProgramID
      WHERE a.ApplicationID = NEW.ApplicationID)
BEGIN
    SELECT RAISE(ABORT, 'BR15: reviewer must belong to the department offering the program');
END;

-- Reviews (2,3): no more than 3 reviewers per application
CREATE TRIGGER trg_review_max3
BEFORE INSERT ON Review
WHEN (SELECT COUNT(*) FROM Review WHERE ApplicationID = NEW.ApplicationID) >= 3
BEGIN
    SELECT RAISE(ABORT, 'An application can be reviewed by at most 3 professors');
END;

-- BR15/BR18: a decision needs at least 2 completed reviews
CREATE TRIGGER trg_decision_needs_reviews
BEFORE INSERT ON AdmissionDecision
WHEN (SELECT COUNT(*) FROM Review WHERE ApplicationID = NEW.ApplicationID) < 2
BEGIN
    SELECT RAISE(ABORT, 'BR18: a decision requires at least 2 completed reviews');
END;

-- Issuing a decision closes the application
CREATE TRIGGER trg_decision_sets_status
AFTER INSERT ON AdmissionDecision
BEGIN
    UPDATE Application SET ApplicationStatus = 'Decided'
    WHERE ApplicationID = NEW.ApplicationID;
END;

-- BR20: aid only for applications with an Accepted decision
CREATE TRIGGER trg_aid_only_accepted
BEFORE INSERT ON FinancialAidAward
WHEN NOT EXISTS (SELECT 1 FROM AdmissionDecision
                 WHERE ApplicationID = NEW.ApplicationID AND DecisionType = 'Accepted')
BEGIN
    SELECT RAISE(ABORT, 'BR20: financial aid requires an Accepted decision');
END;

-- BR22: total aid for an undergraduate cannot exceed 80% of tuition
CREATE TRIGGER trg_aid_undergrad_cap
BEFORE INSERT ON FinancialAidAward
WHEN NEW.AidPercentage > 80
 AND (SELECT p.DegreeLevel FROM Application a JOIN Program p ON p.ProgramID = a.ProgramID
      WHERE a.ApplicationID = NEW.ApplicationID) = 'Undergraduate'
BEGIN
    SELECT RAISE(ABORT, 'BR22: undergraduate aid cannot exceed 80% of tuition');
END;

-- ---------------------------------------------------------------------
-- Views for derived attributes (calculated on demand, never stored)
-- ---------------------------------------------------------------------

-- Age (derived from DateOfBirth)
CREATE VIEW vApplicant AS
SELECT a.*,
       (CAST(strftime('%Y', 'now') AS INTEGER) - CAST(strftime('%Y', a.DateOfBirth) AS INTEGER))
       - (strftime('%m-%d', 'now') < strftime('%m-%d', a.DateOfBirth)) AS Age
FROM Applicant a;

-- AverageReviewScore and DaysSinceSubmission (derived)
CREATE VIEW vApplicationSummary AS
SELECT ap.ApplicationID, ap.ApplicantID, ap.ProgramID, ap.AdmissionYear,
       ap.AdmissionRound, ap.ApplicationStatus, ap.SubmissionDate,
       CAST(julianday('now') - julianday(ap.SubmissionDate) AS INTEGER) AS DaysSinceSubmission,
       COUNT(r.ProfessorID)          AS ReviewCount,
       ROUND(AVG(r.ReviewScore), 1)  AS AverageReviewScore
FROM Application ap
LEFT JOIN Review r ON r.ApplicationID = ap.ApplicationID
GROUP BY ap.ApplicationID;
