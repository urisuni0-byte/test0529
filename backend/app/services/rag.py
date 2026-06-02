import json
from typing import Any

from google import genai
from google.genai import types
from sqlmodel import Session, or_, select

from app.core.config import settings
from app.models import Neighborhood, Product, SupportFaq

_SYSTEM_PROMPT = """당신은 중고거래 마켓플레이스 '중고거래 MVP'의 친절한 고객센터 AI 상담원입니다.
아래 FAQ를 참고하고, 필요하면 search_products 도구로 실제 상품을 검색하여 답변해 주세요.

답변 지침:
- 간결하고 명확하게 한국어로 답변하세요.
- 상품 검색 결과가 있으면 제목·가격을 목록으로 보여주세요.
- FAQ에 없고 상품도 없으면 "고객센터(support@junggo.com)로 문의해 주세요."라고 안내하세요.
- 공손하고 친절한 말투를 유지하세요."""

_SEARCH_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="search_products",
            description="중고거래 마켓에서 키워드로 상품을 검색합니다. 사용자가 '~있어?', '~찾아줘', '~검색해줘' 같이 상품을 찾을 때 호출하세요.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "keyword": types.Schema(
                        type=types.Type.STRING,
                        description="검색할 상품 키워드 (예: 의자, 노트북, 자전거)",
                    ),
                    "search_my_neighborhood": types.Schema(
                        type=types.Type.BOOLEAN,
                        description="True이면 사용자 동네 상품만 검색, False이면 전체 검색",
                    ),
                },
                required=["keyword"],
            ),
        )
    ]
)


def _do_search_products(
    session: Session,
    keyword: str,
    search_my_neighborhood: bool,
    user_neighborhood_id: int | None,
) -> str:
    """실제 DB에서 상품을 검색하고 JSON 문자열로 반환."""
    stmt = (
        select(Product, Neighborhood)
        .join(Neighborhood, Product.neighborhood_id == Neighborhood.id, isouter=True)
        .where(
            Product.status == "SALE",
            or_(
                Product.title.icontains(keyword),
                Product.description.icontains(keyword),
            ),
        )
    )
    if search_my_neighborhood and user_neighborhood_id:
        # 같은 구(district) 내 검색: parent_id가 같은 동네들
        user_dong = session.get(Neighborhood, user_neighborhood_id)
        if user_dong and user_dong.parent_id:
            siblings = session.exec(
                select(Neighborhood.id).where(
                    Neighborhood.parent_id == user_dong.parent_id
                )
            ).all()
            stmt = stmt.where(Product.neighborhood_id.in_(siblings))  # type: ignore[arg-type]
        else:
            stmt = stmt.where(Product.neighborhood_id == user_neighborhood_id)

    rows = session.exec(stmt.limit(5)).all()

    if not rows:
        return json.dumps({"found": False, "message": "해당 상품이 없습니다."}, ensure_ascii=False)

    items = []
    for product, neighborhood in rows:
        items.append({
            "title": product.title,
            "price": f"{product.price:,}원",
            "category": product.category,
            "location": neighborhood.name if neighborhood else "위치 미상",
        })
    return json.dumps({"found": True, "count": len(items), "items": items}, ensure_ascii=False)


def _build_faq_context(faqs: list[SupportFaq]) -> str:
    return "\n\n".join(
        f"[{faq.category}] Q: {faq.question}\nA: {faq.answer}" for faq in faqs
    )


def get_rag_response(
    session: Session,
    user_message: str,
    history: list[dict[str, Any]],
    user_neighborhood_id: int | None = None,
) -> str:
    faqs = session.exec(select(SupportFaq)).all()
    faq_context = _build_faq_context(list(faqs))
    system = f"{_SYSTEM_PROMPT}\n\n=== FAQ ===\n{faq_context}\n==="

    client = genai.Client(api_key=settings.GOOGLE_GEMINI_API_KEY)

    # 대화 히스토리 변환
    contents: list[types.Content] = []
    for msg in history:
        role = "user" if msg["role"] == "user" else "model"
        contents.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))
    contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))

    config = types.GenerateContentConfig(
        system_instruction=system,
        tools=[_SEARCH_TOOL],
    )

    # Function Calling 루프 (최대 3회)
    for _ in range(3):
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=config,
        )

        # 텍스트 응답이면 종료
        if response.candidates[0].content.parts[0].text:
            return response.text

        # Function call 처리
        fn_call = response.candidates[0].content.parts[0].function_call
        if fn_call and fn_call.name == "search_products":
            args = dict(fn_call.args)
            result_str = _do_search_products(
                session=session,
                keyword=args.get("keyword", ""),
                search_my_neighborhood=args.get("search_my_neighborhood", False),
                user_neighborhood_id=user_neighborhood_id,
            )
            # AI 응답 + 검색 결과를 contents에 추가
            contents.append(response.candidates[0].content)
            contents.append(
                types.Content(
                    role="user",
                    parts=[types.Part(
                        function_response=types.FunctionResponse(
                            name="search_products",
                            response={"result": result_str},
                        )
                    )],
                )
            )
        else:
            break

    return response.text
