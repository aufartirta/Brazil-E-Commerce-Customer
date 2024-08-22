--Identify the preferred payment methods
SELECT
	payment_type,
	COUNT(*) AS amount,
	ROUND(SUM(payment_value::INTEGER), 2) AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY amount DESC; 

---Compare total order value and total payment value. Identify the differences
WITH OrderValues AS (
    SELECT
        op.order_id,
        oi.product_id,
        ROUND((oi.price::DECIMAL * COUNT(*)) + (oi.freight_value::DECIMAL * COUNT(*)), 2) AS total_order_value,
        op.payment_type,
		op.payment_installments,
        SUM(op.payment_value::DECIMAL) AS total_payment_value
    FROM order_payments op
    JOIN order_items oi ON op.order_id = oi.order_id
    WHERE payment_type IN ('credit_card','debit_card','boleto')
    GROUP BY 
        op.order_id,
        oi.product_id,
        oi.price,
        oi.freight_value,
        op.payment_type,
		op.payment_installments
)
SELECT
    order_id,
    product_id,
    total_order_value,
    total_payment_value,
	payment_type,
	payment_installments,
    total_order_value - total_payment_value AS difference
FROM OrderValues
ORDER BY difference;

--Identify percentage of 0 difference
SELECT 
    ROUND((SUM(CASE WHEN (oi.price + oi.freight_value) = op.payment_value THEN 1 ELSE 0 END) * 100.0) / COUNT(*), 2) AS zero_diff_percentage
FROM order_payments op
JOIN order_items oi ON op.order_id = oi.order_id
WHERE op.payment_type IN ('credit_card', 'debit_card', 'boleto');

--Identify average review score based on duration of delivery
SELECT 
	CASE
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '7 days' THEN 'Fast'
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '30 days' THEN 'Normal'
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '30 days' THEN 'Slow'
		ELSE 'Very Slow'
	END AS duration_category,
	ROUND(AVG(r.review_score),2) AS average_review_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY duration_category;

--Identify average delivery duration for top 10 cities with most orders
--using CTE:
WITH top_city AS (
    SELECT
        customer_city,
        COUNT(customer_id) AS total_orders
    FROM customers
    GROUP BY customer_city
    ORDER BY COUNT(customer_id) DESC
    LIMIT 10
)
SELECT
    c.customer_city,
    AVG(o.order_delivered_customer_date - o.order_purchase_timestamp) AS average_duration
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN top_city tc ON c.customer_city = tc.customer_city
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_city
ORDER BY average_duration;

---using sub query:
SELECT
    c.customer_city,
    AVG(o.order_delivered_customer_date - o.order_purchase_timestamp) AS average_duration
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
AND o.order_delivered_customer_date IS NOT NULL
AND c.customer_city IN (
    SELECT
        customer_city
    FROM customers
    GROUP BY customer_city
    ORDER BY COUNT(customer_id) DESC
    LIMIT 10
)
GROUP BY c.customer_city
ORDER BY average_duration;

/*Customer Segmentation: CLV (Customer Lifetime Value) Analysis*/

WITH customer_revenue AS ( --Calculate Total Revenue per Customer
    SELECT
        c.customer_unique_id,
        SUM(op.payment_value) AS total_revenue,
        COUNT(DISTINCT o.order_id) AS total_orders,
        MIN(o.order_purchase_timestamp) AS first_purchase,
        MAX(o.order_purchase_timestamp) AS last_purchase
    FROM
        customers c
    JOIN
        orders o ON c.customer_id = o.customer_id
    JOIN
        order_payments op ON o.order_id = op.order_id
    WHERE
        o.order_status = 'delivered'
    GROUP BY
        c.customer_unique_id
),
customer_lifetime AS ( --Calculate Customer's Lifespan in Days
    SELECT
        customer_unique_id,
        total_revenue,
        total_orders,
        first_purchase,
        last_purchase,
        EXTRACT(DAY FROM (last_purchase - first_purchase)) AS customer_lifespan_days,
        (total_revenue / total_orders) AS avg_purchase_value --Calculate Average Purchase Value
    FROM
        customer_revenue
),
clv_calculation AS (
    -- Calculate Purchase Frequency and CLV
    SELECT
        customer_unique_id,
        total_revenue,
        total_orders,
        avg_purchase_value,
        COALESCE(NULLIF(customer_lifespan_days, 0), 1) AS customer_lifespan_days,  -- Handle customers with only one purchase
        -- Calculate purchase frequency per year; handle cases where lifespan is 0
        COALESCE(total_orders / NULLIF(customer_lifespan_days / 365.0, 0), 1) AS purchase_frequency_per_year,
        (avg_purchase_value * COALESCE(total_orders / NULLIF(customer_lifespan_days / 365.0, 0), 1) * (customer_lifespan_days / 365.0)) AS clv
    FROM
        customer_lifetime
)
SELECT
    customer_unique_id,
    total_revenue,
    total_orders,
    customer_lifespan_days,
    avg_purchase_value,
    purchase_frequency_per_year,
    ROUND(clv::DECIMAL, 2) AS estimated_clv
