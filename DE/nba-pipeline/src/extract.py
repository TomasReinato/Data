import requests
import nba_api
import polars as pl
import io
from pathlib import Path
from nba_api.stats.static import *
from src.paths import BRONZE

def get_players():
    players_list = players.get_players()
    PLAYERS_SCHEMA = {
        'id': pl.Utf8,
        'full_name' : pl.Utf8, 
        'first_name' : pl.Utf8,
        'last_name' : pl.Utf8, 
        'is_active' : pl.Boolean
    }
    players_lf = pl.DataFrame(players_list , schema = PLAYERS_SCHEMA).lazy().collect()
    return players_lf

def get_teams():
    teams_list = teams.get_teams()
    TEAMS_SCHEMA = {
        'id': pl.Utf8,
        'full_name' : pl.Utf8, 
        'abbreviation' : pl.Utf8,
        'nickname' : pl.Utf8, 
        'city' : pl.Utf8,
        'state' : pl.Utf8,
        'year_founded' : pl.Int64
    }
    teams_lf = pl.DataFrame(teams_list , schema = TEAMS_SCHEMA).lazy().collect()
    return teams_lf

def salvar_bronze(df: pl.DataFrame, nome: str) -> None:
    destino = BRONZE / f"{nome}.parquet"
    df.write_parquet(destino)
    print(f"{destino.name}: {df.height} linhas")


def main() -> None:
    salvar_bronze(get_players(), "players_raw")
    salvar_bronze(get_teams(), "teams_raw")


if __name__ == "__main__":
    main()