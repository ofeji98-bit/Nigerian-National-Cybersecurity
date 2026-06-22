-- ============================================================
-- NIGERIA CYBERSECURITY INCIDENT ANALYSIS (2019–2024)
-- SQL Capstone Project
-- Analyst: Fejiro | TDI Emerald Cohort
-- ============================================================

-- create database National_Cybersecurity
-- use National_Cybersecurity


-- ============================================================
-- SECTION 1: FOREIGN KEY CONSTRAINTS
-- ============================================================

SELECT TOP 2 *
FROM incidents;

ALTER TABLE incidents
ADD CONSTRAINT fk_incidents_org
FOREIGN KEY (org_id) REFERENCES organizations(org_id);

ALTER TABLE incidents
ADD CONSTRAINT fk_incidents_team
FOREIGN KEY (team_id) REFERENCES response_teams(team_id);

ALTER TABLE incidents
ADD CONSTRAINT fk_incidents_attack
FOREIGN KEY (attack_type_id) REFERENCES attack_types(attack_type_id);


-- ============================================================
-- SECTION 2: DUPLICATE CHECK
-- ============================================================

-- INCIDENTS TABLE
WITH occurrences AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY incident_id ORDER BY incident_id) AS rn
    FROM incidents
)
SELECT *
FROM occurrences
WHERE rn > 1;

-- ATTACK_TYPES TABLE
WITH occurrences AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY attack_type_id ORDER BY attack_type_id) AS rn
    FROM attack_types
)
SELECT *
FROM occurrences
WHERE rn > 1;

-- ORGANIZATIONS TABLE
WITH occurrences AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY org_id ORDER BY org_id) AS rn
    FROM organizations
)
SELECT *
FROM occurrences
WHERE rn > 1;

-- RESPONSE_TEAMS TABLE
WITH occurrences AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY team_id) AS rn
    FROM response_teams
)
SELECT *
FROM occurrences
WHERE rn > 1;

-- Since the incidents table has duplicate rows, delete the duplicates
WITH occurrence AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY incident_id ORDER BY incident_id) AS rn
    FROM incidents
)
DELETE FROM occurrence
WHERE rn > 1;


-- ============================================================
-- SECTION 3: EXPLORATORY CHECKS
-- ============================================================

SELECT *
FROM organizations;

SELECT DISTINCT city
FROM organizations;


-- ============================================================
-- SECTION 4: DATA STANDARDIZATION
-- ============================================================

-- FOR ORGANIZATIONS: Standardize sector values
UPDATE organizations
SET sector =
    CASE
        WHEN LOWER(sector) LIKE '%banking%'    THEN 'Banking'
        WHEN LOWER(sector) LIKE '%education%'  THEN 'Education'
        WHEN LOWER(sector) LIKE '%fintech%'    THEN 'Fintech'
        WHEN LOWER(sector) LIKE '%government%' THEN 'Government'
        WHEN LOWER(sector) LIKE '%healthcare%' THEN 'Healthcare'
        WHEN LOWER(sector) LIKE '%oil%gas%'    THEN 'Oil & Gas'
        WHEN LOWER(sector) LIKE '%telecom%'    THEN 'Telecom'
        ELSE sector
    END;

-- FOR ORGANIZATIONS: Trim whitespace from city
UPDATE organizations
SET city = TRIM(city);

-- FOR ORGANIZATIONS: Proper-case city names
UPDATE organizations
SET city = UPPER(LEFT(city, 1)) + LOWER(SUBSTRING(city, 2, LEN(city)));

-- FOR ORGANIZATIONS: Fix Ile-Ife variants
UPDATE organizations
SET city =
    CASE
        WHEN LOWER(city) LIKE '%ile%' THEN 'Ile-Ife'
        ELSE city
    END;

-- FOR INCIDENTS: Proper-case status
UPDATE incidents
SET status = UPPER(LEFT(status, 1)) + LOWER(SUBSTRING(status, 2, LEN(status)));

-- FOR INCIDENTS: Fix 'Under Investigation' variants
UPDATE incidents
SET status =
    CASE
        WHEN LOWER(status) LIKE '%under%investigation%' THEN 'Under Investigation'
        ELSE status
    END;

-- FOR INCIDENTS: Proper-case severity
UPDATE incidents
SET severity = UPPER(LEFT(severity, 1)) + LOWER(SUBSTRING(severity, 2, LEN(severity)));


-- ============================================================
-- SECTION 5: RESEARCH QUESTIONS
-- ============================================================

-- ------------------------------------------------------------
-- RQ1: What is the percentage of financial loss per incident status?
-- ------------------------------------------------------------
WITH loss_per_status AS (
    SELECT status,
           SUM(financial_loss_ngn) AS total_loss
    FROM incidents
    GROUP BY status
),
full_loss AS (
    SELECT SUM(total_loss) AS tl
    FROM loss_per_status
)
SELECT status,
       ROUND(total_loss / (SELECT tl FROM full_loss) * 100, 2) AS pct_loss
