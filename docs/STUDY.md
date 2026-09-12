# Guida di studio — per la discussione

Documento per chi deve **spiegare** il progetto, non per chi lo legge. In italiano, con i termini tecnici in
inglese tra parentesi: sono quelli da usare alla discussione. Cinque sessioni da un'ora, ognuna con i file da
leggere, i concetti del corso che tocca e le domande da sapersi fare da soli. In fondo, venti domande probabili
con la risposta breve.

Regola: ogni file SQL va **eseguito a mano** in `psql` mentre lo si legge, guardando i risultati. Non basta leggerlo.

```bash
cd ~/Desktop/dm-olist-dw
export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
psql -d olist_dw          # poi \i demo/psqlrc per i bordi e i NULL visibili
```

---

## Sessione 1 — Dalle sorgenti al livello riconciliato, prima metà (1 h)

**File**: `scripts/load_staging.py`, `sql/00_schemas.sql`, `sql/20_reconciled_lookups.sql`, `sql/21_reconciled_geolocation.sql`, `sql/22_reconciled_customers_sellers.sql`, `sql/23_reconciled_products.sql`.

**Concetti del corso**: architettura a tre livelli (sources → *reconciled layer* → data warehouse), ETL (*extraction, transformation, loading*), pulizia (*data cleaning*), integrazione di sorgenti, dimensioni conformi (*conformed dimensions*) preparate a monte.

**Cosa capire**
- Perché staging ha tutte le colonne `TEXT`: nessuna interpretazione durante il caricamento, tutte le conversioni sono in SQL e visibili. Il BOM nel file delle traduzioni è l'esempio di cosa succede a fidarsi dei file.
- `20_lookups`: le due sorgenti aggiunte (regioni IBGE, macro-categorie) e perché servono (gerarchie per il roll-up). La `DO $$ … RAISE EXCEPTION` finale è un controllo di integrità del lookup.
- `21_geolocation`: il problema (52 punti per CEP, 42 fuori dal Brasile, 8 CEP con due stati) e la soluzione (bbox, moda di (stato, città), mediana di lat/lng). Perché la mediana e non la media: robusta ai punti sbagliati.
- `22_customers_sellers`: la trappola più importante del dataset. `customer_id` è per ordine; la persona è `customer_unique_id`. La `customer_order_map` tiene il legame ordine → persona. `DISTINCT ON … ORDER BY purchase DESC` prende l'indirizzo dell'ordine più recente. Per i seller la città viene dalla geolocation perché il testo libero è sporco.
- `23_products`: `COALESCE(categoria, 'unknown')` e i join sui lookup. Notare `product_name_lenght`: refuso nella sorgente, rinominato.

**Prove da fare**
```sql
SELECT count(*), count(DISTINCT customer_unique_id) FROM staging.customers;      -- 99441 vs 96096
SELECT * FROM reconciled.geolocation WHERE zip_prefix = '01037';                   -- una riga, mediana
SELECT seller_city FROM staging.sellers WHERE seller_id = 'cbf09e831b0c11f6f23ffb51004db972';  -- 'sbc/sp'
SELECT city FROM reconciled.seller WHERE seller_id = 'cbf09e831b0c11f6f23ffb51004db972';        -- 'sao bernardo do campo'
```

---

## Sessione 2 — Livello riconciliato, seconda metà (1 h)

**File**: `sql/24_reconciled_orders.sql`, `sql/25_reconciled_order_items.sql`, `sql/26_reconciled_payments.sql`, `sql/27_reconciled_reviews.sql`.

**Concetti del corso**: misure derivate, chiave naturale vs chiave "dichiarata", deduplicazione, aggregazione a una grana diversa da quella della sorgente.

**Cosa capire**
- `24_orders`: tutte le misure di consegna nascono qui, una volta sola: `delivery_days`, `estimated_days`, `delay_days`, `is_late`. Perché `is_late` confronta **date** e non timestamp: la data promessa non ha ora (è mezzanotte), confrontando i timestamp 1.292 ordini consegnati il giorno promesso sarebbero "in ritardo".
- `25_order_items`: `freight_ratio` e la distanza haversine. Da dove vengono le coordinate del cliente: dal CEP **dell'ordine** (`customer_order_map`), non da quello della persona (potrebbe essere cambiato). La distanza è per riga perché 1.278 ordini hanno più seller.
- `26_payments`: da più righe a una per ordine. `DISTINCT ON (order_id) ORDER BY payment_value DESC` = il tipo di pagamento principale; `max(installments)`, `sum(value)`.
- `27_reviews`: `review_id` non è una chiave (789 id su più ordini). La chiave naturale della review in questo dataset è l'ordine. Si tiene la più recente: `DISTINCT ON (order_id) ORDER BY answer_ts DESC NULLS LAST`. Perché non la media: la review è un giudizio, non una quantità.

**Prove da fare**
```sql
SELECT order_id, count(*) FROM staging.order_reviews GROUP BY 1 HAVING count(*) > 1 LIMIT 3;
SELECT * FROM reconciled.review WHERE order_id = '<uno di quelli>';
SELECT is_late, count(*) FROM reconciled.orders WHERE status = 'delivered' GROUP BY 1;   -- 6534 late, 8 NULL
```

