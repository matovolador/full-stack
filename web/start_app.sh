alembic upgrade head
coverage run tests.py || exit 1
coverage xml
coverage lcov
coverage html
genbadge coverage -i - < coverage.xml
gunicorn --bind 0.0.0.0:5050 -w 3 __init__:app