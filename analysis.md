## Customer Analysis & Segmentation - Brazil E-commerce
Author: Aufar Tirta

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