---

## Sessione 3 — Lo schema a stella (1 h)

**File**: `sql/30_dw_dimensions.sql`, `sql/40_dw_facts.sql`, `sql/60_quality_checks.sql`, `docs/dfm/*.svg`, `docs/DESIGN.md` §4–6.

**Concetti del corso**: DFM (*fact, measures, dimensions, dimensional attributes, hierarchies, descriptive attributes, optional arcs*), grana (*grain / granularity*), schema a stella vs a fiocco di neve (*star vs snowflake*), chiavi surrogate (*surrogate keys*), dimensione degenere (*degenerate dimension*), dimensione con più ruoli (*role-playing dimension*), additività (*additive, semi-additive, non-additive measures*), costellazione di fatti (*fact constellation*) e *drill-across*.

**Cosa capire**
- Le sei dimensioni e le loro gerarchie: date (giorno → mese → trimestre → anno, più giorno della settimana), customer e seller (CEP → città → stato → regione), product (prodotto → categoria → macro-categoria), status e payment type (un solo livello).
- `dim_date` generata con `generate_series`: da min(purchase) a max(estimated/delivered), 800 giorni. Chiave `yyyymmdd` leggibile. Usata **tre volte** da `fact_order` (acquisto, consegna, promessa): dimensione con più ruoli.
- Perché **due fatti**: `fact_order_item` (riga: price, freight, distanza) e `fact_order` (ordine: consegna, pagamento, review). Copiare `review_score` sulle righe conta tre volte un ordine da tre pezzi in una media per categoria. È la risposta a "modellazione accurata" della FAQ Q10.
- `status_key` anche in `fact_order_item`: è una chiave, non una misura → nessun problema di additività, e permette lo slice "solo ordini consegnati" senza join fra i fatti.
- Perché **stella**: dimensioni piccole, gerarchie strette (ogni città in uno stato), caricamento una tantum → la ridondanza non costa e non crea anomalie; le query fanno un join per dimensione. Snowflake avrebbe senso con una `dim_geography` condivisa e mantenuta a parte, o con dimensioni grandi. Delfino chiede di **motivare**, non di scegliere snowflake.
- `60_quality_checks`: i sei controlli e perché ognuno esiste (nulla perso, nulla duplicato, i due fatti concordano sui totali, coerenza `is_late`/`delay_days`, calendario senza buchi).

**Prove da fare**
```sql
\d dw.fact_order
SELECT sum(total_price) FROM dw.fact_order;  SELECT sum(price) FROM dw.fact_order_item;   -- uguali
SELECT * FROM dw.dim_date WHERE full_date = '2017-11-24';
```

---

## Sessione 4 — Le sessioni OLAP (1 h)

**File**: `sql/olap/01…07.sql`, `docs/OLAP.md`.

**Concetti del corso**: operazioni OLAP — *roll-up, drill-down, slice, dice, pivot, drill-across*; `GROUP BY ROLLUP / CUBE / GROUPING SETS`, `GROUPING()`, *window functions*; viste materializzate (*materialized views*) come ottimizzazione fisica.

**Cosa capire, per sessione**
1. **ROLLUP** su (macro, categoria): `GROUPING()` dice a che livello sta la riga; la quota per livello usa una window `PARTITION BY GROUPING(...)`. Drill-down = stessa misura, un livello più fine.
2. **GROUPING SETS** ((regione), (regione, stato)) = due roll-up in una query. Drill-down alle città = slice su SP + group by città.
3. **Slice** temporale esplicito (mesi comparabili), **pivot** con `FILTER (WHERE year = …)`, `LAG` per la crescita mese su mese, drill-down al giorno (Black Friday).
4. **Dice** regione seller × regione cliente. **Drill-across**: seller e distanza stanno in `fact_order_item`, consegna in `fact_order` → join su `order_id`, ristretto agli ordini con un solo seller. Sapere perché la restrizione.
5. Bucket di `delay_days` con `CASE`, poi dice per regione e per trimestre. I numeri da ricordare: 4.03 → 2.71 → 1.67; penalità ≈ 2 stelle ovunque.
6. **CUBE** (macro, fascia di distanza): tutti i marginali in una query; `COALESCE(..., 'ALL')` per etichettare i totali.
7. **Window functions**: `rank()`, `sum() OVER (ORDER BY …)` per la quota cumulata; `FILTER` per "quanti seller per il 50 %".

**Viste materializzate**: cosa sono (risultato salvato di una query, con `REFRESH`), perché sono ottimizzazione fisica e non modello, i numeri misurati (270–1.900 ms → 4 ms). Le OLAP sono scritte sui fatti, non sulle viste, per tracciabilità.

**Prove da fare**: eseguire ogni file con `\i`, poi cambiare una cosa (un anno, una regione, un livello) e rieseguire.

---

## Sessione 5 — Il quadro e le domande (1 h)

