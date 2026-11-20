-- Cut streams are charged from what actually streamed (the proxy stores the input estimate per call)
alter table public.proxy_inflight add column if not exists est_in bigint;