FROM loss_per_status;


-- ------------------------------------------------------------
-- RQ2: What are the top 3 teams with the highest number of resolved incidents?
-- ------------------------------------------------------------
SELECT TOP 3
    r.team_name,
    COUNT(i.incident_id) AS incident_count
FROM response_teams r
JOIN incidents i ON r.team_id = i.team_id
WHERE i.status = 'Resolved'
GROUP BY r.team_name
ORDER BY incident_count DESC;


-- ------------------------------------------------------------
-- RQ3: Which organization has the highest number of affected users?
-- ------------------------------------------------------------
SELECT TOP 1
    org_name,
    SUM(affected_users) AS affected_users
FROM organizations o
JOIN incidents i ON i.org_id = o.org_id
GROUP BY org_name
ORDER BY affected_users DESC;


-- ------------------------------------------------------------
-- RQ4: Which sectors have a total financial loss above the national
--      sector average, and by how much do they exceed it, ranked
--      from most to least exposed?
-- ------------------------------------------------------------
WITH highest_affected_sectors AS (
    SELECT sector,
           SUM(financial_loss_ngn) AS financial_loss
    FROM incidents i
    JOIN organizations o ON i.org_id = o.org_id
    GROUP BY sector
),
national_average AS (
    SELECT AVG(financial_loss) AS avg_loss
    FROM highest_affected_sectors
)
SELECT sector,
       ROUND(financial_loss, 2) AS fin_loss,
       (SELECT avg_loss FROM national_average) AS national_average,
       ROUND(financial_loss - (SELECT avg_loss FROM national_average), 2) AS difference,
       CASE
           WHEN financial_loss > (SELECT avg_loss FROM national_average) THEN 'Above Average'
           ELSE 'Below Average'
       END AS status
FROM highest_affected_sectors
GROUP BY financial_loss, sector
ORDER BY fin_loss DESC;


-- ------------------------------------------------------------
-- RQ5: For each attack type, what is the year-over-year change in
--      total financial loss between 2019 and 2024, and which attack
--      types are growing the fastest?
-- ------------------------------------------------------------
SELECT attack_name,
       year,
       total_loss,
       previous_year,
       ROUND((loss_2024 - loss_2019) / NULLIF(loss_2019, 0) * 100, 2) AS pct_growth_2019_2024
