FROM python:3.12

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
ENV WORKERS 4
RUN apt-get update && \
    apt-get install -y --no-install-recommends easy-rsa && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY . .

CMD uvicorn portal:asgi_app --host 0.0.0.0 --workers $WORKERS --port 8080
