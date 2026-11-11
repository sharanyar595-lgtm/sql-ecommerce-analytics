/* ============================================================
   File: 03_advanced_queries.sql
   Purpose: Real-world analytics in T-SQL using CTEs and window
            functions: monthly trend, RFM segmentation, customer
            lifetime value, cohort retention, top product per category.
   Run each numbered section as one block (highlight, then F5).
   ============================================================ */
USE shop_simple;
GO

/* ---------- A. Monthly revenue and month-over-month growth ---------- */
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS month_start,
           COUNT(*)                  AS orders,
           SUM(o.quantity * p.price) AS revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1)
)
SELECT month_start, orders, revenue,
       LAG(revenue) OVER (ORDER BY month_start) AS prev_month_revenue,
       CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
            / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0) AS DECIMAL(7,2)) AS mom_growth_pct,
       SUM(revenue) OVER (ORDER BY month_start) AS running_total
FROM monthly
ORDER BY month_start;


/* ---------- B. RFM segmentation ----------
   R = Recency   (days since last order; fewer days = higher score)
   F = Frequency (number of orders)
   M = Monetary  (total spend)
   Each is scored 1-5 with NTILE(5), then mapped to a segment.     */
IF OBJECT_ID('tempdb..#rfm') IS NOT NULL DROP TABLE #rfm;

DECLARE @ref DATE = (SELECT DATEADD(DAY, 1, MAX(order_date)) FROM orders);

WITH cust AS (
    SELECT c.customer_id, c.name,
           DATEDIFF(DAY, MAX(o.order_date), @ref) AS recency_days,
           COUNT(o.order_id)                      AS frequency,
           SUM(o.quantity * p.price)              AS monetary
    FROM customers c
    JOIN orders   o ON c.customer_id = o.customer_id
    JOIN products p ON o.product_id  = p.product_id
    GROUP BY c.customer_id, c.name
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM cust
)
SELECT *,
       CASE WHEN r_score >= 4 AND f_score >= 4 THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'New / Promising'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
            ELSE 'Needs Attention'
       END AS segment
INTO #rfm
FROM scored;

-- B1. Customer-level RFM table
SELECT customer_id, name, recency_days, frequency, monetary,
       r_score, f_score, m_score, segment
FROM #rfm
ORDER BY monetary DESC;

-- B2. Segment summary: how much revenue each segment brings
SELECT segment,
       COUNT(*)      AS customers,
       SUM(monetary) AS revenue,
       CAST(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue
FROM #rfm
GROUP BY segment
ORDER BY revenue DESC;


/* ---------- C. Customer lifetime value (CLV) ---------- */
SELECT c.name, c.city,
       MIN(o.order_date)                          AS first_order,
       MAX(o.order_date)                          AS last_order,
       DATEDIFF(DAY, MIN(o.order_date), MAX(o.order_date)) AS customer_lifespan_days,
       COUNT(o.order_id)                          AS orders,
       SUM(o.quantity * p.price)                  AS lifetime_value,
       CAST(SUM(o.quantity * p.price) * 1.0
            / COUNT(o.order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM customers c
JOIN orders   o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id  = p.product_id
GROUP BY c.name, c.city
ORDER BY lifetime_value DESC;


/* ---------- D. Repeat vs one-time customers ---------- */
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM orders
    GROUP BY customer_id
)
SELECT CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
       COUNT(*) AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_customers
FROM per_customer
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END;


/* ---------- E. Cohort retention ----------
   Cohort = month of a customer's first order.
   Shows how many of each cohort ordered again 1, 2, 3... months later. */
WITH first_order AS (
    SELECT customer_id,
           DATEFROMPARTS(YEAR(MIN(order_date)), MONTH(MIN(order_date)), 1) AS cohort_month
    FROM orders
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id,
           DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS active_month
    FROM orders o
)
SELECT f.cohort_month,
       DATEDIFF(MONTH, f.cohort_month, a.active_month) AS months_since_first_order,
       COUNT(DISTINCT a.customer_id)                   AS active_customers
FROM first_order f
JOIN activity a ON f.customer_id = a.customer_id
GROUP BY f.cohort_month, DATEDIFF(MONTH, f.cohort_month, a.active_month)
ORDER BY f.cohort_month, months_since_first_order;


/* ---------- F. Top-selling product in each category ---------- */
WITH product_sales AS (
    SELECT p.category, p.product_name,
           SUM(o.quantity)           AS units_sold,
           SUM(o.quantity * p.price) AS revenue
    FROM orders o
    JOIN products p ON o.product_id = p.product_id
    GROUP BY p.category, p.product_name
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS rn
    FROM product_sales
)
SELECT category, product_name, units_sold, revenue
FROM ranked
WHERE rn = 1
ORDER BY revenue DESC;
