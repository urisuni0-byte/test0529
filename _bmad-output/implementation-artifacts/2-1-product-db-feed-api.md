# Story 2.1 — 상품 DB 모델 & 피드/상세 API

**Status:** done

## Summary

Products table + alembic migration + GET /api/v1/products feed and detail endpoints.

## Acceptance Criteria

1. `alembic upgrade head` creates `products` table with required columns and indexes
2. `GET /api/v1/products?neighborhood_id={id}&page=1&limit=20` returns SALE+RESERVED products
3. `GET /api/v1/products/{id}` returns full product detail, 404 if not found
4. Both endpoints are public (no auth required)
