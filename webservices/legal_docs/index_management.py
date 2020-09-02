import logging
import elasticsearch
import copy
import datetime

from webservices import utils
from webservices.env import env

logger = logging.getLogger(__name__)

# ==== start define mapping for index: docs
SORT_MAPPINGS = {
    "sort1": {"type": "integer"},
    "sort2": {"type": "integer"},
}

CASE_DOCUMENT_MAPPINGS = {
    "type": "nested",
    "properties": {
        "category": {"type": "keyword"},
        "description": {"type": "text"},
        "document_date": {"type": "date", "format": "dateOptionalTime"},
        "document_id": {"type": "long"},
        "length": {"type": "long"},
        "text": {"type": "text"},
        "url": {"type": "text"},
    },
}

ADMIN_FINES = {
    "type": {"type": "keyword"},
    "no": {"type": "keyword", "index": True},
    "doc_id": {"type": "keyword", "index": False},
    "name": {"type": "text", "analyzer": "english"},
    "url": {"type": "text", "index": False},
    "committee_id": {"type": "text", "index": False},
    "report_year": {"type": "keyword"},
    "report_type": {"type": "text", "index": False},
    "reason_to_believe_action_date": {
        "type": "date",
        "format": "dateOptionalTime",
    },
    "reason_to_believe_fine_amount": {"type": "long"},
    "challenge_receipt_date": {"type": "date", "format": "dateOptionalTime"},
    "challenge_outcome": {"type": "text", "index": False},
    "final_determination_date": {"type": "date", "format": "dateOptionalTime"},
    "final_determination_amount": {"type": "long"},
    "check_amount": {"type": "long", "index": False},
    "treasury_referral_date": {"type": "date", "format": "dateOptionalTime"},
    "treasury_referral_amount": {"type": "long", "index": False},
    "petition_court_filing_date": {
        "type": "date",
        "format": "dateOptionalTime",
    },
    "petition_court_decision_date": {
        "type": "date",
        "format": "dateOptionalTime",
    },
    "commission_votes": {
        "properties": {
            "text": {"type": "text"},
            "vote_date": {"type": "date", "format": "dateOptionalTime"},
        }
    },
    "documents": CASE_DOCUMENT_MAPPINGS,
}

ADVISORY_OPINIONS = {
    "type": {"type": "keyword"},
    "no": {"type": "keyword", "index": False},
    "name": {"type": "text", "analyzer": "english"},
    "summary": {"type": "text", "analyzer": "english"},
    "issue_date": {"type": "date", "format": "dateOptionalTime"},
    "is_pending": {"type": "boolean"},
    "status": {"type": "text"},
    "ao_citations": {
        "properties": {"name": {"type": "text"}, "no": {"type": "text"}}
    },
    "aos_cited_by": {
        "properties": {"name": {"type": "text"}, "no": {"type": "text"}}
    },
    "statutory_citations": {
        "type": "nested",
        "properties": {
            "section": {"type": "text"},
            "title": {"type": "long"},
        },
    },
    "regulatory_citations": {
        "type": "nested",
        "properties": {
            "part": {"type": "long"},
            "section": {"type": "long"},
            "title": {"type": "long"},
        },
    },
    "requestor_names": {"type": "text"},
    "requestor_types": {"type": "keyword", "index": False},
    "documents": {
        "type": "nested",
        "properties": {
            "document_id": {"type": "long", "index": False},
            "category": {"type": "keyword", "index": False},
            "description": {"type": "text"},
            "date": {"type": "date", "format": "dateOptionalTime"},
            "text": {"type": "text"},
            "url": {"type": "text", "index": False},
        },
    },
}

CITATIONS = {
    "type": {"type": "keyword"},
    "citation_type": {"type": "keyword", "index": False},
    "citation_text": {"type": "text", "index": False},
}

