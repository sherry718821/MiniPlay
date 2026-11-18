-- MINI PARTY · Supabase schema and RPC API
-- Run this entire file in Supabase SQL Editor as project owner.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.mp_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  host_name text not null,
  host_token_hash text not null,
  obs_token_hash text not null,
  max_players integer not null check (max_players between 2 and 32),
  rounds_total integer not null check (rounds_total in (3,5,10,15,20)),
  current_round integer not null default 0,
  status text not null default 'lobby' check (status in ('lobby','playing','finished','closed')),
  created_at timestamptz not null default now()
);
create table if not exists public.mp_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.mp_rooms(id) on delete cascade,
  nickname text not null,
  token_hash text not null,
  score integer not null default 0,
  is_host boolean not null default false,
  joined_at timestamptz not null default now(),
  unique(room_id,nickname),
  unique(token_hash)
);
create table if not exists public.mp_rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.mp_rooms(id) on delete cascade,
  round_no integer not null,
  game_type text not null,
  game_data jsonb not null,
  status text not null default 'playing' check(status in ('playing','completed')),
  started_at timestamptz not null default now(),
  opens_at timestamptz not null default now(),
  unique(room_id,round_no)
);
create table if not exists public.mp_answers (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.mp_rounds(id) on delete cascade,
  player_id uuid not null references public.mp_players(id) on delete cascade,
  answer jsonb not null,
  is_correct boolean not null default false,
  response_ms integer not null default 20000,
  points_awarded integer not null default 0,
  submitted_at timestamptz not null default now(),
  unique(round_id,player_id)
);

create index if not exists mp_players_room_idx on public.mp_players(room_id);
create index if not exists mp_rounds_room_idx on public.mp_rounds(room_id,round_no);
create index if not exists mp_answers_round_idx on public.mp_answers(round_id);

alter table public.mp_rooms enable row level security;
alter table public.mp_players enable row level security;
alter table public.mp_rounds enable row level security;
alter table public.mp_answers enable row level security;
-- No direct table access for browser roles. All access goes through checked RPC functions.
revoke all on public.mp_rooms,public.mp_players,public.mp_rounds,public.mp_answers from anon,authenticated;

