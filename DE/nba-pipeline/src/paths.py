from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DATA = ROOT / "data"
BRONZE = DATA / "bronze"
SILVER = DATA / "silver"
GOLD = DATA / "gold"

for p in (BRONZE, SILVER, GOLD):
    p.mkdir(parents=True, exist_ok=True)