## Customer Analysis & Segmentation - Brazil E-commerce
Author: Aufar Tirta

```sql
--Identify the preferred payment methods
SELECT
	payment_type,
	COUNT(*) AS amount,
	ROUND(SUM(payment_value::INTEGER), 2) AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY amount DESC; 
```
Result:
payment_type|amount|total_value
---|---|---
credit_card|76795|12542393.00
boleto|19784|2869488.00
voucher|5775|379391.00
debit_card|1529|218002.00
not_defined|3|0.00