MUR_ADR_MAPPINGS = {
    "type": {"type": "keyword"},
    "no": {"type": "keyword", "index": False},
    "doc_id": {"type": "keyword", "index": False},
    "name": {"type": "text", "analyzer": "english"},
    "election_cycles": {"type": "long"},
    "open_date": {"type": "date", "format": "dateOptionalTime"},
    "close_date": {"type": "date", "format": "dateOptionalTime"},
    "url": {"type": "text", "index": False},
    "subjects": {"type": "text"},
    "commission_votes": {
        "properties": {
            "text": {"type": "text"},
            "vote_date": {"type": "date", "format": "dateOptionalTime"},
        }
    },
    "dispositions": {
        "properties": {
            "citations": {
                "properties": {
                    "text": {"type": "text"},
                    "title": {"type": "text"},
                    "type": {"type": "text"},
                    "url": {"type": "text"},
                }
            },
            "disposition": {"type": "text", "index": False},
            "penalty": {"type": "double"},
            "respondent": {"type": "text"},
        }
    },
    "documents": CASE_DOCUMENT_MAPPINGS,
    "participants": {
        "properties": {
            "citations": {"type": "object"},
            "name": {"type": "text"},
            "role": {"type": "text"},
        }
    },
    "respondents": {"type": "text"},
}

MUR_MAPPINGS = copy.deepcopy(MUR_ADR_MAPPINGS)
MUR_MAPPINGS["mur_type"] = {"type": "keyword"}

STATUTES = {
    "type": {"type": "keyword"},
    "doc_id": {"type": "keyword", "index": False},
    "name": {"type": "text", "analyzer": "english"},
    "text": {"type": "text", "analyzer": "english"},
    "no": {"type": "keyword", "index": False},
    "title": {"type": "text"},
    "chapter": {"type": "text"},
    "subchapter": {"type": "text"},
    "url": {"type": "text", "index": False},
}


REGULATIONS = {
    "type": {"type": "keyword"},
    "doc_id": {"type": "keyword", "index": False},
    "name": {"type": "text", "analyzer": "english"},
    "text": {"type": "text", "analyzer": "english"},
    "no": {"type": "text", "index": False},
    "url": {"type": "text", "index": False},
}

ALL_MAPPINGS = {}
ALL_MAPPINGS.update(ADMIN_FINES)
ALL_MAPPINGS.update(ADVISORY_OPINIONS)
ALL_MAPPINGS.update(CITATIONS)
ALL_MAPPINGS.update(ADVISORY_OPINIONS)
ALL_MAPPINGS.update(MUR_ADR_MAPPINGS)
ALL_MAPPINGS.update(REGULATIONS)
ALL_MAPPINGS.update(STATUTES)
ALL_MAPPINGS.update(SORT_MAPPINGS)

MAPPINGS = {"properties": ALL_MAPPINGS}
# ==== end define mapping for index: docs


# ==== start define mapping for index: archived_murs
ARCH_MUR_DOCUMENT_MAPPINGS = {
    "type": "nested",
    "properties": {
        "document_id": {"type": "integer"},
        "length": {"type": "long"},
        "text": {"type": "text"},
        "url": {"type": "text"},
    },
}

ARCH_MUR_MAPPINGS = {
    "dynamic": "false",
    "properties": {
        "type": {"type": "keyword"},
        "doc_id": {"type": "keyword", "index": False},
        "no": {"type": "keyword"},
        "mur_name": {"type": "text"},
        "mur_type": {"type": "keyword"},
        "open_date": {"type": "date", "format": "dateOptionalTime"},
        "close_date": {"type": "date", "format": "dateOptionalTime"},
        "url": {"type": "text"},
        "subjects": {"type": "text"},
        "citations": {
            "properties": {
                "text": {"type": "text"},
                "title": {"type": "text"},
                "type": {"type": "text"},
                "url": {"type": "text"},
            }
        },
        "complainants": {"type": "text"},
        "respondent": {"type": "text"},
        "documents": ARCH_MUR_DOCUMENT_MAPPINGS,
    }
}
ARCH_MUR_MAPPINGS.update(SORT_MAPPINGS)

# ==== end define mapping for index: archived_murs


ANALYZER_SETTINGS = {"analysis": {"analyzer": {"default": {"type": "english"}}}}

BACKUP_REPOSITORY_NAME = "legal_s3_repository"

BACKUP_DIRECTORY = "es-backups"


def create_docs_index():
    """
    Initialize Elasticsearch for storing legal documents.
    Create the `docs` index, and set up the aliases `docs_index` and `docs_search`
    to point to the `docs` index. If the `doc` index already exists, delete it.
    """

    es = utils.get_elasticsearch_connection()
    try:
        logger.info("Delete index 'docs'")
        es.indices.delete('docs')
    except elasticsearch.exceptions.NotFoundError:
        pass

    try:
        logger.info("Delete index 'docs_index'")
        es.indices.delete('docs_index')
    except elasticsearch.exceptions.NotFoundError:
        pass

    logger.info("Create index 'docs'")
    es.indices.create(
        'docs',
        {
            "mappings": MAPPINGS,
            "settings": ANALYZER_SETTINGS,
            "aliases": {'docs_index': {}, 'docs_search': {}},
        },
    )


