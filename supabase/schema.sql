-- Gia phả Họ tộc Lê Công · schema v1
-- Tài khoản tự quản (SĐT + mật khẩu băm bcrypt). Mọi truy cập đi qua hàm RPC kiểm tra phiên đăng nhập.
create extension if not exists pgcrypto with schema extensions;

create table public.persons(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  alias text,
  gender text not null default 'nam' check (gender in ('nam','nu')),
  gen int not null default 1,
  parent_id uuid references public.persons(id) on delete set null,
  mother_id uuid references public.persons(id) on delete set null,
  spouse_of uuid references public.persons(id) on delete set null,
  birth_order int,
  born_d int, born_m int, born_y int,
  died boolean not null default false,
  died_d int, died_m int, died_leap boolean default false, died_y int,
  burial text, place text, phone text, job text, note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_users(
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  name text not null,
  pass_hash text not null,
  role text not null default 'member' check (role in ('admin','member')),
  status text not null default 'pending' check (status in ('pending','active','rejected')),
  person_id uuid references public.persons(id) on delete set null,
  rel text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create table public.sessions(
  token uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '180 days'
);

create table public.change_requests(
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('add','edit','delete')),
  target_id uuid references public.persons(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  why text,
  link_self boolean not null default false,
  status text not null default 'pending' check (status in ('pending','done','rejected')),
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

alter table public.persons enable row level security;
alter table public.app_users enable row level security;
alter table public.sessions enable row level security;
alter table public.change_requests enable row level security;
revoke all on public.persons, public.app_users, public.sessions, public.change_requests from anon, authenticated;

-- ---------- helpers (không cấp quyền gọi trực tiếp) ----------
create or replace function public._norm_phone(p text) returns text language sql immutable
set search_path = public as $$ select regexp_replace(coalesce(p,''),'\D','','g') $$;

create or replace function public._user(p_token uuid) returns public.app_users
language plpgsql security definer set search_path = public as $$
declare u public.app_users;
begin
  select a.* into u from public.sessions s join public.app_users a on a.id=s.user_id
   where s.token=p_token and s.expires_at>now() and a.status='active';
  if u.id is null then raise exception 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'; end if;
  return u;
end $$;

create or replace function public._admin(p_token uuid) returns public.app_users
language plpgsql security definer set search_path = public as $$
declare u public.app_users;
begin
  u := public._user(p_token);
  if u.role<>'admin' then raise exception 'Chỉ Admin được làm việc này.'; end if;
  return u;
end $$;

create or replace function public._i(d jsonb,k text) returns int language sql immutable
set search_path = public as $$ select nullif(d->>k,'')::int $$;
create or replace function public._t(d jsonb,k text) returns text language sql immutable
set search_path = public as $$ select nullif(btrim(d->>k),'') $$;
create or replace function public._u(d jsonb,k text) returns uuid language sql immutable
set search_path = public as $$ select nullif(d->>k,'')::uuid $$;

create or replace function public._apply(c public.change_requests) returns uuid
language plpgsql security definer set search_path = public as $$
declare d jsonb := c.data; nid uuid; g int; par uuid; sp uuid;
begin
  if c.type='add' then
    par := public._u(d,'parent_id'); sp := public._u(d,'spouse_of');
    g := coalesce((select gen+1 from persons where id=par),(select gen from persons where id=sp),public._i(d,'gen'),1);
    insert into persons(name,alias,gender,gen,parent_id,mother_id,spouse_of,birth_order,born_d,born_m,born_y,died,died_d,died_m,died_leap,died_y,burial,place,phone,job,note)
    values(public._t(d,'name'),public._t(d,'alias'),coalesce(public._t(d,'gender'),'nam'),g,par,public._u(d,'mother_id'),sp,public._i(d,'birth_order'),
      public._i(d,'born_d'),public._i(d,'born_m'),public._i(d,'born_y'),coalesce((d->>'died')::boolean,false),
      public._i(d,'died_d'),public._i(d,'died_m'),coalesce((d->>'died_leap')::boolean,false),public._i(d,'died_y'),
      public._t(d,'burial'),public._t(d,'place'),public._t(d,'phone'),public._t(d,'job'),public._t(d,'note'))
    returning id into nid;
    if c.link_self and c.created_by is not null then update app_users set person_id=nid where id=c.created_by; end if;
    return nid;
  elsif c.type='edit' then
    update persons p set
      name=case when d?'name' then coalesce(public._t(d,'name'),p.name) else p.name end,
      alias=case when d?'alias' then public._t(d,'alias') else p.alias end,
      gender=case when d?'gender' then coalesce(public._t(d,'gender'),p.gender) else p.gender end,
      parent_id=case when d?'parent_id' then public._u(d,'parent_id') else p.parent_id end,
      mother_id=case when d?'mother_id' then public._u(d,'mother_id') else p.mother_id end,
      spouse_of=case when d?'spouse_of' then public._u(d,'spouse_of') else p.spouse_of end,
      birth_order=case when d?'birth_order' then public._i(d,'birth_order') else p.birth_order end,
      gen=case when d?'gen' then coalesce(public._i(d,'gen'),p.gen) else p.gen end,
      born_d=case when d?'born_d' then public._i(d,'born_d') else p.born_d end,
      born_m=case when d?'born_m' then public._i(d,'born_m') else p.born_m end,
      born_y=case when d?'born_y' then public._i(d,'born_y') else p.born_y end,
      died=case when d?'died' then coalesce((d->>'died')::boolean,false) else p.died end,
      died_d=case when d?'died_d' then public._i(d,'died_d') else p.died_d end,
      died_m=case when d?'died_m' then public._i(d,'died_m') else p.died_m end,
      died_leap=case when d?'died_leap' then coalesce((d->>'died_leap')::boolean,false) else p.died_leap end,
      died_y=case when d?'died_y' then public._i(d,'died_y') else p.died_y end,
      burial=case when d?'burial' then public._t(d,'burial') else p.burial end,
      place=case when d?'place' then public._t(d,'place') else p.place end,
      phone=case when d?'phone' then public._t(d,'phone') else p.phone end,
      job=case when d?'job' then public._t(d,'job') else p.job end,
      note=case when d?'note' then public._t(d,'note') else p.note end,
      updated_at=now()
    where p.id=c.target_id;
    -- đời tính lại theo cha hoặc vợ/chồng nếu có
    update persons p set gen=coalesce((select gen+1 from persons where id=p.parent_id),(select gen from persons where id=p.spouse_of),p.gen) where p.id=c.target_id;
    return c.target_id;
  elsif c.type='delete' then
    if exists(select 1 from persons where parent_id=c.target_id) then raise exception 'Người này còn con trong gia phả. Xóa hoặc chuyển các con trước.'; end if;
    delete from persons where id=c.target_id or spouse_of=c.target_id and not exists(select 1 from persons k where k.parent_id=persons.id);
    return c.target_id;
  end if;
  return null;
end $$;

-- ---------- API công khai ----------
create or replace function public.register(p_phone text,p_name text,p_pass text,p_rel text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare ph text := public._norm_phone(p_phone);
begin
  if length(ph)<9 then raise exception 'Số điện thoại chưa đúng.'; end if;
  if coalesce(length(p_pass),0)<6 then raise exception 'Mật khẩu cần ít nhất 6 ký tự.'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'Nhập họ và tên.'; end if;
  if exists(select 1 from app_users where phone=ph) then raise exception 'Số điện thoại này đã đăng ký.'; end if;
  insert into app_users(phone,name,pass_hash,rel) values(ph,btrim(p_name),crypt(p_pass,gen_salt('bf')),nullif(btrim(p_rel),''));
  return 'pending';
end $$;

create or replace function public.login(p_phone text,p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u app_users; t uuid;
begin
  select * into u from app_users where phone=public._norm_phone(p_phone);
  if u.id is null or u.pass_hash<>crypt(p_pass,u.pass_hash) then raise exception 'Số điện thoại hoặc mật khẩu chưa đúng.'; end if;
  if u.status='pending' then raise exception 'Tài khoản đang chờ Ban quản trị duyệt.'; end if;
  if u.status='rejected' then raise exception 'Tài khoản chưa được chấp nhận. Liên hệ Ban quản trị.'; end if;
  delete from sessions where expires_at<now();
  insert into sessions(user_id) values(u.id) returning token into t;
  return jsonb_build_object('token',t);
end $$;

create or replace function public.logout(p_token uuid) returns void
language sql security definer set search_path = public as $$ delete from sessions where token=p_token $$;

create or replace function public.get_data(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u app_users; res jsonb;
begin
  u := public._user(p_token);
  res := jsonb_build_object(
    'me',jsonb_build_object('id',u.id,'name',u.name,'phone',u.phone,'role',u.role,'person_id',u.person_id),
    'persons',coalesce((select jsonb_agg(to_jsonb(p) - 'created_at' - 'updated_at') from persons p),'[]'::jsonb),
    'my_pending',(select count(*) from change_requests where created_by=u.id and status='pending'));
  if u.role='admin' then
    res := res || jsonb_build_object(
      'users',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'phone',a.phone,'role',a.role,'status',a.status,'person_id',a.person_id,'rel',a.rel,'created_at',a.created_at,'decided_at',a.decided_at) order by a.created_at desc) from app_users a),'[]'::jsonb),
      'changes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'type',c.type,'target_id',c.target_id,'data',c.data,'why',c.why,'link_self',c.link_self,'status',c.status,'created_at',c.created_at,'decided_at',c.decided_at,'by',(select name from app_users where id=c.created_by)) order by c.created_at desc)
                 from (select * from change_requests order by created_at desc limit 60) c),'[]'::jsonb));
  end if;
  return res;
