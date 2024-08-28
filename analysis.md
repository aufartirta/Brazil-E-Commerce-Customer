## Customer Behavior Analysis & Segmentation - Brazil E-commerce
Author: Aufar Tirta

### 1. Payment Behavior
```sql
WITH total_payment AS(
	SELECT COUNT(*) AS total
	FROM order_payments
)
SELECT
	payment_type,
	COUNT(*) AS amount,
	ROUND((COUNT(*) * 100.0) / (SELECT total FROM total_payment), 2) AS percentage,
	ROUND(SUM(payment_value::INTEGER), 2) AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY amount DESC; 
```
Result:
|payment_type|amount|percentage|total_value|
|---|---|---|---|
credit_card|76795|73.92|12542393.00
boleto|19784|19.04|2869488.00
voucher|5775|5.56|379391.00
debit_card|1529|1.47|218002.00
not_defined|3|0|0.00

The most common payment method is the credit card, which is used in 73.92% of transactions, making it the predominant choice. Boleto, a widely popular cash payment method in Brazil, follows as the second most utilized payment option.

```sql
--Identify the relation between payment value and payment installments
SELECT
	ROUND(SUM(payment_value::INTEGER), 2) AS total_payment_value,
	ROUND(AVG(payment_value::INTEGER), 2) AS average_payment_value,
	payment_installments
FROM order_payments
GROUP BY
	payment_installments
ORDER BY average_payment_value DESC
LIMIT 10;
```
Result:
total_payment_value|average_payment_value|payment_installments
---|---|---
10469.00|615.82|20
10980.00|610.00|24
13137.00|486.56|18
32976.00|445.62	|15
2211569.00|415.08|10
42784.00|321.68	|12
1313436.00|307.74|8
1463.00|292.60|16
731.00|243.67|21
236.00|236.00|23

In larger payments, customers prefer to break down larger payments into smaller parts.

```sql
--Compare total order value and total payment value. Identify the differences
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
```
The difference between total_order_value and total_payment_value can signify various factors depending on the data context and underlying business logic. The total_order_value encompasses the sum of product prices and freight costs for all items in an order, while total_payment_value reflects the actual amount paid for the order. Discrepancies between these two values could arise due to several potential causes and have different implications:

1. Partial Payments: If total_payment_value is less than total_order_value, it could indicate that the customer has not yet completed the payment for the order. This situation might occur in cases where payments are made in installments or if there are pending payments.

2. Overpayments: If total_payment_value is greater than total_order_value, it might suggest overpayment. This could happen due to various reasons such as customers paying more than the order amount, duplicate payments, or adjustments and refunds not yet processed.

3. Discounts and Adjustments: Discounts, promotional codes, or manual adjustments may not be reflected in the total_order_value but could affect the total_payment_value. If discounts are applied directly to the payment without changing the item prices or freight values, this would lead to a difference between the two values.

4. Payment Processing Fees: Payment processing fees might be included in the total_payment_value but not in the total_order_value. This discrepancy can occur if the system records the fees paid by customers as part of the total payment amount.

5. Fraudulent Transactions: Significant discrepancies might also indicate potential fraudulent transactions or errors in the order processing system that need to be investigated.

```sql
--Identify the percentage of transactions with 0 difference
SELECT 
    ROUND((SUM(CASE WHEN (oi.price + oi.freight_value) = op.payment_value THEN 1 ELSE 0 END) * 100.0) / COUNT(*), 2) AS zero_diff_percentage
FROM order_payments op
JOIN order_items oi ON op.order_id = oi.order_id
WHERE op.payment_type IN ('credit_card', 'debit_card', 'boleto');
```
Result: 59.21

Of all transactions, 59.21% show no difference between total_order_value and total_payment_value. This indicates that nearly 40% of transactions have discrepancies, making this issue worth further investigation.

### 2. Customer Rating Behavior

```sql
--Identify the average review score based on the duration of delivery
SELECT 
	CASE
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '7 days' THEN 'Fast'
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '14 days' THEN 'Normal'
		WHEN (o.order_delivered_customer_date - o.order_purchase_timestamp) <= '30 days' THEN 'Slow'
		ELSE 'Very Slow'
	END AS duration_category,
	COUNT(*) AS total_orders,
	ROUND(AVG(r.review_score),2) AS average_review_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY duration_category;
```
Result:
duration_category|total_orders|average_review_score
--|---|---
Fast|26040|4.42
Normal|40214|4.31
Slow|25644|3.98
Very Slow|4455|2.25

Faster delivery is generally associated with good ratings from customers. 

```sql
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
```
Result:
customer_city|average_duration
---|---
guarulhos|		7 days
sao paulo|		7 days
sao bernardo do campo|	7 days
campinas|		9 days
curitiba|		10 days
belo horizonte|		10 days 
brasilia|		12 days
rio de janeiro|		14 days 
porto alegre|		15 days 
salvador|		18 days 

In the top 10 cities with the highest number of transactions, delivery time ranges from 7 to 18 days.