def create_archived_murs_index():
    """
    Initialize Elasticsearch for storing archived MURs.
    If the `archived_murs` index already exists, delete it.
    Create the `archived_murs` index.
    Set up the alias `archived_murs_index` to point to the `archived_murs` index.
    Set up the alias `docs_search` to point `archived_murs` index, allowing the
    legal search to work across current and archived MURs
    """

    es = utils.get_elasticsearch_connection()

    try:
        logger.info("Delete index 'archived_murs'")
        es.indices.delete('archived_murs')
    except elasticsearch.exceptions.NotFoundError:
        pass

    logger.info(
        "Create index 'archived_murs' with aliases 'docs_search' and 'archived_murs_index'"
    )

    es.indices.create(
        'archived_murs',
        {
            "mappings": ARCH_MUR_MAPPINGS,
            "settings": ANALYZER_SETTINGS,
            "aliases": {'archived_murs_index': {}, 'docs_search': {}},
        },
    )
    # es.indices.create(
    #     'archived_murs',
    #     {
    #         "mappings": MAPPINGS,
    #         "settings": ANALYZER_SETTINGS,
    #         "aliases": {'archived_murs_index': {}, 'docs_search': {}},
    #     },
    # )


def delete_all_indices():
    """
    Delete index `docs`.
    This is usually done in preparation for restoring indexes from a snapshot backup.
    """

    es = utils.get_elasticsearch_connection()
    try:
        logger.info("Delete index 'docs'")
        es.indices.delete('docs')
    except elasticsearch.exceptions.NotFoundError:
        pass

    try:
        logger.info("Delete index 'archived_murs'")
        es.indices.delete('archived_murs')
    except elasticsearch.exceptions.NotFoundError:
        pass


def create_staging_index():
    """
    Create the index `docs_staging`.
    Move the alias docs_index to point to `docs_staging` instead of `docs`.
    """
    es = utils.get_elasticsearch_connection()
    try:
        logger.info("Delete index 'docs_staging'")
        es.indices.delete('docs_staging')
    except Exception:
        pass

    logger.info("Create index 'docs_staging'")
    es.indices.create(
        'docs_staging', {"mappings": MAPPINGS, "settings": ANALYZER_SETTINGS, }
    )

    logger.info("Move alias 'docs_index' to point to 'docs_staging'")
    es.indices.update_aliases(
        body={
            "actions": [
                {"remove": {"index": 'docs', "alias": 'docs_index'}},
                {"add": {"index": 'docs_staging', "alias": 'docs_index'}},
            ]
        }
    )


def restore_from_staging_index():
    """
    A 4-step process:
    1. Move the alias docs_search to point to `docs_staging` instead of `docs`.
    2. Reinitialize the index `docs`.
    3. Reindex `doc_staging` to `docs`
    4. Move `docs_index` and `docs_search` aliases to point to the `docs` index.
       Delete index `docs_staging`.
    """
    es = utils.get_elasticsearch_connection()

    logger.info("Move alias 'docs_search' to point to 'docs_staging'")
    es.indices.update_aliases(
        body={
            "actions": [
                {"remove": {"index": 'docs', "alias": 'docs_search'}},
                {"add": {"index": 'docs_staging', "alias": 'docs_search'}},
            ]
        }
    )

    logger.info("Delete and re-create index 'docs'")
    es.indices.delete('docs')
    es.indices.create('docs', {"mappings": MAPPINGS, "settings": ANALYZER_SETTINGS})

    logger.info("Reindex all documents from index 'docs_staging' to index 'docs'")

    body = {"source": {"index": "docs_staging", }, "dest": {"index": "docs"}}
    es.reindex(body=body, wait_for_completion=True, request_timeout=1500)

    move_aliases_to_docs_index()


def move_aliases_to_docs_index():
    """
    Move `docs_index` and `docs_search` aliases to point to the `docs` index.
    Delete index `docs_staging`.
    """

    es = utils.get_elasticsearch_connection()

    logger.info("Move aliases 'docs_index' and 'docs_search' to point to 'docs'")
    es.indices.update_aliases(
        body={
            "actions": [
                {"remove": {"index": 'docs_staging', "alias": 'docs_index'}},
                {"remove": {"index": 'docs_staging', "alias": 'docs_search'}},
                {"add": {"index": 'docs', "alias": 'docs_index'}},
                {"add": {"index": 'docs', "alias": 'docs_search'}},
            ]
        }
    )
    logger.info("Delete index 'docs_staging'")
    es.indices.delete('docs_staging')


