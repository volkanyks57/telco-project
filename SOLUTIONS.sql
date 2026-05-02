--1.1 List the customers who are subscribed to the 'Kobiye Destek' tariff.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    c.SIGNUP_DATE,
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
WHERE
    t.NAME = 'Kobiye Destek'
ORDER BY
    c.NAME;
/*
  APPROACH:
  We join the CUSTOMERS table with the TARIFFS table on TARIFF_ID,
  which allows us to filter directly by tariff name in the WHERE clause
  and ensures the query remains intact even if TARIFF_ID values change in the future.
  Note that the column is named NAME, not TARIFF_NAME,
  as it is defined that way in the TARIFFS table.
  Results are returned sorted alongside the customer name and city,
  so the output can be used directly by a customer service team.
*/

--1.2 Find the newest customer who subscribed to this tariff.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    c.SIGNUP_DATE,
    t.MONTHLY_FEE
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
WHERE
    t.NAME = 'Kobiye Destek'
    AND c.SIGNUP_DATE = (
        SELECT MAX(c2.SIGNUP_DATE)
        FROM   CUSTOMERS c2
               JOIN TARIFFS t2 ON c2.TARIFF_ID = t2.TARIFF_ID
        WHERE  t2.NAME = 'Kobiye Destek'
    );
/*
  APPROACH:
  We want to find the customer with the latest SIGNUP_DATE
  among those subscribed to the 'Kobiye Destek' tariff.
  A scalar subquery calculates the maximum SIGNUP_DATE for this tariff,
  and the outer query returns all rows matching that date,
  so if multiple customers signed up on the same day, none of them are missed.
  A scalar subquery was preferred over NOT EXISTS because we are looking
  for a single matching value, making it more readable and performant.
*/

--2.1 Find the distribution of tariffs among the customers.
SELECT
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE,
    COUNT(c.CUSTOMER_ID) AS SUBSCRIBER_COUNT,
    ROUND(
        COUNT(c.CUSTOMER_ID) * 100.0
        / NULLIF(SUM(COUNT(c.CUSTOMER_ID)) OVER (), 0)
    , 2) AS RATIO_PCT
FROM
    TARIFFS   t
    LEFT JOIN CUSTOMERS c ON t.TARIFF_ID = c.TARIFF_ID
GROUP BY
    t.NAME, t.MONTHLY_FEE
ORDER BY
    SUBSCRIBER_COUNT DESC;
/*
  APPROACH:
  We use the TARIFFS table as the driving table (left side of LEFT JOIN),
  so that tariffs with no subscribers still appear in the results
  and the entire product portfolio can be evaluated in a single query.
  We use an analytic function (SUM ... OVER()) inside COUNT to calculate
  the total number of subscribers without needing a separate subquery.
  The RATIO_PCT column is added to simplify proportional comparisons,
  making it possible to evaluate small and large tariffs on the same scale.
*/

--3.1 Identify the earliest customers to sign up.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    c.SIGNUP_DATE,
    t.NAME AS TARIFF_NAME
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
WHERE
    c.SIGNUP_DATE = (SELECT MIN(SIGNUP_DATE) FROM CUSTOMERS)
ORDER BY
    c.CUSTOMER_ID;
/*
  APPROACH:
  As stated in the task hint, the earliest signup date does not necessarily
  correspond to the lowest CUSTOMER_ID, so sorting must be done by SIGNUP_DATE
  rather than CUSTOMER_ID.
  The subquery finds the minimum SIGNUP_DATE across all customers,
  and the outer query returns all rows that match that date.
  This ensures that if multiple "first customers" signed up on the same day,
  none of them are missed.
*/

--3.2 Find the distribution of these earliest customers across different cities, including the total count for each city.
SELECT
    c.CITY,
    COUNT(*) AS CUSTOMER_COUNT,
    SUM(COUNT(*)) OVER () AS TOTAL_COUNT,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS CITY_RATIO_PCT
FROM
    CUSTOMERS c
WHERE
    c.SIGNUP_DATE = (SELECT MIN(SIGNUP_DATE) FROM CUSTOMERS)
GROUP BY
    c.CITY
ORDER BY
    CUSTOMER_COUNT DESC;
/*
  APPROACH:
  We combine the filter from 3.1 (minimum SIGNUP_DATE) with GROUP BY
  to see which cities the earliest customer cohort is concentrated in.
  The analytic SUM ... OVER() calculates the total row count in a single pass,
  so the percentage for each city is also produced within the same query.
  This table carries historical value as it reveals which cities
  the company focused on during its launch period.
*/

--4.1 Every customer has a monthly fee, and the dataset contains this month's usage values. However, an insertion error occurred, and some customers' monthly records are missing. Identify the IDs of these missing customers.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
WHERE
    NOT EXISTS (
        SELECT 1
        FROM   MONTHLY_STATS ms
        WHERE  ms.CUSTOMER_ID = c.CUSTOMER_ID
    )
