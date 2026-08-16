# TODO(codeguard:supply-chain): digest verified 2026-08-10 for python:3.13-slim; re-pin when you bump.
FROM python:3.13-slim@sha256:ffb752e139c0a19692a43af8d8523b274222dd68eebad5d583b45c2201c6e30a
RUN useradd -u 10001 -m app
WORKDIR /app
COPY pyproject.toml ./
RUN pip install --no-cache-dir . 2>/dev/null || pip install --no-cache-dir "langgraph==1.2.11" "langchain==1.3.15" "langchain-openai==1.5.1" "fastapi==0.141.1" "uvicorn==0.52.3" "httpx==0.28.1" "pydantic==2.13.4"
COPY app.py tools/ ./
USER 10001
EXPOSE 8000
CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
