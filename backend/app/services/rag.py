import json
from typing import Any

from google import genai
from google.genai import types
from sqlmodel import Session, or_, select

from app.core.config import settings
from app.models import Neighborhood, Product, SupportFaq

_SYSTEM_PROMPT = """당신은 중고거래 마켓플레이스 '중고거래 MVP'의 친절한 고객센터 AI 상담원입니다.

【핵심 규칙】
사용자가 특정 물건을 언급하거나 "~있어?", "~찾아줘", "~검색", "~얼마", 가격 조건(이하/이상/원) 등
상품 관련 질문을 하면 반드시 search_products 도구를 먼저 호출하여 실제 DB를 검색하세요.
"검색 기능이 없다", "제공하지 않는다"는 말은 절대 하지 마세요.

답변 지침:
- 검색 결과가 있으면 제목·가격·위치를 목록으로 보여주세요.
- 검색 결과가 없으면 "현재 해당 조건의 상품이 없습니다"라고 안내하세요.
- 일반 문의(반품, 계정 등)는 아래 FAQ를 참고하여 답변하세요.
- 공손하고 친절한 말투를 유지하세요."""

_SEARCH_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="search_products",
            description=(
                "중고거래 마켓에서 상품을 검색합니다. "
                "사용자가 물건 이름, 가격 조건, '~있어?', '~찾아줘', '~검색', '얼마' 등을 언급하면 즉시 호출하세요."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "keyword": types.Schema(
                        type=types.Type.STRING,
                        description="검색 키워드 (예: 의자, 노트북, 자전거). 빈 문자열이면 전체 조회.",
                    ),
                    "max_price": types.Schema(
                        type=types.Type.INTEGER,
                        description="최대 가격 (원). '1000원 이하'이면 1000. 조건 없으면 생략.",
                    ),
                    "min_price": types.Schema(
                        type=types.Type.INTEGER,
                        description="최소 가격 (원). '5000원 이상'이면 5000. 조건 없으면 생략.",
                    ),
                    "search_my_neighborhood": types.Schema(
                        type=types.Type.BOOLEAN,
                        description="True이면 사용자 동네 상품만, False이면 전체 검색. '우리 동네'가 언급되면 True.",
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
    max_price: int | None = None,
    min_price: int | None = None,
) -> str:
    stmt = (
        select(Product, Neighborhood)
        .join(Neighborhood, Product.neighborhood_id == Neighborhood.id, isouter=True)
        .where(Product.status == "SALE")
    )

    if keyword:
        stmt = stmt.where(
            or_(
                Product.title.icontains(keyword),
                Product.description.icontains(keyword),
            )
        )

    if max_price is not None:
        stmt = stmt.where(Product.price <= max_price)

    if min_price is not None:
        stmt = stmt.where(Product.price >= min_price)

    if search_my_neighborhood and user_neighborhood_id:
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

    stmt = stmt.order_by(Product.created_at.desc()).limit(5)  # type: ignore[union-attr]
    rows = session.exec(stmt).all()

    if not rows:
        conditions = []
        if keyword:
            conditions.append(f"키워드: {keyword}")
        if max_price is not None:
            conditions.append(f"{max_price:,}원 이하")
        if min_price is not None:
            conditions.append(f"{min_price:,}원 이상")
        if search_my_neighborhood:
            conditions.append("내 동네")
        cond_str = ", ".join(conditions) if conditions else "전체"
        return json.dumps(
            {"found": False, "message": f"조건({cond_str})에 해당하는 상품이 없습니다."},
            ensure_ascii=False,
        )

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

    contents: list[types.Content] = []
    for msg in history:
        role = "user" if msg["role"] == "user" else "model"
        contents.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))
    contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))

    config = types.GenerateContentConfig(
        system_instruction=system,
        tools=[_SEARCH_TOOL],
        tool_config=types.ToolConfig(
            function_calling_config=types.FunctionCallingConfig(mode="AUTO"),
        ),
    )

    for _ in range(3):
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=config,
        )

        part = response.candidates[0].content.parts[0]

        if part.text:
            return response.text

        fn_call = part.function_call
        if fn_call and fn_call.name == "search_products":
            args = dict(fn_call.args)
            result_str = _do_search_products(
                session=session,
                keyword=args.get("keyword", ""),
                search_my_neighborhood=bool(args.get("search_my_neighborhood", False)),
                user_neighborhood_id=user_neighborhood_id,
                max_price=int(args["max_price"]) if args.get("max_price") else None,
                min_price=int(args["min_price"]) if args.get("min_price") else None,
            )
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
