-- =====================================================================
--  AUB Mediterraneo Admissions Database
--  File 3 of 4: queries
--  Run after 01_schema.sql and 02_sample_data.sql
-- =====================================================================

PRAGMA foreign_keys = ON;

-- Q1 (filtering + sorting)
-- Which applications were submitted in the Early round of the 2027 cycle?
-- Listed from the oldest submission so the office can process them in order.
SELECT ApplicationID, ApplicantID, ProgramID, SubmissionDate, ApplicationStatus
FROM Application
WHERE AdmissionYear = 2027
  AND AdmissionRound = 'Early'
ORDER BY SubmissionDate ASC;

-- Q2 (multi-table join)
-- Full application list for the 2026 cycle: applicant, program, department and decision.
SELECT ap.ApplicationID,
       a.FirstName || ' ' || a.LastName AS ApplicantName,
       p.ProgramName,
       d.DepartmentName,
       ap.AdmissionRound,
       ad.DecisionType
FROM Application ap
JOIN Applicant  a  ON a.ApplicantID  = ap.ApplicantID
JOIN Program    p  ON p.ProgramID    = ap.ProgramID
JOIN Department d  ON d.DepartmentID = p.DepartmentID
LEFT JOIN AdmissionDecision ad ON ad.ApplicationID = ap.ApplicationID
WHERE ap.AdmissionYear = 2026
ORDER BY p.ProgramName, ApplicantName;

-- Q3 (aggregate + GROUP BY + LEFT JOIN)
-- How many applications did each program receive in each cycle?
-- LEFT JOIN keeps programs with no applications (optional participation of Program in Targets).
SELECT p.ProgramID, p.ProgramName, ap.AdmissionYear,
       COUNT(ap.ApplicationID) AS NumApplications
FROM Program p
LEFT JOIN Application ap ON ap.ProgramID = p.ProgramID
GROUP BY p.ProgramID, p.ProgramName, ap.AdmissionYear
ORDER BY p.ProgramID, ap.AdmissionYear;

