-- =====================================================================
-- Pandapp Family — taula subscripcions_push (fase 4, notificacions push)
-- =====================================================================
-- Cada fila és una subscripció Web Push d'un dispositiu concret d'un
-- usuari (`endpoint`, `p256dh`, `auth` són els tres camps que retorna
-- `PushSubscription.toJSON()` del navegador). Un usuari pot tenir varis
-- dispositius subscrits alhora — per això `unique (usuari_id, endpoint)` en
-- lloc de clau primària per usuari_id, i no `usuari_id` sol.
--
-- El client hi escriu/llegeix directament amb RLS normal (com `likes` o
-- `comentaris`): no hi ha cap regla de negoci a protegir, només cal que
-- cadascú només pugui veure/crear/esborrar les seves pròpies subscripcions.
-- Qui SÍ ha de poder llegir subscripcions d'ALTRES usuaris (per exemple,
-- per notificar tota la família quan algú fa una activitat) és l'edge
-- function `enviar-push`, que hi accedeix amb la clau de servei
-- (service_role), que salta la RLS — mai des del client.
-- =====================================================================

create table public.subscripcions_push (
  id         uuid primary key default gen_random_uuid(),
  usuari_id  uuid not null references public.profiles (id) on delete cascade,
  endpoint   text not null,
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz not null default now(),

  unique (usuari_id, endpoint)
);

comment on table public.subscripcions_push is
  'Subscripcions Web Push per dispositiu (fase 4). El client hi escriu/llegeix directament (RLS): només les pròpies. enviar-push hi accedeix amb service_role per notificar altres usuaris.';

create index idx_subscripcions_push_usuari on public.subscripcions_push (usuari_id);

alter table public.subscripcions_push enable row level security;

create policy "subscripcions_push: veure les propies" on public.subscripcions_push
  for select
  to authenticated
  using (usuari_id = auth.uid());

create policy "subscripcions_push: crear les propies" on public.subscripcions_push
  for insert
  to authenticated
  with check (usuari_id = auth.uid());

-- Necessària per a upsert (subscriure el mateix dispositiu una segona
-- vegada, p. ex. si el navegador rota l'endpoint, actualitza en lloc de
-- duplicar gràcies a `unique (usuari_id, endpoint)`).
create policy "subscripcions_push: actualitzar les propies" on public.subscripcions_push
  for update
  to authenticated
  using (usuari_id = auth.uid())
  with check (usuari_id = auth.uid());

create policy "subscripcions_push: esborrar les propies" on public.subscripcions_push
  for delete
  to authenticated
  using (usuari_id = auth.uid());