create or replace function public.mp_make_game(p_kind text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare q text; a text; opts jsonb; n1 int; n2 int; seq text; target text;
begin
  if p_kind='quiz' then
    case floor(random()*6)::int
      when 0 then q:='대한민국의 수도는?'; a:='서울'; opts:=jsonb_build_array('서울','부산','인천','대전');
      when 1 then q:='태양계에서 가장 큰 행성은?'; a:='목성'; opts:=jsonb_build_array('목성','지구','화성','금성');
      when 2 then q:='한글을 창제한 왕은?'; a:='세종대왕'; opts:=jsonb_build_array('세종대왕','정조','태조','광개토대왕');
      when 3 then q:='물의 화학식은?'; a:='H2O'; opts:=jsonb_build_array('H2O','CO2','O2','NaCl');
      when 4 then q:='일주일은 며칠일까요?'; a:='7'; opts:=jsonb_build_array('5','6','7','8');
      else q:='세계에서 가장 큰 바다는?'; a:='태평양'; opts:=jsonb_build_array('태평양','대서양','인도양','북극해');
    end case;
    return jsonb_build_object('question',q,'answer',a,'options',opts,'description','제한 시간 안에 정답을 선택하세요.');
  elsif p_kind='math' then
    n1:=2+floor(random()*18)::int; n2:=2+floor(random()*18)::int;
    return jsonb_build_object('question',n1||' × '||n2||' = ?','answer',(n1*n2)::text,'description','계산 문제를 가장 빠르고 정확하게 풀어보세요.');
  elsif p_kind='memory' then
    seq:=lpad(floor(random()*100000)::text,5,'0');
    return jsonb_build_object('sequence',seq,'answer',seq,'description','잠깐 공개되는 숫자 다섯 자리를 기억하세요.');
  elsif p_kind='color' then
    a:=(array['빨강','파랑','초록','노랑'])[1+floor(random()*4)::int];
    opts:=jsonb_build_array('빨강','파랑','초록','노랑');
    return jsonb_build_object('question',a||'을(를) 선택하세요.','answer',a,'options',opts,'description','제시된 색깔을 선택하세요.');
  elsif p_kind='number' then
    a:=(1+floor(random()*10)::int)::text;
    return jsonb_build_object('question','1부터 10 사이의 숫자를 맞혀보세요.','answer',a,'description','정답 숫자를 입력하세요.');
  elsif p_kind='typing' then
    target:=(array['MINIPARTY','STREAM','VICTORY','GAMETIME','TOGETHER'])[1+floor(random()*5)::int];
    return jsonb_build_object('question',target,'answer',target,'description','화면에 표시된 영문 단어를 그대로 입력하세요.');
  else
    return jsonb_build_object('question','초록색 신호가 켜지면 클릭하세요.','answer','tap','description','신호가 켜지기 전에 누르면 무효입니다.');
  end if;
end $$;

create or replace function public.mp_open_round(p_room_id uuid,p_round_no integer)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare kinds text[]:=array['reaction','quiz','memory','math','color','number','typing']; k text;
begin
  k:=kinds[1+floor(random()*array_length(kinds,1))::int];
  insert into public.mp_rounds(room_id,round_no,game_type,game_data,started_at,opens_at)
  values(p_room_id,p_round_no,k,public.mp_make_game(k),now(),
    case when k='reaction' then now()+interval '2.5 seconds' else now() end);
  update public.mp_rooms set current_round=p_round_no,status='playing' where id=p_room_id;
end $$;

create or replace function public.mp_finalize_round(p_round_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if (select status from public.mp_rounds where id=p_round_id)='completed' then return; end if;
  with ranked as (
    select id,row_number() over(order by is_correct desc,response_ms asc,submitted_at asc) as pos
    from public.mp_answers where round_id=p_round_id and is_correct=true
  )
  update public.mp_answers a set points_awarded=case r.pos when 1 then 10 when 2 then 7 when 3 then 5 when 4 then 3 when 5 then 2 else 1 end
  from ranked r where a.id=r.id;
  update public.mp_players p set score=p.score+a.points_awarded
  from public.mp_answers a where a.round_id=p_round_id and a.player_id=p.id;
  update public.mp_rounds set status='completed' where id=p_round_id;
end $$;

create or replace function public.mp_create_room(p_nickname text,p_max_players integer default 8,p_rounds integer default 5)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_code text; v_host text:=encode(extensions.gen_random_bytes(24),'hex'); v_player text:=encode(extensions.gen_random_bytes(24),'hex'); v_obs text:=encode(extensions.gen_random_bytes(24),'hex'); v_room uuid;
begin
  if length(trim(coalesce(p_nickname,'')))<1 or length(trim(p_nickname))>18 then raise exception '닉네임은 1~18자로 입력해 주세요.'; end if;
  if p_max_players not between 2 and 32 then raise exception '최대 인원은 2~32명이어야 합니다.'; end if;
  if p_rounds not in (3,5,10,15,20) then raise exception '게임 판수를 확인해 주세요.'; end if;
  loop v_code:=upper(substr(encode(extensions.gen_random_bytes(5),'hex'),1,5)); exit when not exists(select 1 from public.mp_rooms where room_code=v_code); end loop;
  insert into public.mp_rooms(room_code,host_name,host_token_hash,obs_token_hash,max_players,rounds_total)
  values(v_code,trim(p_nickname),encode(extensions.digest(v_host,'sha256'),'hex'),encode(extensions.digest(v_obs,'sha256'),'hex'),p_max_players,p_rounds) returning id into v_room;
  insert into public.mp_players(room_id,nickname,token_hash,is_host) values(v_room,trim(p_nickname),encode(extensions.digest(v_player,'sha256'),'hex'),true);
  return jsonb_build_object('room_code',v_code,'host_token',v_host,'player_token',v_player,'obs_token',v_obs);
end $$;

create or replace function public.mp_join_room(p_room_code text,p_nickname text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; v_token text:=encode(extensions.gen_random_bytes(24),'hex');
begin
  if length(trim(coalesce(p_nickname,'')))<1 or length(trim(p_nickname))>18 then raise exception '닉네임은 1~18자로 입력해 주세요.'; end if;
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code)) for update;
  if not found or r.status not in ('lobby','playing') then raise exception '참가할 수 있는 게임방이 없습니다.'; end if;
  if (select count(*) from public.mp_players where room_id=r.id)>=r.max_players then raise exception '게임방 인원이 가득 찼습니다.'; end if;
  if exists(select 1 from public.mp_players where room_id=r.id and lower(nickname)=lower(trim(p_nickname))) then raise exception '이미 사용 중인 닉네임입니다.'; end if;
  insert into public.mp_players(room_id,nickname,token_hash) values(r.id,trim(p_nickname),encode(extensions.digest(v_token,'sha256'),'hex'));
  return jsonb_build_object('room_code',r.room_code,'player_token',v_token);
end $$;

create or replace function public.mp_get_state(p_room_code text,p_player_token text,p_host_token text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; me uuid; rd public.mp_rounds%rowtype; players jsonb; round_json jsonb;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code));
  if not found then raise exception '게임방을 찾을 수 없습니다.'; end if;
  select id into me from public.mp_players where room_id=r.id and token_hash=encode(extensions.digest(coalesce(p_player_token,''),'sha256'),'hex');
  if me is null and (p_host_token is null or r.host_token_hash<>encode(extensions.digest(p_host_token,'sha256'),'hex')) then raise exception '참가 인증이 만료되었습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'score',score,'is_host',is_host,'is_me',id=me) order by joined_at),'[]'::jsonb) into players from public.mp_players where room_id=r.id;
  select * into rd from public.mp_rounds where room_id=r.id and round_no=r.current_round;
  round_json:=null;
  if found then round_json:=jsonb_build_object('id',rd.id,'round_no',rd.round_no,'game_type',rd.game_type,'public_data',rd.game_data-'answer','opens_at',rd.opens_at,'status',rd.status); end if;
  return jsonb_build_object('room_code',r.room_code,'status',r.status,'max_players',r.max_players,'rounds_total',r.rounds_total,'current_round',r.current_round,'players',players,'round',round_json);
