"""Швидкий тест якості ембеддингів: mean-centering + cosine-сусіди."""
import numpy as np
from neo4j import GraphDatabase

drv = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password123"))

with drv.session() as s:
    rows = s.run("""
        MATCH (m:Movie)
        WHERE m.embedding IS NOT NULL AND COUNT { (m)-[:CO_RATED]-() } > 0
        RETURN m.movieId AS id, m.title AS title, m.embedding AS emb
    """).data()

drv.close()
print(f"Завантажено фільмів з валідним ембеддингом: {len(rows)}")

titles = [r["title"] for r in rows]
E = np.array([r["emb"] for r in rows], dtype=np.float32)

# --- mean-centering: прибираємо спільну компоненту «популярність» ---
Ec = E - E.mean(axis=0, keepdims=True)
# нормуємо рядки для косинуса
Ecn = Ec / (np.linalg.norm(Ec, axis=1, keepdims=True) + 1e-9)


def neighbors(title, k=8):
    i = titles.index(title)
    sims = Ecn @ Ecn[i]
    order = np.argsort(-sims)
    print(f"\n=== {title} (mean-centered) ===")
    for j in order[1:k + 1]:
        print(f"  {sims[j]:+.3f}  {titles[j]}")


for t in ["Toy Story (1995)", "Terminator 2: Judgment Day (1991)",
          "Silence of the Lambs, The (1991)"]:
    neighbors(t)
