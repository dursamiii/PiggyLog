FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIGGYLOG_DATABASE=/data/piggylog.db

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py ./

RUN mkdir -p /data
VOLUME ["/data"]
EXPOSE 5123

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5123"]
