/*
This is to solve issue #3736
the calculation here for the election_year is similar to the election_yr_to_be_included column in ofec_cand_cmte_linkage table, but not exactly the same.  
The purpose of election_yr_to_be_included is to calculated the election_cycle the cycle financial data belongs to and an odd year will be rounded up and folded into its even year cycle.  
Here the election_year is for the election year, an odd election year need to be preserved, separated from its even year cycle.

The calculation is based on the fec_election_yr, the cand_election_yr, the cycle length (6, 4, 2), the next_election 
Simple and straight foward rules first, followed by more complicated rules.  
NOTE: there are some cand_id (219 out of 40144) that has one election_yr's data does not fit the fec_election_yr and candidate_election_yr and can not fit in any of the following rule. 
*/

CREATE OR REPLACE VIEW public.ofec_candidate_history_vw AS 
WITH
election_yr AS (
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
CASE
	-- #1
	WHEN cand.cand_election_yr = cand.fec_election_yr THEN cand.cand_election_yr
	-- #2
	-- Some early data the candidate_election_yr does not have correspoinding fec_election_yr
	WHEN cand.fec_election_yr = yrs.next_election THEN yrs.next_election
	-- #3
	-- handle odd year House here since it is simple.  P and S need more consideration and are handled in the following rules.
        WHEN cand.cand_election_yr%2 = 1 and substr(cand.cand_id::text, 1, 1) = 'H' THEN
            CASE 
            WHEN cand.fec_election_yr <= cand.cand_election_yr+cand.cand_election_yr%2 then cand.cand_election_yr
            ELSE NULL
            END
	-- #4 
	-- when this is the last election this candidate has, and the fec_election_yr falls in this candidate election cycle. 
	WHEN yrs.next_election IS NULL THEN
	    CASE
	    WHEN cand.fec_election_yr <= yrs.cand_election_yr+yrs.cand_election_yr%2 AND (yrs.cand_election_yr-cand.fec_election_yr <
		    CASE
		    WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		    WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		    WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		    ELSE NULL::integer
		    END::numeric) 
	    THEN yrs.cand_election_yr
	    ELSE NULL::numeric
	    END
	-- #5
	-- this is a special case of #6
	WHEN cand.fec_election_yr > cand.cand_election_yr AND yrs.next_election%2 =1 and cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr <= (yrs.next_election+yrs.next_election%2 -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN null
	-- #6
	-- when fec_election_yr is between previous cand_election and next_election, and fec_election_cycle is within the duration of the next_election cycle
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr > (yrs.next_election -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN yrs.next_election
	-- #7
	-- when fec_election_yr is after previous cand_election, but NOT within the duration of the next_election cycle (previous cand_election and the next_election has gaps)
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr <= (yrs.next_election -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN NULL::numeric
	-- #8
	-- fec_election_yr are within THIS election_cycle
	WHEN cand.fec_election_yr < cand.cand_election_yr AND (yrs.cand_election_yr-cand.fec_election_yr <
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN yrs.cand_election_yr
	-- 
ELSE NULL::numeric
END::numeric(4,0) AS election_year
, yrs.next_election
FROM disclosure.cand_valid_fec_yr cand
LEFT JOIN cand_election_yrs yrs ON cand.cand_id = yrs.cand_id AND cand.cand_election_yr = yrs.cand_election_yr
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
SELECT DISTINCT ON (fec_yr.cand_id, fec_yr.fec_election_yr) row_number() OVER () AS idx,
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
  WHERE unverified_filers_vw.cmte_id::text ~ similar_escape('(P|S|H)%'::text, NULL::text)));


ALTER TABLE public.ofec_candidate_history_vw
  OWNER TO fec;
GRANT ALL ON TABLE public.ofec_candidate_history_vw TO fec;
GRANT SELECT ON TABLE public.ofec_candidate_history_vw TO fec_read;


DROP MATERIALIZED VIEW IF EXISTS public.ofec_candidate_history_mv_tmp;

CREATE MATERIALIZED VIEW public.ofec_candidate_history_mv_tmp AS 
WITH
election_yr AS (
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
CASE
	-- #1
	WHEN cand.cand_election_yr = cand.fec_election_yr THEN cand.cand_election_yr
	-- #2
	-- Some early data the candidate_election_yr does not have correspoinding fec_election_yr
	WHEN cand.fec_election_yr = yrs.next_election THEN yrs.next_election
	-- #3
	-- handle odd year House here since it is simple.  P and S need more consideration and are handled in the following rules.
        WHEN cand.cand_election_yr%2 = 1 and substr(cand.cand_id::text, 1, 1) = 'H' THEN
            CASE 
            WHEN cand.fec_election_yr <= cand.cand_election_yr+cand.cand_election_yr%2 then cand.cand_election_yr
            ELSE NULL
            END
	-- #4 
	-- when this is the last election this candidate has, and the fec_election_yr falls in this candidate election cycle. 
	WHEN yrs.next_election IS NULL THEN
	    CASE
	    WHEN cand.fec_election_yr <= yrs.cand_election_yr+yrs.cand_election_yr%2 AND (yrs.cand_election_yr-cand.fec_election_yr <
		    CASE
		    WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		    WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		    WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		    ELSE NULL::integer
		    END::numeric) 
	    THEN yrs.cand_election_yr
	    ELSE NULL::numeric
	    END
	-- #5
	-- this is a special case of #6
	WHEN cand.fec_election_yr > cand.cand_election_yr AND yrs.next_election%2 =1 and cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr <= (yrs.next_election+yrs.next_election%2 -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN null
	-- #6
	-- when fec_election_yr is between previous cand_election and next_election, and fec_election_cycle is within the duration of the next_election cycle
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr < yrs.next_election AND cand.fec_election_yr > (yrs.next_election -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN yrs.next_election
	-- #7
	-- when fec_election_yr is after previous cand_election, but NOT within the duration of the next_election cycle (previous cand_election and the next_election has gaps)
	WHEN cand.fec_election_yr > cand.cand_election_yr AND cand.fec_election_yr <= (yrs.next_election -
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN NULL::numeric
	-- #8
	-- fec_election_yr are within THIS election_cycle
	WHEN cand.fec_election_yr < cand.cand_election_yr AND (yrs.cand_election_yr-cand.fec_election_yr <
		CASE
		WHEN substr(cand.cand_id, 1, 1) = 'P'::text THEN 4
		WHEN substr(cand.cand_id, 1, 1) = 'S'::text THEN 6
		WHEN substr(cand.cand_id, 1, 1) = 'H'::text THEN 2
		ELSE NULL::integer
		END::numeric) 
	THEN yrs.cand_election_yr
	-- 
ELSE NULL::numeric
END::numeric(4,0) AS election_year
, yrs.next_election
FROM disclosure.cand_valid_fec_yr cand
LEFT JOIN cand_election_yrs yrs ON cand.cand_id = yrs.cand_id AND cand.cand_election_yr = yrs.cand_election_yr
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
SELECT DISTINCT ON (fec_yr.cand_id, fec_yr.fec_election_yr) row_number() OVER () AS idx,
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
