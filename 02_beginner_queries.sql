/* ============================================================
   File: 02_beginner_queries.sql
   Purpose: 8 queries, from basic to intermediate (SQL Server)
   Run each query one at a time (highlight it, then press F5).
   ============================================================ */
USE shop_simple;
GO

-- 1. View raw data in each table
SELECT * FROM customers;
SELECT * FROM products;
SELECT * FROM orders;

-- 2. Filter rows: customers in Hyderabad
SELECT customer_id, name, city
FROM customers
WHERE city = N'Hyderabad';

-- 3. Sort results: products from most to least expensive
SELECT product_name, category, price
FROM products
ORDER BY price DESC;

-- 4. Count rows: orders and distinct buyers
SELECT COUNT(*)                    AS total_orders,
       COUNT(DISTINCT customer_id) AS customers_who_ordered
FROM orders;

-- 5. JOIN: line-item total for each order
SELECT o.order_id, c.name, p.product_name,
       o.quantity, p.price,
       o.quantity * p.price AS line_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN products  p ON o.product_id  = p.product_id
ORDER BY o.order_id;

-- 6. JOIN + GROUP BY + SUM: total spent per customer (top 10)
SELECT TOP 10 c.name, c.city,
       COUNT(o.order_id)           AS orders_placed,
       SUM(o.quantity * p.price)   AS total_spent
FROM customers c
JOIN orders   o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id  = p.product_id
GROUP BY c.name, c.city
ORDER BY total_spent DESC;

-- 7. Best-selling products by units sold (top 5)
SELECT TOP 5 p.product_name, p.category,
       SUM(o.quantity) AS units_sold
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.product_name, p.category
ORDER BY units_sold DESC;

-- 8. Revenue by product category
SELECT p.category,
       SUM(o.quantity * p.price) AS revenue,
       CAST(100.0 * SUM(o.quantity * p.price)
            / SUM(SUM(o.quantity * p.price)) OVER () AS DECIMAL(5,2)) AS pct_of_total
FROM orders o
JOIN products p ON o.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;