end $$;

create or replace function public.mp_submit_answer(p_room_code text,p_player_token text,p_answer jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; pl public.mp_players%rowtype; rd public.mp_rounds%rowtype; ok boolean:=false; ms integer;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code));
  if not found or r.status<>'playing' then raise exception '현재 진행 중인 게임이 없습니다.'; end if;
  select * into pl from public.mp_players where room_id=r.id and token_hash=encode(extensions.digest(coalesce(p_player_token,''),'sha256'),'hex');
  if not found then raise exception '참가 인증이 만료되었습니다.'; end if;
  select * into rd from public.mp_rounds where room_id=r.id and round_no=r.current_round and status='playing' for update;
  if not found then raise exception '이미 종료된 라운드입니다.'; end if;
  if exists(select 1 from public.mp_answers where round_id=rd.id and player_id=pl.id) then raise exception '이미 답안을 제출했습니다.'; end if;
  if rd.game_type='reaction' and now()<rd.opens_at then raise exception '너무 빨라요! 신호가 켜진 뒤 클릭해 주세요.'; end if;
  ms:=greatest(0,least(20000,(extract(epoch from (now()-rd.opens_at))*1000)::integer));
  if rd.game_type='reaction' then ok:=coalesce(p_answer->>'value','')='tap';
  else ok:=lower(trim(coalesce(p_answer->>'value','')))=lower(trim(coalesce(rd.game_data->>'answer',''))); end if;
  insert into public.mp_answers(round_id,player_id,answer,is_correct,response_ms) values(rd.id,pl.id,p_answer,ok,ms);
  if (select count(*) from public.mp_answers where round_id=rd.id)>=(select count(*) from public.mp_players where room_id=r.id) then perform public.mp_finalize_round(rd.id); end if;
  return jsonb_build_object('correct',ok,'message',case when ok then '정답입니다! 제출 완료.' else '제출 완료! 다음 라운드를 기다려 주세요.' end);
end $$;

create or replace function public.mp_start_game(p_room_code text,p_host_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.mp_rooms%rowtype;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code)) for update;
  if not found or r.host_token_hash<>encode(extensions.digest(coalesce(p_host_token,''),'sha256'),'hex') then raise exception '방장 권한이 없습니다.'; end if;
  if r.status<>'lobby' then raise exception '이미 시작된 게임방입니다.'; end if;
  if (select count(*) from public.mp_players where room_id=r.id)<1 then raise exception '참가자가 없습니다.'; end if;
  perform public.mp_open_round(r.id,1);
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.mp_advance_round(p_room_code text,p_host_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.mp_rooms%rowtype; rd public.mp_rounds%rowtype;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code)) for update;
  if not found or r.host_token_hash<>encode(extensions.digest(coalesce(p_host_token,''),'sha256'),'hex') then raise exception '방장 권한이 없습니다.'; end if;
  if r.status<>'playing' then raise exception '진행 중인 게임이 아닙니다.'; end if;
  select * into rd from public.mp_rounds where room_id=r.id and round_no=r.current_round;
  if rd.status='playing' then perform public.mp_finalize_round(rd.id); end if;
  if r.current_round>=r.rounds_total then update public.mp_rooms set status='finished' where id=r.id; return jsonb_build_object('finished',true); end if;
  perform public.mp_open_round(r.id,r.current_round+1);
  return jsonb_build_object('finished',false,'round',r.current_round+1);
