from typing import Any

import anthropic
from sqlmodel import Session, select

from app.core.config import settings
from app.models import SupportFaq

_SYSTEM_TEMPLATE = """당신은 중고거래 마켓플레이스 '중고거래 MVP'의 친절한 고객센터 AI 상담원입니다.
아래 FAQ를 참고하여 사용자의 질문에 정확하고 친절하게 한국어로 답변해 주세요.

답변 시 지침:
- 간결하고 명확하게 답변하세요 (3~5문장 이내).
- FAQ에 없는 내용은 "해당 내용은 직접 확인이 필요합니다. 추가 도움이 필요하시면 고객센터(support@junggo.com)로 문의해 주세요."라고 안내하세요.
- 공손하고 친절한 말투를 유지하세요.

=== 자주 묻는 질문 (FAQ) ===
{faq_context}
==="""


def _build_faq_context(faqs: list[SupportFaq]) -> str:
    lines = []
    for faq in faqs:
        lines.append(f"[{faq.category}] Q: {faq.question}\nA: {faq.answer}")
    return "\n\n".join(lines)


def get_rag_response(
    session: Session,
    user_message: str,
    history: list[dict[str, Any]],
) -> str:
    faqs = session.exec(select(SupportFaq)).all()
    faq_context = _build_faq_context(list(faqs))
    system_prompt = _SYSTEM_TEMPLATE.format(faq_context=faq_context)

    messages: list[dict[str, Any]] = list(history) + [
        {"role": "user", "content": user_message}
    ]

    client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system=system_prompt,
        messages=messages,
    )
    return response.content[0].text  # type: ignore[union-attr]
