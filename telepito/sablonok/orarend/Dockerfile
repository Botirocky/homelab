FROM python:3.13-alpine
RUN apk add --no-cache tzdata && adduser -D -u 1000 orarend
WORKDIR /app
COPY app/ /app/
USER orarend
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/egeszseg || exit 1
CMD ["python", "/app/app.py"]
