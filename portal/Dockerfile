FROM python:3

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

RUN apt-get update && \
    apt-get install -y --no-install-recommends easy-rsa && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY . .

CMD [ "uvicorn", "portal:asgi_app", "--host", "0.0.0.0", "--workers", "4", "--port", "8080"]
