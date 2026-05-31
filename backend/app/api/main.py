from fastapi import APIRouter

from app.api.routes import admin, auth, chat, likes, neighborhoods, products, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(neighborhoods.router)
api_router.include_router(products.router)
api_router.include_router(likes.router)
api_router.include_router(chat.router)
api_router.include_router(admin.router)
