# FlaskInit Sample
## App Coverage
[![Coverage Status](./coverage-badge.svg?dummy=8484744)](./coverage.xml)
## Description
This is a sample project entirelly generated with a shell script ("./flaskinit.sh"). This script is hosted on another repo of mine called "shell-magik".
This repo is basically a flask application that contains unittests, ORM, migrations, and full docker integration as a sample project.
Flask init is a shell script that creates a basic project structure, with best development practices containing a full suite of automatic deployment, unittests and coverage that is ran automatically whenever the docker images are deployed.
If you can't execute the script, use $ `chmod +x ./flaskinit.sh` to provide the script with executable permissions. No sudo permissions are required.

* Note that recent addition of docker is not yet reflected into the flaskinit.sh script. This is a TODO.

## Requirements
* docker
* docker-compose
* this was done under WSL2: ubuntu-20

## Usage
Deployment of all images (nginx reverse proxy, postgres DB and flask API) are done with `./deploy.sh`. This script also executes unittests and database migrations. Also copies results of coverage scan into the actual project root folder so it can be displayed in the README.md badge, and analyzed in pull requests if so required.
The Flask API itself comes with some base routes and some basic stuff to get you started quickly into adding more routes. It also comes with unittests, codecoverage, and alembic database migrations and SQL_Alchemy
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.

## "Dev" Usage
1) Deploy database: `$ docker-compose up --build -d db`
2) Go into `web` folder
3) Run app: 
`$ source venv/bin/activate`
`$ python __init__.py`
4) Run tests and coverage:
`$ ./coverageme.sh`

### Migrations, Unittests and Code Coverage
Migrations, unit tests and code coverage badges and analysis are all executed automatically by the deploy script: `./deploy.sh`
If you wish to get rid of the database alterations that were made by alembic, just run `alembic downgrade base` using the web/venv/bin/python interpreter and you can then remove the revisions from their folder, and start writing your own models inside `./web/modules/database.py`. Please refer to Alembic documentation on how to create revisions and use migration commands.

## TODOs
* Need to add more info on how docker was implemented
* Need to add this branch's feature modifications (basically project restructure and docker implementation) to `flaskinit.sh` contents.