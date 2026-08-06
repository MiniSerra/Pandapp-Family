-- =====================================================================
-- Pandapp Family — reconciliació puntual de monedes (executar un sol cop)
-- =====================================================================
-- No és una migració estructural (per això no porta prefix "fase3-", i no
-- cal mantenir-la ni tornar-la a córrer): posa monedes.saldo al valor que
-- hauria tingut sempre si processar_punts_validats hagués donat monedes a
-- CADA completion validada des del principi (1 per cada 10 punts,
-- arrodonit avall), no només a la que creuava el llindar diari — MENYS el
-- que ja s'hagi gastat en bescanvis, si n'hi ha algun.
--
-- S'exclouen les completions de "Bonus de ratxa": són punts de sistema,
-- no d'una reclamació real, i mai han passat per processar_punts_validats
-- a ells mateixos (no han donat ni donaran monedes, ni abans ni ara).
-- Només compten participacions confirmades (confirmat = true) de
-- completions ja validades — el mateix criteri que fa servir el rànquing.
-- =====================================================================

insert into public.monedes (usuari_id, saldo)
select
  guanyades.usuari_id,
  greatest(guanyades.total - coalesce(gastades.total, 0), 0) as saldo
from (
  select p.usuari_id, sum(floor(p.punts_assignats / 10.0))::integer as total
  from public.participacions p
  join public.completions c on c.id = p.completion_id
  join public.activitats a on a.id = c.activitat_id
  where c.estat = 'validada'
    and p.confirmat = true
    and a.nom <> 'Bonus de ratxa'
  group by p.usuari_id
) guanyades
left join (
  select usuari_id, sum(cost_pagat)::integer as total
  from public.bescanvis
  group by usuari_id
) gastades on gastades.usuari_id = guanyades.usuari_id
on conflict (usuari_id) do update set saldo = excluded.saldo;

-- Comprovació: saldo de monedes per membre després de la reconciliació.
select pr.nom, m.saldo
from public.monedes m
join public.profiles pr on pr.id = m.usuari_id
order by m.saldo desc;
