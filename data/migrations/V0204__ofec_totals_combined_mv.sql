/*
This is migration file 2 of 3 to solve issue #4463
*/

-- ---------------------------------------
-- Now point the public.ofec_totals_combined_mv to the "new"/"tmp" ofec_fiings_all_mv, 
--   which referencing a tmp table that has the new tres_nm length
-- Please note, usually switch source MV need to update flow.py/manage.py
-- But since ofec_filings_all_mv and ofec_filings_mv is in the same group in manage.py, this step is not needed
-- ---------------------------------------
DO $$
DECLARE
    execute_flg integer;
BEGIN
    execute 'SELECT count(*)
    FROM pg_attribute a
    JOIN pg_class t on a.attrelid = t.oid
    JOIN pg_namespace s on t.relnamespace = s.oid
    WHERE a.attnum > 0 
    AND NOT a.attisdropped
    and relname = ''f_rpt_or_form_sub''
    and a.attname = ''tres_nm''
    and pg_catalog.format_type(a.atttypid, a.atttypmod) = ''character varying(38)''
    and s.nspname = ''disclosure'''
    into execute_flg;

    if execute_flg = 1 then

	DROP MATERIALIZED VIEW IF EXISTS public.ofec_totals_combined_mv_tmp;

	CREATE MATERIALIZED VIEW ofec_totals_combined_mv_tmp AS
	WITH last_subset AS (
		 SELECT DISTINCT ON (v_sum_and_det_sum_report.cmte_id, (get_cycle(v_sum_and_det_sum_report.rpt_yr))) v_sum_and_det_sum_report.orig_sub_id,
		    v_sum_and_det_sum_report.cmte_id,
		    v_sum_and_det_sum_report.coh_cop,
		    v_sum_and_det_sum_report.debts_owed_by_cmte,
		    v_sum_and_det_sum_report.debts_owed_to_cmte,
		    v_sum_and_det_sum_report.net_op_exp,
		    v_sum_and_det_sum_report.net_contb,
		    v_sum_and_det_sum_report.rpt_yr,
		    get_cycle(v_sum_and_det_sum_report.rpt_yr) AS cycle
		   FROM disclosure.v_sum_and_det_sum_report
		  WHERE get_cycle(v_sum_and_det_sum_report.rpt_yr) >= 1979 AND (v_sum_and_det_sum_report.form_tp_cd::text <> 'F5'::text OR v_sum_and_det_sum_report.form_tp_cd::text = 'F5'::text AND (v_sum_and_det_sum_report.rpt_tp::text <> ALL (ARRAY['24'::character varying::text, '48'::character varying::text]))) AND v_sum_and_det_sum_report.form_tp_cd::text NOT IN ('F6','SL')
		  ORDER BY v_sum_and_det_sum_report.cmte_id, (get_cycle(v_sum_and_det_sum_report.rpt_yr)), (to_timestamp(v_sum_and_det_sum_report.cvg_end_dt::double precision)) DESC NULLS LAST
		), last AS (
		 SELECT ls.cmte_id,
		    ls.orig_sub_id,
		    ls.coh_cop,
		    ls.cycle,
		    ls.debts_owed_by_cmte,
		    ls.debts_owed_to_cmte,
		    ls.net_op_exp,
		    ls.net_contb,
		    ls.rpt_yr,
		    of.candidate_id,
		    of.beginning_image_number,
		    of.coverage_end_date,
		    of.form_type,
		    of.report_type_full,
		    of.report_type,
		    of.candidate_name,
		    of.committee_name
		   FROM last_subset ls
		     LEFT JOIN ofec_filings_all_vw of ON ls.orig_sub_id = of.sub_id
		), first AS (
		 SELECT DISTINCT ON (v_sum_and_det_sum_report.cmte_id, (get_cycle(v_sum_and_det_sum_report.rpt_yr))) v_sum_and_det_sum_report.coh_bop AS cash_on_hand,
		    v_sum_and_det_sum_report.cmte_id AS committee_id,
			CASE
			    WHEN v_sum_and_det_sum_report.cvg_start_dt = 99999999::numeric THEN NULL::timestamp without time zone
			    ELSE v_sum_and_det_sum_report.cvg_start_dt::text::date::timestamp without time zone
			END AS coverage_start_date,
		    get_cycle(v_sum_and_det_sum_report.rpt_yr) AS cycle
		   FROM disclosure.v_sum_and_det_sum_report
		  WHERE get_cycle(v_sum_and_det_sum_report.rpt_yr) >= 1979 AND (v_sum_and_det_sum_report.form_tp_cd::text <> 'F5'::text OR v_sum_and_det_sum_report.form_tp_cd::text = 'F5'::text AND (v_sum_and_det_sum_report.rpt_tp::text <> ALL (ARRAY['24'::character varying::text, '48'::character varying::text]))) AND v_sum_and_det_sum_report.form_tp_cd::text NOT IN ('F6','SL')
		  ORDER BY v_sum_and_det_sum_report.cmte_id, (get_cycle(v_sum_and_det_sum_report.rpt_yr)), (to_timestamp(v_sum_and_det_sum_report.cvg_end_dt::double precision))
		), committee_info AS (
		 SELECT DISTINCT ON (cmte_valid_fec_yr.cmte_id, cmte_valid_fec_yr.fec_election_yr) cmte_valid_fec_yr.cmte_id,
		    cmte_valid_fec_yr.fec_election_yr,
		    cmte_valid_fec_yr.cmte_nm,
		    cmte_valid_fec_yr.cmte_tp,
		    cmte_valid_fec_yr.cmte_dsgn,
		    cmte_valid_fec_yr.cmte_pty_affiliation_desc
		   FROM disclosure.cmte_valid_fec_yr
		)
	 SELECT get_cycle(vsd.rpt_yr) AS cycle,
	    max(last.candidate_id::text) AS candidate_id,
	    max(last.candidate_name::text) AS candidate_name,
	    max(last.committee_name::text) AS committee_name,
	    max(last.beginning_image_number) AS last_beginning_image_number,
	    max(last.coh_cop) AS last_cash_on_hand_end_period,
	    max(last.debts_owed_by_cmte) AS last_debts_owed_by_committee,
	    max(last.debts_owed_to_cmte) AS last_debts_owed_to_committee,
	    max(last.net_contb) AS last_net_contributions,
	    max(last.net_op_exp) AS last_net_operating_expenditures,
	    max(last.report_type::text) AS last_report_type,
	    max(last.report_type_full::text) AS last_report_type_full,
	    max(last.rpt_yr) AS last_report_year,
	    max(last.coverage_end_date) AS coverage_end_date,
	    max(vsd.orig_sub_id) AS sub_id,
	    min(first.cash_on_hand) AS cash_on_hand_beginning_period,
	    min(first.coverage_start_date) AS coverage_start_date,
	    sum(vsd.all_loans_received_per) AS all_loans_received,
	    sum(vsd.cand_cntb) AS candidate_contribution,
	    sum(vsd.cand_loan_repymnt + vsd.oth_loan_repymts) AS loan_repayments_made,
	    sum(vsd.cand_loan_repymnt) AS loan_repayments_candidate_loans,
	    sum(vsd.cand_loan) AS loans_made_by_candidate,
	    sum(vsd.cand_loan_repymnt) AS repayments_loans_made_by_candidate,
	    sum(vsd.cand_loan) AS loans_received_from_candidate,
	    sum(vsd.coord_exp_by_pty_cmte_per) AS coordinated_expenditures_by_party_committee,
	    sum(vsd.exempt_legal_acctg_disb) AS exempt_legal_accounting_disbursement,
	    sum(vsd.fed_cand_cmte_contb_per) AS fed_candidate_committee_contributions,
	    sum(vsd.fed_cand_contb_ref_per) AS fed_candidate_contribution_refunds,
	    sum(vsd.fed_funds_per) > 0::numeric AS federal_funds_flag,
	    sum(vsd.ttl_fed_disb_per) AS fed_disbursements,
	    sum(vsd.fed_funds_per) AS federal_funds,
	    sum(vsd.fndrsg_disb) AS fundraising_disbursements,
	    sum(vsd.indv_contb) AS individual_contributions,
	    sum(vsd.indv_item_contb) AS individual_itemized_contributions,
	    sum(vsd.indv_ref) AS refunded_individual_contributions,
	    sum(vsd.indv_unitem_contb) AS individual_unitemized_contributions,
	    sum(vsd.loan_repymts_received_per) AS loan_repayments_received,
	    sum(vsd.loans_made_per) AS loans_made,
	    sum(vsd.net_contb) AS net_contributions,
	    sum(vsd.net_op_exp) AS net_operating_expenditures,
	    sum(vsd.non_alloc_fed_elect_actvy_per) AS non_allocated_fed_election_activity,
	    sum(vsd.offsets_to_fndrsg) AS offsets_to_fundraising_expenditures,
	    sum(vsd.offsets_to_legal_acctg) AS offsets_to_legal_accounting,
	    sum(vsd.offsets_to_op_exp + vsd.offsets_to_fndrsg + vsd.offsets_to_legal_acctg) AS total_offsets_to_operating_expenditures,
	    sum(vsd.offsets_to_op_exp) AS offsets_to_operating_expenditures,
	    sum(
		CASE
		    WHEN vsd.form_tp_cd::text = 'F3X'::text THEN vsd.ttl_op_exp_per
		    ELSE vsd.op_exp_per
		END) AS operating_expenditures,
	    sum(vsd.oth_cmte_contb) AS other_political_committee_contributions,
	    sum(vsd.oth_cmte_ref) AS refunded_other_political_committee_contributions,
	    sum(vsd.oth_loan_repymts) AS loan_repayments_other_loans,
	    sum(vsd.oth_loan_repymts) AS repayments_other_loans,
	    sum(vsd.oth_loans) AS all_other_loans,
	    sum(vsd.oth_loans) AS other_loans_received,
	    sum(vsd.other_disb_per) AS other_disbursements,
	    sum(vsd.other_fed_op_exp_per) AS other_fed_operating_expenditures,
	    sum(vsd.other_receipts) AS other_fed_receipts,
	    sum(vsd.other_receipts) AS other_receipts,
	    sum(vsd.pol_pty_cmte_contb) AS refunded_political_party_committee_contributions,
	    sum(vsd.pty_cmte_contb) AS political_party_committee_contributions,
	    sum(vsd.shared_fed_actvy_fed_shr_per) AS shared_fed_activity,
	    sum(vsd.shared_fed_actvy_nonfed_per) AS allocated_federal_election_levin_share,
	    sum(vsd.shared_fed_actvy_nonfed_per) AS shared_fed_activity_nonfed,
	    sum(vsd.shared_fed_op_exp_per) AS shared_fed_operating_expenditures,
	    sum(vsd.shared_nonfed_op_exp_per) AS shared_nonfed_operating_expenditures,
	    sum(vsd.tranf_from_nonfed_acct_per) AS transfers_from_nonfed_account,
	    sum(vsd.tranf_from_nonfed_levin_per) AS transfers_from_nonfed_levin,
	    sum(vsd.tranf_from_other_auth_cmte) AS transfers_from_affiliated_committee,
	    sum(vsd.tranf_from_other_auth_cmte) AS transfers_from_affiliated_party,
	    sum(vsd.tranf_from_other_auth_cmte) AS transfers_from_other_authorized_committee,
	    sum(vsd.tranf_to_other_auth_cmte) AS transfers_to_affiliated_committee,
	    sum(vsd.tranf_to_other_auth_cmte) AS transfers_to_other_authorized_committee,
	    sum(vsd.ttl_contb_ref) AS contribution_refunds,
	    sum(vsd.ttl_contb) AS contributions,
	    sum(vsd.ttl_disb) AS disbursements,
	    sum(vsd.ttl_fed_elect_actvy_per) AS fed_election_activity,
	    sum(vsd.ttl_fed_receipts_per) AS fed_receipts,
	    sum(vsd.ttl_loan_repymts) AS loan_repayments,
	    sum(vsd.ttl_loans) AS loans_received,
	    sum(vsd.ttl_loans) AS loans,
	    sum(vsd.ttl_nonfed_tranf_per) AS total_transfers,
	    sum(vsd.ttl_receipts) AS receipts,
	    max(committee_info.cmte_tp::text) AS committee_type,
	    max(expand_committee_type(committee_info.cmte_tp::text)) AS committee_type_full,
	    max(committee_info.cmte_dsgn::text) AS committee_designation,
	    max(expand_committee_designation(committee_info.cmte_dsgn::text)) AS committee_designation_full,
	    max(committee_info.cmte_pty_affiliation_desc::text) AS party_full,
	    vsd.cmte_id AS committee_id,
	    vsd.form_tp_cd AS form_type,
		CASE
		    WHEN max(last.form_type::text) = ANY (ARRAY['F3'::text, 'F3P'::text]) THEN NULL::numeric
		    ELSE sum(vsd.indt_exp_per)
		END AS independent_expenditures,
	    sum(vsd.exp_subject_limits_per) AS exp_subject_limits,
	    sum(vsd.exp_prior_yrs_subject_lim_per) AS exp_prior_years_subject_limits,
	    sum(vsd.ttl_exp_subject_limits) AS total_exp_subject_limits,
	    sum(vsd.subttl_ref_reb_ret_per) AS refunds_relating_convention_exp,
	    sum(vsd.item_ref_reb_ret_per) AS itemized_refunds_relating_convention_exp,
	    sum(vsd.unitem_ref_reb_ret_per) AS unitemized_refunds_relating_convention_exp,
	    sum(vsd.subttl_other_ref_reb_ret_per) AS other_refunds,
	    sum(vsd.item_other_ref_reb_ret_per) AS itemized_other_refunds,
	    sum(vsd.unitem_other_ref_reb_ret_per) AS unitemized_other_refunds,
	    sum(vsd.item_other_income_per) AS itemized_other_income,
	    sum(vsd.unitem_other_income_per) AS unitemized_other_income,
	    sum(vsd.subttl_convn_exp_disb_per) AS convention_exp,
	    sum(vsd.item_convn_exp_disb_per) AS itemized_convention_exp,
	    sum(vsd.unitem_convn_exp_disb_per) AS unitemized_convention_exp,
	    sum(vsd.item_other_disb_per) AS itemized_other_disb,
	    sum(vsd.unitem_other_disb_per) AS unitemized_other_disb
	   FROM disclosure.v_sum_and_det_sum_report vsd
	     LEFT JOIN last ON vsd.cmte_id::text = last.cmte_id::text AND get_cycle(vsd.rpt_yr) = last.cycle
	     LEFT JOIN first ON vsd.cmte_id::text = first.committee_id::text AND get_cycle(vsd.rpt_yr) = first.cycle
	     LEFT JOIN committee_info ON vsd.cmte_id::text = committee_info.cmte_id::text AND get_cycle(vsd.rpt_yr)::numeric = committee_info.fec_election_yr
	  WHERE get_cycle(vsd.rpt_yr) >= 1979 AND (vsd.form_tp_cd::text <> 'F5'::text OR vsd.form_tp_cd::text = 'F5'::text AND (vsd.rpt_tp::text <> ALL (ARRAY['24'::character varying::text, '48'::character varying::text]))) AND vsd.form_tp_cd::text NOT IN ('F6','SL')
	  GROUP BY vsd.cmte_id, vsd.form_tp_cd, (get_cycle(vsd.rpt_yr))
	  WITH DATA;

	ALTER TABLE public.ofec_totals_combined_mv_tmp OWNER TO fec;

	GRANT ALL ON TABLE public.ofec_totals_combined_mv_tmp TO fec;
	GRANT SELECT ON TABLE public.ofec_totals_combined_mv_tmp TO fec_read;

	CREATE UNIQUE INDEX idx_ofec_totals_combined_mv_tmp_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_cmte_dsgn_full_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (committee_designation_full COLLATE pg_catalog."default", sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_cmte_id_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (committee_id , sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_cmte_tp_full_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (committee_type_full, sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_cycle_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (cycle, sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_disb_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (disbursements, sub_id);
	CREATE INDEX idx_ofec_totals_combined_mv_tmp_receipts_sub_id
	    ON public.ofec_totals_combined_mv_tmp USING btree
	    (receipts, sub_id);

	-- recreate vw -> select all from new _tmp MV
	CREATE OR REPLACE VIEW ofec_totals_combined_vw 
	AS SELECT * FROM ofec_totals_combined_mv_tmp;

	ALTER VIEW ofec_totals_combined_vw OWNER TO fec;
	GRANT SELECT ON ofec_totals_combined_vw TO fec_read;

	-- drop old `MV`
	DROP MATERIALIZED VIEW public.ofec_totals_combined_mv;

	-- rename _tmp mv to mv
	ALTER MATERIALIZED VIEW IF EXISTS public.ofec_totals_combined_mv_tmp RENAME TO ofec_totals_combined_mv;

	-- rename indexes
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_cmte_dsgn_full_sub_id RENAME TO idx_ofec_totals_combined_mv_cmte_dsgn_full_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_cmte_id_sub_id RENAME TO idx_ofec_totals_combined_mv_cmte_id_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_cmte_tp_full_sub_id RENAME TO idx_ofec_totals_combined_mv_cmte_tp_full_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_cycle_sub_id RENAME TO idx_ofec_totals_combined_mv_cycle_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_disb_sub_id RENAME TO idx_ofec_totals_combined_mv_disb_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_receipts_sub_id RENAME TO idx_ofec_totals_combined_mv_receipts_sub_id;
	ALTER INDEX IF EXISTS idx_ofec_totals_combined_mv_tmp_sub_id RENAME TO idx_ofec_totals_combined_mv_sub_id;

    else
	null;
    end if;

EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'some other error: %, %',  sqlstate, sqlerrm;
END$$;


