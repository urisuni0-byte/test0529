"""fix products schema: image_urls default, neighborhood_id not null, feed index

Revision ID: 006
Revises: 005
Create Date: 2026-05-30

"""
from typing import Sequence, Union

from alembic import op

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Fix image_urls DEFAULT — was {} (invalid SQL), must be '{}'
    op.execute("ALTER TABLE products ALTER COLUMN image_urls SET DEFAULT '{}'")

    # Require neighborhood_id — safe because no products exist before Epic 3
    op.alter_column("products", "neighborhood_id", nullable=False)

    # Composite index for the feed query: WHERE neighborhood_id=? AND status IN (...)
    # ORDER BY created_at DESC — replaces the need to filter+sort in memory
    op.execute(
        "CREATE INDEX idx_products_feed"
        " ON products (neighborhood_id, status, created_at DESC)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_products_feed")
    op.alter_column("products", "neighborhood_id", nullable=True)
    op.execute("ALTER TABLE products ALTER COLUMN image_urls DROP DEFAULT")
