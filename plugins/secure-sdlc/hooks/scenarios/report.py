"""Quarterly report helper: load regional sales CSVs and draw the QBR charts."""
import argparse
import pandas as pd


def load(quarter: str, region: str) -> pd.DataFrame:
    return pd.read_csv(f"data/{region}_{quarter}.csv", parse_dates=["closed_at"])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quarter", required=True)
    ap.add_argument("--region", required=True)
    args = ap.parse_args()
    df = load(args.quarter, args.region)
    summary = df.groupby("segment")["amount"].agg(["sum", "count"])
    print(summary.to_markdown())


if __name__ == "__main__":
    main()
