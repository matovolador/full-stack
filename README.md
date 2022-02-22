# FlaskInit Sample
[![Coverage Status](./coverage-badge.svg?dummy=8484744)](./coverage.xml)
## Description
This is a sample project entirelly generated with a shell script ("./flaskinit.sh"). This script is hosted on another repo of mine called "shell-magik".
This repo is basically a flask application that contains unittests, ORM, and migrations as a sample project.
Tests are ran by using "./coverageme.sh" script, which also generates coverage files and badges for the README.md file.
Flask init is a shell script that creates a basic project structure, with a few dependencies within a virtualenv folder, using python3.6 (which you need to have installed previously, along with virtualenv)
If you can't execute the script, use $ `chmod +x ./flaskinit.sh` to provide the script with executable permissions. No sudo permissions are required.
## Requirements
* python3.x 
* python venv module
* PostgreSQL server
## Usage
After you execute the script, you will have a folder containing all the project structure and files. The file `__init__.py` on the root folder will be the "flask app file". It comes with a default route and some basic stuff to get you started quickly into adding more routes.
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.
To start the flask app, just activate the virtualenv by doing `source venv/bin/activate` and then starting the flask app with `python __init__.py`
To start tests use `./coverageme.sh`
