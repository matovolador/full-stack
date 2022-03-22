source venv/bin/activate
alembic downgrade base
alembic upgrade head
coverage run tests.py || exit 1
alembic downgrade base
coverage xml
coverage lcov
coverage html
genbadge coverage -i - < coverage.xml