ORDER BY
    c.CUSTOMER_ID;
/*
  APPROACH:
  Each customer should have exactly one record in the MONTHLY_STATS table;
  the UNIQUE constraint (UQ_STAT_CUSTOMER) guarantees this, however some
  customers may have no record at all due to a data loading error.
  We use a NOT EXISTS anti-join; compared to NOT IN, NOT IN can silently
  return an empty result when the subquery contains a NULL value,
  whereas NOT EXISTS works correctly regardless of this risk.
  Results are returned with a JOIN from the CUSTOMERS table, so it is
  also possible to see which tariff and city the missing record belongs to.
*/

--4.2 Find the distribution of these missing customers across different cities.
SELECT
    c.CITY,
    COUNT(*) AS MISSING_COUNT,
    SUM(COUNT(*)) OVER () AS TOTAL_MISSING,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS CITY_RATIO_PCT
FROM
    CUSTOMERS c
WHERE
    NOT EXISTS (
        SELECT 1
        FROM   MONTHLY_STATS ms
        WHERE  ms.CUSTOMER_ID = c.CUSTOMER_ID
    )
GROUP BY
    c.CITY
ORDER BY
    MISSING_COUNT DESC;
/*
  APPROACH:
  We wrap the NOT EXISTS filter from 4.1 with GROUP BY to calculate
  how many customers have missing records on a city basis.
  This view can be used to determine whether the missing records
  originate from a specific region or are randomly distributed;
  if there is a regional system failure, city concentration will reveal it.
  The percentage ratio provides a fair scale when comparing
  cities of different sizes.
*/

--5.1 Find the customers who have used at least 75% of their data limit.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME AS TARIFF_NAME,
    t.DATA_LIMIT,
    ms.DATA_USAGE,
    ROUND(ms.DATA_USAGE / NULLIF(t.DATA_LIMIT, 0) * 100, 2) AS DATA_USAGE_PCT
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE
    t.DATA_LIMIT > 0
    AND ms.DATA_USAGE / NULLIF(t.DATA_LIMIT, 0) >= 0.75
ORDER BY
    DATA_USAGE_PCT DESC;
/*
  APPROACH:
  We join the CUSTOMERS, TARIFFS and MONTHLY_STATS tables to compare
  each customer's data consumption (DATA_USAGE) against their tariff's
  DATA_LIMIT value.
  The NULLIF(t.DATA_LIMIT, 0) expression prevents a division by zero error
  for tariffs with a zero data limit (such as the 'Kurumsal SMS' package).
  Since the threshold is defined as a ratio (>= 0.75) rather than a fixed MB value,
  the query works consistently across all tariffs.
*/

--5.2 Identify the customers who have completely exhausted all of their package limits (data, minutes, and SMS).
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    t.NAME AS TARIFF_NAME,
    ms.DATA_USAGE, t.DATA_LIMIT,
    ms.MINUTE_USAGE, t.MINUTE_LIMIT,
    ms.SMS_USAGE, t.SMS_LIMIT
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE
    ms.DATA_USAGE >= t.DATA_LIMIT
    AND ms.MINUTE_USAGE >= t.MINUTE_LIMIT
    AND ms.SMS_USAGE >= t.SMS_LIMIT
ORDER BY
    c.CUSTOMER_ID;
/*
  APPROACH:
  The conditions are combined with AND since all three resources must be
  exhausted simultaneously, which identifies the most constrained customer profile.
  The >= operator is used to account for the possibility that usage may
  occasionally exceed the limit due to rounding or delayed throttling in the source system.
  There are no customers in the current dataset that satisfy this condition;
  the query is working correctly and an empty result is the expected outcome.
*/

--6.1 Find the customers who have unpaid fees.
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    ms.PAYMENT_STATUS,
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE
    ms.PAYMENT_STATUS IN ('LATE', 'UNPAID')
ORDER BY
    ms.PAYMENT_STATUS, t.MONTHLY_FEE DESC;
/*
  APPROACH:
  Values other than 'PAID' in the PAYMENT_STATUS column (LATE, UNPAID
  indicate a payment problem. We handle these statuses in a single condition
  using the IN operator; if new status codes are added in the future,
  only this list needs to be updated.
  Tariff and monthly fee information is also included in the results, so the
  output can be used directly as an accounts receivable report containing debt amounts.
  Results are sorted by PAYMENT_STATUS so that overdue (LATE) customers appear at the top.
*/