def move_archived_murs():
    '''
    Move archived MURs from `docs` index to `archived_murs_index`
    This should only need to be run once.
    Once archived MURs are on their own index, we will be able to
    re-index current legal docs after a schema change much more quickly.
    '''
    es = utils.get_elasticsearch_connection()

    body = {
        "source": {
            "index": "docs",
            "type": "murs",
            "query": {"match": {"mur_type": "archived"}},
        },
        "dest": {"index": "archived_murs"},
    }

    logger.info("Copy archived MURs from 'docs' index to 'archived_murs' index")
    es.reindex(body=body, wait_for_completion=True, request_timeout=1500)


def configure_backup_repository(repository=BACKUP_REPOSITORY_NAME):
    '''
    Configure s3 backup repository using api credentials.
    This needs to get re-run when s3 credentials change for each API deployment
    '''
    es = utils.get_elasticsearch_connection()
    logger.info("Configuring backup repository: {0}".format(repository))
    body = {
        'type': 's3',
        'settings': {
            'bucket': env.get_credential("bucket"),
            'region': env.get_credential("region"),
            'access_key': env.get_credential("access_key_id"),
            'secret_key': env.get_credential("secret_access_key"),
            'base_path': BACKUP_DIRECTORY,
        },
    }
    es.snapshot.create_repository(repository=repository, body=body)


def create_elasticsearch_backup(repository_name=None, snapshot_name="auto_backup"):
    '''
    Create elasticsearch shapshot in the `legal_s3_repository` or specified repository.
    '''
    es = utils.get_elasticsearch_connection()

    repository_name = repository_name or BACKUP_REPOSITORY_NAME
    configure_backup_repository(repository_name)

    snapshot_name = "{0}_{1}".format(
        datetime.datetime.today().strftime('%Y%m%d'), snapshot_name
    )
    logger.info("Creating snapshot {0}".format(snapshot_name))
    result = es.snapshot.create(repository=repository_name, snapshot=snapshot_name)
    if result.get('accepted'):
        logger.info("Successfully created snapshot: {0}".format(snapshot_name))
    else:
        logger.error("Unable to create snapshot: {0}".format(snapshot_name))


def restore_elasticsearch_backup(repository_name=None, snapshot_name=None):
    '''
    Restore elasticsearch from backup in the event of catastrophic failure at the infrastructure layer or user error.

    -Delete docs index
    -Restore from elasticsearch snapshot
    -Default to most recent snapshot, optionally specify `snapshot_name`
    '''
    es = utils.get_elasticsearch_connection()

    repository_name = repository_name or BACKUP_REPOSITORY_NAME
    configure_backup_repository(repository_name)

    most_recent_snapshot_name = get_most_recent_snapshot(repository_name)
    snapshot_name = snapshot_name or most_recent_snapshot_name

    if es.indices.exists('docs'):
        logger.info(
            'Found docs index. Creating staging index for zero-downtime restore'
        )
        create_staging_index()

    delete_all_indices()

    logger.info("Retrieving snapshot: {0}".format(snapshot_name))
    body = {"indices": "docs,archived_murs"}
    result = es.snapshot.restore(
        repository=BACKUP_REPOSITORY_NAME, snapshot=snapshot_name, body=body
    )
    if result.get('accepted'):
        logger.info("Successfully restored snapshot: {0}".format(snapshot_name))
        if es.indices.exists('docs_staging'):
            move_aliases_to_docs_index()
    else:
        logger.error("Unable to restore snapshot: {0}".format(snapshot_name))
        logger.info(
            "You may want to try the most recent snapshot: {0}".format(
                most_recent_snapshot_name
            )
        )


def get_most_recent_snapshot(repository_name=None):
    '''
    Get the list of snapshots (sorted by date, ascending) and
    return most recent snapshot name
    '''
    es = utils.get_elasticsearch_connection()

    repository_name = repository_name or BACKUP_REPOSITORY_NAME
    logger.info("Retreiving most recent snapshot")
    snapshot_list = es.snapshot.get(repository=repository_name, snapshot="*").get(
        'snapshots'
    )

    return snapshot_list.pop().get('snapshot')
