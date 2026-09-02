-- BeeAware Global roadmap — one-time manual news backfill for France,
-- Germany, Portugal and Spain.
--
-- Context: FrNewsAdapter/DeNewsAdapter/PtNewsAdapter/EsNewsAdapter only
-- ever see whatever is CURRENTLY in each source's RSS feed (typically
-- the last few days) — an RSS feed is not an archive, so the ~60-90
-- day "recent incidents" window these four countries are meant to
-- cover was almost empty going into this migration (the four crons
-- have only been running for a few days each). This migration
-- backfills that window with real, individually verified incidents
-- (WebSearch + WebFetch against the original article for each one,
-- 2026-09-02) rather than waiting weeks for the crons to accumulate
-- enough rows on their own.
--
-- Every row here is transparently sourced exactly like an automated
-- news adapter's own output: source_type='news' (never 'official' or
-- 'community' — see incident_bottom_sheet.dart's isApproximate
-- handling, which is what makes this honest rather than passing these
-- off as user reports), raw_payload carries the real article title
-- and a working link the user can open, and district/city match the
-- existing geo_areas naming for each country so the resolve_security_
-- event_geo_area() trigger links geo_area_id exactly as it would for
-- an adapter-sourced row.
--
-- Departure from every adapter to date: `location` is set to a real,
-- individually geocoded (Nominatim) point per incident — city or
-- neighbourhood-level, per event, not the département/Bundesland/
-- município CENTROID every FR/DE news event has used until now. This
-- is what 20260909090000_nearby_news_pins_use_real_location.sql exists
-- for: without it, all of a country's pins still stack on one point
-- regardless of how many distinct real locations are behind them.
-- geo_precision reflects the honest confidence of each specific point:
-- 'NEIGHBORHOOD' where the source article names a specific square/
-- street/quarter (geocoded to that place, not just the city),
-- 'MUNICIPALITY' where only the town/city itself is known.
--
-- occurred_at uses each article's own confirmed date, time normalised
-- to noon UTC (same simplification madrid_accidents.ts's file header
-- documents: a few hours of offset never changes which day/month an
-- event falls into, which is the only thing occurred_at drives
-- downstream). Two dates are the closest defensible reconstruction
-- rather than a confirmed exact day: Karlsruhe (article says "Saturday
-- afternoon", published 2026-08-24 — used the Saturday immediately
-- before) and Porto (day drawn from a search-engine synthesis of the
-- source article rather than a direct fetch, which 403'd — see
-- headline conflict below if this is ever revisited).