end $$;

create or replace function public.propose(p_token uuid,p_type text,p_target uuid,p_data jsonb,p_why text,p_link_self boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare u app_users; c change_requests;
begin
  u := public._user(p_token);
  if p_type not in ('add','edit','delete') then raise exception 'Loại yêu cầu không hợp lệ.'; end if;
  if p_type='add' and public._t(p_data,'name') is null then raise exception 'Nhập họ và tên.'; end if;
  if p_type='delete' and u.role<>'admin' then raise exception 'Chỉ Admin được xóa người khỏi gia phả.'; end if;
  insert into change_requests(type,target_id,data,why,link_self,created_by,status)
    values(p_type,p_target,coalesce(p_data,'{}'::jsonb),nullif(btrim(p_why),''),coalesce(p_link_self,false),u.id,'pending') returning * into c;
  if u.role='admin' then
    perform public._apply(c);
    update change_requests set status='done',decided_at=now() where id=c.id;
    return 'done';
  end if;
  return 'pending';
end $$;

create or replace function public.decide_change(p_token uuid,p_id uuid,p_ok boolean) returns text
language plpgsql security definer set search_path = public as $$
declare c change_requests;
begin
  perform public._admin(p_token);
  select * into c from change_requests where id=p_id and status='pending';
  if c.id is null then raise exception 'Yêu cầu này đã được xử lý.'; end if;
  if p_ok then perform public._apply(c); end if;
  update change_requests set status=case when p_ok then 'done' else 'rejected' end,decided_at=now() where id=p_id;
  return 'ok';
end $$;

create or replace function public.decide_user(p_token uuid,p_id uuid,p_ok boolean,p_person uuid default null) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform public._admin(p_token);
  update app_users set status=case when p_ok then 'active' else 'rejected' end,
     person_id=coalesce(p_person,person_id),decided_at=now() where id=p_id;
  return 'ok';
end $$;

create or replace function public.link_user(p_token uuid,p_user uuid,p_person uuid) returns text
language plpgsql security definer set search_path = public as $$
begin perform public._admin(p_token); update app_users set person_id=p_person where id=p_user; return 'ok'; end $$;

create or replace function public.set_role(p_token uuid,p_user uuid,p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare u app_users;
begin
  u := public._admin(p_token);
  if p_user=u.id then raise exception 'Không tự đổi quyền của chính mình.'; end if;
  update app_users set role=p_role where id=p_user; return 'ok';
end $$;

create or replace function public.change_password(p_token uuid,p_old text,p_new text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare u app_users;
begin
  u := public._user(p_token);
  if u.pass_hash<>crypt(p_old,u.pass_hash) then raise exception 'Mật khẩu hiện tại chưa đúng.'; end if;
  if coalesce(length(p_new),0)<6 then raise exception 'Mật khẩu mới cần ít nhất 6 ký tự.'; end if;
  update app_users set pass_hash=crypt(p_new,gen_salt('bf')) where id=u.id;
  delete from sessions where user_id=u.id and token<>p_token;
  return 'ok';
end $$;

create or replace function public.reset_password(p_token uuid,p_user uuid,p_new text) returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._admin(p_token);
  if coalesce(length(p_new),0)<6 then raise exception 'Mật khẩu cần ít nhất 6 ký tự.'; end if;
  update app_users set pass_hash=crypt(p_new,gen_salt('bf')) where id=p_user;
  delete from sessions where user_id=p_user;
  return 'ok';
end $$;

-- quyền gọi
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.register(text,text,text,text), public.login(text,text), public.logout(uuid),
  public.get_data(uuid), public.propose(uuid,text,uuid,jsonb,text,boolean), public.decide_change(uuid,uuid,boolean),
  public.decide_user(uuid,uuid,boolean,uuid), public.link_user(uuid,uuid,uuid), public.set_role(uuid,uuid,text),
  public.change_password(uuid,text,text), public.reset_password(uuid,uuid,text) to anon;
