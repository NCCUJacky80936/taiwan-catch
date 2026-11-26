create schema taiwan_catch;
revoke all on schema taiwan_catch from public;
grant usage on schema taiwan_catch to anon;

create table taiwan_catch.scores (
  id bigint generated always as identity primary key,
  round_id uuid not null unique,
  name text not null check (char_length(btrim(name)) between 1 and 24 and name !~ '[[:cntrl:]]'),
  score integer not null check (score >= 0 and score % 10 = 0)
);
create index scores_rank_order on taiwan_catch.scores (score desc, id);

alter table taiwan_catch.scores enable row level security;
grant select (id, round_id, name, score) on taiwan_catch.scores to anon;
grant insert (round_id, name, score) on taiwan_catch.scores to anon;
grant usage on sequence taiwan_catch.scores_id_seq to anon;
create policy score_read on taiwan_catch.scores for select to anon using (true);
create policy score_add on taiwan_catch.scores for insert to anon with check (true);

create function public.taiwan_catch_top_scores()
returns jsonb
language sql stable security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'score', score)
    order by score desc, id), '[]'::jsonb)
  from (
    select id, name, score
    from taiwan_catch.scores
    order by score desc, id
    limit 10
  ) as top_scores;
$$;

create function public.taiwan_catch_submit_score(p_round_id uuid, p_name text, p_score integer)
returns jsonb
language plpgsql volatile security invoker
set search_path = ''
as $$
declare
  player_name text := btrim(p_name);
  cutoff integer;
  accepted boolean;
begin
  if p_round_id is null or player_name is null or char_length(player_name) not between 1 and 24
    or player_name ~ '[[:cntrl:]]' or p_score is null or p_score < 0 or p_score % 10 <> 0 then
    raise exception 'Invalid name or score.' using errcode = '22023';
  end if;

  -- Concurrent submissions share one cutoff and keep the first entry on a tie.
  perform pg_advisory_xact_lock(69420381, 37861911);
  select exists (
    select 1 from taiwan_catch.scores where round_id = p_round_id
  ) into accepted;

  if not accepted then
    select score into cutoff
    from taiwan_catch.scores
    order by score desc, id
    offset 9 limit 1;

    accepted := cutoff is null or p_score > cutoff;
    if accepted then
      insert into taiwan_catch.scores (round_id, name, score)
      values (p_round_id, player_name, p_score);
    end if;
  end if;

  return jsonb_build_object('accepted', accepted, 'ranks', public.taiwan_catch_top_scores());
end;
$$;

revoke all on function public.taiwan_catch_top_scores() from public, anon, authenticated;
revoke all on function public.taiwan_catch_submit_score(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.taiwan_catch_top_scores() to anon;
grant execute on function public.taiwan_catch_submit_score(uuid, text, integer) to anon;