**File**: `docs/DESIGN.md` intero, `docs/DEMO.md`, le slide.

- Rileggere DESIGN §3 (tabella problemi → soluzione → file) fino a saperla riprodurre a voce in 2 minuti.
- Provare la demo di 5 minuti con il cronometro, due volte.
- Provare le slide a voce con il cronometro: obiettivo 12 minuti, limite 15.
- Rispondere alle 20 domande sotto **senza guardare**.

---

## Venti domande probabili

1. **Qual è la grana dei fatti?** `fact_order_item`: una riga d'ordine. `fact_order`: un ordine. Dichiarata prima delle misure, perché decide cosa è additivo.
2. **Perché due fatti e non uno?** Le misure di consegna e la review sono dell'ordine: sulle righe verrebbero ripetute (9.803 ordini multi-riga) e le medie per prodotto sarebbero sbagliate. Dimensioni conformi + drill-across su `order_id` le ricollegano.
3. **Cos'è il livello riconciliato e perché lo avete fatto?** La vista integrata e pulita dell'operazionale da cui si carica il DW. Separa "aggiustare i dati" da "dargli forma per l'analisi"; ogni passo è SQL leggibile e rieseguibile; la FAQ dice che alza il voto.
4. **Stella o fiocco di neve, e perché?** Stella: dimensioni piccole, gerarchie strette caricate una volta, query con un join per dimensione. Snowflake se la geografia fosse una dimensione condivisa mantenuta a parte o se le dimensioni fossero grandi.
5. **Quali misure sono additive?** Prezzi, freight, totali, n. item: additive. Giorni, distanze, rapporti: solo come media. `review_score`: non additiva, un giudizio. Flag: contati (tasso).
6. **Perché una sola review per ordine?** `review_id` non è univoco (789 id su più ordini) e 547 ordini ne hanno due. La chiave naturale è l'ordine; si tiene la più recente. La media di due giudizi non ha senso.
7. **Cos'è una dimensione con più ruoli?** La stessa `dim_date` referenziata tre volte da `fact_order` (acquisto, consegna, promessa). Un'unica tabella, tre chiavi esterne.
8. **Cos'è una dimensione degenere?** `order_id`: identificatore nel fatto senza tabella dimensione. Serve per il drill-across e per contare gli ordini.
9. **Perché `status_key` sta anche nel fatto a grana riga?** È una chiave, non una misura: replicarla non altera somme né medie, e consente lo slice "consegnati" senza join fra fatti.
10. **Come avete gestito la geolocation?** Bounding box del Brasile, moda di (stato, città) per CEP, mediana di lat/lng → 19.010 righe da un milione. Mediana perché robusta ai punti sbagliati.
11. **Come calcolate la distanza?** Haversine sulle coordinate mediane del CEP del seller e del CEP dell'ordine. Approssimata (±10–20 km in città). NULL per 555 righe senza coordinate.
12. **Perché `is_late` confronta le date?** La data promessa non ha ora: confrontando i timestamp, 1.292 ordini consegnati il giorno promesso risulterebbero in ritardo.
13. **ROLLUP, CUBE, GROUPING SETS: differenza?** ROLLUP: prefissi della gerarchia (a,b), (a), (). CUBE: tutti i sottoinsiemi. GROUPING SETS: quelli che scelgo io. `GROUPING()` distingue i subtotali dai NULL veri.
14. **Cos'è il drill-across?** Combinare due fatti sulle dimensioni comuni (qui `order_id` + dimensioni conformi). Sessione 04: distanza e seller dalla riga, consegna dall'ordine.
15. **Cosa sono le viste materializzate e perché non le usate nelle OLAP?** Risultato precalcolato, aggiornato con `REFRESH`. Ottimizzazione fisica: le OLAP sono scritte sui fatti per tracciabilità; le viste servono a mostrare il guadagno (270–1.900 ms → 4 ms).
16. **Perché escludete alcuni mesi nella stagionalità?** Set–dic 2016 (329 ordini) e set–ott 2018 (20) sono parziali: confrontarli con mesi pieni falsa la crescita. Lo slice è esplicito e commentato.
17. **Il risultato più interessante?** Il ritardo rispetto alla promessa: sul giorno promesso 4.03, fino a una settimana dopo 2.71, oltre 1.67 (70 % di una stella). Penalità ≈ 2 stelle in ogni regione. Essere in anticipo non premia.
18. **Quali sono i limiti?** Coordinate per prefisso CEP; anni parziali; macro-categorie definite da noi; `total_paid` ≠ prezzo + freight su pochi ordini (voucher, arrotondamenti).
19. **Cosa controllano i quality check?** Conteggi = sorgenti; i due fatti concordano su prezzo e freight; `n_items` = righe; `is_late` coerente con `delay_days`; calendario senza buchi; ogni flag review ha un punteggio. Un fallimento ferma la build.
20. **Come si riproduce?** `uv sync`, `scripts/download_data.sh`, `scripts/run_all.sh` (~10 s, finisce con i check), poi `psql -f sql/olap/…`. Tutto nel repository, i dati grezzi si scaricano da Kaggle.
