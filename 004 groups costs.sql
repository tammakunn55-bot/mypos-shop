-- =====================================================================
-- 004_groups_costs.sql — จัดกลุ่มสินค้าหลายขนาด + ตั้งราคาทุนที่ว่างอัตโนมัติ
-- รันทั้งไฟล์ใน Supabase > SQL Editor หนึ่งครั้ง (รันซ้ำได้ ข้อมูลเดิมไม่หาย)
-- =====================================================================

-- 1) คอลัมน์กลุ่มสินค้า (ชื่อกลุ่มเดียวกัน = แสดงรวมกลุ่มเดียวกัน ถ้าเว้นว่างจะจัดตามชื่อสินค้าที่ซ้ำกัน)
alter table products add column if not exists group_name text;
create index if not exists products_group_idx on products (group_name) where group_name is not null;

-- 2) ตั้งราคาทุนที่ยังเป็น 0 ให้เท่ากับสัดส่วนของราคาขาย (ค่าเริ่มต้น 80%)
--    p_apply = false → นับจำนวนที่จะถูกเปลี่ยนเฉยๆ (ไม่แก้ข้อมูล)   p_apply = true → แก้จริง
create or replace function fill_missing_costs(p_ratio numeric default 0.8, p_apply boolean default false)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not is_owner() then raise exception 'เฉพาะเจ้าของร้านเท่านั้น'; end if;
  if p_ratio is null or p_ratio <= 0 or p_ratio > 1.5 then raise exception 'สัดส่วนไม่ถูกต้อง'; end if;
  if p_apply then
    update product_units set cost = round(price * p_ratio, 2) where coalesce(cost, 0) = 0 and price > 0;
    get diagnostics n = row_count;
  else
    select count(*) into n from product_units where coalesce(cost, 0) = 0 and price > 0;
  end if;
  return n;
end $$;

-- 3) จัดกลุ่มอัตโนมัติ: สินค้าที่ไม่มีช่อง "ขนาด" แต่ชื่อลงท้ายด้วยตัวเลข/ขนาด เช่น "สามทาง PPR 20" "สามทาง PPR 25"
--    → ตั้งกลุ่มเป็น "สามทาง PPR" (เฉพาะกรณีที่มีอย่างน้อย 2 ขนาด ไม่แก้ชื่อสินค้า)
create or replace view auto_group_candidates as
with b as (
  select id, name,
         trim(regexp_replace(name, '\s+[0-9]+([./-][0-9]+)*\s?("|นิ้ว|มิล|มม\.?|mm|cm|ซม\.?)?$', '', 'i')) as base
  from products where group_name is null and coalesce(spec, '') = ''
)
select id, name, base from b
where base <> '' and base <> name
  and base in (select base from b where base <> name group by base having count(*) >= 2);
revoke all on auto_group_candidates from anon, authenticated;

create or replace function auto_group_products(p_mode text default 'preview') returns jsonb
language plpgsql security definer set search_path = public as $$
declare n integer; g integer; ex jsonb;
begin
  if not is_owner() then raise exception 'เฉพาะเจ้าของร้านเท่านั้น'; end if;
  if p_mode = 'clear' then
    update products set group_name = null where group_name is not null;
    get diagnostics n = row_count;
    return jsonb_build_object('mode', 'clear', 'products', n);
  end if;
  select count(*), count(distinct base) into n, g from auto_group_candidates;
  select coalesce(jsonb_agg(jsonb_build_object('base', x.base, 'name', x.name)), '[]'::jsonb) into ex
    from (select base, name from auto_group_candidates order by base, name limit 12) x;
  if p_mode = 'apply' then
    update products p set group_name = c.base from auto_group_candidates c where p.id = c.id;
  end if;
  return jsonb_build_object('mode', p_mode, 'products', n, 'groups', g, 'examples', ex);
end $$;

revoke execute on function fill_missing_costs(numeric, boolean) from public, anon;
revoke execute on function auto_group_products(text) from public, anon;
grant  execute on function fill_missing_costs(numeric, boolean) to authenticated;
grant  execute on function auto_group_products(text) to authenticated;

notify pgrst, 'reload schema';
