"""initial schema - users and neighborhoods

Revision ID: 001
Revises:
Create Date: 2026-05-29

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # neighborhoods 테이블 (users보다 먼저 — FK 의존성)
    op.create_table(
        'neighborhoods',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('name', sa.String(50), nullable=False),
        sa.Column('parent_id', sa.Integer(), sa.ForeignKey('neighborhoods.id', ondelete='SET NULL'), nullable=True),
        sa.Column('level', sa.String(20), nullable=False),
        sa.CheckConstraint("level IN ('city', 'district', 'dong')", name='ck_neighborhoods_level'),
    )
    op.create_index('idx_neighborhoods_parent_id', 'neighborhoods', ['parent_id'])

    # users 테이블
    op.create_table(
        'users',
        sa.Column('id', sa.Uuid(), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('email', sa.String(255), nullable=False, unique=True),  # unique=True가 UNIQUE 제약 생성
        sa.Column('nickname', sa.String(15), nullable=True),
        sa.Column('profile_image_url', sa.Text(), nullable=True),
        sa.Column(
            'neighborhood_id',
            sa.Integer(),
            sa.ForeignKey('neighborhoods.id', ondelete='SET NULL'),
            nullable=True,
        ),
        sa.Column('role', sa.String(20), nullable=False, server_default=sa.text("'user'")),
        sa.Column('is_superuser', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('fcm_token', sa.Text(), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('now()')),
    )
    # neighborhood_id 인덱스 (피드 필터 쿼리 성능)
    op.create_index('idx_users_neighborhood_id', 'users', ['neighborhood_id'])
    # NOTE: email의 UNIQUE 제약은 위 unique=True로 이미 생성됨 — 별도 인덱스 불필요


def downgrade() -> None:
    # DROP TABLE이 관련 인덱스와 제약도 자동 삭제함
    op.drop_table('users')
    op.drop_table('neighborhoods')
