FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app
RUN pip install .

EXPOSE 8000

# Database migrations should be run separately using Prisma:
# cd prisma && npm install && npm run migrate:deploy
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