end $$;

create or replace function public.mp_leave_room(p_room_code text,p_player_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; pl public.mp_players%rowtype;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code));
  if not found then return jsonb_build_object('ok',true); end if;
  select * into pl from public.mp_players where room_id=r.id and token_hash=encode(extensions.digest(coalesce(p_player_token,''),'sha256'),'hex');
  if not found then return jsonb_build_object('ok',true); end if;
  if pl.is_host then update public.mp_rooms set status='closed' where id=r.id; end if;
  delete from public.mp_players where id=pl.id;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.mp_get_obs_state(p_room_code text,p_obs_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; players jsonb;
begin
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code));
  if not found or r.obs_token_hash<>encode(extensions.digest(coalesce(p_obs_token,''),'sha256'),'hex') then raise exception 'OBS 인증 정보가 올바르지 않습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'score',score) order by score desc,joined_at),'[]'::jsonb) into players from public.mp_players where room_id=r.id;
  return jsonb_build_object('room_code',r.room_code,'status',r.status,'current_round',r.current_round,'rounds_total',r.rounds_total,'players',players);
end $$;

-- RPCs are the only public API. Internal helper functions are not executable by browser roles.
revoke all on function public.mp_make_game(text) from public,anon,authenticated;
revoke all on function public.mp_open_round(uuid,integer) from public,anon,authenticated;
revoke all on function public.mp_finalize_round(uuid) from public,anon,authenticated;
revoke all on function public.mp_create_room(text,integer,integer) from public;
revoke all on function public.mp_join_room(text,text) from public;
revoke all on function public.mp_get_state(text,text,text) from public;
revoke all on function public.mp_submit_answer(text,text,jsonb) from public;
revoke all on function public.mp_start_game(text,text) from public;
revoke all on function public.mp_advance_round(text,text) from public;
revoke all on function public.mp_leave_room(text,text) from public;
revoke all on function public.mp_get_obs_state(text,text) from public;
grant execute on function public.mp_create_room(text,integer,integer) to anon,authenticated;
grant execute on function public.mp_join_room(text,text) to anon,authenticated;
grant execute on function public.mp_get_state(text,text,text) to anon,authenticated;
grant execute on function public.mp_submit_answer(text,text,jsonb) to anon,authenticated;
grant execute on function public.mp_start_game(text,text) to anon,authenticated;
grant execute on function public.mp_advance_round(text,text) to anon,authenticated;
grant execute on function public.mp_leave_room(text,text) to anon,authenticated;
grant execute on function public.mp_get_obs_state(text,text) to anon,authenticated;


-- Nickname editing for anonymous room participants.
create or replace function public.mp_update_nickname(p_room_code text,p_player_token text,p_nickname text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r public.mp_rooms%rowtype; pl public.mp_players%rowtype;
begin
  if length(trim(coalesce(p_nickname,'')))<1 or length(trim(p_nickname))>18 then raise exception '닉네임은 1~18자로 입력해 주세요.'; end if;
  select * into r from public.mp_rooms where room_code=upper(trim(p_room_code));
  if not found then raise exception '게임방을 찾을 수 없습니다.'; end if;
  select * into pl from public.mp_players where room_id=r.id and token_hash=encode(extensions.digest(coalesce(p_player_token,''),'sha256'),'hex');
  if not found then raise exception '참가 인증이 만료되었습니다.'; end if;
  if exists(select 1 from public.mp_players where room_id=r.id and id<>pl.id and lower(nickname)=lower(trim(p_nickname))) then raise exception '이미 사용 중인 닉네임입니다.'; end if;
  update public.mp_players set nickname=trim(p_nickname) where id=pl.id;
  if pl.is_host then update public.mp_rooms set host_name=trim(p_nickname) where id=r.id; end if;
  return jsonb_build_object('ok',true,'nickname',trim(p_nickname));
end $$;
revoke all on function public.mp_update_nickname(text,text,text) from public;
grant execute on function public.mp_update_nickname(text,text,text) to anon,authenticated;
