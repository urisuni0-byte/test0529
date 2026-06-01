"""add support tables (faqs, conversations, messages)

Revision ID: 010
Revises: 009
Create Date: 2026-06-01

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "010"
down_revision: Union[str, None] = "009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

FAQS = [
    ("회원가입은 어떻게 하나요?", "이메일과 비밀번호로 회원가입하거나 구글 계정으로 간편하게 가입할 수 있습니다. 앱 로그인 화면에서 '회원가입' 버튼을 눌러주세요.", "계정"),
    ("비밀번호를 잊어버렸어요.", "현재 비밀번호 재설정 기능은 준비 중입니다. 구글 계정으로 로그인하시거나 고객센터로 문의해 주세요.", "계정"),
    ("닉네임은 어떻게 변경하나요?", "앱 하단 설정 탭 → 닉네임 옆 '편집' 버튼을 누르면 변경할 수 있습니다. 닉네임은 2~15자 한글·영문·숫자만 사용 가능합니다.", "계정"),
    ("계정을 탈퇴하고 싶어요.", "현재 앱에서 직접 탈퇴 기능은 준비 중입니다. 고객센터로 문의하시면 처리해 드리겠습니다.", "계정"),
    ("상품은 어떻게 등록하나요?", "피드 화면 우측 하단의 '글쓰기' 버튼을 누르세요. 사진, 제목, 가격, 카테고리, 설명을 입력하고 등록하면 됩니다.", "상품"),
    ("사진은 몇 장까지 올릴 수 있나요?", "상품당 최대 10장까지 사진을 등록할 수 있습니다. 사진 한 장당 최대 1MB입니다.", "상품"),
    ("등록한 상품을 수정하거나 삭제할 수 있나요?", "본인이 등록한 상품 상세 화면에서 수정 및 삭제가 가능합니다. 삭제된 상품은 복구할 수 없으니 주의해 주세요.", "상품"),
    ("판매 완료는 어떻게 표시하나요?", "내가 등록한 상품 상세 화면에서 상태를 '판매완료'로 변경할 수 있습니다.", "상품"),
    ("채팅은 어떻게 시작하나요?", "관심 있는 상품 상세 화면에서 '채팅하기' 버튼을 누르면 판매자와 1:1 채팅이 시작됩니다.", "거래"),
    ("판매자가 답장을 안 해요.", "판매자가 바쁠 수 있습니다. 조금 기다리거나 다른 상품을 찾아보세요. 사기가 의심되면 고객센터로 신고해 주세요.", "거래"),
    ("직거래는 어떻게 진행하나요?", "채팅을 통해 만날 장소와 시간을 협의하세요. 안전한 거래를 위해 공공장소에서 만나는 것을 권장합니다.", "거래"),
    ("결제는 어떻게 하나요?", "현재 앱 내 결제 기능은 지원하지 않습니다. 판매자와 채팅으로 직접 협의하여 현금 또는 계좌이체로 거래하세요.", "거래"),
    ("사기를 당한 것 같아요.", "즉시 고객센터로 신고해 주세요. 거래 채팅 내역과 상품 정보를 함께 제공해 주시면 빠르게 처리하겠습니다.", "신고"),
    ("허위 매물을 신고하고 싶어요.", "고객센터 채팅으로 해당 상품 링크와 사유를 알려주시면 검토 후 조치하겠습니다.", "신고"),
    ("동네 설정은 어떻게 하나요?", "앱 가입 후 동네를 설정할 수 있습니다. 설정 탭에서도 변경 가능합니다. 시·구·동 단위로 선택할 수 있습니다.", "기타"),
    ("앱이 느리거나 오류가 발생해요.", "앱을 종료 후 다시 실행해 보세요. 문제가 지속되면 앱 버전을 최신으로 업데이트하거나 고객센터로 문의해 주세요.", "기타"),
    ("관심 상품은 어떻게 저장하나요?", "상품 상세 화면에서 하트(♡) 버튼을 누르면 관심 상품으로 저장됩니다.", "기타"),
    ("알림이 오지 않아요.", "스마트폰 설정에서 앱 알림을 허용했는지 확인해 주세요. 앱을 재실행하면 알림이 다시 등록됩니다.", "기타"),
]


def upgrade() -> None:
    op.create_table(
        "support_faqs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("question", sa.Text(), nullable=False),
        sa.Column("answer", sa.Text(), nullable=False),
        sa.Column("category", sa.String(50), nullable=True),
    )

    op.create_table(
        "support_conversations",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True),
                  primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
    )

    op.create_table(
        "support_messages",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True),
                  primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("conversation_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("support_conversations.id", ondelete="CASCADE"), nullable=False),
        sa.Column("role", sa.String(10), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
    )

    # Seed FAQ data
    op.bulk_insert(
        sa.table(
            "support_faqs",
            sa.column("question", sa.Text),
            sa.column("answer", sa.Text),
            sa.column("category", sa.String),
        ),
        [{"question": q, "answer": a, "category": c} for q, a, c in FAQS],
    )


def downgrade() -> None:
    op.drop_table("support_messages")
    op.drop_table("support_conversations")
    op.drop_table("support_faqs")