with events(
  country_code, source_adapter, source_record_id, event_category, event_type,
  occurred_at, lng, lat, geo_precision, location_confidence, district, city,
  severity, title, subtitle, link
) as (
  values
    -- ===== FRANCE =====
    ('FR', 'ManualResearch:FR3Regions', 'manual-fr-marseille-corniche-20260819', 'VIOLENCE', 'attempted_homicide',
     '2026-08-19T12:30:00Z'::timestamptz, 5.3629156, 43.2728391, 'NEIGHBORHOOD', 0.75, 'Bouches-du-Rhône', 'Marseille',
     'high', 'Tentative de meurtre sur la Corniche à Marseille',
     'Un homme agressé au couteau, l''assaillant hospitalisé',
     'https://france3-regions.franceinfo.fr/provence-alpes-cote-d-azur/bouches-du-rhone/marseille/tentative-de-meurtre-sur-la-corniche-a-marseille-un-homme-agresse-au-couteau-l-assaillant-hospitalise-3404317.html'),
    ('FR', 'ManualResearch:LyonMag', 'manual-fr-bron-collier-20260611', 'PROPERTY', 'robbery',
     '2026-06-11T17:40:00Z'::timestamptz, 4.9092352, 45.7337532, 'MUNICIPALITY', 0.5, 'Rhône', 'Bron',
     'medium', 'Une femme aspergée de gaz lacrymogène pour son collier à un arrêt de bus',
     'Secteur Bron Aviation, agglomération lyonnaise',
     'https://www.lyonmag.com/article/152517/une-sortie-de-travail-qui-vire-au-cauchemar-pres-de-lyon-une-femme-aspergee-de-gaz-lacrymogene-pour-son-collier-a-un-arret-de-bus'),
    ('FR', 'ManualResearch:LyonCapitale', 'manual-fr-caluire-chaine-or-20260825', 'PROPERTY', 'robbery',
     '2026-08-25T14:30:00Z'::timestamptz, 4.8423304, 45.7969952, 'NEIGHBORHOOD', 0.75, 'Rhône', 'Caluire-et-Cuire',
     'low', 'Nouveau vol à l''arraché dans l''agglomération lyonnaise',
     'Un sexagénaire agressé pour sa chaîne en or, quartier de Cuire-le-Bas',
     'https://www.lyoncapitale.fr/actualite/nouveau-vol-a-l-arrache-dans-l-agglomeration-lyonnaise-un-sexagenaire-agresse-pour-sa-chaine-en-or'),
    ('FR', 'ManualResearch:TitresPresse', 'manual-fr-paris-marais-20260830', 'VIOLENCE', 'assault',
     '2026-08-30T02:00:00Z'::timestamptz, 2.3607420, 48.8603823, 'NEIGHBORHOOD', 0.75, 'Paris', 'Paris',
     'high', 'Agression du président de FLAG! dans le Marais',
     'Violences aggravées et vol, suspect mis en examen',
     'https://www.titrespresse.com/19617902603/paris-pierre-picavet'),
    ('FR', 'ManualResearch:CNEWS', 'manual-fr-paris-11e-pieces-or-20260830', 'PROPERTY', 'theft',
     '2026-08-30T15:00:00Z'::timestamptz, 2.3797030, 48.8584160, 'NEIGHBORHOOD', 0.75, 'Paris', 'Paris',
     'low', 'Un homme vole 40 000 euros de pièces d''or dans un bar',
     '11e arrondissement, Café de France',
     'https://www.cnews.fr/france/2026-08-31/paris-un-homme-vole-40000-euros-de-pieces-dor-dans-un-bar-1911806'),

    -- ===== GERMANY =====
    ('DE', 'ManualResearch:RegionalspiegelSachsen', 'manual-de-dresden-adplatz-20260826', 'PROPERTY', 'robbery',
     '2026-08-26T23:15:00Z'::timestamptz, 13.6787334, 51.0434839, 'NEIGHBORHOOD', 0.75, 'Sachsen', 'Dresden',
     'high', 'Verdacht des Raubes und der gefährlichen Körperverletzung',
     'Amalie-Dietrich-Platz, zwei Beschuldigte in Untersuchungshaft',
     'https://www.regionalspiegel-sachsen.de/verdacht-des-raubes-und-der-gefaehrlichen-koerperverletzung-zwei-beschuldigte-in-haft-polizeimeldung-dresden-vom-28-08-2026'),
    ('DE', 'ManualResearch:NachrichtenHeute', 'manual-de-karlsruhe-raub81-20260822', 'PROPERTY', 'robbery',
     '2026-08-22T17:00:00Z'::timestamptz, 8.3680784, 49.0064054, 'NEIGHBORHOOD', 0.75, 'Baden-Württemberg', 'Karlsruhe',
     'medium', 'Zeugen nach mutmaßlichem Raubüberfall auf 81-Jährige gesucht',
     'Wichernstraße, Mühlburg',
     'https://www.nachrichten-heute.net/1734724-polizei-karlsruhe-ka-karlsruhe-zeugen-nach-mutmasslichem-raubueberfall-auf-81-jaehrige-gesucht.html'),
    ('DE', 'ManualResearch:DigitalDaily', 'manual-de-muenchen-schwabing-20260830', 'PROPERTY', 'robbery',
     '2026-08-30T22:30:00Z'::timestamptz, 11.5899503, 48.1689260, 'NEIGHBORHOOD', 0.75, 'Bayern', 'München',
     'medium', 'Raubüberfall in Schwabing',
     'Polizei sucht vier maskierte Männer',
     'https://digitaldaily.de/raubueberfall-in-schwabing-polizei-sucht-vier-maskierte-maenner/'),
    ('DE', 'ManualResearch:Presseportal', 'manual-de-frankfurt-ostend-20260723', 'VIOLENCE', 'assault',
     '2026-07-23T12:00:00Z'::timestamptz, 8.6999671, 50.1123728, 'NEIGHBORHOOD', 0.75, 'Hessen', 'Frankfurt am Main',
     'high', 'Aggressiver Ladendieb greift Supermarktmitarbeiter im Nachgang mit Messer an',
     'Frankfurt-Ostend, Zeugenaufruf',
     'https://www.presseportal.de/blaulicht/pm/4970/6320751'),
    ('DE', 'ManualResearch:Presseportal', 'manual-de-hamburg-stpauli-20260901', 'VIOLENCE', 'homicide',
     '2026-09-01T22:00:00Z'::timestamptz, 9.9594316, 53.5539347, 'NEIGHBORHOOD', 0.75, 'Hamburg', 'Hamburg',
     'high', 'Erste Erkenntnisse und Zeugenaufruf nach Tötungsdelikt in Hamburg-St. Pauli',
     'Lagerstraße, zwei Tote und ein Schwerverletzter',
     'https://www.presseportal.de/blaulicht/pm/6337/6344346'),
    ('DE', 'ManualResearch:PolizeiBerlin', 'manual-de-berlin-tempelhof-20260902', 'VIOLENCE', 'assault',
     '2026-09-02T16:25:00Z'::timestamptz, 13.3893312, 52.4487714, 'NEIGHBORHOOD', 0.75, 'Berlin', 'Berlin',
     'high', 'Mann von unbekannten Tätern mehrmals angeschossen und schwer verletzt',
     'Tempelhof-Schöneberg',
     'https://www.berlin.de/polizei/polizeimeldungen/2026/pressemitteilung.1709849.php'),

    -- ===== PORTUGAL =====
    ('PT', 'ManualResearch:CorreioDaManha', 'manual-pt-lisboa-baixa-relogio-20260823', 'PROPERTY', 'robbery',
     '2026-08-23T12:00:00Z'::timestamptz, -9.1370238, 38.7101237, 'NEIGHBORHOOD', 0.75, 'Lisboa', 'Lisboa',
     'medium', 'Assalto na Baixa de Lisboa rende 18 mil euros em relógio de luxo', null,
     'https://www.cmjornal.pt/portugal/detalhe/assalto-na-baixa-de-lisboa-rende-18-mil-euros-em-relogio-de-luxo'),
    ('PT', 'ManualResearch:CorreioDaManha', 'manual-pt-loures-casa-20260811', 'PROPERTY', 'robbery',
     '2026-08-11T12:00:00Z'::timestamptz, -9.1684512, 38.8308741, 'MUNICIPALITY', 0.5, 'Loures', 'Loures',
     'high', 'Mulher assaltada e agredida em casa em Loures',
     'Suspeitos levaram dois mil euros em anéis',
     'https://www.cmjornal.pt/portugal/detalhe/mulher-assaltada-e-agredida-em-casa-em-loures-suspeitos-levaram-dois-mil-euros-em-aneis'),
    ('PT', 'ManualResearch:CNNPortugal', 'manual-pt-lisboa-patek-20260809', 'PROPERTY', 'robbery',
     '2026-08-09T12:00:00Z'::timestamptz, -9.1370238, 38.7101237, 'MUNICIPALITY', 0.5, 'Lisboa', 'Lisboa',
     'medium', 'Casal assaltado e agredido em Lisboa',
     'Suspeitos levam relógio Patek Philippe de 90 mil euros',
     'https://cnnportugal.iol.pt/assalto/lisboa/casal-assaltado-e-agredido-em-lisboa-suspeitos-relogio-patek-philippe-de-90-mil-euros/20260809/6a78c100d34ed0733ba7ef71'),
    ('PT', 'ManualResearch:CorreioDaManha', 'manual-pt-coimbra-caixa-multibanco-20260719', 'PROPERTY', 'burglary',
     '2026-07-19T04:00:00Z'::timestamptz, -8.4291478, 40.2111874, 'MUNICIPALITY', 0.5, 'Coimbra', 'Coimbra',
     'medium', 'Assaltantes rebentam porta de supermercado e fazem explodir caixa multibanco em Coimbra', null,
     'https://www.cmjornal.pt/portugal/detalhe/assaltantes-rebentam-porta-de-supermercado-e-fazem-explodir-caixa-multibanco-em-coimbra'),
    ('PT', 'ManualResearch:BragaTV', 'manual-pt-porto-empreiteiro-20260708', 'VIOLENCE', 'homicide',
     '2026-07-08T22:00:00Z'::timestamptz, -8.6103497, 41.1502195, 'MUNICIPALITY', 0.5, 'Porto', 'Porto',
     'high', 'Empreiteiro do Porto morreu asfixiado após assalto', null,
     'https://bragatv.pt/empreiteiro-do-porto-morreu-asfixiado-apos-assalto/'),
    ('PT', 'ManualResearch:RTPNoticias', 'manual-pt-rabodepeixe-psp-20260821', 'VIOLENCE', 'police_intervention',
     '2026-08-21T12:00:00Z'::timestamptz, -25.5824158, 37.8142769, 'NEIGHBORHOOD', 0.75, 'Ribeira Grande', 'Rabo de Peixe',
     'medium', 'Agentes da PSP atacados em Rabo de Peixe', 'Avança inquérito criminal',
     'https://www.rtp.pt/noticias/pais/agentes-da-psp-atacados-em-rabo-de-peixe-avanca-inquerito-criminal_n1760735'),

    -- ===== SPAIN =====
    ('ES', 'ManualResearch:ElDiarioDeMadrid', 'manual-es-getafe-atraco-20260803', 'PROPERTY', 'robbery',
     '2026-08-03T12:00:00Z'::timestamptz, -3.7331808, 40.3070639, 'MUNICIPALITY', 0.5, 'Getafe', 'Getafe',
     'medium', 'Dos detenidos por cinco atracos en Madrid con pistolas, un hacha y un pico',
     'Getafe, 3 de agosto: tienda de alimentación',
     'https://www.eldiariodemadrid.es/articulo/sucesos-en-madrid/detenidos-asaltar-tiendas-alimentacion/20260826114213140063.html'),
    ('ES', 'ManualResearch:ElDiarioDeMadrid', 'manual-es-vallecas-atraco-20260810', 'PROPERTY', 'robbery',
     '2026-08-10T12:00:00Z'::timestamptz, -3.6591803, 40.3868601, 'NEIGHBORHOOD', 0.75, 'Madrid', 'Puente de Vallecas, Madrid',
     'medium', 'Dos detenidos por cinco atracos en Madrid con pistolas, un hacha y un pico',
     'Puente de Vallecas, 10 de agosto: establecimiento de alimentación',
     'https://www.eldiariodemadrid.es/articulo/sucesos-en-madrid/detenidos-asaltar-tiendas-alimentacion/20260826114213140063.html'),
    ('ES', 'ManualResearch:ElDiarioDeMadrid', 'manual-es-moratalaz-atraco-20260810', 'PROPERTY', 'robbery',
     '2026-08-10T18:00:00Z'::timestamptz, -3.6448737, 40.4059332, 'NEIGHBORHOOD', 0.75, 'Madrid', 'Moratalaz, Madrid',
     'high', 'Dos detenidos por cinco atracos en Madrid con pistolas, un hacha y un pico',
     'Moratalaz, 10 de agosto: tienda de alimentación, mobiliario dañado',
     'https://www.eldiariodemadrid.es/articulo/sucesos-en-madrid/detenidos-asaltar-tiendas-alimentacion/20260826114213140063.html'),
    ('ES', 'ManualResearch:ElDiarioDeMadrid', 'manual-es-coslada-atraco-20260812', 'PROPERTY', 'robbery',
     '2026-08-12T12:00:00Z'::timestamptz, -3.5552882, 40.4238020, 'MUNICIPALITY', 0.5, 'Coslada', 'Coslada',
     'medium', 'Dos detenidos por cinco atracos en Madrid con pistolas, un hacha y un pico',
     'Coslada, 12 de agosto: gasolinera',
     'https://www.eldiariodemadrid.es/articulo/sucesos-en-madrid/detenidos-asaltar-tiendas-alimentacion/20260826114213140063.html'),
    ('ES', 'ManualResearch:ElDiarioDeMadrid', 'manual-es-retiro-atraco-20260817', 'PROPERTY', 'robbery',
     '2026-08-17T12:00:00Z'::timestamptz, -3.6760566, 40.4111495, 'NEIGHBORHOOD', 0.75, 'Madrid', 'Retiro, Madrid',
     'medium', 'Dos detenidos por cinco atracos en Madrid con pistolas, un hacha y un pico',
     'Retiro, 17 de agosto: móvil dañado con un pico',
     'https://www.eldiariodemadrid.es/articulo/sucesos-en-madrid/detenidos-asaltar-tiendas-alimentacion/20260826114213140063.html'),
    ('ES', 'ManualResearch:Telecinco', 'manual-es-barcelona-raval-reloj-20260729', 'PROPERTY', 'robbery',
     '2026-07-29T03:30:00Z'::timestamptz, 2.1686823, 41.3798479, 'NEIGHBORHOOD', 0.75, 'Barcelona', 'El Raval, Barcelona',
     'medium', 'Un turista responde al robo de su reloj propinando una brutal paliza a uno de los ladrones', 'Barrio del Raval, Barcelona',
     'https://www.telecinco.es/noticias/sucesos/20260729/atraco-turista-barrio-raval-barcelona-reloj-paaliza_18_019835489.html')
)
insert into security_events (
  country_code, source_id, source_record_id, source_type, event_category, event_type,
  occurred_at, published_at, location, geo_precision, location_confidence,
  district, city, occurrence_count, severity, confidence_score, raw_payload
)
select
  e.country_code,
  ss.id,
  e.source_record_id,
  'news',
  e.event_category::security_event_category,
  e.event_type,
  e.occurred_at,
  e.occurred_at,
  st_setsrid(st_makepoint(e.lng, e.lat), 4326),
  e.geo_precision::geo_precision,
  e.location_confidence,
  e.district,
  e.city,
  1,
  e.severity,
  round((0.75 * e.location_confidence)::numeric, 3),
  jsonb_build_object('title', e.title, 'subtitle', e.subtitle, 'link', e.link)
from events e
join security_sources ss on ss.adapter_name = e.source_adapter
on conflict (source_id, source_record_id) do nothing;
