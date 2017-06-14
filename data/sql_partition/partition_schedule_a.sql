-- Creates the partition of schedule A data
DROP TABLE IF EXISTS ofec_sched_a_master_tmp CASCADE;

CREATE TABLE ofec_sched_a_master_tmp (
    cmte_id                     VARCHAR(9),
    cmte_nm                     VARCHAR(200),
    contbr_id                   VARCHAR(9),
    contbr_nm                   VARCHAR(200),
    contbr_nm_first             VARCHAR(38),
    contbr_m_nm                 VARCHAR(20),
    contbr_nm_last              VARCHAR(38),
    contbr_prefix               VARCHAR(10),
    contbr_suffix               VARCHAR(10),
    contbr_st1                  VARCHAR(34),
    contbr_st2                  VARCHAR(34),
    contbr_city                 VARCHAR(30),
    contbr_st                   VARCHAR(2),
    contbr_zip                  VARCHAR(9),
    entity_tp                   VARCHAR(3),
    entity_tp_desc              VARCHAR(50),
    contbr_employer             VARCHAR(38),
    contbr_occupation           VARCHAR(38),
    election_tp                 VARCHAR(5),
    fec_election_tp_desc        VARCHAR(20),
    fec_election_yr             VARCHAR(4),
    election_tp_desc            VARCHAR(20),
    contb_aggregate_ytd         NUMERIC(14,2),
    contb_receipt_dt            TIMESTAMP,
    contb_receipt_amt           NUMERIC(14,2),
    receipt_tp                  VARCHAR(3),
    receipt_tp_desc             VARCHAR(90),
    receipt_desc                VARCHAR(100),
    memo_cd                     VARCHAR(1),
    memo_cd_desc                VARCHAR(50),
    memo_text                   VARCHAR(100),
    cand_id                     VARCHAR(9),
    cand_nm                     VARCHAR(90),
    cand_nm_first               VARCHAR(38),
    cand_m_nm                   VARCHAR(20),
    cand_nm_last                VARCHAR(38),
    cand_prefix                 VARCHAR(10),
    cand_suffix                 VARCHAR(10),
    cand_office                 VARCHAR(1),
    cand_office_desc            VARCHAR(20),
    cand_office_st              VARCHAR(2),
    cand_office_st_desc         VARCHAR(20),
    cand_office_district        VARCHAR(2),
    conduit_cmte_id             VARCHAR(9),
    conduit_cmte_nm             VARCHAR(200),
    conduit_cmte_st1            VARCHAR(34),
    conduit_cmte_st2            VARCHAR(34),
    conduit_cmte_city           VARCHAR(30),
    conduit_cmte_st             VARCHAR(2),
    conduit_cmte_zip            VARCHAR(9),
    donor_cmte_nm               VARCHAR(200),
    national_cmte_nonfed_acct   VARCHAR(9),
    increased_limit             VARCHAR(1),
    action_cd                   VARCHAR(1),
    action_cd_desc              VARCHAR(15),
    tran_id                     TEXT,
    back_ref_tran_id            TEXT,
    back_ref_sched_nm           VARCHAR(8),
    schedule_type               VARCHAR(2),
    schedule_type_desc          VARCHAR(90),
    line_num                    VARCHAR(12),
    image_num                   VARCHAR(18),
    file_num                    NUMERIC(7,0),
    link_id                     NUMERIC(19,0),
    orig_sub_id                 NUMERIC(19,0),
    sub_id                      NUMERIC(19,0) NOT NULL,
    filing_form                 VARCHAR(8) NOT NULL,
    rpt_tp                      VARCHAR(3),
    rpt_yr                      NUMERIC(4,0),
    election_cycle              NUMERIC(4,0),
    timestamp                   TIMESTAMP,
    pg_date                     TIMESTAMP,
    pdf_url                     TEXT,
    contributor_name_text       TSVECTOR,
    contributor_employer_text   TSVECTOR,
    contributor_occupation_text TSVECTOR,
    is_individual               BOOLEAN,
    clean_contbr_id             VARCHAR(9),
    two_year_transaction_period SMALLINT
);

-- Create the child tables.
SELECT create_itemized_schedule_partition('a', 1978, 2018);
SELECT finalize_itemized_schedule_a_tables(1978, 2018);

-- Create the insert trigger so that records go into the proper child table.
DROP TRIGGER IF EXISTS insert_sched_a_trigger_tmp ON ofec_sched_a_master_tmp;
CREATE trigger insert_sched_a_trigger_tmp BEFORE INSERT ON ofec_sched_a_master_tmp FOR EACH ROW EXECUTE PROCEDURE insert_sched_master('ofec_sched_a_');

SELECT rename_table_cascade('ofec_sched_a_master');
--
---- Insert the records from the view
--INSERT INTO ofec_sched_a_master_tmp SELECT
--    cmte_id,
--    cmte_nm,
--    contbr_id,
--    contbr_nm,
--    contbr_nm_first,
--    contbr_m_nm,
--    contbr_nm_last,
--    contbr_prefix,
--    contbr_suffix,
--    contbr_st1,
--    contbr_st2,
--    contbr_city,
--    contbr_st,
--    contbr_zip,
--    entity_tp,
--    entity_tp_desc,
--    contbr_employer,
--    contbr_occupation,
--    election_tp,
--    fec_election_tp_desc,
--    fec_election_yr,
--    election_tp_desc,
--    contb_aggregate_ytd,
--    contb_receipt_dt,
--    contb_receipt_amt,
--    receipt_tp,
--    receipt_tp_desc,
--    receipt_desc,
--    memo_cd,
--    memo_cd_desc,
--    memo_text,
--    cand_id,
--    cand_nm,
--    cand_nm_first,
--    cand_m_nm,
--    cand_nm_last,
--    cand_prefix,
--    cand_suffix,
--    cand_office,
--    cand_office_desc,
--    cand_office_st,
--    cand_office_st_desc,
--    cand_office_district,
--    conduit_cmte_id,
--    conduit_cmte_nm,
--    conduit_cmte_st1,
--    conduit_cmte_st2,
--    conduit_cmte_city,
--    conduit_cmte_st,
--    conduit_cmte_zip,
--    donor_cmte_nm,
--    national_cmte_nonfed_acct,
--    increased_limit,
--    action_cd,
--    action_cd_desc,
--    tran_id,
--    back_ref_tran_id,
--    back_ref_sched_nm,
--    schedule_type,
--    schedule_type_desc,
--    line_num,
--    image_num,
--    file_num,
--    link_id,
--    orig_sub_id,
--    sub_id,
--    filing_form,
--    rpt_tp,
--    rpt_yr,
--    election_cycle,
--    CURRENT_TIMESTAMP as timestamp,
--    CURRENT_TIMESTAMP as pg_date,
--    image_pdf_url(image_num) AS pdf_url,
--    to_tsvector(concat(contbr_nm, ' ', contbr_id)) AS contributor_name_text,
--    to_tsvector(contbr_employer) AS contributor_employer_text,
--    to_tsvector(contbr_occupation) AS contributor_occupation_text,
--    is_individual(contb_receipt_amt, receipt_tp, line_num, memo_cd, memo_text) AS is_individual,
--    clean_repeated(contbr_id, cmte_id) AS clean_contbr_id,
--    get_transaction_year(contb_receipt_dt, rpt_yr) AS two_year_transaction_period
--FROM fec_vsum_sched_a_vw; -- TODO:  Make fec_fitem_sched_a_vw