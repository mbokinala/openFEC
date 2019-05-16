/*
This is to solve issue #3736
the calculation here for the election_year is similar to the election_yr_to_be_included column in ofec_cand_cmte_linkage table, but not exactly the same.  
The purpose of election_yr_to_be_included is to calculated the election_cycle the cycle financial data belongs to and an odd year will be rounded up and folded into its even year cycle.  
Here the election_year is for the election year, an odd election year need to be preserved, separated from its even year cycle.

The calculation is based on the fec_election_yr, the cand_election_yr, the cycle length (6, 4, 2), the next_election 
Simple and straight foward rules first, followed by more complicated rules.  
NOTE: there are some cand_id (219 out of 40152) that has one election_yr's data does not fit the fec_election_yr and candidate_election_yr and can not fit in any of the following rule. 

cycles,
election_years,
election_districts,
active_through
are still based on the original cand_election_yr from disclosure.cand_valid_fec_yr
so the interface will not be impacted.
Only candidate_election_year information is updated 
*/
-- ---------------------------------
-- public.ofec_candidate_history_mv
-- ---------------------------------
DROP MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_mv_tmp;

CREATE MATERIALIZED VIEW public.ofec_candidate_history_mv_tmp AS 
WITH
cycle_data_available AS (
	select max(fec_election_yr) max_cycle_available
	,min(fec_election_yr) min_cycle_available
	from disclosure.cand_valid_fec_yr
), election_yr AS (
    SELECT cand_id,
    cand_election_yr
    FROM disclosure.cand_valid_fec_yr
    GROUP BY cand_id, cand_election_yr
), cand_election_yrs AS (
    SELECT election_yr.cand_id,
    election_yr.cand_election_yr,
    lead(election_yr.cand_election_yr) OVER (PARTITION BY election_yr.cand_id ORDER BY election_yr.cand_election_yr) AS next_election
    FROM election_yr
)
, fec_yr AS (
	SELECT cand.cand_valid_yr_id,
	cand.cand_id,
	cand.fec_election_yr,
	cand.cand_election_yr,
	cand.cand_status,
	cand.cand_ici,
	cand.cand_office,
	cand.cand_office_st,
	cand.cand_office_district,
	cand.cand_pty_affiliation,
	cand.cand_name,
	cand.cand_st1,
	cand.cand_st2,
	cand.cand_city,
	cand.cand_state,
	cand.cand_zip,
	cand.race_pk,
	cand.lst_updt_dt,
	cand.latest_receipt_dt,
	cand.user_id_entered,
	cand.date_entered,
	cand.user_id_changed,
	cand.date_changed,
	cand.ref_cand_pk,
	cand.ref_lst_updt_dt,
	cycle_data_available.max_cycle_available,
	cycle_data_available.min_cycle_available,
CASE
	-- #1
	-- when the cand_election_yr is greater than the max cycle data available, can not calculate based on fec_election_cycle, just take the value as it is
	WHEN cand.cand_election_yr > cycle_data_available.max_cycle_available THEN cand.cand_election_yr
	-- #2
	-- when the cand_election_yr is earlier than the min cycle data available, can not calculate based on fec_election_cycle, just take the value as it is
	WHEN cand.cand_election_yr < cycle_data_available.min_cycle_available THEN cand.cand_election_yr
	-- #3
	WHEN cand.cand_election_yr = cand.fec_election_yr THEN cand.cand_election_yr
	-- #4
	-- handle odd year House here since it is simple.  P and S need more consideration and are handled in the following rules.
        WHEN cand.cand_election_yr%2 = 1 and substr(cand.cand_id::text, 1, 1) = 'H' THEN
            CASE 
            WHEN cand.fec_election_yr <= cand.cand_election_yr+cand.cand_election_yr%2 then cand.cand_election_yr
            ELSE NULL
            END
	-- #5 
	-- when this is the last election this candidate has, and the fec_election_yr falls in this candidate election cycle. 
	WHEN yrs.next_election IS NULL THEN
	    CASE
	    WHEN cand.fec_election_yr <= yrs.cand_election_yr+yrs.cand_election_yr%2 AND (yrs.cand_election_yr-cand.fec_election_yr <
		    election_duration (substr(cand.cand_id, 1, 1)::text)) 
	    THEN yrs.cand_election_yr
	    ELSE NULL::numeric
	    END
	-- #6
	-- this is a special case of #7
	WHEN cand.fec_election_yr > cand.cand_election_yr AND yrs.next_election%2 =1 and cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr <= (yrs.next_election+yrs.next_election%2 -
		election_duration (substr(cand.cand_id, 1, 1)::text)) 
	THEN null
	-- #7
	-- when fec_election_yr is between previous cand_election and next_election, and fec_election_cycle is within the duration of the next_election cycle
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr > (yrs.next_election -
		election_duration (substr(cand.cand_id, 1, 1)::text)) 
	THEN yrs.next_election
	-- #8
	-- when fec_election_yr is after previous cand_election, but NOT within the duration of the next_election cycle (previous cand_election and the next_election has gaps)
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr <= (yrs.next_election -
		election_duration (substr(cand.cand_id, 1, 1)::text)) 
	THEN NULL::numeric
	-- #9
	-- fec_election_yr are within THIS election_cycle
	WHEN cand.fec_election_yr < cand.cand_election_yr AND (yrs.cand_election_yr-cand.fec_election_yr <
		election_duration (substr(cand.cand_id, 1, 1)::text)) 
	THEN yrs.cand_election_yr
	-- 
ELSE NULL::numeric
END::numeric(4,0) AS election_year
, yrs.next_election
FROM disclosure.cand_valid_fec_yr cand
LEFT JOIN cand_election_yrs yrs ON cand.cand_id = yrs.cand_id AND cand.cand_election_yr = yrs.cand_election_yr
, cycle_data_available
ORDER BY cand_id, fec_election_yr
)
, elections AS (
	SELECT dedup.cand_id,
	array_agg(dedup.cand_office_district)::text[] AS election_districts
	FROM 
	( 
		--SELECT DISTINCT ON (fec_yr_1.cand_id, fec_yr_1.election_year) fec_yr_1.cand_valid_yr_id,
		SELECT DISTINCT ON (fec_yr_1.cand_id, fec_yr_1.cand_election_yr) fec_yr_1.cand_valid_yr_id,
		fec_yr_1.cand_id,
		fec_yr_1.fec_election_yr,
		fec_yr_1.cand_election_yr,
		fec_yr_1.cand_office_district,
		fec_yr_1.election_year
		FROM fec_yr fec_yr_1
		--where fec_yr_1.election_year is not null
		--ORDER BY fec_yr_1.cand_id, fec_yr_1.election_year, fec_yr_1.fec_election_yr
		ORDER BY fec_yr_1.cand_id, fec_yr_1.cand_election_yr, fec_yr_1.fec_election_yr
	) dedup  
	GROUP BY dedup.cand_id
), cycles AS (
	SELECT fec_yr_1.cand_id,
	--
	max(cand_election_yr) AS active_through,
	array_agg(distinct cand_election_yr)::integer[] AS election_years,
	--
	array_agg(fec_yr_1.fec_election_yr)::integer[] AS cycles,
	max(fec_yr_1.fec_election_yr) AS max_cycle
	FROM fec_yr fec_yr_1
	GROUP BY fec_yr_1.cand_id
), dates AS (
-- financial reports such as F3 and F3P should be filed under cmte_id, not cand_id, however, there are some reports are filed under cand_id in the past.  therefore last_file_date and last_f2_date may not be the same
	SELECT f_rpt_or_form_sub.cand_cmte_id AS cand_id,
	min(f_rpt_or_form_sub.receipt_dt) AS first_file_date,
	max(f_rpt_or_form_sub.receipt_dt) AS last_file_date,
	max(f_rpt_or_form_sub.receipt_dt) FILTER (WHERE f_rpt_or_form_sub.form_tp::text = 'F2'::text) AS last_f2_date
	FROM disclosure.f_rpt_or_form_sub
	where substr(cand_cmte_id, 1, 1) in ('S','H','P')
	GROUP BY f_rpt_or_form_sub.cand_cmte_id
)
SELECT row_number() OVER () AS idx,
    fec_yr.lst_updt_dt AS load_date,
    fec_yr.fec_election_yr AS two_year_period,
    fec_yr.election_year AS candidate_election_year,
    fec_yr.cand_id AS candidate_id,
    fec_yr.cand_name AS name,
    fec_yr.cand_state AS address_state,
    fec_yr.cand_city AS address_city,
    fec_yr.cand_st1 AS address_street_1,
    fec_yr.cand_st2 AS address_street_2,
    fec_yr.cand_zip AS address_zip,
    fec_yr.cand_ici AS incumbent_challenge,
    expand_candidate_incumbent(fec_yr.cand_ici::text) AS incumbent_challenge_full,
    fec_yr.cand_status AS candidate_status,
    inactive.cand_id IS NOT NULL AS candidate_inactive,
    fec_yr.cand_office AS office,
    expand_office(fec_yr.cand_office::text) AS office_full,
    fec_yr.cand_office_st AS state,
    fec_yr.cand_office_district AS district,
    fec_yr.cand_office_district::integer AS district_number,
    fec_yr.cand_pty_affiliation AS party,
    clean_party(ref_party.pty_desc::text) AS party_full,
    cycles.cycles,
    dates.first_file_date::text::date AS first_file_date,
    dates.last_file_date::text::date AS last_file_date,
    dates.last_f2_date::text::date AS last_f2_date,
    cycles.election_years,
    elections.election_districts,
    cycles.active_through
    --,fec_yr.cand_election_yr AS original_cand_election_yr
    --,fec_yr.next_election
