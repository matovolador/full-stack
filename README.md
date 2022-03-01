# FlaskInit Sample
[![Coverage Status](./coverage-badge.svg?dummy=8484744)](./coverage.xml)
## Description
This is a sample project entirelly generated with a shell script ("./flaskinit.sh"). This script is hosted on another repo of mine called "shell-magik".
This repo is basically a flask application that contains unittests, ORM, and migrations as a sample project.
Tests are ran by using "./coverageme.sh" script, which also generates coverage files and badges for the README.md file.
Flask init is a shell script that creates a basic project structure, with a few dependencies within a virtualenv folder, using python3.6 (which you need to have installed previously, along with virtualenv)
If you can't execute the script, use $ `chmod +x ./flaskinit.sh` to provide the script with executable permissions. No sudo permissions are required.

* Note that recent addition of docker is not yet reflected into the flaskinit.sh script. This is a TODO.

## Requirements
* docker
* docker-compose
* this was done under WSL2: ubuntu-20
## Usage
After you execute the script, you will have a folder containing all the project structure and files. The file `__init__.py` on the web folder will be the "flask app file". It comes with a default route and some basic stuff to get you started quickly into adding more routes.
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.
To start the flask app, just activate the virtualenv by doing `source venv/bin/activate` and then starting the flask app with `python __init__.py`
To start tests use `./coverageme.sh`

## App Coverage
[![Coverage Status](./coverage-badge.svg?dummy=8484744)](./coverage.xml)
## Usage
Deployment of all images (nginx reverse proxy, postgres DB and flask API) are done with `./deploy.sh`. This script also executes unittests and database migrations. Also copies results of coverage scan into the actual project root folder so it can be displayed in the README.md badge, and analyzed in pull requests if so required.
The Flask API itself comes with some base routes and some basic stuff to get you started quickly into adding more routes. It also comes with unittests, codecoverage, and alembic database migrations and SQL_Alchemy
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.

### Migrations, Unittests and Code Coverage
Migrations, unit tests and code coverage badges and analysis are all executed automatically by the deploy script: `./deploy.sh`
If you wish to get rid of the database alterations that were made by alembic, just run `alembic downgrade base` using the web/venv/bin/python interpreter and you can then remove the revisions from their folder, and start writing your own models inside `./web/modules/database.py`. Please refer to Alembic documentation on how to create revisions and use migration commands.

## TODOs
* Need to add more info on how docker was implemented
* Need to add this branch's feature modifications (basically project restructure and docker implementation) to `flaskinit.sh` contents.