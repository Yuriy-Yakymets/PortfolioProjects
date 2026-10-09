/* ============================================================
   DATA CLEANING: AI Usage and Impact on Students & Professionals
   Source:   Kaggle, 300 rows, 19 columns
   Database: ai_usage (MySQL 8)
   Author:   Yuriy Yakymets

   TABLE WORKFLOW
   ai_raw           - raw CSV import, never modified
   ai_raw_staging   - first copy, kept as a reference
   ai_raw_staging2  - working table, all cleaning happens here

   Keeping an untouched copy made it possible to recover
   original NULL values in Monthly_Income (step 7.3).
   ============================================================ */


/* ------------------------------------------------------------
   STEP 1. CREATE A STAGING COPY
   ------------------------------------------------------------ */

CREATE TABLE ai_raw_staging LIKE ai_raw;

INSERT INTO ai_raw_staging
SELECT * FROM ai_raw;

-- Check: expected 300 rows
SELECT COUNT(*) FROM ai_raw_staging;


/* ------------------------------------------------------------
   STEP 2. IDENTIFY DUPLICATES

   User_ID is a natural key, so duplicates are detected by ID
   rather than by comparing all 19 columns.
   ------------------------------------------------------------ */

SELECT User_ID, COUNT(*)
FROM ai_raw_staging
GROUP BY User_ID
HAVING COUNT(*) > 1;

-- Before deleting, verify the rows are fully identical.
-- Same ID with different answers would be a data conflict,
-- not a duplicate.
SELECT *
FROM ai_raw_staging
WHERE User_ID IN (
    SELECT User_ID
    FROM ai_raw_staging
    GROUP BY User_ID
    HAVING COUNT(*) > 1
)
ORDER BY User_ID;
-- Result: rows are identical, 12 duplicates found.


/* ------------------------------------------------------------
   STEP 3. CREATE WORKING TABLE WITH row_num

   MySQL does not allow DELETE from a CTE, so the row number
   is stored as a physical column.
   All columns are varchar on purpose: raw values like "$874"
   and "23 yrs" are loaded as-is; types are assigned after cleaning.
   ------------------------------------------------------------ */

