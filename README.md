# Brazilian E-Commerce (Olist) Analysis

End-to-end analysis of the Olist public dataset (96K orders, 93K customers, 2017-2018) using **Python, SQL, and Power BI**.

## Business Questions
- Who are the customers, and do they come back?
- How do revenue and AOV change over time?
- Does late delivery hurt reviews?
- Which categories and states drive revenue?
- How much does freight cost in remote states?

## Key Findings
| Area | Finding |
|---|---|
| Scale | 96K orders, 93K customers, 13.22M revenue (price only, no freight) |
| Retention | Repeat rate is only **3%**. Less than 1% of customers return in any month |
| RFM | New customers are the biggest segment (36K) and bring the most revenue (5.07M). Only 122 Champions |
| Growth | Orders grew from 0.8K (Jan 2017) to 7.3K (Nov 2017), then stayed flat. AOV stayed between 125 and 148 |
| Delivery | Average review drops from **4.3 (early)** to **1.7 (7+ days late)** |
| Geography | SP brings about **39%** of revenue. Top 10 categories bring about **62%** |
| Freight | Freight is up to **28%** of product price in remote states (RR), vs 13.9% in SP |
| Payments | 75% of orders use credit card. Orders with 7+ installments have AOV 334 vs 120 for single payment |

## Dashboard Pages
1. Overview & RFM Segments
2. AOV & Revenue Trends
3. MoM & Retention Matrix
4. Delivery Delay vs Reviews
5. Reviews, Payments & Installments
6. Top/Bottom Categories & States
7. Spend Distribution & Freight %

## Recommendations
- Fix late delivery first. It is the clearest driver of low reviews.
- Run a second-purchase campaign for New customers.
- Reduce freight cost or add free-shipping thresholds in remote states.

## Project Structure
- `Python/`: cleaning and EDA notebook, source CSVs
- `SQL/`: queries and views (RFM, cohort, sales trend, delivery vs review, category Pareto)
- `Power BI/`: interactive report

## Tools
Python (Pandas), SQL Server, Power BI (DAX, Power Query)

## Dataset
[Brazilian E-Commerce Public Dataset by Olist (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
