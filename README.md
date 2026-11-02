# DockCheck: Shipment Delay & Receiving Discrepancy Investigation

SQL (PostgreSQL) investigation of two questions: **why are shipments late**, and **where do shipped units go missing**.

| Part | Data | What it shows |
| --- | --- | --- |
| A. Late shipments | Public dataset (DataCo, Kaggle) | Hypothesis testing to a root cause |
| B. Receiving discrepancies | Simulated by `scripts/generate_receiving_log.py` | The investigation method: spot a spike, drill down, build a case list |

## Data

- **Public:** [DataCo Smart Supply Chain](https://www.kaggle.com/datasets/shashwatwork/dataco-smart-supply-chain-for-big-data-analysis) (Kaggle): 180,519 order items, 65,752 orders, 2015–2018. Not included (95 MB); download it from Kaggle. It is a public practice dataset, not a company's live operations: its patterns look generated (for example, each value of actual shipping days appears in almost exactly 20% of orders of a shipping mode), so the findings describe this dataset.
- **Simulated:** `data/fc_receiving_log.csv`, 172,765 receiving records (shipped vs received units), one per shipped order item. DataCo has no inbound data, so each shipped item is treated as a transfer into the regional fulfilment centre (FC) of its market, received on its shipping date. The script uses a fixed seed (same file every run) and **documented rules that plant the patterns** Part B looks for: a shortage spike at FC-03 in Oct–Dec 2017, more shortages on 4–5 unit items and on late shipments, more damage in Golf and Fitness.

## Model

Flat 53-column file → 6 linked tables: `customers`, `products`, `orders`, `order_items`, `fulfillment_centres`, `fc_receiving_log` (primary and foreign keys, indexes).

## Part A findings (public DataCo data)

- **57.3%** of shipped orders were late (36,048 of 62,897).
- Market and time are not the cause: late rate 56.5–57.7% across markets and 56.5–58.7% across quarters.
- Shipping mode is: **every First Class order took 2 days against a 1-day promise (100% late)**. Second Class averaged 4.0 days, the same as Standard, against a 2-day promise (80% late).
- A 1-day First Class promise is never met in this data. With realistic promises (2 days First Class, 4 days Second Class) the late rate would be **34.3%**. Delivery does not get faster; this shows how much of "late" comes from the promise itself, so either the promise or the process has to change.
- **52.1%** of canceled orders were flagged as suspected fraud.

## Part B results (simulated receiving log)

These patterns were planted by the generator's rules. The queries recover them, which shows the method works; they are not discoveries about a real FC.

- 7,245 discrepancy cases: 7,913 units short, 3,778 damaged, 674 overages.
- The `LAG` query catches the FC-03 shortage rate jumping from 2.49% (Sep 2017) to 7.84% (Oct 2017). Receipts fell at the same time, but only because DataCo's Europe data ends in Nov 2017.
- Drill-down: in Oct–Nov 2017, 4–5 unit items at FC-03 were short 16.67% of the time (29 of 174 receipts, a small sample).
- `v_discrepancy_cases` lists every case with a priority (P1 nothing received … P4 overage) and value at risk, ready for a team to work from.

## Data quality issues found and handled (9)

1. Product description empty in every row (column dropped)
2. Order zipcode empty in 86% of rows
3. Customer email and password masked (columns dropped)
4. One "Electronics" label used for two categories that hold slides (footwear) and golf balls (flagged as untrustworthy)
5. 3 customers with address columns shifted by one (fixed)
6. Trailing spaces in product and department names (trimmed)
7. Country names in Spanish, "EE. UU." (translated)
8. Canceled orders still carry shipping days (excluded from the late rate)
9. Markets cover different date ranges (USCA only Apr 2016 – Jan 2017; after Nov 2017 only Pacific Asia), so monthly trends need care

## SQL techniques

Staging tables with all-TEXT columns, type casting, regex checks, CTEs, window functions (`LAG`, `DENSE_RANK`, `SUM() OVER (PARTITION BY)`), `FILTER`, `CASE`, multi-table joins, views.

## Repository

| Path | Contents |
| --- | --- |
| `sql/01_create_staging.sql` | Staging tables (everything as TEXT) |
| `sql/02_data_quality_checks.sql` | 11 checks before cleaning |
| `sql/03_clean_and_model.sql` | Cleaning + the 6-table model |
| `sql/04_investigation_delays.sql` | Part A, queries A1–A8 |
| `sql/05_investigation_receiving.sql` | Part B, queries B1–B11 and the case-list view |
| `scripts/generate_receiving_log.py` | Creates the simulated receiving log |
| `data/fc_receiving_log.csv` | The simulated receiving log |
| `outputs/sql_results.txt` | Results of every query |

## How to run

1. Create database `dockcheck` in PostgreSQL.
2. Run `sql/01_create_staging.sql`.
3. Import the DataCo CSV into `stg_dataco` (encoding LATIN1, header on) and `data/fc_receiving_log.csv` into `stg_receiving_log`.
4. Run `sql/02` (checks), `sql/03` (clean + model), then `sql/04` and `sql/05` one query at a time.

To recreate the simulated log: `python scripts/generate_receiving_log.py DataCoSupplyChainDataset.csv data/fc_receiving_log.csv` (needs pandas and numpy).

---
Author: **Salil Gokhale** · [LinkedIn](https://www.linkedin.com/in/salil-gokhale-analytics)
