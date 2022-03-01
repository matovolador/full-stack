# pull official base image
FROM python:3

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# set work directory
RUN mkdir /code
WORKDIR /code

# copy files
COPY . /code/

# install dependencies
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# run migrations
# RUN alembic upgrade head

# RUN chmod +x ./coverageme.sh
RUN chmod +x ./wait-for-it.sh
RUN chmod +x ./start_app.sh

# execute tests
# RUN ./coverageme.sh



# run debug
#CMD python __init__.py

# run command __init__.py via gunicorn with 3 workers
# CMD gunicorn --bind 0.0.0.0:5050 -w 3 __init__:app


