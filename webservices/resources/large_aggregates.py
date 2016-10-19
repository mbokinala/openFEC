from flask_apispec import doc

from webservices import args
from webservices import docs
from webservices import utils
from webservices import schemas
from webservices.common import models
from webservices.common.views import ApiResource


@doc(
    tags=['financial'],
    description="PLACE HOLDER WRITE THIS LATER",
)
class EntityRecieptsTotalsView(ApiResource):

    model = models.EntityRecieptsTotals
    schema = schemas.EntityRecieptsTotalsSchema
    page_schema = schemas.EntityRecieptsTotalsPageSchema

    filter_match_fields = [
        ('cycle', model.cycle),
    ]

    @property
    def args(self):
        return utils.extend(
            args.paging,
            args.large_aggregates,
        )

    @property
    def index_column(self):
        return self.model.idx


@doc(
    tags=['financial'],
    description="PLACE HOLDER WRITE THIS LATER",
)
class EntityDisbursementsTotalsView(ApiResource):

    model = models.EntityDisbursementsTotals
    schema = schemas.EntityDisbursementsTotalsSchema
    page_schema = schemas.EntityDisbursementsTotalsPageSchema

    filter_match_fields = [
        ('cycle', model.cycle),
    ]

    @property
    def args(self):
        return utils.extend(
            args.paging,
            args.large_aggregates,
        )

    @property
    def index_column(self):
        return self.model.idx