FROM fec_yr
LEFT JOIN cycles USING (cand_id)
LEFT JOIN elections USING (cand_id)
LEFT JOIN dates USING (cand_id)
LEFT JOIN disclosure.cand_inactive inactive ON fec_yr.cand_id = inactive.cand_id AND fec_yr.election_year = inactive.election_yr
LEFT JOIN staging.ref_pty ref_party ON fec_yr.cand_pty_affiliation::text = ref_party.pty_cd::text
WHERE cycles.max_cycle >= 1979::numeric AND NOT (fec_yr.cand_id::text IN 
( SELECT DISTINCT unverified_filers_vw.cmte_id
   FROM unverified_filers_vw
  WHERE unverified_filers_vw.cmte_id::text ~ similar_escape('(P|S|H)%'::text, NULL::text)))
WITH DATA;

-- permissions:
ALTER TABLE public.ofec_candidate_history_mv_tmp
  OWNER TO fec;
GRANT ALL ON TABLE public.ofec_candidate_history_mv_tmp TO fec;
GRANT SELECT ON TABLE public.ofec_candidate_history_mv_tmp TO fec_read;

-- indexes:
CREATE INDEX idx_ofec_candidate_history_mv_tmp_1st_file_dt
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (first_file_date);

CREATE INDEX idx_ofec_candidate_history_mv_tmp_cand_id
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (candidate_id COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_mv_tmp_cycle
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (two_year_period);

CREATE INDEX idx_ofec_candidate_history_mv_tmp_cycle_cand_id
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (two_year_period, candidate_id COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_mv_tmp_dstrct
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (district COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_mv_tmp_dstrct_nbr
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (district_number);

CREATE INDEX idx_ofec_candidate_history_mv_tmp_load_dt
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (load_date);

CREATE INDEX idx_ofec_candidate_history_mv_tmp_office
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (office COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_mv_tmp_state
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (state COLLATE pg_catalog."default");

CREATE UNIQUE INDEX idx_ofec_candidate_history_mv_tmp2_idx
  ON public.ofec_candidate_history_mv_tmp
  USING btree
  (idx);

-- ---------------
CREATE OR REPLACE VIEW public.ofec_candidate_history_vw AS 
SELECT * FROM public.ofec_candidate_history_mv_tmp;
-- ---------------
-- drop the original view:
DROP MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_mv;

-- rename the tmp MV to be real mv:
ALTER MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_mv_tmp RENAME TO ofec_candidate_history_mv;

-- rename indexes:
ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_1st_file_dt RENAME TO idx_ofec_candidate_history_mv_1st_file_dt;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_cand_id RENAME TO idx_ofec_candidate_history_mv_cand_id;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_cycle RENAME TO idx_ofec_candidate_history_mv_cycle;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_cycle_cand_id RENAME TO idx_ofec_candidate_history_mv_cycle_cand_id;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_dstrct RENAME TO idx_ofec_candidate_history_mv_dstrct;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_dstrct_nbr RENAME TO idx_ofec_candidate_history_mv_dstrct_nbr;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_load_dt RENAME TO idx_ofec_candidate_history_mv_load_dt; 

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_office RENAME TO idx_ofec_candidate_history_mv_office;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp_state RENAME TO idx_ofec_candidate_history_mv_state;

ALTER INDEX IF EXISTS idx_ofec_candidate_history_mv_tmp2_idx RENAME TO idx_ofec_candidate_history_mv_idx;


-- Recreate the view to point to the base mv
CREATE OR REPLACE VIEW public.ofec_candidate_history_vw as select * from public.ofec_candidate_history_mv;
ALTER VIEW public.ofec_candidate_history_vw OWNER TO fec;
GRANT SELECT ON public.ofec_candidate_history_vw TO fec_read;

-- ---------------
-- ofec_candidate_history_with_future_election_mv
-- added the order by clause with DISTINCT ON (cand_hist.candidate_id) when adding future cycle, just to ensure the consistency. 
-- ---------------
DROP MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_with_future_election_mv_tmp;

CREATE MATERIALIZED VIEW public.ofec_candidate_history_with_future_election_mv_tmp AS 
WITH combined AS 
(
         SELECT cand_hist.load_date,
            cand_hist.two_year_period,
            cand_hist.candidate_election_year + cand_hist.candidate_election_year % 2::numeric AS candidate_election_year,
            cand_hist.candidate_id,
            cand_hist.name,
            cand_hist.address_state,
            cand_hist.address_city,
            cand_hist.address_street_1,
            cand_hist.address_street_2,
            cand_hist.address_zip,
            cand_hist.incumbent_challenge,
            cand_hist.incumbent_challenge_full,
            cand_hist.candidate_status,
            cand_hist.candidate_inactive,
            cand_hist.office,
            cand_hist.office_full,
            cand_hist.state,
            cand_hist.district,
            cand_hist.district_number,
            cand_hist.party,
            cand_hist.party_full,
            cand_hist.cycles,
            cand_hist.first_file_date,
            cand_hist.last_file_date,
            cand_hist.last_f2_date,
            cand_hist.election_years,
            cand_hist.election_districts,
            cand_hist.active_through
           FROM ofec_candidate_history_vw cand_hist
        UNION
        (
            SELECT DISTINCT ON (cand_hist.candidate_id) cand_hist.load_date,
            cand_hist.candidate_election_year + cand_hist.candidate_election_year % 2::numeric AS two_year_period,
            cand_hist.candidate_election_year + cand_hist.candidate_election_year % 2::numeric AS candidate_election_year,
            cand_hist.candidate_id,
            cand_hist.name,
            cand_hist.address_state,
            cand_hist.address_city,
            cand_hist.address_street_1,
            cand_hist.address_street_2,
            cand_hist.address_zip,
            cand_hist.incumbent_challenge,
            cand_hist.incumbent_challenge_full,
            cand_hist.candidate_status,
            cand_hist.candidate_inactive,
            cand_hist.office,
            cand_hist.office_full,
            cand_hist.state,
            cand_hist.district,
            cand_hist.district_number,
            cand_hist.party,
            cand_hist.party_full,
            cand_hist.cycles,
            cand_hist.first_file_date,
            cand_hist.last_file_date,
            cand_hist.last_f2_date,
            cand_hist.election_years,
            cand_hist.election_districts,
            cand_hist.active_through
           FROM ofec_candidate_history_vw cand_hist
          WHERE (cand_hist.candidate_election_year::double precision - date_part('year'::text, 'now'::text::date)) >= 2::double precision
          --
          ORDER BY cand_hist.candidate_id, cand_hist.candidate_election_year, cand_hist.two_year_period desc
          --
        )
)
 SELECT row_number() OVER () AS idx,
    combined.load_date,
    combined.two_year_period,
    combined.candidate_election_year + combined.candidate_election_year % 2::numeric AS candidate_election_year,
    combined.candidate_id,
    combined.name,
    combined.address_state,
    combined.address_city,
    combined.address_street_1,
    combined.address_street_2,
    combined.address_zip,
    combined.incumbent_challenge,
    combined.incumbent_challenge_full,
    combined.candidate_status,
    combined.candidate_inactive,
    combined.office,
    combined.office_full,
    combined.state,
    combined.district,
    combined.district_number,
    combined.party,
    combined.party_full,
    combined.cycles,
    combined.first_file_date,
    combined.last_file_date,
    combined.last_f2_date,
    combined.election_years,
    combined.election_districts,
    combined.active_through
   FROM combined
WITH DATA;

ALTER TABLE public.ofec_candidate_history_with_future_election_mv_tmp
  OWNER TO fec;
GRANT ALL ON TABLE public.ofec_candidate_history_with_future_election_mv_tmp TO fec;
GRANT SELECT ON TABLE public.ofec_candidate_history_with_future_election_mv_tmp TO fec_read;

CREATE UNIQUE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_idx
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (idx);

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_cand_id
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (candidate_id COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_dstr
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (district COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_dstr_nbr
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (district_number);

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_1st_file
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (first_file_date);

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_load_dt
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (load_date);

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_office
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (office COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_state
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (state COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_candidate_history_with_future_election_mv_tmp_cycle
  ON public.ofec_candidate_history_with_future_election_mv_tmp
  USING btree
  (two_year_period, candidate_id COLLATE pg_catalog."default");

-- ---------------
CREATE OR REPLACE VIEW public.ofec_candidate_history_with_future_election_vw AS 
SELECT * FROM public.ofec_candidate_history_with_future_election_mv_tmp;
-- ---------------

DROP MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_with_future_election_mv;

ALTER MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_with_future_election_mv_tmp RENAME TO ofec_candidate_history_with_future_election_mv;

-- ---------------
ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_idx RENAME TO idx_ofec_candidate_history_with_future_election_mv_idx;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_cand_id RENAME TO idx_ofec_candidate_history_with_future_election_mv_cand_id;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_dstr RENAME TO idx_ofec_candidate_history_with_future_election_mv_dstr;
 
ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_dstr_nbr RENAME TO idx_ofec_candidate_history_with_future_election_mv_dstr_nbr;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_1st_file RENAME TO idx_ofec_candidate_history_with_future_election_mv_1st_file_dt;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_load_dt RENAME TO idx_ofec_candidate_history_with_future_election_mv_load_dt;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_office RENAME TO idx_ofec_candidate_history_with_future_election_mv_office;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_state RENAME TO idx_ofec_candidate_history_with_future_election_mv_state;

ALTER INDEX IF EXISTS public.idx_ofec_candidate_history_with_future_election_mv_tmp_cycle RENAME TO idx_ofec_candidate_history_with_future_election_mv_cycle;

-- ----------------------
-- ofec_cand_cmte_linkage_mv
-- tighten up logic for ofec_cand_cmte_linkage_mv (updated rule #4)
-- ----------------------
DROP MATERIALIZED VIEW IF EXISTS public.ofec_cand_cmte_linkage_mv_tmp;
CREATE MATERIALIZED VIEW ofec_cand_cmte_linkage_mv_tmp AS
WITH 
election_yr AS (
    SELECT cand_cmte_linkage.cand_id,
    cand_cmte_linkage.cand_election_yr AS orig_cand_election_yr,
    cand_cmte_linkage.cand_election_yr + cand_cmte_linkage.cand_election_yr % 2::numeric AS cand_election_yr
    FROM disclosure.cand_cmte_linkage
    WHERE substr(cand_cmte_linkage.cand_id::text, 1, 1) = cand_cmte_linkage.cmte_tp::text OR (cand_cmte_linkage.cmte_tp::text <> ALL (ARRAY['P'::character varying::text, 'S'::character varying::text, 'H'::character varying::text]))
    GROUP BY cand_cmte_linkage.cand_id, cand_election_yr, (cand_cmte_linkage.cand_election_yr + cand_cmte_linkage.cand_election_yr % 2::numeric)
), cand_election_yrs AS (
    SELECT election_yr.cand_id,
    election_yr.orig_cand_election_yr,
    election_yr.cand_election_yr,
    lead(election_yr.cand_election_yr) OVER (PARTITION BY election_yr.cand_id ORDER BY election_yr.orig_cand_election_yr) AS next_election
    FROM election_yr
)
SELECT row_number() OVER () AS idx,
    link.linkage_id,
    link.cand_id,
    link.cand_election_yr,
    link.fec_election_yr,
    link.cmte_id,
    link.cmte_tp,
    link.cmte_dsgn,
    link.linkage_type,
    link.user_id_entered,
    link.date_entered,
    link.user_id_changed,
    link.date_changed,
    link.cmte_count_cand_yr,
    link.efile_paper_ind,
    link.pg_date,
        CASE
        -- #1
            WHEN link.cand_election_yr = link.fec_election_yr THEN link.cand_election_yr
	    -- #2
    	    -- handle odd year House here since it is simple.  P and S need more consideration and are handled in the following rules.
            WHEN link.cand_election_yr%2 = 1 and substr(link.cand_id::text, 1, 1) = 'H' THEN
            CASE 
            WHEN link.fec_election_yr <= link.cand_election_yr+link.cand_election_yr%2 then link.cand_election_yr+link.cand_election_yr%2
            ELSE NULL
            END
        -- #3
	    -- when this is the last election this candidate has, and the fec_election_yr falls in this candidate election cycle. 
            WHEN yrs.next_election IS NULL THEN
            CASE
            WHEN link.fec_election_yr <= yrs.cand_election_yr AND (yrs.cand_election_yr-link.fec_election_yr <
                CASE WHEN link.cmte_tp::text in ('H', 'S', 'P')
                THEN election_duration (link.cmte_tp::text)
                ELSE null
                END
            ) 
            THEN yrs.cand_election_yr
                ELSE NULL::numeric
                END
	    -- #4
	    -- when fec_election_yr is between previous cand_election and next_election, and fec_election_cycle is within the duration of the next_election cycle
	    -- note: different from the calculation in candidate_history the next_election here is a rounded number so it need to include <=
	    WHEN link.fec_election_yr > link.cand_election_yr AND link.fec_election_yr <= yrs.next_election AND link.fec_election_yr > (yrs.next_election -
        --WHEN link.fec_election_yr > link.cand_election_yr AND link.fec_election_yr > (yrs.next_election -
                CASE WHEN link.cmte_tp::text in ('H', 'S', 'P')
                THEN election_duration (link.cmte_tp::text)
                ELSE null
                END
            ) 
                THEN yrs.next_election
        -- #5
	    -- when fec_election_yr is after previous cand_election, but NOT within the duration of the next_election cycle (previous cand_election and the next_election has gaps)
            WHEN link.fec_election_yr > link.cand_election_yr AND link.fec_election_yr <= (yrs.next_election -
                CASE WHEN link.cmte_tp::text in ('H', 'S', 'P')
                THEN election_duration (link.cmte_tp::text)
                ELSE null
                END
            ) 
                THEN NULL::numeric
        -- #6                
	    -- fec_election_yr are within THIS election_cycle
            WHEN link.fec_election_yr < link.cand_election_yr AND (yrs.cand_election_yr-link.fec_election_yr <
                CASE WHEN link.cmte_tp::text in ('H', 'S', 'P')
                THEN election_duration (link.cmte_tp::text)
                ELSE null
                END
            ) 
                THEN yrs.cand_election_yr
            ELSE NULL::numeric
        END::numeric(4,0) AS election_yr_to_be_included
        --, yrs.next_election
        --, yrs.cand_election_yr yrs_cand_yr
   FROM disclosure.cand_cmte_linkage link
     LEFT JOIN cand_election_yrs yrs ON link.cand_id::text = yrs.cand_id::text AND link.cand_election_yr = yrs.orig_cand_election_yr
  WHERE substr(link.cand_id::text, 1, 1) = link.cmte_tp::text OR (link.cmte_tp::text <> ALL (ARRAY['P'::character varying::text, 'S'::character varying::text, 'H'::character varying::text]))
  WITH DATA;

  --Permissions
ALTER TABLE public.ofec_cand_cmte_linkage_mv_tmp OWNER TO fec;
GRANT ALL ON TABLE public.ofec_cand_cmte_linkage_mv_tmp TO fec;
GRANT SELECT ON TABLE public.ofec_cand_cmte_linkage_mv_tmp TO fec_read;

--Indexes
CREATE INDEX idx_ofec_cand_cmte_linkage_mv_tmp_cand_elec_yr
  ON public.ofec_cand_cmte_linkage_mv_tmp
  USING btree
  (cand_election_yr);

CREATE INDEX idx_ofec_cand_cmte_linkage_mv_tmp_cand_id
  ON public.ofec_cand_cmte_linkage_mv_tmp
  USING btree
  (cand_id COLLATE pg_catalog."default");

CREATE INDEX idx_ofec_cand_cmte_linkage_mv_tmp_cmte_id
  ON public.ofec_cand_cmte_linkage_mv_tmp
  USING btree
  (cmte_id COLLATE pg_catalog."default");

CREATE UNIQUE INDEX idx_ofec_cand_cmte_linkage_mv_tmp_idx
  ON public.ofec_cand_cmte_linkage_mv_tmp
  USING btree
  (idx);

-- ---------------
CREATE OR REPLACE VIEW public.ofec_cand_cmte_linkage_vw AS 
SELECT * FROM public.ofec_cand_cmte_linkage_mv_tmp;
-- ---------------

-- drop old MV
DROP MATERIALIZED VIEW public.ofec_cand_cmte_linkage_mv;

-- rename _tmp mv to mv
ALTER MATERIALIZED VIEW IF EXISTS public.ofec_cand_cmte_linkage_mv_tmp RENAME TO ofec_cand_cmte_linkage_mv;

-- rename indexes
ALTER INDEX IF EXISTS idx_ofec_cand_cmte_linkage_mv_tmp_cand_elec_yr RENAME TO idx_ofec_cand_cmte_linkage_mv_cand_elec_yr;

ALTER INDEX IF EXISTS idx_ofec_cand_cmte_linkage_mv_tmp_cand_id RENAME TO idx_ofec_cand_cmte_linkage_mv_cand_id;

ALTER INDEX IF EXISTS idx_ofec_cand_cmte_linkage_mv_tmp_cmte_id RENAME TO idx_ofec_cand_cmte_linkage_mv_cmte_id;

ALTER INDEX IF EXISTS idx_ofec_cand_cmte_linkage_mv_tmp_idx RENAME TO idx_ofec_cand_cmte_linkage_mv_idx;

-- ---------------
REFRESH MATERIALIZED VIEW CONCURRENTLY ofec_candidate_totals_mv;
