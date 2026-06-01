from typing import Any

from google import genai
from google.genai import types
from sqlmodel import Session, select

from app.core.config import settings
from app.models import SupportFaq

_SYSTEM_PROMPT = """당신은 중고거래 마켓플레이스 '중고거래 MVP'의 친절한 고객센터 AI 상담원입니다.
아래 FAQ를 참고하여 사용자의 질문에 정확하고 친절하게 한국어로 답변해 주세요.

답변 시 지침:
- 간결하고 명확하게 답변하세요 (3~5문장 이내).
- FAQ에 없는 내용은 "해당 내용은 추가 확인이 필요합니다. 더 자세한 도움이 필요하시면 고객센터(support@junggo.com)로 문의해 주세요."라고 안내하세요.
- 공손하고 친절한 말투를 유지하세요."""


def _build_faq_context(faqs: list[SupportFaq]) -> str:
    return "\n\n".join(
        f"[{faq.category}] Q: {faq.question}\nA: {faq.answer}" for faq in faqs
    )


def get_rag_response(
    session: Session,
    user_message: str,
    history: list[dict[str, Any]],
) -> str:
    faqs = session.exec(select(SupportFaq)).all()
    faq_context = _build_faq_context(list(faqs))
    system = f"{_SYSTEM_PROMPT}\n\n=== 자주 묻는 질문 ===\n{faq_context}\n==="

    client = genai.Client(api_key=settings.GOOGLE_GEMINI_API_KEY)

    # 대화 히스토리 변환
    contents: list[types.Content] = []
    for msg in history:
        role = "user" if msg["role"] == "user" else "model"
        contents.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))
    contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=contents,
        config=types.GenerateContentConfig(system_instruction=system),
    )
    return response.text
