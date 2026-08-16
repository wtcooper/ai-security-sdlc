FROM python:3.13-slim@sha256:ffb752e139c0a19692a43af8d8523b274222dd68eebad5d583b45c2201c6e30a
RUN useradd -u 10001 -m app
WORKDIR /app
RUN pip install --no-cache-dir "fastapi==0.141.1" "uvicorn==0.52.3" "langchain-openai==1.5.1" "langchain-qdrant==1.1.0" "qdrant-client==1.19.0" "pydantic==2.13.4"
COPY main.py retrieval.py ./
USER 10001
CMD ["uvicorn", "main:api", "--host", "0.0.0.0", "--port", "8000"]
