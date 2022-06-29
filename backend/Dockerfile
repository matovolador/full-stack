FROM python:3.8.10


# set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

 
# set work directory
RUN mkdir /app
WORKDIR /app

# copy files
COPY . /app/


# install dependencies
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

RUN chmod +x ./start_app.sh
RUN chmod +x ./wait-for-it.sh

EXPOSE 5000