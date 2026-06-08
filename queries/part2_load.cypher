// ============================================================================
// Частина 2 — Завантаження даних MovieLens 1M у Neo4j
// Запускати по черзі (Neo4j Browser або cypher-shell). CSV лежать в import/.
// ============================================================================

// ----------------------------------------------------------------------------
// КРОК 0. Індекси/обмеження — СТВОРЮЄМО ДО завантаження.
// Constraint = унікальність + індекс «за один укол». Індекс потрібен ще до
// завантаження ребер: коли для кожної з 1М оцінок ми робимо MATCH (u:User{...})
// та MATCH (m:Movie{...}), без індексу це був би повний скан вузлів на КОЖНУ
// оцінку (O(N) × 1M). З індексом — пошук за O(log N).
// ----------------------------------------------------------------------------
CREATE CONSTRAINT user_id   IF NOT EXISTS FOR (u:User)  REQUIRE u.userId  IS UNIQUE;
CREATE CONSTRAINT movie_id  IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE CONSTRAINT genre_name IF NOT EXISTS FOR (g:Genre) REQUIRE g.name   IS UNIQUE;

// ----------------------------------------------------------------------------
// КРОК 1. Користувачі (6040).
// MERGE замість CREATE — захист від дублів при повторному запуску скрипту:
// MERGE спершу шукає вузол за ключем і створює лише якщо не знайшов.
// ----------------------------------------------------------------------------
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender     = row.gender,
    u.age        = toInteger(row.age),
    u.occupation = toInteger(row.occupation);

// ----------------------------------------------------------------------------
// КРОК 2. Фільми (3883) + жанри (18) + ребра HAS_GENRE (6408).
// Рік дістаємо з назви "Toy Story (1995)" — 4 символи перед останньою дужкою.
// split(genres,'|') + UNWIND розкладає список жанрів у рядки, далі MERGE кожного
// Genre (дедуплікація: «Action» створиться один раз) і ребро Movie->Genre.
// ----------------------------------------------------------------------------
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = row.title,
    m.year  = toInteger(substring(trim(row.title), size(trim(row.title)) - 5, 4))
WITH m, row
UNWIND split(row.genres, '|') AS gname
MERGE (g:Genre {name: gname})
MERGE (m)-[:HAS_GENRE]->(g);

// ----------------------------------------------------------------------------
// КРОК 3. Оцінки (~1 000 209 ребер RATED).
// 1М ребер не можна вантажити однією транзакцією — впаде по пам'яті/таймауту.
// apoc.periodic.iterate розбиває роботу на батчі по 10000 і комітить кожен окремо.
//   parallel: false — бо MERGE ребра конкурує: паралельні потоки могли б одночасно
//   намагатися створити те саме ребро. (MATCH вузлів безпечний, але MERGE ребра — ні.)
//   MERGE (а не CREATE) — ідемпотентність: повторний запуск не подвоїть оцінки.
// ----------------------------------------------------------------------------
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User  {userId:  toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating = toInteger(row.rating), r.timestamp = toInteger(row.timestamp)",
  {batchSize: 10000, parallel: false}
)
YIELD batches, total, errorMessages
RETURN batches, total, errorMessages;

// ----------------------------------------------------------------------------
// КРОК 4. Перевірка завантаження.
// ----------------------------------------------------------------------------
MATCH (u:User)            RETURN count(u) AS users;
MATCH (m:Movie)           RETURN count(m) AS movies;
MATCH (g:Genre)           RETURN count(g) AS genres;
MATCH ()-[r:RATED]->()    RETURN count(r) AS ratings;
MATCH ()-[h:HAS_GENRE]->() RETURN count(h) AS has_genre;
