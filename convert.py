"""
convert.py — конвертація MovieLens 1M (.dat) → CSV для завантаження в Neo4j.

Запустіть один раз перед завантаженням:  python convert.py

Чому це потрібно:
  - .dat-файли MovieLens використовують роздільник "::" і кодування latin-1.
  - Neo4j LOAD CSV очікує "звичайний" CSV: один символ-роздільник і UTF-8.
  - csv.writer сам бере поля в лапки, якщо всередині є кома (а коми трапляються
    в назвах фільмів, напр. "City of Lost Children, The (1995)").

Рік випуску та розбиття жанрів НЕ робимо тут — це зручніше зробити в Cypher
під час завантаження (рік -> властивість Movie.year, жанри -> окремі вузли Genre).
"""
import csv
import os

SRC = "data/ml-1m"
DST = "import"
os.makedirs(DST, exist_ok=True)


def convert(src_name, dst_name, header, ncols):
    """Прочитати .dat (latin-1, роздільник '::') і записати CSV (utf-8, кома)."""
    src = os.path.join(SRC, src_name)
    dst = os.path.join(DST, dst_name)
    rows = 0
    with open(src, encoding="latin-1") as f_in, \
         open(dst, "w", newline="", encoding="utf-8") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(header)
        for line in f_in:
            parts = line.rstrip("\n").split("::")
            writer.writerow(parts[:ncols])  # для users відрізаємо zip-код
            rows += 1
    print(f"  {src_name:14s} -> {dst_name:14s} : {rows:>8} рядків")


if __name__ == "__main__":
    print("Конвертація MovieLens 1M -> CSV ...")
    # movies.dat:  MovieID::Title::Genres
    convert("movies.dat", "movies.csv", ["movieId", "title", "genres"], 3)
    # users.dat:   UserID::Gender::Age::Occupation::Zip   (zip відкидаємо)
    convert("users.dat", "users.csv", ["userId", "gender", "age", "occupation"], 4)
    # ratings.dat: UserID::MovieID::Rating::Timestamp
    convert("ratings.dat", "ratings.csv", ["userId", "movieId", "rating", "timestamp"], 4)
    print("Готово. CSV у папці import/")