-- Q4 (aggregate + GROUP BY + HAVING)
-- Acceptance rate per program in 2026, only for programs that received at least 3 decided applications.
SELECT p.ProgramName,
       COUNT(*)                                                   AS Decided,
       SUM(CASE WHEN ad.DecisionType = 'Accepted' THEN 1 ELSE 0 END) AS Accepted,
       ROUND(100.0 * SUM(CASE WHEN ad.DecisionType = 'Accepted' THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                                  AS AcceptanceRatePct
FROM AdmissionDecision ad
JOIN Application ap ON ap.ApplicationID = ad.ApplicationID
JOIN Program     p  ON p.ProgramID      = ap.ProgramID
WHERE ap.AdmissionYear = 2026
GROUP BY p.ProgramName
HAVING COUNT(*) >= 3
ORDER BY AcceptanceRatePct DESC;

-- Q5 (derived attribute: average review score, GROUP BY + HAVING)
-- Average review score of each 2026 application with its decision, best files first.
-- AverageReviewScore is derived (BR17): calculated here, never stored.
SELECT ap.ApplicationID,
       a.FirstName || ' ' || a.LastName AS ApplicantName,
       ap.ProgramID,
       COUNT(r.ProfessorID)          AS NumReviews,
       ROUND(AVG(r.ReviewScore), 1)  AS AverageReviewScore,
       ad.DecisionType
FROM Application ap
JOIN Applicant a ON a.ApplicantID = ap.ApplicantID
JOIN Review    r ON r.ApplicationID = ap.ApplicationID
LEFT JOIN AdmissionDecision ad ON ad.ApplicationID = ap.ApplicationID
WHERE ap.AdmissionYear = 2026
GROUP BY ap.ApplicationID, ApplicantName, ap.ProgramID, ad.DecisionType
HAVING COUNT(r.ProfessorID) >= 2
ORDER BY AverageReviewScore DESC;

-- Q6 (join + filter): Phase I objective 6
-- Accepted applicants per program in the Fall 2026 term.
SELECT p.ProgramName,
       COUNT(*) AS AcceptedApplicants
FROM AdmissionDecision ad
JOIN Application ap ON ap.ApplicationID = ad.ApplicationID
JOIN Program     p  ON p.ProgramID      = ap.ProgramID
WHERE ad.DecisionType = 'Accepted'
  AND ap.AdmissionYear = 2026 AND ap.AdmissionTerm = 'Fall'
GROUP BY p.ProgramName
ORDER BY AcceptedApplicants DESC, p.ProgramName;

-- Q7 (aggregate functions): Phase I objective 6
-- Average, minimum and maximum financial aid offered per program.
SELECT p.ProgramName,
       COUNT(f.AwardID)             AS NumAwards,
       ROUND(AVG(f.AidPercentage), 1) AS AvgAidPct,
       MIN(f.AidPercentage)         AS MinAidPct,
       MAX(f.AidPercentage)         AS MaxAidPct
FROM FinancialAidAward f
JOIN Application ap ON ap.ApplicationID = f.ApplicationID
JOIN Program     p  ON p.ProgramID      = ap.ProgramID
GROUP BY p.ProgramName
ORDER BY AvgAidPct DESC;

-- Q8 (subquery, weak entity): Phase I objective 6
-- Undergraduate applications in the current (2027) cycle still missing a Grade 12 transcript (BR14).
SELECT ap.ApplicationID,
       a.FirstName || ' ' || a.LastName AS ApplicantName,
       a.Email,
       ap.ProgramID,
       ap.ApplicationStatus
FROM Application ap
JOIN Applicant a ON a.ApplicantID = ap.ApplicantID
JOIN Program   p ON p.ProgramID   = ap.ProgramID
WHERE ap.AdmissionYear = 2027
  AND p.DegreeLevel = 'Undergraduate'
  AND NOT EXISTS (SELECT 1 FROM ApplicationDocument doc
                  WHERE doc.ApplicationID = ap.ApplicationID
                    AND doc.DocumentType  = 'Grade 12 Transcript')
ORDER BY ap.ApplicationID;

-- Q9 (M:N relationship, LEFT JOIN + GROUP BY): Phase I objective 6
-- Review workload of each professor in the 2026 and 2027 cycles (including professors with no reviews).
SELECT pr.ProfessorID,
       pr.FirstName || ' ' || pr.LastName AS ProfessorName,
       pr.DepartmentID,
       COUNT(r.ApplicationID)             AS ReviewsDone,
       ROUND(AVG(r.ReviewScore), 1)       AS AvgScoreGiven
FROM Professor pr
LEFT JOIN Review r ON r.ProfessorID = pr.ProfessorID
GROUP BY pr.ProfessorID, ProfessorName, pr.DepartmentID
ORDER BY ReviewsDone DESC, pr.ProfessorID;

-- Q10 (multivalued attribute, GROUP BY + HAVING)
-- Applicants who declared more than one nationality.
SELECT a.ApplicantID,
       a.FirstName || ' ' || a.LastName      AS ApplicantName,
       COUNT(n.CountryCode)                  AS NumNationalities,
       GROUP_CONCAT(n.CountryCode, ', ')     AS Nationalities
FROM Applicant a
JOIN ApplicantNationality n ON n.ApplicantID = a.ApplicantID
GROUP BY a.ApplicantID, ApplicantName
HAVING COUNT(n.CountryCode) > 1
ORDER BY a.ApplicantID;

-- Q11 (derived attribute: Age, uses view vApplicant)
-- Average age of applicants per degree level in the 2027 cycle.
SELECT p.DegreeLevel,
       COUNT(DISTINCT v.ApplicantID) AS NumApplicants,
       ROUND(AVG(v.Age), 1)          AS AvgAge,
       MIN(v.Age)                    AS Youngest,
       MAX(v.Age)                    AS Oldest
FROM vApplicant v
JOIN Application ap ON ap.ApplicantID = v.ApplicantID
JOIN Program     p  ON p.ProgramID    = ap.ProgramID
WHERE ap.AdmissionYear = 2027
GROUP BY p.DegreeLevel;

-- Q12 (GROUP BY on two columns)
-- Decision outcome by admission round in 2026: does applying early change the outcome?
SELECT ap.AdmissionRound, ad.DecisionType, COUNT(*) AS NumApplications
FROM Application ap
JOIN AdmissionDecision ad ON ad.ApplicationID = ap.ApplicationID
WHERE ap.AdmissionYear = 2026
GROUP BY ap.AdmissionRound, ad.DecisionType
ORDER BY ap.AdmissionRound, ad.DecisionType;

-- Q13 (M:N Program Requires Requirement)
-- Mandatory admission requirements for each active program.
SELECT p.ProgramID, p.DegreeLevel,
       GROUP_CONCAT(r.RequirementName, '; ') AS MandatoryRequirements
FROM Program p
JOIN ProgramRequirement pr ON pr.ProgramID = p.ProgramID
JOIN Requirement        r  ON r.RequirementID = pr.RequirementID
WHERE pr.IsMandatory = 'Y' AND p.ProgramStatus = 'Active'
GROUP BY p.ProgramID, p.DegreeLevel
ORDER BY p.DegreeLevel DESC, p.ProgramID;

-- Q14 (derived attribute: DaysSinceSubmission, uses view vApplicationSummary)
-- Current-cycle applications that are still open, with how long they have been waiting.
SELECT ApplicationID, ProgramID, ApplicationStatus, SubmissionDate,
       DaysSinceSubmission, ReviewCount
FROM vApplicationSummary
WHERE AdmissionYear = 2027 AND ApplicationStatus <> 'Decided'
ORDER BY DaysSinceSubmission DESC;
