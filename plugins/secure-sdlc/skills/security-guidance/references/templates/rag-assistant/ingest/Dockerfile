FROM python:3.13-slim@sha256:ffb752e139c0a19692a43af8d8523b274222dd68eebad5d583b45c2201c6e30a
RUN useradd -u 10001 -m app
WORKDIR /app
RUN pip install --no-cache-dir "langchain-openai==1.5.1" "langchain-text-splitters==1.1.2" "qdrant-client==1.19.0"
COPY ingest.py ./
USER 10001
CMD ["python", "ingest.py"]
