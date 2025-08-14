FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WORKERS=4

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    easy-rsa  \
    procps \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./
RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["uvicorn", "portal:asgi_app", "--host", "0.0.0.0", "--port", "8080"]
HEALTHCHECK --interval=10s --timeout=1s CMD /usr/bin/pkill -0 uvicorn || exit 1
