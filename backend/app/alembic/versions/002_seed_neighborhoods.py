"""seed neighborhoods data - 서울특별시 주요 구/동

Revision ID: 002
Revises: 001
Create Date: 2026-05-29

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '002'
down_revision: Union[str, None] = '001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


neighborhoods_data = [
    # (id, name, parent_id, level)
    # Level 1: city
    (1, '서울특별시', None, 'city'),
    # Level 2: district
    (2, '강남구', 1, 'district'),
    (3, '마포구', 1, 'district'),
    (4, '성동구', 1, 'district'),
    (5, '송파구', 1, 'district'),
    (6, '서초구', 1, 'district'),
    # Level 3: dong - 강남구
    (7, '역삼동', 2, 'dong'),
    (8, '삼성동', 2, 'dong'),
    (9, '논현동', 2, 'dong'),
    (10, '청담동', 2, 'dong'),
    # Level 3: dong - 마포구
    (11, '합정동', 3, 'dong'),
    (12, '망원동', 3, 'dong'),
    (13, '연남동', 3, 'dong'),
    (14, '상암동', 3, 'dong'),
    # Level 3: dong - 성동구
    (15, '성수동1가', 4, 'dong'),
    (16, '성수동2가', 4, 'dong'),
    (17, '왕십리동', 4, 'dong'),
    (18, '금호동', 4, 'dong'),
    # Level 3: dong - 송파구
    (19, '잠실동', 5, 'dong'),
    (20, '석촌동', 5, 'dong'),
    (21, '가락동', 5, 'dong'),
    # Level 3: dong - 서초구
    (22, '서초동', 6, 'dong'),
    (23, '반포동', 6, 'dong'),
    (24, '방배동', 6, 'dong'),
]

_MAX_SEED_ID = 24


def upgrade() -> None:
    neighborhoods_table = sa.table(
        'neighborhoods',
        sa.column('id', sa.Integer()),
        sa.column('name', sa.String()),
        sa.column('parent_id', sa.Integer()),
        sa.column('level', sa.String()),
    )
    op.bulk_insert(
        neighborhoods_table,
        [
            {'id': row[0], 'name': row[1], 'parent_id': row[2], 'level': row[3]}
            for row in neighborhoods_data
        ],
    )
    # SERIAL 시퀀스를 마지막 삽입 ID로 앞당겨 다음 auto-insert가 충돌하지 않도록 함
    op.execute(sa.text(f"SELECT setval('neighborhoods_id_seq', {_MAX_SEED_ID})"))


def downgrade() -> None:
    # 시드 데이터만 삭제하고 시퀀스 초기화
    op.execute(sa.text(f"DELETE FROM neighborhoods WHERE id <= {_MAX_SEED_ID}"))
    op.execute(sa.text("SELECT setval('neighborhoods_id_seq', 1, false)"))
