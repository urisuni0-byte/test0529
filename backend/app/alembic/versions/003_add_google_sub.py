"""add google_sub to users

Revision ID: 003
Revises: 002
Create Date: 2026-05-30

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("google_sub", sa.String(), nullable=True),
    )
    op.create_index("idx_users_google_sub", "users", ["google_sub"])


def downgrade() -> None:
    op.drop_index("idx_users_google_sub", table_name="users")
    op.drop_column("users", "google_sub")
