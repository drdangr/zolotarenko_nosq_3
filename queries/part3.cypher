// ============================================================================
// Частина 3 — Запити різної складності
// ============================================================================

// ----------------------------------------------------------------------------
// Запит 1. Фільми жанру «Thriller» із середнім рейтингом вище 4.0.
// Йдемо від вузла Genre (пивот) -> фільми цього жанру -> їхні оцінки;
// агрегуємо avg(rating) на фільм, фільтруємо > 4.0. numRatings показує «опору»
// середнього (скільки оцінок за ним стоїть).
// ----------------------------------------------------------------------------
MATCH (g:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH m, avg(r.rating) AS avgRating, count(r) AS numRatings
WHERE avgRating > 4.0
RETURN m.title AS movie, round(avgRating, 2) AS avgRating, numRatings
ORDER BY avgRating DESC, numRatings DESC;

// ----------------------------------------------------------------------------
// Запит 2. Користувачі, які поставили оцінку 5 більш ніж 50 фільмам.
// Фільтруємо ребра rating=5, рахуємо на користувача, лишаємо тих, у кого > 50.
// ----------------------------------------------------------------------------
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(*) AS fives
WHERE fives > 50
RETURN u.userId AS userId, fives
ORDER BY fives DESC;

// ----------------------------------------------------------------------------
// Запит 3. Фільми, які userId=1 і userId=2 обидва оцінили високо (>= 4).
// Один патерн ловить обидві оцінки на тому самому фільмі — це природний для
// графа «трикутник» (u1)->(m)<-(u2), у SQL це був би JOIN ratings із самим собою.
// ----------------------------------------------------------------------------
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS movie, r1.rating AS u1_rating, r2.rating AS u2_rating
ORDER BY movie;

// ----------------------------------------------------------------------------
// Запит 4. Жанри зі стабільно високими оцінками — середній рейтинг і кількість.
// Агрегуємо всі оцінки фільмів кожного жанру. numRatings важливий: avg по жанру
// з 44 фільмів (Film-Noir) надійніший за рідкісний, тому показуємо обидва.
// ----------------------------------------------------------------------------
MATCH (g:Genre)<-[:HAS_GENRE]-(:Movie)<-[r:RATED]-()
WITH g, avg(r.rating) AS avgRating, count(r) AS numRatings
RETURN g.name AS genre, round(avgRating, 3) AS avgRating, numRatings
ORDER BY avgRating DESC;

// ----------------------------------------------------------------------------
// Запит 5. Рекомендація «користувачі зі схожими смаками також дивилися».
// Для userId=1: (1) знаходимо схожих — тих, хто високо оцінив ті самі фільми;
// беремо топ-50 за кількістю спільних високих оцінок. (2) дивимось, що ВОНИ
// високо оцінили, але чого користувач №1 ще НЕ бачив. Ранжуємо за тим, скільки
// схожих користувачів рекомендують фільм.
// ----------------------------------------------------------------------------
MATCH (me:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(other:User)
WHERE r1.rating >= 4 AND r2.rating >= 4
WITH me, other, count(m) AS shared
ORDER BY shared DESC
LIMIT 50
MATCH (other)-[r3:RATED]->(rec:Movie)
WHERE r3.rating >= 4 AND NOT (me)-[:RATED]->(rec)
WITH rec, count(DISTINCT other) AS recommenders, avg(r3.rating) AS avgRating
RETURN rec.title AS recommendation, recommenders, round(avgRating, 2) AS avgRating
ORDER BY recommenders DESC, avgRating DESC
LIMIT 10;

// ----------------------------------------------------------------------------
// Запит 6. Найкоротший ланцюжок зв'язку між двома користувачами через спільні
// фільми. shortestPath по ребрах RATED (ненапрямлено: User-Movie-User-...).
// Довжина 2 = обидва оцінили один фільм; 4 = через одного посередника; і т.д.
// ----------------------------------------------------------------------------
MATCH (u1:User {userId: 1}), (u2:User {userId: 2})
MATCH p = shortestPath((u1)-[:RATED*..10]-(u2))
RETURN [n IN nodes(p) | CASE WHEN n:User THEN 'User ' + n.userId
                             ELSE n.title END] AS chain,
       length(p) AS pathLength;