FROM (
    SELECT attack_name,
           year,
           total_loss,
           FIRST_VALUE(total_loss) OVER (
               PARTITION BY attack_name
               ORDER BY year
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS loss_2019,
           LAST_VALUE(total_loss) OVER (
               PARTITION BY attack_name
               ORDER BY year
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS loss_2024,
           LAG(total_loss) OVER (
               PARTITION BY attack_name
               ORDER BY year ASC
           ) AS previous_year
    FROM (
        SELECT attack_name,
               YEAR(incident_date) AS year,
               ROUND(SUM(financial_loss_ngn), 2) AS total_loss
        FROM incidents i
        JOIN attack_types a ON i.attack_type_id = a.attack_type_id
        GROUP BY attack_name, YEAR(incident_date)
    ) AS attack_year
) AS pct
ORDER BY attack_name, year ASC;


-- ------------------------------------------------------------
-- RQ6: Which months consistently produce the highest cybersecurity
--      incidents across all 6 years, and is there a seasonal
--      pattern that Nigerian organizations should prepare for?
-- ------------------------------------------------------------
WITH consistent AS (
    SELECT DATENAME(MONTH, incident_date) AS month,
           YEAR(incident_date) AS year,
           COUNT(incident_id) AS incident_count,
           RANK() OVER (
               PARTITION BY YEAR(incident_date)
               ORDER BY COUNT(incident_id) DESC
           ) AS rn
    FROM incidents
    GROUP BY DATENAME(MONTH, incident_date),
             YEAR(incident_date)
)
SELECT *
FROM consistent
WHERE rn = 1;


-- ------------------------------------------------------------
-- RQ7: Which organizations have been attacked in every single year
--      from 2019 to 2024, identifying Nigeria's most persistently
--      targeted institutions?
-- ------------------------------------------------------------
WITH attacked_org AS (
    SELECT org_name,
           YEAR(incident_date) AS year,
           COUNT(incident_id) AS incident_count
    FROM organizations o
    JOIN incidents i ON o.org_id = i.org_id
    GROUP BY org_name, YEAR(incident_date)
)
SELECT org_name,
       SUM(incident_count) AS total_incidents
FROM attacked_org
GROUP BY org_name
HAVING COUNT(year) = 6
ORDER BY total_incidents DESC;


-- ------------------------------------------------------------
-- RQ8: What is the total financial exposure from currently unresolved
--      and under-investigation incidents per sector, and what
--      percentage of each sector's total loss remains unrecovered?
-- ------------------------------------------------------------
WITH total_status_loss AS (
    SELECT sector,
           status,
           SUM(financial_loss_ngn) AS total_loss
    FROM organizations o
    JOIN incidents i ON o.org_id = i.org_id
    GROUP BY sector, status
),
total_loss AS (
    SELECT sector,
           SUM(total_loss) AS loss
    FROM total_status_loss
    GROUP BY sector
),
unrecovered_loss AS (
    SELECT sector,
           SUM(total_loss) AS loss
    FROM total_status_loss
    WHERE status IN ('Unresolved', 'Under Investigation')
    GROUP BY sector
)
SELECT tl.sector,
       ul.loss AS unrecovered_loss,
       tl.loss AS total_loss,
       ROUND((ul.loss / tl.loss * 100), 2) AS unrecovered_pct,
       RANK() OVER (ORDER BY ul.loss DESC) AS f_e_rank
FROM unrecovered_loss ul
JOIN total_loss tl ON ul.sector = tl.sector
ORDER BY f_e_rank ASC;


-- ------------------------------------------------------------
-- RQ9: Which cities have response teams but handle a disproportionately
--      high number of incidents relative to their team count,
--      identifying where Nigeria needs to deploy more cybersecurity
--      resources?
-- ------------------------------------------------------------
WITH teams AS (
    SELECT rt.team_name as team_name,
           rt.base_city AS city,
           COUNT(incident_id) AS no_of_incidents
    FROM response_teams rt
    LEFT JOIN incidents i ON rt.team_id = i.team_id
    GROUP BY rt.team_name, rt.base_city
),

national_average as (
    SELECT  AVG(no_of_incidents) as avg
        FROM teams),

team_count AS (
    SELECT city,
           COUNT(team_name) AS team_count,
           SUM(no_of_incidents) AS incidents
    FROM teams
    GROUP BY city
),
proportion AS (
    SELECT city,
           team_count,
           ROUND((incidents / team_count), 2) AS proportion
    FROM team_count
)
SELECT *
FROM proportion
WHERE proportion > (SELECT avg FROM national_average)
ORDER BY proportion DESC;


-- ============================================================
-- SECTION 6: FLAT VIEW FOR EXCEL / POWER QUERY
-- ============================================================

CREATE VIEW full_spreadsheet AS
SELECT
    org_name,
    o.org_id,
    o.sector,
    attack_name,
    i.attack_type_id,
    i.status,
    a.description,
    i.affected_users,
    r.base_city,
    r.team_id,
    r.team_name,
    incident_id,
    default_severity,
    severity,
    financial_loss_ngn,
    YEAR(incident_date) AS year,
    MONTH(incident_date) AS month,
    DATENAME(WEEKDAY, incident_date) AS day,
    resolution_time_hours
FROM attack_types a
JOIN incidents i ON a.attack_type_id = i.attack_type_id
JOIN organizations o ON i.org_id = o.org_id
JOIN response_teams r ON r.team_id = i.team_id;


-- ============================================================
-- SECTION 7: KEY PERFORMANCE INDICATORS
-- ============================================================

-- Total Incidents | Total Loss | Sectors Affected | Organizations | Teams | Avg Loss per Incident
SELECT
    COUNT(incident_id) AS total_incidents,
    ROUND(SUM(financial_loss_ngn), 2) AS total_loss,
    COUNT(DISTINCT sector) AS sectors_affected,
    COUNT(DISTINCT team_name) AS team_count,
    COUNT(DISTINCT o.org_name) AS no_of_organizations,
    ROUND(AVG(financial_loss_ngn), 2) AS avg_loss_per_incident
FROM incidents i
JOIN organizations o ON i.org_id = o.org_id
JOIN response_teams r ON r.team_id = i.team_id;


-- Resolution Rate | Total Open Incident Rate
WITH status_loss AS (
    SELECT status,
           SUM(financial_loss_ngn) AS total
    FROM incidents
    GROUP BY status
),
unresolved_count AS (
    SELECT SUM(total) AS unresolved_total
    FROM status_loss
    WHERE status IN ('Unresolved', 'Under Investigation')
),
total_loss AS (
    SELECT SUM(total) AS total_loss
    FROM status_loss
)
SELECT
    ROUND((SELECT total FROM status_loss WHERE status = 'Resolved') / total_loss * 100.00, 2) AS Resolution_Rate,
    ROUND((SELECT unresolved_total FROM unresolved_count) / total_loss * 100.00, 2) AS Total_Open_Incident_Rate
FROM total_loss;

