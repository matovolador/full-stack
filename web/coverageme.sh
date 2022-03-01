coverage run tests.py || exit 1
coverage xml
coverage lcov
coverage html
genbadge coverage -i - < coverage.xml