"""
Environment-based configuration for all backend services.
Uses Pydantic Settings for type-safe config with .env file support.
"""

from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Global application settings loaded from environment variables."""

    # ─── Application ──────────────────────────────────────────────────────
    APP_NAME: str = "DynamicPricingEngine"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"

    # ─── API Gateway ──────────────────────────────────────────────────────
    GATEWAY_HOST: str = "0.0.0.0"
    GATEWAY_PORT: int = 8000

    # ─── Service URLs (for inter-service communication) ───────────────────
    INTENT_SERVICE_URL: str = "http://localhost:8001"
    ROUTE_SERVICE_URL: str = "http://localhost:8002"
    CARRIER_SERVICE_URL: str = "http://localhost:8003"
    PRICING_SERVICE_URL: str = "http://localhost:8004"
    RECOMMENDATION_SERVICE_URL: str = "http://localhost:8005"
    BOOKING_SERVICE_URL: str = "http://localhost:8006"

    # ─── Database ─────────────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/pricing_engine"
    DATABASE_POOL_SIZE: int = 20
    DATABASE_MAX_OVERFLOW: int = 10

    # ─── Redis ────────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_CACHE_TTL: int = 300  # 5 minutes

    # ─── Ollama (AI/ML) ──────────────────────────────────────────────────
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    OLLAMA_ASR_MODEL: str = "whisper:tiny"
    OLLAMA_LLM_MODEL: str = "mistral:7b"
    OLLAMA_EMBEDDING_MODEL: str = "nomic-embed-text"
    OLLAMA_TIMEOUT: int = 60

    # ─── Pricing Configuration ────────────────────────────────────────────
    PRICING_DEFAULT_MARGIN_PCT: float = 0.08  # 8% default margin
    PRICING_MIN_MARGIN_PCT: float = 0.03      # 3% minimum
    PRICING_MAX_MARGIN_PCT: float = 0.15      # 15% maximum
    PRICING_DEMAND_WEIGHT: float = 0.3
    PRICING_FUEL_WEIGHT: float = 0.25
    PRICING_TRAFFIC_WEIGHT: float = 0.2
    PRICING_WEATHER_WEIGHT: float = 0.25

    # ─── Carrier Scoring Weights ──────────────────────────────────────────
    CARRIER_COST_WEIGHT: float = 0.35
    CARRIER_RELIABILITY_WEIGHT: float = 0.30
    CARRIER_AVAILABILITY_WEIGHT: float = 0.15
    CARRIER_ETA_WEIGHT: float = 0.20

    # ─── External Signal APIs (placeholder URLs) ──────────────────────────
    WEATHER_API_URL: str = ""
    WEATHER_API_KEY: str = ""
    FUEL_PRICE_API_URL: str = ""
    TRAFFIC_API_URL: str = ""

    # ─── S3 / MinIO ──────────────────────────────────────────────────────
    S3_ENDPOINT: str = "http://localhost:9000"
    S3_ACCESS_KEY: str = "minioadmin"
    S3_SECRET_KEY: str = "minioadmin"
    S3_BUCKET: str = "pricing-engine"

    # ─── JWT Auth ─────────────────────────────────────────────────────────
    JWT_SECRET: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRY_MINUTES: int = 60

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


# Global settings instance
settings = Settings()
