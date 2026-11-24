-- 0.18.1: el panel ve los cupos de sede de un negocio antes de dar más.
-- Solo lectura. Devuelve el total que puede tener (branch_allowance), cuántas sedes
-- tiene abiertas y los cupos vigentes con su fecha de fin.

create or replace function public.admin_branch_slots(p_business_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_require('SUPPORT');
  return jsonb_build_object(
    'allowance', public.branch_allowance(p_business_id),
    'open', (select count(*) from public.branches b where b.business_id = p_business_id and b.status = 'ACTIVE'),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object('slots', s.slots, 'ends_at', s.ends_at, 'source', s.source) order by s.ends_at)
      from public.branch_slots s
      where s.business_id = p_business_id and s.ends_at > now()
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_branch_slots(text) from public, anon;
grant execute on function public.admin_branch_slots(text) to authenticated;
