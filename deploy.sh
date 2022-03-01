docker-compose down
docker-compose up --build -d || exit 1
docker-compose logs


flask_app_id=$(docker inspect --format="{{.Id}}" flaskinit-flask_app-1)
db_id=$(docker inspect --format="{{.Id}}" flaskinit-db-1)
proxy_id=$(docker inspect --format="{{.Id}}" flaskinit-proxy-1)

sleep 10

docker cp $flask_app_id:/code/coverage-badge.svg ./coverage-badge.svg
docker cp $flask_app_id:/code/coverage.xml ./coverage.xml
docker cp $flask_app_id:/code/coverage.lcov ./coverage.lcov
docker cp $flask_app_id:/code/.coverage ./.coverage
docker cp $flask_app_id:/code/htmlcov ./htmlcov