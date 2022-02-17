# Welcome to flaskinit
## Description
Flask init is a shell script that creates a basic project structure, with a few dependencies within a virtualenv folder, using python3.6 (which you need to have installed previously, along with virtualenv)
If you can't execute the script, use $ `chmod +x ./flaskinit.sh` to provide the script with executable permissions. No sudo permissions are required.
## Requirements
* python3.x 
* python venv module
* PostgreSQL server
## Usage
After you execute the script, you will have a folder containing all the project structure and files. The file `__init__.py` on the root folder will be the "flask app file". It comes with a default route and some basic stuff to get you started quickly into adding more routes. Even if the script is meant to generate a squeleton for a Rest API, the templates and static folders are also created just in case you want to do a HTML response application.
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.
To start the flask app, just activate the virtualenv by doing `source venv/bin/activate` and then starting the flask app with `python __init__.py`
