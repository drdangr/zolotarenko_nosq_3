"""
BONUS — рекомендатор фільмів на графових ембеддингах (FastRP) + векторний пошук.

Як працює:
  1. На старті вантажимо з Neo4j ембеддинги фільмів (Movie.embedding), що мають
     ребра CO_RATED (≈794 «ядрових» фільмів), + метадані (жанри, рейтинг).
  2. mean-centering: віднімаємо спільний вектор «популярність», лишаючи «смак».
  3. Користувач відмічає улюблені фільми -> профіль = середній (центрований) вектор.
  4. Для обраного жанру рахуємо cosine(профіль, фільм) -> топ-5 невідмічених.
     Це і є векторний пошук — лишень вектори тут структурні (з графа), а не з тексту.

Запуск:  uvicorn app:app --port 8000   (Neo4j має бути піднятий)
"""
import numpy as np
from neo4j import GraphDatabase
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import os

NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://localhost:7687")
HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------
# Завантаження + підготовка даних (один раз на старті)
# ----------------------------------------------------------------------------
print("Завантажую ембеддинги з Neo4j...")
_drv = GraphDatabase.driver(NEO4J_URI, auth=("neo4j", "password123"))
with _drv.session() as s:
    _rows = s.run("""
        MATCH (m:Movie)
        WHERE m.embedding IS NOT NULL AND COUNT { (m)-[:CO_RATED]-() } > 0
        OPTIONAL MATCH (m)-[:HAS_GENRE]->(g:Genre)
        RETURN m.movieId AS id, m.title AS title, m.embedding AS emb,
               m.numRatings AS num, m.avgRating AS avg, collect(g.name) AS genres
    """).data()
_drv.close()

MOVIES = [{"id": r["id"], "title": r["title"], "num": r["num"] or 0,
           "avg": round(r["avg"], 2) if r["avg"] else None,
           "genres": r["genres"]} for r in _rows]

# матриця ембеддингів: mean-centering + нормування рядків (для косинуса)
_E = np.array([r["emb"] for r in _rows], dtype=np.float32)
_E = _E - _E.mean(axis=0, keepdims=True)                       # прибрати «популярність»
_E = _E / (np.linalg.norm(_E, axis=1, keepdims=True) + 1e-9)   # одиничні вектори
EMB = _E

ID2IDX = {m["id"]: i for i, m in enumerate(MOVIES)}

# жанр -> індекси фільмів, відсортовані за популярністю (для шортлистів)
GENRE2IDX = {}
for i, m in enumerate(MOVIES):
    for g in m["genres"]:
        GENRE2IDX.setdefault(g, []).append(i)
for g in GENRE2IDX:
    GENRE2IDX[g].sort(key=lambda i: MOVIES[i]["num"], reverse=True)

# показуємо лише жанри, де є щонайменше 3 «ядрові» фільми
GENRES = sorted([g for g, idxs in GENRE2IDX.items() if len(idxs) >= 3])
print(f"Готово: {len(MOVIES)} фільмів, {len(GENRES)} жанрів.")

# ----------------------------------------------------------------------------
# API
# ----------------------------------------------------------------------------
app = FastAPI(title="MovieLens Graph Recommender (bonus)")


@app.get("/api/genres")
def genres(top: int = 10):
    """Жанри + шортлист найпопулярніших фільмів у кожному (для відмітки вподобань)."""
    out = []
    for g in GENRES:
        films = [{"id": MOVIES[i]["id"], "title": MOVIES[i]["title"],
                  "num": MOVIES[i]["num"], "avg": MOVIES[i]["avg"]}
                 for i in GENRE2IDX[g][:top]]
        out.append({"genre": g, "films": films})
    return {"genres": out}


class RecRequest(BaseModel):
    likedIds: list[int]
    genre: str
    k: int = 5


@app.post("/api/recommend")
def recommend(req: RecRequest):
    liked = [ID2IDX[i] for i in req.likedIds if i in ID2IDX]
    if not liked:
        return {"error": "Відмітьте хоча б один фільм, щоб побудувати профіль."}
    if req.genre not in GENRE2IDX:
        return {"error": f"Невідомий жанр: {req.genre}"}

    # профіль смаку = середній центрований вектор відмічених фільмів
    taste = EMB[liked].mean(axis=0)
    taste = taste / (np.linalg.norm(taste) + 1e-9)

    liked_ids = set(req.likedIds)
    cand = [i for i in GENRE2IDX[req.genre] if MOVIES[i]["id"] not in liked_ids]
    sims = EMB[cand] @ taste                       # cosine (вектори нормовані)
    order = np.argsort(-sims)[:req.k]
    recs = [{"title": MOVIES[cand[j]]["title"], "score": round(float(sims[j]), 3),
             "avg": MOVIES[cand[j]]["avg"], "num": MOVIES[cand[j]]["num"]}
            for j in order]
    return {"genre": req.genre, "profileSize": len(liked), "recommendations": recs}


@app.get("/")
def index():
    return FileResponse(os.path.join(HERE, "static", "index.html"))


app.mount("/static", StaticFiles(directory=os.path.join(HERE, "static")), name="static")
