from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel
from sqlmodel import select

from app.api.deps import SessionDep
from app.models import Neighborhood

router = APIRouter(prefix="/neighborhoods", tags=["neighborhoods"])


class NeighborhoodItem(BaseModel):
    id: int
    name: str
    parent_id: int | None
    level: str


class NeighborhoodsListResponse(BaseModel):
    items: list[NeighborhoodItem]


@router.get("", response_model=NeighborhoodsListResponse)
def list_neighborhoods(session: SessionDep) -> Any:
    """Return all neighborhoods as a flat list (public endpoint).

    Ordered by level then id so parents always precede their children:
    city < district < dong (alphabetically).
    """
    neighborhoods = session.exec(
        select(Neighborhood).order_by(Neighborhood.level, Neighborhood.id)
    ).all()
    return NeighborhoodsListResponse(
        items=[
            NeighborhoodItem(
                id=n.id,
                name=n.name,
                parent_id=n.parent_id,
                level=n.level,
            )
            for n in neighborhoods
        ]
    )
