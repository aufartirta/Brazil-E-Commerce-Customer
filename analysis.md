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