### 3. Customer Lifetime Value (CLV) Analysis
Customer Lifetime Value (CLV) is a critical metric that estimates the total revenue a business can expect from a single customer throughout their relationship with the company. CLV helps identify the most valuable customers by analyzing their purchasing behavior, including the frequency of purchases, the average order value, and the duration of the customer relationship.

Calculating CLV involves assessing the total revenue generated by a customer across all their orders, adjusting for the frequency of their purchases, and the length of time they have been an active customer. This insight allows company to:
1. Identify High-Value Customers: By recognizing customers who contribute the most to the business over time, Olist can focus retention efforts on these valuable customers.
2. Optimize Marketing Spend: Resources can be allocated more effectively by targeting customers with a higher CLV with personalized marketing strategies.
3. Enhance Customer Engagement: Understanding which customers have higher lifetime value helps in developing strategies that increase customer satisfaction and loyalty, ultimately boosting overall revenue.

CLV is calculated by evaluating the total revenue generated, dividing it by the number of orders to get the average purchase value, and then considering the frequency of purchases and the lifespan of the customer relationship to estimate the long-term value of each customer to the business.

```sql
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
        COALESCE(total_orders / NULLIF(GREATEST(customer_lifespan_days / 365.0, 0.1), 1), 1) AS purchase_frequency_per_year,
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
    estimated_clv DESC;
```
Result:
customer_unique_id|total_revenue|total_orders|customer_lifespan_days|avg_purchase_value|purchase_frequency_per_year|estimated_clv
---|---|---|---|---|---|---|
c8460e42xx|4655.91|4|1|1163.97|40.0|4655.91
59d66d72xx|3559.99|2|161|1779.99|4.53|3559.99
eae0a83dxx|2783.01|2|81	|1391.50|9.01|2783.01
86df00dcxx|2400.48|3|127|800.16|8.62|2400.48
1da09dd6xx|2164.40|3|245|721.46|4.46|2164.40

Interpreting the Results:
* High CLV: Customers with a high estimated_clv are the most valuable. They likely have a high average purchase value, frequent orders, or a long customer lifespan.
* Low CLV: Customers with a low estimated_clv contribute less revenue over time. This could be due to infrequent purchases, low average order value, or a short customer lifespan.
* Total Orders & Lifespan: By analyzing total_orders and customer_lifespan_days, you can see if high CLV is driven by frequent purchases over a long period or by high-value purchases in a short timeframe.
* Revenue Trends: The total_revenue column helps in understanding which customers are contributing the most revenue, while avg_purchase_value shows the consistency in the purchase amounts.

Actions Based on Interpretation:
* Retention Strategies: For high CLV customers, focus on retention strategies such as loyalty programs, personalized offers, or premium support.
* Reactivation Campaigns: For low CLV customers, consider reactivation campaigns to encourage more frequent purchases or higher-value orders.
* Segmentation: Use these insights to segment your customers for targeted marketing campaigns, ensuring that high-value customers receive the most attention.

### 4. RFM (Recency, Frequency, Monetary) Analysis
RFM Analysis is a customer segmentation technique used to categorize customers based on their purchasing behavior. It is a powerful tool for understanding customer value and prioritizing marketing efforts.
* Recency: Measures how recently a customer made a purchase. This would indicate the time elapsed since a customer's last order. Customers who have purchased more recently are often considered more engaged.
* Frequency: Tracks how often a customer makes purchases. This would be the number of orders placed by a customer over a specific period. High-frequency customers are likely more loyal and can be targeted for retention strategies.
* Monetary: Refers to the total amount a customer has spent. This would be calculated based on the total payment value for each customer. Customers with high monetary values are considered more valuable and may warrant special attention.
  
```sql
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
```
The code above demonstrates the calculation of Recency, Frequency, and Monetary individually. The complete RFM calculation is shown on the code below:

```sql

--RFM Analysis
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
		NTILE(5) OVER (ORDER BY recency) AS recency_score,
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
        WHEN recency_score >= 4 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Loyal Customers'
        WHEN recency_score <= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Potential Loyalists'
        WHEN recency_score = 5 AND frequency_score <= 2 AND monetary_score <= 2 THEN 'New Customers'
        ELSE 'At Risk'
    END AS customer_segment
FROM RFMScores;
```
Result:

In the provided code, customers are scored on each of these three dimensions, and then these scores are combined to create an RFM score. Based on their RFM score, customers are segmented into categories such as "Best Customers," "Loyal Customers," "Potential Loyalists," "New Customers," and "At Risk" customers with explanations as follows:
Best Customers: Recent, frequent, and high-spending customers.
Loyal Customers: Frequent buyers with moderate to high spending, but perhaps not as recent.
Potential Loyalists: Customers who are not recent but have a history of moderate to high spending.
New Customers: Recent buyers with lower frequency and monetary value.
At Risk: Customers with low recency, frequency, and monetary scores.

This segmentation allows businesses to tailor their marketing strategies and customer engagement efforts according to the behavior and value of different customer groups.
