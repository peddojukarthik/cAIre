from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
 
from app.core.config import get_settings
 
settings = get_settings()
 
app = FastAPI(
    title="cAIre",
    description="AI-powered clinical information intelligence for patients.",
    version="0.1.0",
)
 
# CORS: restrict to the deployed frontend origin in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: lock to the deployed Vercel frontend URL before submission
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
 
 
@app.get("/api/healthz")
def healthz():
    return {"status": "ok"}


# Routers are added incrementally as each pipeline stage is built:
#   from app.routers import patients, documents, insights, chat
#   app.include_router(patients.router, prefix="/api/patients", tags=["patients"])
#   app.include_router(documents.router, prefix="/api/documents", tags=["documents"])
#   app.include_router(insights.router, prefix="/api/insights", tags=["insights"])
#   app.include_router(chat.router, prefix="/api/chat", tags=["chat"])
