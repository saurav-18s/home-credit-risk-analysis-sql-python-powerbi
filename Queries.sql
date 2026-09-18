-- Q1. What is the overall financial exposure and baseline default risk of the current loan portfolio?
SELECT
	COUNT(SK_ID_CURR) as total_applicants,
	ROUND(AVG(TARGET) * 100, 2) AS default_rate_percentage,
	ROUND(SUM(AMT_CREDIT) / 1000000000, 2) AS total_credit_disbursed_billions,
	ROUND(SUM(CASE WHEN TARGET = 1 THEN AMT_CREDIT ELSE 0 END) / 1000000000, 2) AS total_amount_at_risk_billion
FROM application_train;



-- Q2. How does physical asset ownership (Car vs. Real Estate) impact a borrower's likelihood to default?
SELECT
	CASE
		WHEN FLAG_OWN_CAR = 'Y' AND FLAG_OWN_REALTY = 'Y' THEN 'Owns Both Car + Realty'
		WHEN FLAG_OWN_CAR = 'N' AND FLAG_OWN_REALTY = 'Y' THEN 'Only Realty'
		WHEN FLAG_OWN_CAR = 'Y' AND FLAG_OWN_REALTY = 'N' THEN 'Only Car'
		ELSE 'Owns Neither'
	END AS assets_status,
	COUNT(SK_ID_CURR) AS total_applicants,
	SUM(TARGET) AS total_default,
	ROUND(AVG(TARGET) * 100, 2) AS default_rate_pct
FROM application_train
GROUP BY assets_status
ORDER BY default_rate_pct DESC;


-- Q3. Is there a correlation between the number of dependents a client supports and their credit default risk?
SELECT 
	CASE 
		WHEN CNT_CHILDREN = 0 THEN '0 Children'
		WHEN CNT_CHILDREN = 1 THEN '1 Children'
		WHEN CNT_CHILDREN = 2 THEN '2 Children'
		ELSE '3+ Children'
	END AS num_children,
	COUNT(SK_ID_CURR) AS total_applicants,
	SUM(TARGET) AS total_defaulters,
	ROUND(AVG(TARGET) * 100, 20) AS default_rate_pct
FROM application_train
GROUP BY num_children
ORDER BY num_children; 


-- Q4. What are the primary drivers for historical loan rejections within the bank's underwriting process?
SELECT
	CODE_REJECT_REASON,
	(SELECT COUNT(*) FROM prev_application) AS total_applicants,
	COUNT(SK_ID_CURR) AS total_rejections,
	ROUND(COUNT(SK_ID_CURR) * 100.0 / (SELECT COUNT(*) FROM prev_application WHERE NAME_CONTRACT_STATUS = 'Refused'), 2) AS pct_total_rejection
FROM prev_application
WHERE NAME_CONTRACT_STATUS = 'Refused'
GROUP BY CODE_REJECT_REASON
ORDER BY total_rejections DESC;


-- Q5. Does taking a loan significantly larger than one's annual income increase the likelihood of default?
SELECT
	CASE WHEN TARGET = 1 THEN 'Default (1)' ELSE 'Non-Default (0)' END AS loan_status,
	COUNT(SK_ID_CURR) AS total_applicants,
	ROUND(AVG(AMT_CREDIT * 1.0 / AMT_INCOME_TOTAL), 2) AS avg_credit_to_income_ratio
FROM application_train
GROUP BY TARGET;



-- Q6. Does the bank face higher risk from acquiring new clients or from lending to existing, proven clients?
WITH past AS(
	SELECT
		SK_ID_CURR,
		NAME_CLIENT_TYPE,
		ROW_NUMBER() OVER(PARTITION BY SK_ID_CURR ORDER BY MONTHS_SINCE_DECISION DESC) AS r_n       -- Having duplicate rows (SK_ID_CURR) One to Many relation
	FROM prev_application
)
SELECT 
	c.NAME_CLIENT_TYPE,
	COUNT(a.SK_ID_CURR) AS total_applicants,
	SUM(a.TARGET) AS total_defaulters,
	ROUND(AVG(a.TARGET) * 100, 2) AS default_rate_pct
FROM application_train a
JOIN past c 
	ON a.SK_ID_CURR = c.SK_ID_CURR
WHERE c.r_n  = 1                                                                                 -- select only one row if duplicate exist
	AND c.NAME_CLIENT_TYPE != 'Unknown'
GROUP BY c.NAME_CLIENT_TYPE
ORDER BY default_rate_pct DESC;



-- Q7. Which education demographic is responsible for the largest absolute dollar loss in the bank's loan portfolio?
SELECT 
	NAME_EDUCATION_TYPE,
	COUNT(SK_ID_CURR) AS total_applicants,
	SUM(TARGET) AS total_defaulters,
	ROUND(SUM(CASE WHEN TARGET = 1 THEN AMT_CREDIT ELSE 0 END) / 1000000000, 2) AS total_money_lost_billions
