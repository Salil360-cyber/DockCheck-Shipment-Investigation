"""
DockCheck - generate the SIMULATED fulfillment-centre receiving log.

The DataCo dataset has no "units received" data, so this script creates one
receiving record per shipped order item, using fixed, documented rules and a
fixed random seed (same output every run). Everything in fc_receiving_log.csv
is SIMULATED. Delivery/shipping-delay data in the main dataset is REAL.

Usage: python generate_receiving_log.py DataCoSupplyChainDataset.csv fc_receiving_log.csv
"""
import sys
import numpy as np
import pandas as pd

SEED = 42
FC_BY_MARKET = {"USCA": "FC-01", "LATAM": "FC-02", "Europe": "FC-03",
                "Pacific Asia": "FC-04", "Africa": "FC-05"}

# --- Rules used to simulate discrepancies (documented on purpose) ---
BASE_SHORT = 0.015      # 1.5% of items arrive short
MULTI_UNIT_X = 2.5      # items with 4-5 units are 2.5x more likely to be short
LATE_X = 1.3            # late shipments are 1.3x more likely to be short
PEAK_FC = "FC-03"       # one FC has a peak-season problem...
PEAK_MONTHS = ("2017-10", "2017-11", "2017-12")
PEAK_X = 4.0            # ...4x shortage risk in Oct-Dec 2017
BASE_OVER = 0.004       # 0.4% arrive with 1 extra unit
BASE_DAMAGE = 0.010     # 1% arrive with damaged units
FRAGILE_DEPTS = {"Golf", "Fitness"}
FRAGILE_X = 3.0

def main(src, out):
    rng = np.random.default_rng(SEED)
    df = pd.read_csv(src, encoding="latin-1")
    df = df[df["Delivery Status"] != "Shipping canceled"].copy()  # canceled = never shipped
    df = df.sort_values("Order Item Id").reset_index(drop=True)

    ship = pd.to_datetime(df["shipping date (DateOrders)"], format="%m/%d/%Y %H:%M")
    month = ship.dt.strftime("%Y-%m")
    fc = df["Market"].map(FC_BY_MARKET)
    qty = df["Order Item Quantity"].to_numpy()
    n = len(df)

    p_short = np.full(n, BASE_SHORT)
    p_short *= np.where(qty >= 4, MULTI_UNIT_X, 1.0)
    p_short *= np.where(df["Late_delivery_risk"].to_numpy() == 1, LATE_X, 1.0)
    p_short *= np.where((fc == PEAK_FC).to_numpy() & month.isin(PEAK_MONTHS).to_numpy(), PEAK_X, 1.0)
    p_damage = BASE_DAMAGE * np.where(df["Department Name"].isin(FRAGILE_DEPTS).to_numpy(), FRAGILE_X, 1.0)

    u1, u2, u3 = rng.random(n), rng.random(n), rng.random(n)
    is_short = u1 < p_short
    is_over = (~is_short) & (u2 < BASE_OVER)
    is_damaged = (~is_short) & (~is_over) & (u3 < p_damage)

    short_units = np.array([rng.integers(1, q + 1) for q in qty])
    dmg_units = np.array([rng.integers(1, q + 1) for q in qty])

    received = qty.copy()
    received = np.where(is_short, qty - short_units, received)
    received = np.where(is_over, qty + 1, received)
    damaged = np.where(is_damaged, dmg_units, 0)
    status = np.select([is_short, is_over, is_damaged], ["SHORT", "OVER", "DAMAGED"], "MATCHED")

    log = pd.DataFrame({
        "receipt_id": np.arange(1, n + 1),
        "order_item_id": df["Order Item Id"],
        "fc_code": fc,
        "received_date": ship.dt.strftime("%Y-%m-%d"),
        "shipped_qty": qty,
        "received_qty": received,
        "damaged_qty": damaged,
        "receipt_status": status,
    })
    log.to_csv(out, index=False)
    print(f"Wrote {len(log):,} rows to {out}")
    print(log["receipt_status"].value_counts().to_string())

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