CREATE TABLE ai_raw_staging2 (
  User_ID                      varchar(255)  DEFAULT NULL,
  Age                          varchar(255)  DEFAULT NULL,
  Gender                       varchar(255)  DEFAULT NULL,
  Country                      varchar(255)  DEFAULT NULL,
  User_Type                    varchar(255)  DEFAULT NULL,
  Education_Level              varchar(255)  DEFAULT NULL,
  Profession                   varchar(255)  DEFAULT NULL,
  Monthly_Income               varchar(255)  DEFAULT NULL,
  AI_Tool                      varchar(255)  DEFAULT NULL,
  AI_Purpose                   varchar(255)  DEFAULT NULL,
  AI_Usage_Hours_Per_Day       varchar(255)  DEFAULT NULL,
  Tasks_Performed              varchar(1000) DEFAULT NULL,
  Monthly_AI_Cost              varchar(255)  DEFAULT NULL,
  Productivity_Score           varchar(255)  DEFAULT NULL,
  Accuracy_Rating              varchar(255)  DEFAULT NULL,
  Satisfaction_Score           varchar(255)  DEFAULT NULL,
  Time_Saved_Hours_Per_Week    varchar(255)  DEFAULT NULL,
  Work_or_Study_Hours_Per_Day  varchar(255)  DEFAULT NULL,
  Would_Recommend              varchar(255)  DEFAULT NULL,
  row_num                      INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO ai_raw_staging2
SELECT *,
       ROW_NUMBER() OVER(PARTITION BY User_ID ORDER BY User_ID) AS row_num
FROM ai_raw_staging;


/* ------------------------------------------------------------
   STEP 4. REMOVE DUPLICATES
   ------------------------------------------------------------ */

-- Preview rows to be deleted (12)
SELECT * FROM ai_raw_staging2 WHERE row_num > 1;

DELETE FROM ai_raw_staging2 WHERE row_num > 1;

ALTER TABLE ai_raw_staging2 DROP COLUMN row_num;

-- Check: 300 - 12 = 288
SELECT COUNT(*) FROM ai_raw_staging2;


/* ------------------------------------------------------------
   STEP 5. STANDARDIZE CATEGORIES

   Each UPDATE is preceded by SELECT DISTINCT to review actual
   values. Patterns are kept narrow: LIKE 'United%' would also
   match United Kingdom and United Arab Emirates.
   ------------------------------------------------------------ */

-- 5.1 Gender: 11 spelling variants
SELECT DISTINCT Gender FROM ai_raw_staging2 ORDER BY 1;

UPDATE ai_raw_staging2 SET Gender = 'Male'   WHERE Gender LIKE 'M%';
UPDATE ai_raw_staging2 SET Gender = 'Female' WHERE Gender LIKE 'F%';
UPDATE ai_raw_staging2 SET Gender = 'Other'  WHERE Gender LIKE 'other%';
-- Non-binary is kept as a separate category

-- 5.2 AI_Tool: 16 variants for 9 tools
SELECT DISTINCT AI_Tool FROM ai_raw_staging2 ORDER BY 1;

UPDATE ai_raw_staging2 SET AI_Tool = 'ChatGPT'           WHERE AI_Tool LIKE '%chat%gpt%';
UPDATE ai_raw_staging2 SET AI_Tool = 'Google Gemini'     WHERE AI_Tool LIKE '%gemini%';
UPDATE ai_raw_staging2 SET AI_Tool = 'Microsoft Copilot' WHERE AI_Tool LIKE '%copilot%';
-- MySQL text comparison is case-insensitive by default

-- 5.3 Education_Level: 16 variants for 6 levels
SELECT DISTINCT Education_Level FROM ai_raw_staging2 ORDER BY 1;

UPDATE ai_raw_staging2 SET Education_Level = 'Master'        WHERE Education_Level LIKE '%master%' OR Education_Level LIKE 'MA/%';
UPDATE ai_raw_staging2 SET Education_Level = 'Bachelor'      WHERE Education_Level LIKE '%bachelor%' OR Education_Level LIKE 'BA/%';
UPDATE ai_raw_staging2 SET Education_Level = 'PhD'           WHERE Education_Level LIKE 'Ph%';
UPDATE ai_raw_staging2 SET Education_Level = 'High School'   WHERE Education_Level LIKE 'H%';
UPDATE ai_raw_staging2 SET Education_Level = 'Undergraduate' WHERE Education_Level LIKE 'undergrad%';

-- 5.4 Country: inconsistent case and abbreviations
SELECT DISTINCT Country FROM ai_raw_staging2 ORDER BY 1;

UPDATE ai_raw_staging2
SET Country = 'United States'
WHERE Country LIKE 'United States%';

UPDATE ai_raw_staging2
SET Country = 'United Kingdom'
WHERE Country IN ('U.K.', 'UK', 'united kingdom');


/* ------------------------------------------------------------
   STEP 6. STRIP UNITS FROM NUMERIC COLUMNS

   Values like "23 yrs", "2 hrs", "$1,884 " keep the column as text,
   so MIN/MAX/AVG would sort alphabetically. Pattern for each column:
   SELECT preview -> UPDATE -> validation query.
   ------------------------------------------------------------ */

-- 6.1 Age: "23 yrs" -> "23"
SELECT Age, TRIM(REPLACE(Age, 'yrs', '')) AS clean
FROM ai_raw_staging2 WHERE Age LIKE '%yrs%' LIMIT 20;

UPDATE ai_raw_staging2
SET Age = TRIM(REPLACE(Age, 'yrs', ''));

-- 6.2 Monthly_Income: "$1,884 " -> "1884"
SELECT Monthly_Income,
       TRIM(REPLACE(REPLACE(Monthly_Income, '$', ''), ',', '')) AS clean
FROM ai_raw_staging2 WHERE Monthly_Income LIKE '%$%' LIMIT 20;

UPDATE ai_raw_staging2
SET Monthly_Income = TRIM(REPLACE(REPLACE(Monthly_Income, '$', ''), ',', ''));

-- 6.3 Monthly_AI_Cost: "$25" -> "25"
UPDATE ai_raw_staging2
SET Monthly_AI_Cost = TRIM(REPLACE(REPLACE(Monthly_AI_Cost, '$', ''), ',', ''));

-- 6.4 Hour columns: "2.7 hrs" -> "2.7"
UPDATE ai_raw_staging2
SET AI_Usage_Hours_Per_Day = TRIM(REPLACE(AI_Usage_Hours_Per_Day, 'hrs', ''));

UPDATE ai_raw_staging2
SET Time_Saved_Hours_Per_Week = TRIM(REPLACE(Time_Saved_Hours_Per_Week, 'hrs', ''));

UPDATE ai_raw_staging2
SET Work_or_Study_Hours_Per_Day = TRIM(REPLACE(Work_or_Study_Hours_Per_Day, 'hrs', ''));

-- Validation: no non-numeric values left
SELECT DISTINCT Monthly_Income
FROM ai_raw_staging2
WHERE Monthly_Income NOT REGEXP '^[0-9]+$'
  AND Monthly_Income IS NOT NULL;


/* ------------------------------------------------------------
   STEP 7. MISSING VALUES AND DATA TYPES
   ------------------------------------------------------------ */

-- 7.1 Empty strings -> NULL
-- '' and NULL differ: IS NULL does not match ''. Without this step
-- the type conversion below would turn '' into 0.
UPDATE ai_raw_staging2
SET Age                         = NULLIF(TRIM(Age), ''),
    Gender                      = NULLIF(TRIM(Gender), ''),
    Country                     = NULLIF(TRIM(Country), ''),
    Education_Level             = NULLIF(TRIM(Education_Level), ''),
    Profession                  = NULLIF(TRIM(Profession), ''),
    Monthly_Income              = NULLIF(TRIM(Monthly_Income), ''),
    AI_Tool                     = NULLIF(TRIM(AI_Tool), ''),
    AI_Purpose                  = NULLIF(TRIM(AI_Purpose), ''),
    Monthly_AI_Cost             = NULLIF(TRIM(Monthly_AI_Cost), ''),
    AI_Usage_Hours_Per_Day      = NULLIF(TRIM(AI_Usage_Hours_Per_Day), ''),
    Time_Saved_Hours_Per_Week   = NULLIF(TRIM(Time_Saved_Hours_Per_Week), ''),
    Work_or_Study_Hours_Per_Day = NULLIF(TRIM(Work_or_Study_Hours_Per_Day), ''),
    Productivity_Score          = NULLIF(TRIM(Productivity_Score), ''),
    Accuracy_Rating             = NULLIF(TRIM(Accuracy_Rating), ''),
    Satisfaction_Score          = NULLIF(TRIM(Satisfaction_Score), ''),
    Would_Recommend             = NULLIF(TRIM(Would_Recommend), '');

-- 7.2 Type conversion (run one statement at a time)
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Age INT;
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Monthly_Income INT;
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Monthly_AI_Cost INT;
ALTER TABLE ai_raw_staging2 MODIFY COLUMN AI_Usage_Hours_Per_Day DECIMAL(4,1);
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Time_Saved_Hours_Per_Week DECIMAL(4,1);
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Work_or_Study_Hours_Per_Day DECIMAL(4,1);
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Productivity_Score DECIMAL(4,1);
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Accuracy_Rating DECIMAL(4,1);
ALTER TABLE ai_raw_staging2 MODIFY COLUMN Satisfaction_Score DECIMAL(4,1);

SHOW COLUMNS FROM ai_raw_staging2;

-- 7.3 Restore NULLs in Monthly_Income
-- After INT conversion, "income not reported" and "income = 0"
-- became indistinguishable. Original values are restored from
-- the untouched staging table.
UPDATE ai_raw_staging2 s2
JOIN ai_raw_staging s1 ON s2.User_ID = s1.User_ID
SET s2.Monthly_Income = NULL
WHERE s1.Monthly_Income IS NULL OR TRIM(s1.Monthly_Income) = '';

-- 7.4 Missing values are not imputed
-- Age, income and scores are individual answers; filling them
-- with averages would fabricate data. Aggregates ignore NULLs.
SELECT
    SUM(Age IS NULL)                AS age_null,
    SUM(Gender IS NULL)             AS gender_null,
    SUM(Country IS NULL)            AS country_null,
    SUM(Education_Level IS NULL)    AS edu_null,
    SUM(Profession IS NULL)         AS prof_null,
    SUM(Monthly_Income IS NULL)     AS income_null,
    SUM(AI_Tool IS NULL)            AS tool_null,
    SUM(Productivity_Score IS NULL) AS prod_null
FROM ai_raw_staging2;


/* ------------------------------------------------------------
   STEP 8. ANOMALIES AND LOGICAL INCONSISTENCIES
   ------------------------------------------------------------ */

-- 8.1 Value ranges
SELECT
    MIN(Age) AS min_age, MAX(Age) AS max_age,
    MIN(AI_Usage_Hours_Per_Day) AS min_ai, MAX(AI_Usage_Hours_Per_Day) AS max_ai,
    MIN(Work_or_Study_Hours_Per_Day) AS min_work, MAX(Work_or_Study_Hours_Per_Day) AS max_work,
    MIN(Monthly_Income) AS min_inc, MAX(Monthly_Income) AS max_inc
FROM ai_raw_staging2;

-- 8.2 AI usage hours exceed total work/study hours (23 rows)
SELECT User_ID, User_Type, AI_Usage_Hours_Per_Day, Work_or_Study_Hours_Per_Day
FROM ai_raw_staging2
WHERE AI_Usage_Hours_Per_Day > Work_or_Study_Hours_Per_Day
ORDER BY AI_Usage_Hours_Per_Day DESC;

-- U0046 reports 23 hours of AI use per day: impossible value, removed.
DELETE FROM ai_raw_staging2 WHERE User_ID = 'U0046';

-- The remaining 22 rows are kept but flagged. A plausible explanation
-- is inconsistent definitions in the survey (personal AI use vs.
-- class hours). Flagged rows are excluded from time-share metrics.
ALTER TABLE ai_raw_staging2 ADD COLUMN time_inconsistent TINYINT DEFAULT 0;

UPDATE ai_raw_staging2
SET time_inconsistent = 1
WHERE AI_Usage_Hours_Per_Day > Work_or_Study_Hours_Per_Day;

-- 8.3 Implausible age
SELECT User_ID, Age, User_Type, Education_Level
FROM ai_raw_staging2
WHERE Age < 18 OR Age > 70
ORDER BY Age;

-- Age 97 for a student / professional: data entry error, removed.
DELETE FROM ai_raw_staging2 WHERE Age > 90;
-- Ages 16-17 with High School / Undergraduate are plausible, kept.

-- 8.4 Incompatible age and education
-- PhD or Master at age under 22 is implausible. It is unknown which
-- field is wrong, so only the questionable field is set to NULL
-- instead of deleting the whole row.
UPDATE ai_raw_staging2
SET Education_Level = NULL
WHERE Age < 22 AND Education_Level IN ('PhD', 'Master');


/* ------------------------------------------------------------
   SUMMARY
   ------------------------------------------------------------ */

SELECT COUNT(*) FROM ai_raw_staging2;

/*
   300 input rows
   -12  duplicates by User_ID
   -1   U0046 (23 hours of AI per day)
   -2   age 97
   = 285 rows in the clean table

   DATA LIMITATIONS
   1. The dataset appears to be synthetic: errors and missing values
      are distributed too evenly, and no survey methodology is
      documented. Suitable for practicing methods, not for
      drawing real-world conclusions.
   2. 22 rows flagged time_inconsistent = 1 should be excluded from
      any metric based on the share of time spent with AI.
   3. Missing values in Age (23), Education_Level (12),
      Profession (14) and AI_Tool (10) are intentionally left as NULL.
*/
