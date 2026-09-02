-- BeeAware Global roadmap — security_sources rows for the manual
-- FR/DE/PT/ES news backfill (20260909110000). Each row here is one
-- REAL outlet whose article is cited on at least one backfilled event
-- — same shape as an adapter's own source() registration, except
-- there's no recurring TS adapter behind these (this is a one-time
-- research pass over the last ~3 months of published incidents, not a
-- live feed), so adapter_name uses a `ManualResearch:` prefix to keep
-- it distinct from any real registered adapter and out of the
-- ingest-security-sources health-check loop (nothing calls
-- getAdapter() with these names).
insert into security_sources (country_code, name, organisation, source_type, source_url, adapter_name, refresh_frequency, active)
values
  ('FR', 'France 3 Régions — Provence-Alpes-Côte d''Azur', 'France Télévisions', 'news', 'https://france3-regions.franceinfo.fr', 'ManualResearch:FR3Regions', 'one-time backfill', true),
  ('FR', 'LyonMag', 'LyonMag', 'news', 'https://www.lyonmag.com', 'ManualResearch:LyonMag', 'one-time backfill', true),
  ('FR', 'Lyon Capitale', 'Lyon Capitale', 'news', 'https://www.lyoncapitale.fr', 'ManualResearch:LyonCapitale', 'one-time backfill', true),
  ('FR', 'Titres Presse', 'Titres Presse', 'news', 'https://www.titrespresse.com', 'ManualResearch:TitresPresse', 'one-time backfill', true),
  ('FR', 'CNEWS', 'CNEWS', 'news', 'https://www.cnews.fr', 'ManualResearch:CNEWS', 'one-time backfill', true),
  ('DE', 'Regionalspiegel Sachsen', 'Regionalspiegel Sachsen', 'news', 'https://www.regionalspiegel-sachsen.de', 'ManualResearch:RegionalspiegelSachsen', 'one-time backfill', true),
  ('DE', 'Nachrichten Heute', 'Nachrichten Heute', 'news', 'https://www.nachrichten-heute.net', 'ManualResearch:NachrichtenHeute', 'one-time backfill', true),
  ('DE', 'Digital Daily', 'Digital Daily', 'news', 'https://digitaldaily.de', 'ManualResearch:DigitalDaily', 'one-time backfill', true),
  ('DE', 'Presseportal (Polizei-Pressemeldungen)', 'dpa-ots / Polizeipressestellen', 'news', 'https://www.presseportal.de', 'ManualResearch:Presseportal', 'one-time backfill', true),
  ('DE', 'Polizei Berlin — Pressemeldungen', 'Polizei Berlin', 'news', 'https://www.berlin.de/polizei/polizeimeldungen', 'ManualResearch:PolizeiBerlin', 'one-time backfill', true),
  ('PT', 'Correio da Manhã', 'Cofina Media', 'news', 'https://www.cmjornal.pt', 'ManualResearch:CorreioDaManha', 'one-time backfill', true),
  ('PT', 'CNN Portugal', 'Medialivre', 'news', 'https://cnnportugal.iol.pt', 'ManualResearch:CNNPortugal', 'one-time backfill', true),
  ('PT', 'BragaTV', 'BragaTV', 'news', 'https://bragatv.pt', 'ManualResearch:BragaTV', 'one-time backfill', true),
  ('PT', 'RTP Notícias', 'Rádio e Televisão de Portugal', 'news', 'https://www.rtp.pt', 'ManualResearch:RTPNoticias', 'one-time backfill', true),
  ('ES', 'El Diario de Madrid', 'El Diario de Madrid', 'news', 'https://www.eldiariodemadrid.es', 'ManualResearch:ElDiarioDeMadrid', 'one-time backfill', true),
  ('ES', 'Telecinco', 'Mediaset España', 'news', 'https://www.telecinco.es', 'ManualResearch:Telecinco', 'one-time backfill', true)
on conflict do nothing;
