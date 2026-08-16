FROM python:3.13-slim@sha256:ffb752e139c0a19692a43af8d8523b274222dd68eebad5d583b45c2201c6e30a
RUN useradd -u 10001 -m app
WORKDIR /app
RUN pip install --no-cache-dir "mcp==2.0.0" "pyyaml==6.0.2" "httpx==0.28.1"
COPY server.py ./
USER 10001
EXPOSE 8000
CMD ["python", "server.py"]