FROM application_train
GROUP BY NAME_EDUCATION_TYPE
ORDER BY total_money_lost_billions DESC;



-- Q9. Do occupations with the highest EMI burden strictly correlate with the highest default rates?
SELECT
	OCCUPATION_TYPE,
	COUNT(SK_ID_CURR) AS total_applicants,
	ROUND(AVG((AMT_ANNUITY * 100.0) / AMT_INCOME_TOTAL), 2) AS avg_EMI_burden_pct,
	ROUND(AVG(TARGET) * 100, 2) AS default_rate_pct
FROM application_train
GROUP BY OCCUPATION_TYPE
ORDER BY avg_EMI_burden_pct DESC;



-- Q10. Does the stated intent of a previously requested cash loan (e.g., "Urgent needs" vs. "Housing") serve as a reliable predictor for an applicant's current default risk?
WITH past_purpose AS (
	SELECT 
		SK_ID_CURR,
		NAME_CASH_LOAN_PURPOSE,
		ROW_NUMBER() OVER(PARTITION BY SK_ID_CURR ORDER BY MONTHS_SINCE_DECISION DESC) AS r_n
	FROM prev_application
	WHERE
		NAME_CASH_LOAN_PURPOSE NOT IN ('XAP', 'XNA')
)
SELECT
	p.NAME_CASH_LOAN_PURPOSE,
	COUNT(a.SK_ID_CURR) AS total_application,
	ROUND(AVG(a.TARGET) * 100, 2) AS default_rate_pct
FROM application_train a
JOIN past_purpose p 
	ON a.SK_ID_CURR = p.SK_ID_CURR
WHERE p.r_n = 1
GROUP BY p.NAME_CASH_LOAN_PURPOSE
HAVING total_application > 500
ORDER BY default_rate_pct DESC;


-- Q11. How does the recency of a prior loan rejection—specifically whether it occurred within the last 12 months—influence an applicant's current likelihood to default?
WITH reject_timeline AS(
	SELECT 
		SK_ID_CURR,
		CASE
			WHEN MONTHS_SINCE_DECISION <= 12 THEN 'Recent Rejection (<= 1 year)'
			ELSE 'Old Rejection (> 1 year)'
		END AS rejection_timeline,
		ROW_NUMBER() OVER(PARTITION BY SK_ID_CURR ORDER BY MONTHS_SINCE_DECISION ASC) AS r_n
	FROM 
		prev_application
	WHERE 
		NAME_CONTRACT_STATUS = 'Refused'
)
SELECT 
	r.rejection_timeline,
	COUNT(a.SK_ID_CURR) AS total_applicants,
	ROUND(AVG(a.TARGET) * 100, 2) AS default_rate_pct
FROM application_train a
JOIN reject_timeline r
	ON a.SK_ID_CURR = r.SK_ID_CURR
WHERE r.r_n = 1
GROUP BY r.rejection_timeline
ORDER BY default_rate_pct DESC;


-- Q12. Which occupational demographics drive the highest aggregate capital loss for the portfolio, and how does that macro exposure contrast with the average per-defaulter severity?
SELECT 
	OCCUPATION_TYPE,
	COUNT(SK_ID_CURR) AS total_applicants,
	SUM(TARGET) AS total_defaulters,
	ROUND(SUM(CASE WHEN TARGET = 1 THEN AMT_CREDIT ELSE 0 END) / 1000000000, 2) AS total_money_lost_billions,
	ROUND(SUM(CASE WHEN TARGET = 1 THEN AMT_CREDIT ELSE 0 END) / NULLIF(SUM(TARGET), 0), 2) AS avg_money_lost_per_defaulter
FROM application_train
WHERE OCCUPATION_TYPE != 'Unknown'
GROUP BY OCCUPATION_TYPE
ORDER BY total_money_lost_billions DESC;



-- Q13. How does a history of previous loan refusals impact a borrower's current likelihood to default?
WITH prev_refusal_flag AS (
	SELECT 
		SK_ID_CURR,
		MAX(CASE WHEN NAME_CONTRACT_STATUS = 'Refused' THEN 1 ELSE 0 END) AS has_refused
	FROM prev_application
	GROUP BY SK_ID_CURR
)
SELECT
	CASE WHEN p.has_refused = 1 THEN 'Past Loan Refused' ELSE 'No Past Refused' END AS refusal_status,
	COUNT(a.SK_ID_CURR) as total_applicants,
	SUM(a.TARGET) AS total_defaulters,
	ROUND((CAST(SUM(a.TARGET) AS FLOAT) / COUNT(a.SK_ID_CURR)) * 100, 2) AS default_rate_pct
FROM application_train a
LEFT JOIN prev_refusal_flag p 
	ON a.SK_ID_CURR = p.SK_ID_CURR
GROUP BY refusal_status;