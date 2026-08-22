FROM python:3.13-slim@sha256:ffb752e139c0a19692a43af8d8523b274222dd68eebad5d583b45c2201c6e30a
RUN useradd -u 10001 -m app
WORKDIR /app
RUN pip install --no-cache-dir "fastapi==0.141.1" "uvicorn==0.52.3"
COPY run.py ./
USER 10001
EXPOSE 9000
CMD ["uvicorn", "run:api", "--host", "0.0.0.0", "--port", "9000"]
