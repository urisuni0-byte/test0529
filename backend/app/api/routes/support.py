import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, status
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.models import (
    SupportChatRequest,
    SupportChatResponse,
    SupportConversation,
    SupportConversationDetail,
    SupportConversationListItem,
    SupportMessage,
    SupportMessageOut,
    User,
)
from app.services.rag import get_rag_response

router = APIRouter(prefix="/support", tags=["support"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


@router.post("/chat", response_model=SupportChatResponse)
def chat(
    body: SupportChatRequest,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """사용자 메시지를 받아 RAG 기반 AI 답변을 반환하고 대화를 저장합니다."""
    if not body.message.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"detail": "메시지를 입력해 주세요.", "code": "EMPTY_MESSAGE"},
        )

    # 기존 대화 조회 or 새 대화 생성
    conversation: SupportConversation | None = None
    if body.conversation_id:
        try:
            conv_uuid = uuid.UUID(body.conversation_id)
            conversation = session.exec(
                select(SupportConversation).where(
                    SupportConversation.id == conv_uuid,
                    SupportConversation.user_id == current_user.id,
                )
            ).first()
        except ValueError:
            pass

    if conversation is None:
        conversation = SupportConversation(user_id=current_user.id)
        session.add(conversation)
        session.flush()

    # 이전 메시지 로드 (Claude 대화 히스토리용)
    prev_msgs = session.exec(
        select(SupportMessage)
        .where(SupportMessage.conversation_id == conversation.id)
        .order_by(SupportMessage.created_at)  # type: ignore[arg-type]
    ).all()

    history = [{"role": m.role, "content": m.content} for m in prev_msgs]

    # RAG 응답 생성
    answer = get_rag_response(
        session=session,
        user_message=body.message,
        history=history,
    )

    # 메시지 저장
    session.add(SupportMessage(
        conversation_id=conversation.id,
        role="user",
        content=body.message,
    ))
    session.add(SupportMessage(
        conversation_id=conversation.id,
        role="assistant",
        content=answer,
    ))
    conversation.updated_at = _now()
    session.commit()

    return SupportChatResponse(
        conversation_id=str(conversation.id),
        answer=answer,
    )


@router.get("/conversations/me", response_model=list[SupportMessageOut])
def get_my_conversation(
    session: SessionDep,
    current_user: CurrentUser,
    conversation_id: str,
) -> Any:
    """내 특정 대화의 메시지 목록 조회."""
    try:
        conv_uuid = uuid.UUID(conversation_id)
    except ValueError:
        return []
    msgs = session.exec(
        select(SupportMessage)
        .join(SupportConversation, SupportMessage.conversation_id == SupportConversation.id)
        .where(
            SupportConversation.id == conv_uuid,
            SupportConversation.user_id == current_user.id,
        )
        .order_by(SupportMessage.created_at)  # type: ignore[arg-type]
    ).all()
    return [SupportMessageOut(role=m.role, content=m.content, created_at=m.created_at) for m in msgs]


# ─── Admin endpoints ──────────────────────────────────────────────────────────

def _require_admin(current_user: CurrentUser) -> None:
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail={"detail": "관리자만 접근 가능합니다.", "code": "FORBIDDEN"})


@router.get("/admin/conversations", response_model=list[SupportConversationListItem])
def admin_list_conversations(session: SessionDep, current_user: CurrentUser) -> Any:
    """어드민: 전체 고객센터 대화 목록."""
    _require_admin(current_user)
    convs = session.exec(
        select(SupportConversation).order_by(SupportConversation.updated_at.desc())  # type: ignore[union-attr]
    ).all()

    result = []
    for conv in convs:
        user = session.get(User, conv.user_id)
        msgs = session.exec(
            select(SupportMessage)
            .where(SupportMessage.conversation_id == conv.id)
            .order_by(SupportMessage.created_at.desc())  # type: ignore[union-attr]
        ).all()
        last_msg = msgs[0].content[:80] if msgs else None
        result.append(SupportConversationListItem(
            id=str(conv.id),
            user_email=user.email if user else "unknown",
            user_nickname=user.nickname if user else None,
            last_message=last_msg,
            message_count=len(msgs),
            created_at=conv.created_at,
            updated_at=conv.updated_at,
        ))
    return result


@router.get("/admin/conversations/{conversation_id}", response_model=SupportConversationDetail)
def admin_get_conversation(
    conversation_id: str,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """어드민: 특정 대화 상세 메시지."""
    _require_admin(current_user)
    try:
        conv_uuid = uuid.UUID(conversation_id)
    except ValueError:
        raise HTTPException(status_code=404, detail={"detail": "대화를 찾을 수 없습니다.", "code": "NOT_FOUND"})

    conv = session.get(SupportConversation, conv_uuid)
    if not conv:
        raise HTTPException(status_code=404, detail={"detail": "대화를 찾을 수 없습니다.", "code": "NOT_FOUND"})

    user = session.get(User, conv.user_id)
    msgs = session.exec(
        select(SupportMessage)
        .where(SupportMessage.conversation_id == conv.id)
        .order_by(SupportMessage.created_at)  # type: ignore[arg-type]
    ).all()

    return SupportConversationDetail(
        id=str(conv.id),
        user_email=user.email if user else "unknown",
        messages=[SupportMessageOut(role=m.role, content=m.content, created_at=m.created_at) for m in msgs],
    )
