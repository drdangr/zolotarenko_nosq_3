// ============================================================================
// Частина 5 — Графові алгоритми через GDS
// GDS працює не зі збереженим графом, а з ПРОЄКЦІЄЮ в пам'яті — це окремий крок.
// ============================================================================

// ############################################################################
// 5.1. PageRank на графі фільмів
// ############################################################################

// Крок 1: матеріалізуємо ребра фільм-фільм через спільних користувачів (rating>=4).
//   id(m1)<id(m2) — щоб не дублювати пару; поріг ступеня >20 відсікає рідкісні фільми.
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE COUNT { (m1)<-[:RATED]-() } > 20 AND COUNT { (m2)<-[:RATED]-() } > 20
WITH m1, m2, weight ORDER BY weight DESC LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2) SET co.weight = weight;

// Крок 2: проєкція в пам'ять GDS.
CALL gds.graph.project('movieGraph', 'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } })
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: PageRank (зважений). Топ-10 фільмів.
CALL gds.pageRank.stream('movieGraph', {relationshipWeightProperty: 'weight'})
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS m, score
RETURN m.title AS movie, round(score, 3) AS pagerank,
       COUNT { (m)<-[:RATED]-() } AS numRatings
ORDER BY score DESC LIMIT 10;

// Крок 4: прибираємо проєкцію та тимчасові ребра.
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;


// ############################################################################
// 5.2. Виявлення спільнот (Louvain) на графі схожості користувачів
// ############################################################################

// Крок 1: матеріалізуємо ребра користувач-користувач через спільні фільми.
//   ВАЖЛИВО: тут поріг rating = 5 (а не >=4) — з >=4 агрегація пар користувачів
//   перевищує ліміт пам'яті транзакції (дозволено умовою завдання). = 5 різко
//   зменшує проміжний обсяг і дає чистіший сигнал «спільного захоплення».
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight ORDER BY weight DESC LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2) SET sim.weight = weight;

// Крок 2: проєкція.
CALL gds.graph.project('userSimilarity', 'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } })
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Louvain — записуємо community у вузли, дивимось modularity.
CALL gds.louvain.write('userSimilarity',
  {relationshipWeightProperty: 'weight', writeProperty: 'community'})
YIELD communityCount, modularity, ranLevels
RETURN communityCount, round(modularity, 4) AS modularity, ranLevels;

// Крок 3b: 10 найбільших спільнот.
MATCH (u:User) WHERE u.community IS NOT NULL
WITH u.community AS community, count(*) AS size
RETURN community, size ORDER BY size DESC LIMIT 10;

// Крок 3c: відмінні жанри кожної великої спільноти через LIFT (перепредставленість
//   жанру відносно середнього по всьому датасету). Raw count показує лише базову
//   популярність (Drama/Comedy всюди); lift розкриває справжні смаки.
MATCH (:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre) WHERE r.rating >= 4
WITH g.name AS genre, toFloat(count(*)) AS gc
WITH sum(gc) AS gTotal, collect({genre: genre, gc: gc}) AS gl
UNWIND gl AS row
WITH collect({genre: row.genre, gs: row.gc / gTotal}) AS globalShares
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community IN [4168, 5681, 4343, 751] AND r.rating >= 4
WITH globalShares, u.community AS community, g.name AS genre, toFloat(count(*)) AS cc
WITH globalShares, community, collect({genre: genre, cc: cc}) AS cg, sum(cc) AS commTotal
UNWIND cg AS row
WITH community, row.genre AS genre, row.cc / commTotal AS commShare,
     [x IN globalShares WHERE x.genre = row.genre][0].gs AS globalShare
WITH community, genre, commShare / globalShare AS lift
ORDER BY community, lift DESC
WITH community, collect({g: genre, l: lift}) AS lifts
RETURN community, [x IN lifts[0..4] | x.g + ' ' + toString(round(x.l, 2)) + 'x'] AS distinctive_genres;


// ############################################################################
// 5.3. Найкоротший шлях між користувачами (Dijkstra)
// Використовуємо ту саму проєкцію userSimilarity.
// ############################################################################

// Dijkstra між обраною парою (приклад: User 17 -> User 81, різні спільноти).
MATCH (s:User {userId: 17}), (t:User {userId: 81})
CALL gds.shortestPath.dijkstra.stream('userSimilarity',
  {sourceNode: s, targetNode: t, relationshipWeightProperty: 'weight'})
YIELD totalCost, nodeIds
RETURN size(nodeIds) - 1 AS hops, round(totalCost, 1) AS totalCost,
       [n IN nodeIds | gds.util.asNode(n).userId] AS userChain;

// Середня довжина шляху по вибірці пар (нативний shortestPath по SIMILAR).
WITH [17, 27, 33, 34, 81, 97, 146, 161, 10, 18, 36, 44] AS ids
UNWIND ids AS a UNWIND ids AS b
WITH a, b WHERE a < b
MATCH (s:User {userId: a}), (t:User {userId: b})
MATCH p = shortestPath((s)-[:SIMILAR*..10]-(t))
RETURN count(*) AS pairs, round(avg(length(p)), 2) AS avgHops,
       min(length(p)) AS minHops, max(length(p)) AS maxHops;

// Крок прибирання: проєкція + тимчасові ребра + властивість community.
CALL gds.graph.drop('userSimilarity');
MATCH ()-[sim:SIMILAR]-() DELETE sim;
MATCH (u:User) REMOVE u.community;
