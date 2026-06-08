// ============================================================================
// BONUS — рушій рекомендатора: ембеддинги фільмів через FastRP
// Запускати один раз. Пише вектор у властивість Movie.embedding.
// ============================================================================

// Крок 1: матеріалізуємо граф фільм-фільм CO_RATED (як у частині 5).
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE COUNT { (m1)<-[:RATED]-() } > 20 AND COUNT { (m2)<-[:RATED]-() } > 20
WITH m1, m2, weight ORDER BY weight DESC LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2) SET co.weight = weight;

// Крок 2: денормалізуємо avgRating/numRatings у вузли Movie (потрібно фронту для
// шортлистів + це і є «Покращення 1» з частини 6, тепер реалізоване).
MATCH (m:Movie)<-[r:RATED]-()
WITH m, avg(r.rating) AS avg, count(r) AS cnt
SET m.avgRating = avg, m.numRatings = cnt;

// Крок 3: проєкція + FastRP (вектор з положення фільму в графі CO_RATED).
CALL gds.graph.project('movieEmb', 'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } });

CALL gds.fastRP.write('movieEmb', {
  embeddingDimension: 128,
  relationshipWeightProperty: 'weight',
  writeProperty: 'embedding',
  randomSeed: 42
}) YIELD nodePropertiesWritten
RETURN nodePropertiesWritten;

// Крок 4: прибираємо проєкцію (ембеддинги вже записані у вузли).
CALL gds.graph.drop('movieEmb');