--6.2 Find the distribution of all payment statuses across the different tariffs.
SELECT
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE,
    COUNT(ms.ID) AS TOTAL_CUSTOMERS,
    COUNT(CASE WHEN ms.PAYMENT_STATUS = 'PAID'    THEN 1 END) AS PAID_COUNT,
    COUNT(CASE WHEN ms.PAYMENT_STATUS = 'LATE'    THEN 1 END) AS LATE_COUNT,
    COUNT(CASE WHEN ms.PAYMENT_STATUS = 'UNPAID'  THEN 1 END) AS UNPAID_COUNT,
    ROUND(
        COUNT(CASE WHEN ms.PAYMENT_STATUS != 'PAID' THEN 1 END)
        * 100.0 / NULLIF(COUNT(ms.ID), 0)
    , 2) AS DELINQUENCY_RATE_PCT
FROM
    TARIFFS t
    LEFT JOIN CUSTOMERS c ON t.TARIFF_ID = c.TARIFF_ID
    LEFT JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
GROUP BY
    t.NAME, t.MONTHLY_FEE
ORDER BY
    DELINQUENCY_RATE_PCT DESC NULLS LAST;
/*
  APPROACH:
  We use conditional aggregation (COUNT inside CASE WHEN) to display
  the number of PAID / LATE / UNPAID subscribers per tariff
  side by side in a single query, which is more portable than the PIVOT syntax.
  The DELINQUENCY_RATE_PCT column shows the ratio of customers with payment
  problems to the total number of subscribers on that tariff,
  quickly revealing which package carries the highest financial risk.
  LEFT JOIN is used to ensure that tariffs with no subscribers
  also appear in the results.
*/

--BONUS 1: Monthly Revenue at Risk by Tariff
SELECT
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE,
    COUNT(ms.ID) AS DELINQUENT_CUSTOMERS,
    COUNT(ms.ID) * t.MONTHLY_FEE AS REVENUE_AT_RISK_TRY
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE
    ms.PAYMENT_STATUS IN ('LATE', 'UNPAID')
GROUP BY
    t.NAME, t.MONTHLY_FEE
ORDER BY
    REVENUE_AT_RISK_TRY DESC;
/*
  Calculates the total monthly revenue at risk in TRY for customers
  with payment problems, broken down by tariff. Presenting a concrete
  monetary value rather than an abstract number makes it easier
  for the finance team to prioritize actions.
*/

--BONUS 2: High Churn Risk Customers (High Usage + Payment Problem)
SELECT
    c.CUSTOMER_ID,
    c.NAME,
    c.CITY,
    ms.PAYMENT_STATUS,
    t.NAME AS TARIFF_NAME,
    ROUND(ms.DATA_USAGE / NULLIF(t.DATA_LIMIT,0) * 100, 1) AS DATA_USAGE_PCT,
    t.MONTHLY_FEE
FROM
    CUSTOMERS c
    JOIN TARIFFS t ON c.TARIFF_ID = t.TARIFF_ID
    JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE
    t.DATA_LIMIT > 0
    AND ms.DATA_USAGE / NULLIF(t.DATA_LIMIT, 0) >= 0.90
    AND ms.PAYMENT_STATUS IN ('LATE', 'UNPAID')
ORDER BY
    DATA_USAGE_PCT DESC;
/*
  Identifies customers whose data usage is >= 90% AND who have a payment problem.
  This combination represents the "heavy user + debtor" profile and is
  the highest priority intervention group in terms of both revenue loss
  and network quality.
*/

--BONUS 3: Total Revenue Summary by Tariff
SELECT
    t.NAME AS TARIFF_NAME,
    t.MONTHLY_FEE,
    COUNT(c.CUSTOMER_ID) AS TOTAL_SUBSCRIBERS,
    COUNT(c.CUSTOMER_ID) * t.MONTHLY_FEE AS TOTAL_BILLED_TRY,
    COUNT(CASE WHEN ms.PAYMENT_STATUS = 'PAID'  THEN 1 END)
        * t.MONTHLY_FEE AS COLLECTED_TRY,
    (COUNT(c.CUSTOMER_ID) -
     COUNT(CASE WHEN ms.PAYMENT_STATUS = 'PAID' THEN 1 END))
        * t.MONTHLY_FEE AS OUTSTANDING_TRY
FROM
    TARIFFS t
    LEFT JOIN CUSTOMERS c ON t.TARIFF_ID = c.TARIFF_ID
    LEFT JOIN MONTHLY_STATS ms ON c.CUSTOMER_ID = ms.CUSTOMER_ID
GROUP BY
    t.NAME, t.MONTHLY_FEE
ORDER BY
    OUTSTANDING_TRY DESC NULLS LAST;
/*
  Displays the total billed revenue, collected revenue and outstanding
  (at risk) amount for each tariff side by side.
  Can be used for end-of-month financial reconciliation and CFO reporting.
*/