FROM
    clv_calculation
WHERE
    total_orders > 1 
ORDER BY
    customer_lifespan_days DESC;


/*Customer Segmentation: RFM (Recency, Frequency, Monetary) Analysis*/
--Recency
SELECT
	c.customer_unique_id,
    MAX(o.order_purchase_timestamp) AS last_purchase_date,
    CURRENT_DATE - MAX(o.order_purchase_timestamp) AS recency
FROM orders o
JOIN customers c
ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled','unavailable')
GROUP BY c.customer_unique_id
ORDER BY recency;
---Frequency
SELECT
	c.customer_unique_id,
	COUNT(c.customer_id) as frequency --(number of purchase)
FROM orders o
JOIN customers c
ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled','unavailable')
GROUP BY 
	c.customer_unique_id
ORDER BY frequency DESC;
---Monetary
SELECT 
	c.customer_unique_id,
	SUM(op.payment_value) as monetary --(total payment)
FROM customers c
JOIN orders o
ON c.customer_id = o.customer_id
JOIN order_payments op
ON o.order_id = op.order_id
GROUP BY
	c.customer_unique_id
ORDER BY monetary DESC;

--RFM Analysis based on average score
WITH RFMTable AS (
    SELECT
        c.customer_unique_id,
        CURRENT_DATE - MAX(o.order_purchase_timestamp) AS recency,
        COUNT(op.payment_value) AS frequency,
        SUM(op.payment_value) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),
RFMScores AS (
    SELECT
        customer_unique_id,
        NTILE(5) OVER (ORDER BY recency DESC) AS recency_score,
        NTILE(5) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary) AS monetary_score
    FROM RFMTable
),
AverageRFM AS (
    SELECT
        customer_unique_id,
        recency_score,
        frequency_score,
        monetary_score,
        ROUND((recency_score + frequency_score + monetary_score) / 3.0, 2) AS avg_rfm_score,
		NTILE(4) OVER (ORDER BY ROUND((recency_score + frequency_score + monetary_score) / 3.0, 2) DESC) AS segment -- Segment into 4 groups
    FROM RFMScores
)
SELECT 
    customer_unique_id,
    recency_score,
    frequency_score,
    monetary_score,
    avg_rfm_score,
	CASE 
        WHEN segment = 1 THEN 'top loyalist'
        WHEN segment = 2 THEN 'frequent shopper'
        WHEN segment = 3 THEN 'regular member'
        WHEN segment = 4 THEN 'customers at risk'
	END AS segment_name
FROM AverageRFM;

--RFM Analysis based on categorization
WITH RFMTable AS (
    SELECT
        c.customer_unique_id,
        CURRENT_DATE - MAX(o.order_purchase_timestamp) AS recency,
        COUNT(op.payment_value) AS frequency,
        SUM(op.payment_value) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),
RFMScores AS (
    SELECT
        customer_unique_id,
        NTILE(5) OVER (ORDER BY recency DESC) AS recency_score,
        NTILE(5) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary) AS monetary_score
    FROM RFMTable
)
SELECT
    customer_unique_id,
    recency_score,
    frequency_score,
    monetary_score,
    CONCAT(recency_score, frequency_score, monetary_score) AS rfm_score,
    CASE
        WHEN recency_score = 5 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'Best Customers'
        WHEN recency_score = 5 AND frequency_score <= 2 AND monetary_score >= 4 THEN 'Loyal Customers'
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score <= 2 THEN 'Potential Loyalists'
        WHEN recency_score = 5 AND frequency_score <= 2 AND monetary_score <= 2 THEN 'New Customers'
        ELSE 'At Risk'
    END AS customer_segment
FROM RFMScores
ORDER BY customer_segment;
