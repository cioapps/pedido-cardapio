-- =====================================================================
-- 0007 - Banco no horário de Brasília
--   Datas continuam gravadas em timestamptz (instante exato); o fuso padrão
--   faz now(), current_date, to_char e o SQL Editor usarem o horário de Brasília.
--   Vale para as próximas conexões (a API reconecta sozinha).
-- =====================================================================
do $$
begin
  execute format('alter database %I set timezone to %L', current_database(), 'America/Sao_Paulo');
end $$;

-- Lojas novas já nascem com o fuso de Brasília (o padrão da coluna já é esse; reforço)
alter table public.empresas alter column fuso_horario set default 'America/Sao_Paulo';
update public.empresas set fuso_horario = 'America/Sao_Paulo' where fuso_horario is distinct from 'America/Sao_Paulo';
