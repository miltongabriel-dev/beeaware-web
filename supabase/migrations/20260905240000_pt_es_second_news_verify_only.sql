-- Follow-up-only check for 20260905230000's real trigger, which timed
-- out its own 60s poll (NoticiasAoMinutoAdapter processes 490 items). No
-- new trigger here — combined PT/ES news totals across all 4 sources
-- now live (RTP, La Vanguardia, Notícias ao Minuto, El Mundo).
do $$
declare
  r record;
begin
  for r in
    select ss.adapter_name, count(se.id) as events, count(se.geo_area_id) as with_geo_area
    from security_sources ss
    left join security_events se on se.source_id = ss.id
    where ss.adapter_name in ('PtNewsAdapter', 'EsNewsAdapter', 'NoticiasAoMinutoAdapter', 'ElMundoAdapter')
    group by ss.adapter_name
    order by ss.adapter_name
  loop
    raise notice 'adapter=% events=% geo_area_id_set=%', r.adapter_name, r.events, r.with_geo_area;
  end loop;

  for r in
    select country_code, count(*) as total
    from security_events
    where source_type = 'news' and country_code in ('PT', 'ES')
    group by country_code
  loop
    raise notice 'total news events: country=% total=%', r.country_code, r.total;
  end loop;
end $$;
