"""add unique constraint and index on users.nickname

Revision ID: 004
Revises: 003
Create Date: 2026-05-30

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index("idx_users_nickname", "users", ["nickname"])
    op.create_unique_constraint("uq_users_nickname", "users", ["nickname"])


def downgrade() -> None:
    op.drop_constraint("uq_users_nickname", "users", type_="unique")
    op.drop_index("idx_users_nickname", table_name="users")
